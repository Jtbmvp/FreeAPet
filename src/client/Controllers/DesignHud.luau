--!strict
-- Binds the HUD package from Claude Design (Client.DesignUI) to the game's real data.
-- The UI shows server state and sends intents; every mutation stays on the existing services.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local Sfx = require(Shared.Sfx)
local BattleMath = require(Shared.BattleMath)
local Progression = require(Shared.ProgressionMath)
local ResearchMath = require(Shared.ResearchMath)

local Client = script.Parent.Parent
local TabletData = require(Client.UI.TabletData)
local HudActions = require(Client.UI.HudActions)
local ActionState = require(Client.UI.HudActionState)
local HudState = require(Client.UI.HudState)
local BattleSettings = require(Client.Battle.BattleSettings)
local ContextActions = require(script.Parent.ContextActions)
local Notifications = require(script.Parent.Notifications)

local Design = Client.DesignUI
local Layout = require(Design.Core.Layout)
local Theme = require(Design.Core.Theme) :: any
local UIManager = require(Design.Core.UIManager) :: any
local Screens = Design.Screens

local DesignHud: any = {}
local running = false

-- Design slot -> server research node. Slots without a node stay "?" in the tree.
local RESEARCH_NODES = {
	bigger = "IncomeBoost",
	offline = "OfflineIncome",
	carry = "CarryCapacity",
	speed = "MoveSpeed",
	accel = "Accelerator",
}
local GROUP_ORDER = { Neutral = 1, Forest = 2, Desert = 3 }
local LOBBY_COLOURS = { "FF7CC8", "5CB8FF", "FFB04A", "6AE454", "C58BFF", "FFD23C" }
local NOTICE_GAP = 12

local function shortName(name: string): string
	if #name <= 11 then
		return name
	end
	return string.match(name, "(%S+)$") or name
end

function DesignHud.Start()
	if running then
		return
	end
	running = true
	local player = Players.LocalPlayer
	-- The HTML's canvas: 1920x1080 under one global scale, centred, on every viewport.
	local env = (Layout :: any).mount({ Canvas = Vector2.new(1920, 1080) })
	local stage = env.Stage
	-- The trade room has no HTML source: it keeps the supplied phone layout on its own stage.
	local roomEnv = (Layout :: any).mount({ Name = "FreeAPetTrade", Order = 11 })
	local H: any = (require(Screens.HUD) :: any).new(stage)
	local Pets: any = (require(Screens.PetsPanel) :: any).new(stage)
	local Index: any = (require(Screens.IndexPanel) :: any).new(stage)
	local Shop: any = (require(Screens.ShopPanel) :: any).new(stage)
	local Lobby: any = (require(Screens.TradeLobby) :: any).new(stage)
	local Room: any = (require(Screens.TradeRoom) :: any).new(roomEnv.Stage)
	local Settings: any = (require(Screens.SettingsPanel) :: any).new(stage)
	local Research: any = (require(Screens.ResearchTree) :: any).new(stage)
	-- Pop-ups and notices own a gui above every other screen, with their own dim over the whole viewport.
	local popupEnv = (Layout :: any).mount({ Canvas = Vector2.new(1920, 1080), Name = "FreeAPetPopups", Order = 55 })
	local Popups: any = (require(Screens.Popups) :: any).new(popupEnv.Stage, popupEnv.Dim)
	local Notices: any = (require(Screens.Notices) :: any).new(popupEnv.Stage)
	local Manager: any = UIManager.new({
		Dim = env.Dim,
		Hud = H,
		Screens = {
			pets = Pets,
			index = Index,
			shop = Shop,
			trade = Lobby,
			traderoom = Room,
			settings = Settings,
			research = Research,
		},
	})
	Manager.ShouldShowHud = function()
		return player:GetAttribute("InBattle") ~= true
	end
	local function fitEdges()
		local pinned = not (Layout :: any).isMobile()
		H:SetOverscan(env.OverX, env.OverY, pinned)
		Research:SetOverscan(env.OverX, env.OverY, pinned)
		Settings:Dock(H:SettingsCorner())
		Notices:Dock(H:BaseBottom() + NOTICE_GAP)
	end
	env.OnFit = fitEdges
	fitEdges()
	local actions = HudActions.New()

	local function notify(text: string, tone: string)
		Notices:Push(text, tone)
	end
	-- Never over a running battle or its match results, nor over the starter choice.
	local playerGui = player:WaitForChild("PlayerGui")
	local battleEndedAt = 0
	local function screenVisible(guiName: string, childName: string): boolean
		local gui = playerGui:FindFirstChild(guiName)
		local child = gui and gui:FindFirstChild(childName, true)
		return child ~= nil and (child :: any).Visible == true
	end
	player:GetAttributeChangedSignal("InBattle"):Connect(function()
		battleEndedAt = os.clock()
	end)
	local function noticesHeld(): boolean
		if player:GetAttribute("InBattle") == true then
			return true
		end
		-- The battle presentation outlives the attribute by a moment.
		return os.clock() - battleEndedAt < 1.5
			or screenVisible("BattleDesign", "Battle")
			or screenVisible("BattleDesign", "BattleSummary")
			or screenVisible("StarterChoiceDesign", "StarterPick")
	end
	Popups.Held, Notices.Held = noticesHeld, noticesHeld

	------------------------------------------------------------------ live HUD
	local lastCash: number? = nil
	local function live()
		local level = player:GetAttribute("PlayerLevel")
		local ratio, text =
			HudState.Progress(level, player:GetAttribute("PlayerXp"), player:GetAttribute("PlayerXpToNext"))
		if typeof(level) == "number" then
			H:SetPlayerLevel(level, ratio, text)
			H:SetLocks(level, {
				research = Config.Progression.unlocks.Research,
				trade = Config.Progression.unlocks.Trade,
			})
		else
			H.LvNum.Text = "—"
			H.XpText.Text = text
			H.XpBar:SetPct(0)
		end
		local cash = player:GetAttribute("Cash")
		if typeof(cash) == "number" then
			if cash ~= lastCash then
				H:SetCash(cash, lastCash ~= nil and cash > lastCash)
				lastCash = cash
			end
		else
			H.CashLabel.Text = "$—"
		end
		local rate = player:GetAttribute("IncomePerSecond")
		H:SetRate(if typeof(rate) == "number" then rate else nil)
		local friend = player:GetAttribute("FriendBoostPercent")
		H:SetFriendBoost(if typeof(friend) == "number" then friend else nil)
		local plus = player:GetAttribute("PlusBoostPercent")
		H:SetPlusBoost(if typeof(plus) == "number" then plus else nil)
	end
	for _, name in
		{
			"PlayerLevel",
			"PlayerXp",
			"PlayerXpToNext",
			"Cash",
			"IncomePerSecond",
			"FriendBoostPercent",
			"PlusBoostPercent",
		}
	do
		player:GetAttributeChangedSignal(name):Connect(live)
	end

	local boardKey = ""
	local function refreshBoard()
		local list = Players:GetPlayers()
		table.sort(list, function(a, b)
			return (a:GetAttribute("IncomePerSecond") or 0 :: any)
				> (b:GetAttribute("IncomePerSecond") or 0 :: any)
		end)
		local rows = {}
		local parts = {}
		for position, other in list do
			-- Top four plus the player, so the panel never runs off a phone screen.
			if position <= 4 or other == player then
				local lv = other:GetAttribute("PlayerLevel")
				local rate = other:GetAttribute("IncomePerSecond")
				local row = {
					name = if other == player then "You" else other.DisplayName,
					lv = if typeof(lv) == "number" then lv else 0,
					rate = if typeof(rate) == "number" then rate else 0,
					me = other == player,
				}
				table.insert(rows, row)
				table.insert(parts, `{row.name}:{row.lv}:{string.format("%.2f", row.rate)}`)
			end
		end
		local key = table.concat(parts, ";")
		if key ~= boardKey then
			boardKey = key
			H:SetLeaderboard(rows)
		end
	end

	---------------------------------------------------------------------- Pets
	local petsKey, petsCtlKey = "", ""
	local petsAnimate = true
	local pendingTeam: any = nil
	local feedback: string? = nil
	local sale: any = nil
	local saleVersion = 0

	local function nextGain(pet: any): string?
		if pet.level >= Config.Progression.pet.maxLevel then
			return nil
		end
		local ok, now, later = pcall(function()
			return BattleMath.Stats(pet.speciesId, pet.level), BattleMath.Stats(pet.speciesId, pet.level + 1)
		end)
		if not ok then
			return nil
		end
		return `+{later.hp - now.hp} HP · +{later.attack - now.attack} Power`
	end
	local function petStats(pet: any, species: any): { any }
		local origin = pet.origin
		local battle = Config.Battle.species[pet.speciesId]
		return {
			{ k = "Species", v = shortName(species.displayName) },
			{ k = "Type", v = if battle and battle.type then tostring(battle.type) else "—" },
			{ k = "HP", v = `{pet.hp} / {pet.maxHp}` },
			{ k = "Power", v = tostring(pet.attack) },
			{ k = "Origin biome", v = species.biome or "—" },
			{ k = "Cash/s", v = `${Format.Short(pet.cashPerSecond)}` },
			{ k = "Original owner", v = if origin then origin.ownerName else "Unknown" },
			{ k = "Caught", v = if origin then origin.place else "Before records" },
		}
	end
	local function refreshPets()
		if Manager.Current ~= "pets" then
			return
		end
		local data = TabletData.Get()
		if Manager.Current ~= "pets" or not data then
			return
		end
		local snapshot, busy = actions.Read()
		local inBattle = player:GetAttribute("InBattle") == true
		if pendingTeam then
			local still
			for _, pet in data.pets do
				if pet.id == pendingTeam.id then
					still = pet
				end
			end
			if not still or still.state ~= pendingTeam.state then
				pendingTeam = nil
			elseif os.clock() - pendingTeam.at > 5 then
				pendingTeam = nil
				notify("Could not confirm team change. Try again.", "warning")
			end
		end
		local canSell = actions.Ready("quoteSell") and not pendingTeam and not inBattle
		local reason = feedback
			or if snapshot
					and snapshot.capabilities
					and snapshot.capabilities.quoteSell == true
				then nil
				else "Selling is unavailable now"
		local list, key, ctl = {}, {}, { tostring(canSell), tostring(reason) }
		local ordered = table.clone(data.pets)
		table.sort(ordered, function(a, b)
			return a.id < b.id
		end)
		for _, pet in ordered do
			local species = Config.Species[pet.speciesId]
			if species then
				local starter = species.rarity == "Starter"
				local eligible = pet.state == "InBase" or pet.state == "Following" or pet.state == "Inventory"
				local teamText = if pendingTeam and pendingTeam.id == pet.id
					then "Waiting…"
					elseif not eligible or busy or inBattle then "Unavailable"
					else nil
				table.insert(list, {
					id = pet.id,
					speciesId = pet.speciesId,
					stage = pet.stage,
					name = species.displayName,
					short = shortName(species.displayName),
					rarity = if starter then "Neutral" else species.rarity,
					starter = starter,
					lv = pet.level,
					isEq = pet.state == "Following",
					xp = math.floor(pet.xp),
					xpNeed = math.max(1, math.floor(pet.xpToNext)),
					nextGain = nextGain(pet),
					stats = petStats(pet, species),
					moves = pet.moves,
					teamText = teamText,
					canSell = canSell,
					reason = reason,
				})
				table.insert(key, `{pet.id}:{pet.level}:{pet.state}:{pet.stage}`)
				table.insert(ctl, `{pet.xp}:{teamText}`)
			end
		end
		local nextKey, nextCtl = table.concat(key, ";"), table.concat(ctl, ";")
		if nextKey ~= petsKey then
			petsKey, petsCtlKey = nextKey, nextCtl
			Pets:SetPets(
				list,
				Config.Gameplay.team.maxEquipped,
				Config.Progression.inventoryCapacity,
				petsAnimate
			)
			petsAnimate = false
		elseif nextCtl ~= petsCtlKey and Pets.Selected then
			petsCtlKey = nextCtl
			Pets._list = list
			Pets:Select(Pets.Selected)
		end
		local team = snapshot and snapshot.equipBest
		local canBest = actions.Ready("equipBest")
			and team ~= nil
			and team.canEquip == true
			and not pendingTeam
			and not inBattle
		Pets.BestBtn:SetEnabled(canBest)
		Pets.BestBtn:SetGrad(if canBest then Theme.Grad.Green else Theme.Grad.Grey)
		Pets.BestBtn:SetText(if busy and busy.kind == "equipBest" then "EQUIPPING…" else "EQUIP BEST")
	end
	local function refreshSale()
		if not sale then
			return
		end
		local _, busy, status = actions.Read()
		local quote = sale.quote
		local valid = ActionState.ValidQuote(quote, sale.id, Workspace:GetServerTimeNow())
		local sending = busy ~= nil and busy.kind == "sellPet"
		local kind = if valid then "sellPet" else "quoteSell"
		Pets:SetSale({
			value = if valid then `+${quote.totalCash}` else "…",
			breakdown = if sale.message and sale.message ~= ""
				then sale.message
				elseif quote and not valid then ActionState.Message("QUOTE_EXPIRED")
				elseif quote then `Rarity ${quote.rarityBase} + level bonus ${quote.levelBonus}`
				elseif status ~= "Ready" then actions.ErrorText()
				else "Checking the price with the server…",
			caution = if sending
				then "Closing this does not cancel a sale already sent."
				else "This can't be undone.",
			confirmText = if busy then "Waiting…" elseif valid then "Sell" else "Check price",
			canConfirm = not pendingTeam and actions.Ready(kind),
			cancelText = if sending then "Close" else "Cancel",
		})
	end
	local function requestQuote()
		if not sale or pendingTeam then
			return
		end
		local context, version = sale, saleVersion
		context.quote, context.message = nil, ""
		actions.Request("quoteSell", { petId = context.id }, function(result: any)
			if sale ~= context or saleVersion ~= version then
				return
			end
			if result.phase == "Quoted" then
				context.quote = result.quote
			else
				context.message = ActionState.Message(result.reasonCode)
			end
			refreshSale()
		end)
		refreshSale()
	end
	local function dismissSale()
		saleVersion += 1
		sale = nil
	end
	Pets.EquipToggle:Connect(function(id: string)
		local data = TabletData.Get()
		local target
		for _, pet in (data and data.pets or {}) :: any do
			if pet.id == id then
				target = pet
			end
		end
		local _, busy = actions.Read()
		if not target or pendingTeam or busy or sale or player:GetAttribute("InBattle") == true then
			return
		end
		if target.state ~= "InBase" and target.state ~= "Following" and target.state ~= "Inventory" then
			return
		end
		pendingTeam = { id = target.id, state = target.state, at = os.clock() }
		Remotes.Get("SetEquipped"):FireServer(target.id, target.state ~= "Following")
		TabletData.Invalidate()
		task.spawn(refreshPets)
	end)
	Pets.EquipBest:Connect(function()
		feedback = nil
		actions.Request("equipBest", {}, function(result: any)
			if result.phase == "Committed" then
				TabletData.Invalidate()
				notify("Best combat team equipped.", "success")
			else
				feedback = ActionState.Message(result.reasonCode)
			end
			task.spawn(refreshPets)
		end)
	end)
	Pets.SellRequested:Connect(function(id: string)
		local pet
		for _, entry in Pets._list do
			if entry.id == id then
				pet = entry
			end
		end
		if not pet or pendingTeam then
			return
		end
		saleVersion += 1
		sale = { id = pet.id, name = pet.name, level = pet.lv }
		requestQuote()
	end)
	Pets.SellCancelled:Connect(dismissSale)
	Pets.SellConfirmed:Connect(function()
		if not sale or pendingTeam then
			return
		end
		local context, version = sale, saleVersion
		if not ActionState.ValidQuote(context.quote, context.id, Workspace:GetServerTimeNow()) then
			requestQuote()
			return
		end
		local quote = context.quote
		actions.Request("sellPet", { petId = context.id, quoteId = quote.quoteId }, function(result: any)
			if result.phase == "Committed" then
				TabletData.Invalidate()
				notify(`Sold {context.name} for ${quote.totalCash} Cash.`, "success")
				if sale == context and saleVersion == version then
					dismissSale()
					Pets:CloseSale()
				end
			elseif sale == context and saleVersion == version then
				-- Every refusal requires a fresh quote and a new explicit confirmation.
				context.message = ActionState.Message(result.reasonCode)
				context.quote = nil
				refreshSale()
			end
			task.spawn(refreshPets)
		end)
		refreshSale()
	end)

	--------------------------------------------------------------------- Index
	local indexKey = ""
	local function refreshIndex()
		if Manager.Current ~= "index" then
			return
		end
		local data = TabletData.Get()
		if Manager.Current ~= "index" or not data then
			return
		end
		local ids = {}
		for id in Config.Species do
			table.insert(ids, id)
		end
		table.sort(ids, function(a, b)
			local sa, sb = Config.Species[a], Config.Species[b]
			local oa = Config.Rarities[sa.rarity].order
			local ob = Config.Rarities[sb.rarity].order
			local ga = GROUP_ORDER[sa.biome or "Neutral"] or 9
			local gb = GROUP_ORDER[sb.biome or "Neutral"] or 9
			if ga ~= gb then
				return ga < gb
			end
			if oa ~= ob then
				return oa < ob
			end
			return a < b
		end)
		local entries, parts = {}, {}
		for _, id in ids do
			local species = Config.Species[id]
			local entry = data.index[id]
			local caught = entry ~= nil and (entry.caught or 0) > 0
			local seen = entry ~= nil and entry.seen == true
			local state = if caught then "c" elseif seen then "s" else "u"
			table.insert(entries, {
				speciesId = id,
				name = shortName(species.displayName),
				group = species.biome or "Neutral",
				rarity = if species.rarity == "Starter" then "Neutral" else species.rarity,
				state = state,
			})
			table.insert(parts, `{id}:{state}`)
		end
		local key = table.concat(parts, ";")
		if key ~= indexKey then
			indexKey = key
			Index:SetEntries(entries)
		end
	end

	---------------------------------------------------------------------- Shop
	local shopKey = ""
	local function refreshShop()
		if Manager.Current ~= "shop" then
			return
		end
		local snapshot, pending, status = actions.Read()
		local capsule = snapshot and snapshot.capsule
		local valid = type(capsule) == "table"
			and ActionState.Integer(capsule.unitPrice)
			and capsule.unitPrice > 0
			and type(capsule.priceVersion) == "string"
			and #capsule.priceVersion > 0
			and #capsule.priceVersion <= 64
		local canBuy = valid and capsule.canBuy == true and actions.Ready("buyCapsule")
		local owned = if capsule and ActionState.Integer(capsule.stock)
			then `You have {capsule.stock}`
			else "You have —"
		local label = if pending
			then "Checking…"
			elseif canBuy then `Buy 1 · ${capsule.unitPrice}`
			elseif status == "Loading" then "Loading…"
			else "Unavailable"
		local note = if pending
			then "Waiting for server confirmation…"
			elseif status ~= "Ready" then actions.ErrorText()
			elseif not valid then "Price is currently unavailable."
			elseif capsule.canBuy ~= true then ActionState.Message(capsule.reasonCode or "UNAVAILABLE")
			else ""
		local key = `{owned}|{label}|{note}|{canBuy}`
		if key == shopKey then
			return
		end
		shopKey = key
		Shop:SetProducts({
			{
				id = "capsule",
				name = "Pet Capsule",
				sub = owned,
				price = label,
				c1 = Theme.hex("5CB8FF"),
				c2 = Theme.hex("2F86E8"),
				icon = "petCapsuleDefault",
				desc = "Throw it in a battle to catch the wild pet. Weaker pets are easier to catch.",
				owned = owned,
				buyLabel = label,
				note = note,
				enabled = canBuy,
			},
			-- Future slots keep the design's structure: no SKU, price, prompt or tap.
			{
				id = "p2",
				name = "Product",
				sub = "A definir",
				price = "Soon",
				c1 = Theme.hex("C58BFF"),
				c2 = Theme.hex("8A45E0"),
				placeholder = true,
				flagText = "placeholder",
			},
			{
				id = "p3",
				name = "Product",
				sub = "A definir",
				price = "Soon",
				c1 = Theme.hex("FF9AD4"),
				c2 = Theme.hex("E0449D"),
				placeholder = true,
				flagText = "placeholder",
			},
		})
	end
	Shop:SetCodesEnabled(false)
	Shop.BuyRequested:Connect(function(id: string)
		local snapshot = actions.Read()
		local capsule = snapshot and snapshot.capsule
		if
			id ~= "capsule"
			or not capsule
			or capsule.canBuy ~= true
			or type(capsule.priceVersion) ~= "string"
		then
			return
		end
		actions.Request(
			"buyCapsule",
			{ quantity = 1, priceVersion = capsule.priceVersion },
			function(result: any)
				if result.phase == "Committed" then
					notify("+1 Pet Capsule", "success")
				else
					notify(ActionState.Message(result.reasonCode), "warning")
				end
				-- Cash and stock always come from the next authoritative snapshot.
				actions.Refresh(true)
			end
		)
		refreshShop()
	end)

	------------------------------------------------------------------ Research
	local researchPending: number? = nil
	local function researchProgress()
		local progress = {}
		local active = player:GetAttribute("ResearchActive")
		local finish = player:GetAttribute("ResearchFinishesAt")
		for id in Config.Research do
			local rank = player:GetAttribute(`Research_{id}`)
			local entry: any = { level = if typeof(rank) == "number" then rank else 0 }
			if active == id and typeof(finish) == "number" then
				entry.activeLevel = entry.level + 1
				entry.finishesAt = finish
			end
			progress[id] = entry
		end
		return progress, math.floor(Workspace:GetServerTimeNow())
	end
	local function refreshResearchTimer()
		local finish = player:GetAttribute("ResearchFinishesAt")
		local active = player:GetAttribute("ResearchActive")
		if typeof(finish) == "number" and typeof(active) == "string" and active ~= "" then
			local left = math.floor(finish - Workspace:GetServerTimeNow())
			H:SetResearchTimer(if left > 0 then left else nil)
		else
			H:SetResearchTimer(nil)
		end
	end
	local function refreshResearch()
		if Manager.Current ~= "research" then
			return
		end
		local progress, now = researchProgress()
		local money = player:GetAttribute("Cash")
		local level = player:GetAttribute("PlayerLevel")
		local ready = player:GetAttribute("DataLoaded") == true and typeof(level) == "number"
		local activeId, _ = ResearchMath.Active(progress, now)
		if researchPending and (activeId or os.clock() - researchPending > 4) then
			researchPending = nil
		end
		local nodes = {}
		local activeState: any = false
		for slot, id in RESEARCH_NODES do
			local node = Config.Research[id]
			if node then
				local rank = ResearchMath.LevelOf(progress, id, now)
				local nextRank = node.levels[rank + 1]
				local blocked: string? = nil
				if nextRank then
					local required = Progression.ResearchLevel(id, rank + 1)
					if not ready then
						blocked = "Loading…"
					elseif (level :: number) < required then
						blocked = `Player Lv {required}`
					elseif not ResearchMath.IsUnlocked(progress, id, now) then
						blocked = "Locked"
					elseif researchPending then
						blocked = "Waiting…"
					elseif typeof(money) ~= "number" or money < nextRank.cost then
						blocked = `Need ${Format.Short(nextRank.cost)}`
					end
				end
				nodes[slot] = {
					name = node.displayName,
					desc = if nextRank
						then `Next: {ResearchMath.Describe(id, rank + 1)}`
						else ResearchMath.Describe(id, rank),
					level = rank,
					max = #node.levels,
					cost = if nextRank then nextRank.cost else 0,
					durationText = if nextRank
						then Format.Duration(ResearchMath.Duration(progress, id, rank + 1, now))
						else "",
					blocked = blocked,
				}
				if activeId == id then
					local total = ResearchMath.Duration(progress, id, rank + 1, now)
					local finish = player:GetAttribute("ResearchFinishesAt")
					local left = if typeof(finish) == "number"
						then math.max(0, math.floor(finish - now))
						else 0
					activeState = { id = slot, left = left, total = math.max(1, total, left) }
				end
			end
		end
		Research:SetState({
			cash = if typeof(money) == "number" then money else 0,
			rate = player:GetAttribute("IncomePerSecond") or 0,
			nodes = nodes,
			active = activeState,
		})
	end
	Research.ResearchRequested:Connect(function(slot: string)
		local id = RESEARCH_NODES[slot]
		if id and not researchPending then
			researchPending = os.clock()
			Remotes.Get("StartResearch"):FireServer(id)
			refreshResearch()
		end
	end)

	--------------------------------------------------------------------- Trade
	local tradeState: any = nil
	local waiting: { [number]: boolean } = {}
	local lobbyKey = ""
	local function refreshLobby()
		if Manager.Current ~= "trade" then
			return
		end
		local list, parts = {}, {}
		local others = Players:GetPlayers()
		table.sort(others, function(a, b)
			return a.UserId < b.UserId
		end)
		for _, other in others do
			if other ~= player then
				local rate = other:GetAttribute("IncomePerSecond")
				local colour = LOBBY_COLOURS[other.UserId % #LOBBY_COLOURS + 1]
				table.insert(list, {
					name = other.DisplayName,
					userId = other.UserId,
					rate = if typeof(rate) == "number" then rate else nil,
					color = Theme.hex(colour),
					waiting = waiting[other.UserId] == true,
				})
				table.insert(parts, `{other.UserId}:{rate}:{waiting[other.UserId]}`)
			end
		end
		local key = table.concat(parts, ";")
		if key ~= lobbyKey or #list == 0 then
			lobbyKey = key
			Lobby:SetPlayers(list)
		end
	end
	local function tradeAction(payload: { [string]: any })
		Remotes.Get("TradeAction"):FireServer(payload)
	end
	local function petEntry(pet: any): any
		local species = Config.Species[pet.speciesId]
		return { id = pet.id, name = shortName(species and species.displayName or "Pet"), lv = pet.level }
	end
	local function refreshRoom()
		local state = tradeState
		if not state or not state.active then
			return
		end
		local mine, offered = {}, {}
		for _, pet in state.mine do
			offered[pet.id] = true
			table.insert(mine, petEntry(pet))
		end
		local theirs = {}
		for _, pet in state.theirs do
			table.insert(theirs, petEntry(pet))
		end
		local myPets = {}
		local data = TabletData.Get()
		for _, pet in (data and data.pets or {}) :: any do
			if pet.state == "InBase" or offered[pet.id] then
				local entry = petEntry(pet)
				entry.inTrade = offered[pet.id] == true
				table.insert(myPets, entry)
			end
		end
		local note, noteColor = "Add pets, then press Ready.", Theme.Colors.Muted
		if state.note then
			note, noteColor = state.note, Theme.Colors.Gold
		elseif state.myConfirm and not state.theirConfirm then
			note = `Waiting for {state.partner} to confirm…`
		elseif state.myReady and state.theirReady then
			note, noteColor = "Both ready! Press Confirm.", Theme.Colors.Cash
		elseif state.myReady then
			note = `Waiting for {state.partner} to get ready…`
		end
		Room:SetState({
			partner = state.partner,
			mine = mine,
			theirs = theirs,
			myPets = myPets,
			ready = state.myReady,
			pReady = state.theirReady,
			conf = state.myConfirm,
			pConf = state.theirConfirm,
			note = note,
			noteColor = noteColor,
		})
		if not state.countdown then
			Room:HideCount()
		end
	end
	Remotes.Get("TradeUpdate").OnClientEvent:Connect(function(state: any)
		local started = state.active and not (tradeState and tradeState.active)
		tradeState = state
		if started then
			table.clear(waiting)
			TabletData.Invalidate()
			if player:GetAttribute("InBattle") ~= true then
				refreshRoom()
				Manager:Open("traderoom")
			end
		elseif state.active then
			refreshRoom()
		else
			TabletData.Invalidate()
			Room:HideCount()
			if Manager.Current == "traderoom" then
				Manager:Close()
			end
			if state.note then
				notify(state.note, "info")
			end
		end
		if state.active and state.countdown then
			task.spawn(function()
				local endsAt = os.clock() + state.countdown
				while tradeState == state and os.clock() < endsAt do
					Room:ShowCount(
						"Trading in…",
						tostring(math.ceil(endsAt - os.clock())),
						Theme.Colors.White
					)
					task.wait(1)
				end
			end)
		end
	end)
	Lobby.TradeRequested:Connect(function(userId: number)
		if player:GetAttribute("TradeUnlocked") ~= true then
			notify("Trading is not available yet.", "locked")
			return
		end
		Remotes.Get("TradeRequest"):FireServer(userId)
		waiting[userId] = true
		refreshLobby()
		task.delay(Config.Gameplay.trade.requestSeconds, function()
			if waiting[userId] then
				waiting[userId] = nil
				refreshLobby()
			end
		end)
	end)
	Lobby.TradeCancelled:Connect(function(userId: number)
		waiting[userId] = nil
		refreshLobby()
	end)
	Room.AddPet:Connect(function(id: string)
		tradeAction({ kind = "add", id = id })
	end)
	Room.RemovePet:Connect(function(id: string)
		tradeAction({ kind = "remove", id = id })
	end)
	Room.ReadyToggled:Connect(function()
		tradeAction({ kind = "ready" })
	end)
	Room.ConfirmPressed:Connect(function()
		tradeAction({ kind = "confirm" })
	end)
	Room.CancelPressed:Connect(function()
		if tradeState and tradeState.active then
			tradeAction({ kind = "cancel" })
		elseif Manager.Current == "traderoom" then
			Manager:Close()
		end
	end)
	Players.PlayerAdded:Connect(function()
		refreshLobby()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshLobby)
	end)

	------------------------------------------------------------------ Settings
	local music, sfx = Sfx.Group("Music"), Sfx.Group("SFX")
	local musicVolume = if music.Volume > 0 then music.Volume else 1
	local sfxVolume = if sfx.Volume > 0 then sfx.Volume else 1
	local showLabels = true
	local PET_LABELS = { IncomeLabel = true, LooseLabel = true }
	local function applyLabel(gui: Instance)
		if gui:IsA("BillboardGui") and PET_LABELS[gui.Name] then
			gui.Enabled = showLabels
		end
	end
	task.spawn(function()
		local animals = Workspace:WaitForChild("Animals", 15)
		if animals then
			animals.DescendantAdded:Connect(function(gui)
				if not showLabels then
					task.defer(applyLabel, gui)
				end
			end)
		end
	end)
	Settings:SetRows({
		{ key = "music", label = "Music", value = music.Volume > 0 },
		{ key = "sfx", label = "Sound Effects", value = sfx.Volume > 0 },
		{ key = "labels", label = "Pet labels", value = true },
		{
			key = "shortIntro",
			label = "Short battle intro",
			value = (BattleSettings :: any).shortIntro == true,
		},
		{ key = "cameraShake", label = "Camera shake", value = (BattleSettings :: any).cameraShake == true },
	})
	Settings.Changed:Connect(function(key: string, value: boolean)
		if key == "music" then
			music.Volume = if value then musicVolume else 0
		elseif key == "sfx" then
			sfx.Volume = if value then sfxVolume else 0
		elseif key == "labels" then
			showLabels = value
			local animals = Workspace:FindFirstChild("Animals")
			if animals then
				for _, gui in animals:GetDescendants() do
					applyLabel(gui)
				end
			end
		else
			(BattleSettings :: any)[key] = value
		end
	end)

	---------------------------------------------------------------- navigation
	local function refreshCurrent()
		local current = Manager.Current
		if current == "pets" then
			task.spawn(refreshPets)
			refreshSale()
		elseif current == "index" then
			task.spawn(refreshIndex)
		elseif current == "shop" then
			refreshShop()
		elseif current == "research" then
			refreshResearch()
		elseif current == "trade" then
			refreshLobby()
		elseif current == "traderoom" then
			task.spawn(refreshRoom)
		end
	end
	local function open(name: string)
		if player:GetAttribute("InBattle") == true or GuiService.MenuIsOpen then
			return
		end
		local required = if name == "research"
			then Config.Progression.unlocks.Research
			elseif name == "trade" then Config.Progression.unlocks.Trade
			else nil
		if required then
			local level = player:GetAttribute("PlayerLevel")
			if typeof(level) ~= "number" or level < required then
				H:ShakeTile(name)
				notify(
					if typeof(level) == "number"
						then `Reach Player Lv {required} to unlock`
						else "Loading your progress…",
					"locked"
				)
				return
			end
		end
		if name == "trade" and tradeState and tradeState.active then
			name = "traderoom"
		end
		Manager:Open(name)
	end
	Manager.Opened:Connect(function(name: string)
		player:SetAttribute("MenuOpen", true)
		TabletData.Invalidate()
		if name == "pets" then
			petsKey, petsAnimate = "", true
			feedback = nil
			actions.Refresh(true)
		elseif name == "index" then
			indexKey = ""
			Index._animate = true
		elseif name == "shop" then
			shopKey = ""
			Shop._animate = true
			Shop._scroll.CanvasPosition = Vector2.zero
			actions.Refresh(true)
		elseif name == "trade" then
			lobbyKey = ""
			Lobby._animate = true
		end
		refreshCurrent()
	end)
	Manager.Closed:Connect(function()
		player:SetAttribute("MenuOpen", false)
		dismissSale()
	end)
	H.Pets:Connect(function()
		open("pets")
	end)
	H.Index:Connect(function()
		open("index")
	end)
	H.Research:Connect(function()
		open("research")
	end)
	H.Trade:Connect(function()
		open("trade")
	end)
	H.Shop:Connect(function()
		open("shop")
	end)
	H.Settings:Connect(function()
		open("settings")
	end)
	H.Base:Connect(function()
		notify("Base travel is not available from this button yet.", "info")
	end)
	H.News:Connect(function()
		notify("No news right now.", "info")
	end)
	player:GetAttributeChangedSignal("InBattle"):Connect(function()
		if player:GetAttribute("InBattle") == true then
			if Manager.Current == "traderoom" then
				tradeAction({ kind = "cancel" })
			end
			Manager:Close()
			H:SetShown(false)
		elseif not Manager.Current then
			H:SetShown(true)
		end
	end)
	ContextActionService:BindAction("DesignHudPets", function(_, state)
		if
			state ~= Enum.UserInputState.Begin
			or UserInputService:GetFocusedTextBox()
			or GuiService.MenuIsOpen
		then
			return Enum.ContextActionResult.Pass
		end
		open("pets")
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.T)
	local boardOpen = true
	H.LeaderboardToggled:Connect(function(value: boolean)
		boardOpen = value
		H.BoardOpen = value
	end)
	ContextActionService:BindAction("DesignHudLeaderboard", function(_, state)
		if
			state ~= Enum.UserInputState.Begin
			or UserInputService:GetFocusedTextBox()
			or GuiService.MenuIsOpen
		then
			return Enum.ContextActionResult.Pass
		end
		H:SetLeaderboardOpen(not boardOpen)
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Tab)

	--------------------------------------------------------- server broadcasts
	actions.Subscribe(function()
		if Manager.Current == "pets" then
			task.spawn(refreshPets)
			refreshSale()
		elseif Manager.Current == "shop" then
			refreshShop()
		end
	end)
	local confirmations = HudState.NewConfirmations()
	Remotes.Get("ProgressionChanged").OnClientEvent:Connect(function(snapshot: any)
		-- A save fires after every reward. It refreshes the screen; a pop-up per save would stop play.
		if HudState.AcceptConfirmation(confirmations, snapshot) then
			refreshCurrent()
		end
	end)
	Notifications.SetPresenter(function(notification: any)
		local action = notification.action
		-- Only these two take the screen; everything else is a line of text at the top.
		if action and action.kind == "trade" then
			Popups:Push("trade", {
				text = notification.text,
				duration = Config.Gameplay.trade.requestSeconds,
				onAction = function()
					Remotes.Get("TradeRespond"):FireServer(action.animalId)
				end,
			})
		elseif notification.icon == "offline" then
			Popups:Push("offline", { text = notification.text })
		else
			Notices:Push(notification.text, notification.icon, notification.kind)
		end
	end)

	-- World actions: ContextActions keeps every rule; the design's button only presents them.
	H.ActionPress:Connect(function()
		ContextActions.Press()
	end)
	H.Action:Connect(function()
		ContextActions.Activate()
	end)
	H.ActionNext:Connect(function()
		ContextActions.Next()
	end)
	ContextActions.SetPresenter(function(view: any)
		if not view then
			H:SetProximity(nil)
			return
		end
		local kind = if view.kind == "heal"
			then "Heal team"
			elseif string.sub(view.label, 1, 5) == "Catch" then "Catch"
			else "Battle"
		H:SetProximity(kind, view.name)
		H.ProxHint.Text = if view.kind == "heal" then "" else "Wild ·"
		H.ProxHint.Visible = view.kind ~= "heal"
		H.ActionBtn:SetText(if view.enabled then view.label else "Waiting…")
		H.ActionBtn:SetEnabled(view.enabled)
		if not view.enabled then
			H.ActionBtn:SetGrad(Theme.Grad.Grey)
		end
		H:SetActionNext(if view.nextVisible then view.nextText else nil)
	end)

	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	-- The HTML's Boosts sit where Roblox's Jump button is: lift Jump clear of them on touch screens.
	local function liftJump(touchGui: Instance)
		local frame = touchGui:WaitForChild("TouchControlFrame", 10)
		if not frame then
			return
		end
		local function watch(jump: GuiObject)
			local lifted: UDim2? = nil
			local function apply()
				-- Roblox re-places Jump when the viewport changes; only that position is lifted again.
				if jump.Position ~= lifted then
					lifted = jump.Position + UDim2.fromOffset(0, -46)
					jump.Position = lifted :: UDim2
				end
			end
			jump:GetPropertyChangedSignal("Position"):Connect(apply)
			apply()
		end
		frame.ChildAdded:Connect(function(child)
			if child.Name == "JumpButton" and child:IsA("GuiObject") then
				watch(child)
			end
		end)
		local jump = frame:FindFirstChild("JumpButton")
		if jump and jump:IsA("GuiObject") then
			watch(jump)
		end
	end
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "TouchGui" then
			task.spawn(liftJump, child)
		end
	end)
	local existingTouch = playerGui:FindFirstChild("TouchGui")
	if existingTouch then
		task.spawn(liftJump, existingTouch)
	end
	if Config.Debug.enabled then
		-- Studio QA only: lets a playtest drive and inspect the live screens.
		DesignHud.QA = { Open = open, Manager = Manager, H = H, Pets = Pets, Shop = Shop, Index = Index, Lobby = Lobby, Research = Research, Settings = Settings, Popups = Popups, Notices = Notices }
	end
	live()
	H:SetShown(player:GetAttribute("InBattle") ~= true)
	task.spawn(function()
		while true do
			local ending = Workspace:GetAttribute("DayEndsAt")
			if typeof(ending) == "number" then
				H:SetDay(math.max(0, math.floor(ending - Workspace:GetServerTimeNow())))
			end
			refreshBoard()
			refreshResearchTimer()
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			H:SetSpeed(if humanoid then humanoid.WalkSpeed else nil)
			local current = Manager.Current
			if current == "pets" or current == "shop" or select(2, actions.Read()) then
				actions.Refresh()
			end
			if current ~= "traderoom" then
				refreshCurrent()
			end
			task.wait(1)
		end
	end)
end

return DesignHud
