--!strict
-- Nova v1 endpoints. One-profile mutations + receipt saved together. No trades,
-- Robux or code rewards. Memory-only caches are never evidence of commitment.
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Config = require(RS.Shared.Config)
local Remotes = require(RS.Shared.Remotes)
local BattleMath = require(RS.Shared.BattleMath)
local PlayerData = require(script.Parent.PlayerDataService)
local PlayerState = require(script.Parent.PlayerStateService)
local Animals = require(script.Parent.AnimalService)
local Home = require(script.Parent.HomeService)
local Team = require(script.Parent.TeamService)
local Trade = require(script.Parent.TradeService)
local Guard = require(script.Parent.PlayerMutationGuard)
local Service = {}
local sessions: { [Player]: any } = {}
local kinds = { equipBest = true, quoteSell = true, sellPet = true, buyCapsule = true }
local function integer(n: any): boolean
	return type(n) == "number" and n == n and n >= 0 and n < math.huge and n % 1 == 0
end
local function textId(id: any, limit: number): boolean
	return type(id) == "string" and #id > 0 and #id <= limit and utf8.len(id) ~= nil
end
local function guid(id: any): boolean
	return textId(id, 36)
		and #id == 36
		and string.match(id, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")
			~= nil
end
local function session(player: Player): any
	if not sessions[player] then
		sessions[player] =
			{ revision = 0, lastRead = -math.huge, lastAction = -math.huge, quotes = {}, pending = nil }
	end
	return sessions[player]
end
local function priceVersion(): string
	return `capsule-v1-{Config.Battle.capsule.price}`
end
local function receiptCount(data: any): number
	local count = 0
	for _ in data.commerce.receipts do
		count += 1
	end
	return count
end
local function reason(player: Player, data: any): string?
	if not Config.Commerce.enabled then
		return "UNAVAILABLE"
	end
	if not data or not PlayerData.IsReady(player) then
		return "LOADING"
	end
	if player:GetAttribute("InBattle") then
		return "IN_BATTLE"
	end
	if Trade.IsTrading(player) then
		return "IN_TRADE"
	end
	if Guard.IsBusy(player) then
		return "SAVE_PENDING"
	end
	if receiptCount(data) >= Config.Commerce.maxReceipts then
		return "CAPACITY_REACHED"
	end
	return nil
end
local function ranked(player: Player, data: any): { any }
	local list = {}
	for id, saved in data.animals do
		local record = Animals.Get(id)
		if
			record
			and record.ownerUserId == player.UserId
			and not saved.unavailableReason
			and Config.Battle.species[record.speciesId]
			and (record.state == "Inventory" or record.state == "InBase" or record.state == "Following")
		then
			local stats = BattleMath.Stats(record.speciesId, record.level)
			if (record.hp or stats.hp) > 0 then
				table.insert(
					list,
					{ record = record, score = stats.hp + stats.attack + stats.defense + stats.speed }
				)
			end
		end
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		if a.record.level ~= b.record.level then
			return a.record.level > b.record.level
		end
		return a.record.id < b.record.id
	end)
	local selected = {}
	for i = 1, math.min(#list, Config.Gameplay.team.maxEquipped) do
		table.insert(selected, list[i].record)
	end
	return selected
end
local function sale(player: Player, data: any, petId: string): (any, string?)
	local saved, record = data.animals[petId], Animals.Get(petId)
	if not saved or not record then
		return nil, "PET_NOT_FOUND"
	end
	if record.ownerUserId ~= player.UserId or saved.speciesId ~= record.speciesId then
		return nil, "NOT_OWNER"
	end
	if record.state ~= "InBase" and record.state ~= "Inventory" and record.state ~= "Following" then
		return nil, "PET_UNAVAILABLE"
	end
	local species = Config.Species[record.speciesId]
	if saved.unavailableReason or not species then
		return nil, "PET_UNAVAILABLE"
	end
	local count = 0
	for _, pet in data.animals do
		if not pet.unavailableReason and Config.Battle.species[pet.speciesId] then
			count += 1
		end
	end
	if Config.Commerce.keepLastPet and count <= 1 then
		return nil, "LAST_PET"
	end
	local base = Config.Commerce.rarityBase[species.rarity]
	if not integer(base) or not integer(record.level) or record.level < 1 then
		return nil, "PET_UNAVAILABLE"
	end
	local bonus = (record.level - 1) * Config.Commerce.perLevel
	return { record = record, rarityBase = base, levelBonus = bonus, totalCash = base + bonus }, nil
end
local snapshot: (Player, any?) -> any
local function outcome(player: Player, receipt: any): any
	local saved = PlayerData.GetCommitted(player)
	local durable = saved and saved.commerce and saved.commerce.receipts[receipt.requestId]
	local confirmed = durable and durable.revision == receipt.revision and durable.kind == receipt.kind
	if confirmed then
		Guard.Release(player, receipt.requestId)
		if session(player).pending == receipt.requestId then
			session(player).pending = nil
		end
	end
	return {
		requestId = receipt.requestId,
		kind = receipt.kind,
		phase = if confirmed then receipt.phase else "Pending",
		reasonCode = if confirmed then receipt.reasonCode else "SAVE_PENDING",
		committedRevision = if confirmed and receipt.phase == "Committed" then receipt.revision else nil,
	}
end
snapshot = function(player: Player, pendingId: any): any
	local data = PlayerData.Get(player)
	if not data or not PlayerData.IsReady(player) then
		return nil
	end
	local s = session(player)
	local result = if guid(pendingId) and data.commerce.receipts[pendingId]
		then outcome(player, data.commerce.receipts[pendingId])
		elseif s.quoteResult and s.quoteResult.requestId == pendingId then table.clone(s.quoteResult)
		else nil
	local block = reason(player, data)
	local equipReason = block or (if #ranked(player, data) == 0 then "NO_ELIGIBLE_PETS" else nil)
	local price = Config.Battle.capsule.price
	local buyReason = block
	if not buyReason then
		if not integer(price) or price <= 0 or not integer(data.capsules) or data.capsules >= 2147483647 then
			buyReason = "CAPACITY_REACHED"
		elseif data.cash < price then
			buyReason = "NOT_ENOUGH_CASH"
		end
	end
	-- Fingerprint only observable fields, including quote/receipt transitions.
	local fingerprint =
		`{data.commerce.revision}/{data.cash}/{data.capsules}/{price}/{tostring(block)}/{tostring(equipReason)}/{tostring(
			buyReason
		)}/{tostring(result and result.phase)}/{tostring(result and result.requestId)}/{tostring(
			result and result.reasonCode
		)}`
	if fingerprint ~= s.fingerprint then
		s.revision += 1
		s.fingerprint = fingerprint
	end
	local view = {
		schemaVersion = 1,
		revision = s.revision,
		ready = true,
		capabilities = {
			equipBest = Config.Commerce.enabled,
			quoteSell = Config.Commerce.enabled,
			sellPet = Config.Commerce.enabled,
			buyCapsule = Config.Commerce.enabled,
		},
		equipBest = { canEquip = equipReason == nil, reasonCode = equipReason },
		capsule = {
			unitPrice = price,
			priceVersion = priceVersion(),
			stock = data.capsules,
			canBuy = buyReason == nil,
			reasonCode = buyReason,
		},
		requestResult = result,
	}
	if result then
		result.snapshot = table.clone(view)
		result.snapshot.requestResult = nil
	end
	return view
end
local function emit(player: Player, result: any)
	result.snapshot = snapshot(player, nil) -- never recursively embed requestResult
	Remotes.Get("HudCommerceResult"):FireClient(player, result)
end
local function remember(player: Player, data: any, intent: any, phase: string, code: string?)
	local s = session(player)
	data.commerce.revision += 1
	local receipt = {
		requestId = intent.requestId,
		kind = intent.kind,
		phase = phase,
		reasonCode = code,
		revision = data.commerce.revision,
	}
	data.commerce.receipts[intent.requestId] = receipt
	s.pending = intent.requestId
	-- Keep the guard across unknown save outcomes, including callback timeout.
	PlayerData.SaveConfirmed(player, function(saved)
		local r = saved.commerce.receipts[intent.requestId]
		return r ~= nil and r.revision == receipt.revision
	end, function()
		emit(player, outcome(player, receipt))
	end)
	emit(player, outcome(player, receipt))
end
local function action(player: Player, intent: any)
	if
		type(intent) ~= "table"
		or not guid(intent.requestId)
		or type(intent.kind) ~= "string"
		or not kinds[intent.kind]
	then
		return
	end
	local s = session(player)
	if os.clock() - s.lastAction < 0.25 then
		return
	end
	s.lastAction = os.clock()
	local data = PlayerData.Get(player)
	if not data or not PlayerData.IsReady(player) then
		return
	end -- unknown outcome is never a terminal rejection
	if s.quoteResult and s.quoteResult.requestId == intent.requestId then
		emit(player, table.clone(s.quoteResult))
		return
	end
	local previous = data.commerce.receipts[intent.requestId]
	if previous then
		-- Same GUID always refers to the original intent, even with tampered fields.
		emit(player, outcome(player, previous))
		return
	end
	-- A different intent cannot obtain a terminal rejection while a save is unknown:
	-- no ephemeral rejection can later turn into a successful replay.
	if Guard.IsBusy(player) then
		if not s.deferred or s.deferred.requestId == intent.requestId then
			s.deferred = { requestId = intent.requestId, kind = intent.kind }
			emit(player, {
				requestId = intent.requestId,
				kind = intent.kind,
				phase = "Pending",
				reasonCode = "SAVE_PENDING",
			})
		end
		return
	end
	if receiptCount(data) >= Config.Commerce.maxReceipts then
		-- This ledger is never pruned. Exhaustion can therefore never admit a late action.
		emit(player, {
			requestId = intent.requestId,
			kind = intent.kind,
			phase = "Rejected",
			reasonCode = "CAPACITY_REACHED",
		})
		return
	end
	local block = reason(player, data)
	if s.deferred and s.deferred.requestId == intent.requestId then
		block = "SAVE_PENDING"
		s.deferred = nil
	end
	if not Guard.Acquire(player, intent.requestId) then
		return
	end
	local function reject(code: string)
		remember(player, data, intent, "Rejected", code)
	end
	if block then
		reject(block)
		return
	end
	if intent.kind == "quoteSell" then
		if not textId(intent.petId, 128) then
			reject("PET_NOT_FOUND")
			return
		end
		local offer, code = sale(player, data, intent.petId)
		if not offer then
			reject(code or "PET_UNAVAILABLE")
			return
		end
		local quote = {
			quoteId = Http:GenerateGUID(false),
			petId = intent.petId,
			petLevel = offer.record.level,
			currency = "Cash",
			rarityBase = offer.rarityBase,
			levelBonus = offer.levelBonus,
			totalCash = offer.totalCash,
			expiresAt = Workspace:GetServerTimeNow() + Config.Commerce.quoteSeconds,
		}
		-- Bounded quote cache: one quote per profile; expired/replaced token cannot sell.
		s.quotes = {
			[quote.quoteId] = { view = quote, speciesId = offer.record.speciesId, state = offer.record.state },
		}
		Guard.Release(player, intent.requestId)
		s.quoteResult = { requestId = intent.requestId, kind = intent.kind, phase = "Quoted", quote = quote }
		emit(player, table.clone(s.quoteResult))
		return
	elseif intent.kind == "equipBest" then
		local selected = ranked(player, data)
		if #selected == 0 then
			reject("NO_ELIGIBLE_PETS")
			return
		end
		if not Team.Replace(player, selected) then
			reject("PET_UNAVAILABLE")
			return
		end
	elseif intent.kind == "buyCapsule" then
		if
			intent.quantity ~= 1
			or not textId(intent.priceVersion, 64)
			or intent.priceVersion ~= priceVersion()
		then
			reject("PRICE_CHANGED")
			return
		end
		local price = Config.Battle.capsule.price
		if not integer(price) or price <= 0 or not integer(data.capsules) or data.capsules >= 2147483647 then
			reject("CAPACITY_REACHED")
			return
		end
		if data.cash < price then
			reject("NOT_ENOUGH_CASH")
			return
		end
		data.cash -= price
		data.capsules += 1
	elseif intent.kind == "sellPet" then
		if not textId(intent.petId, 128) or not textId(intent.quoteId, 128) then
			reject("QUOTE_CHANGED")
			return
		end
		local entry = s.quotes[intent.quoteId]
		if not entry or entry.view.petId ~= intent.petId then
			reject("QUOTE_CHANGED")
			return
		end
		local q = entry.view
		if q.expiresAt <= Workspace:GetServerTimeNow() then
			reject("QUOTE_EXPIRED")
			return
		end
		local offer, code = sale(player, data, intent.petId)
		if not offer then
			reject(code or "PET_UNAVAILABLE")
			return
		end
		if
			q.petLevel ~= offer.record.level
			or q.rarityBase ~= offer.rarityBase
			or q.levelBonus ~= offer.levelBonus
			or entry.speciesId ~= offer.record.speciesId
			or entry.state ~= offer.record.state
		then
			reject("QUOTE_CHANGED")
			return
		end
		if data.cash + q.totalCash == math.huge then
			reject("CAPACITY_REACHED")
			return
		end
		Team.DetachForSale(player, offer.record)
		assert(Home.GiveAway(player, offer.record), "Validated sale lost its owned record")
		Animals.Remove(offer.record)
		data.cash += q.totalCash
		-- Quote is consumed logically with the receipt; same requestId replays it.
		s.quotes = {}
	end
	PlayerState.AddCash(player, 0) -- publish canonical Cash through its owner
	remember(player, data, intent, "Committed", nil)
end
function Service.Start()
	Remotes.Get("HudCommerceAction").OnServerEvent:Connect(action)
	Remotes.GetFunction("GetHudCommerce").OnServerInvoke = function(player, pendingId)
		local s = session(player)
		if os.clock() - s.lastRead < 0.5 then
			return nil
		end
		s.lastRead = os.clock()
		-- Reconcile the existing pending receipt first, including lost callbacks.
		if s.pending then
			snapshot(player, s.pending)
		end
		local view = snapshot(player, pendingId)
		if s.deferred and s.deferred.requestId == pendingId and not Guard.IsBusy(player) then
			local deferred = s.deferred
			local data = PlayerData.Get(player)
			if
				data
				and PlayerData.IsReady(player)
				and receiptCount(data) < Config.Commerce.maxReceipts
				and Guard.Acquire(player, deferred.requestId)
			then
				s.deferred = nil
				remember(player, data, deferred, "Rejected", "SAVE_PENDING")
				view = snapshot(player, pendingId)
			end
		end
		-- Unknown GUID has no terminal rejection: no delayed action is re-admitted.
		return view
	end
	PlayerData.OnReleasing(function(player)
		sessions[player] = nil
		Guard.Forget(player)
	end)
end
return Service
