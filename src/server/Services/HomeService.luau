--!strict
-- The player's base showcase: carried animals are deposited automatically
-- on the free slots when the carrier steps into their own base, and every
-- animal on a slot earns cash each tick. Animals in the base never grow.
-- Owned animals are written to the owner's save when they change hands;
-- growth and slot are refreshed right before every save.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimalMath = require(ReplicatedStorage.Shared.AnimalMath)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local ResearchMath = require(ReplicatedStorage.Shared.ResearchMath)
local AnimalService = require(script.Parent.AnimalService)
local BaseService = require(script.Parent.BaseService)
local CarryService = require(script.Parent.CarryService)
local IndexService = require(script.Parent.IndexService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

type AnimalRecord = AnimalService.AnimalRecord

local HomeService = {}

-- slotIndex -> record, per player
local slotsByPlayer: { [Player]: { [number]: AnimalRecord } } = {}

local function slotCount(player: Player): number
	local data = PlayerDataService.Get(player)
	return if data then data.baseSlots else Config.Economy.baseStartingSlots
end

-- Writes an owned animal into its owner's save.
local function saveAnimal(player: Player, record: AnimalRecord)
	local data = PlayerDataService.Get(player)
	if data and record.slot then
		-- Update in place: other services keep their own fields here (equipped, mutations).
		local saved = data.animals[record.id]
		if saved then
			saved.speciesId = record.speciesId
			saved.size = record.size
			saved.growth = record.growth
			saved.slot = record.slot :: number
			saved.origin = saved.origin or record.origin
			saved.level, saved.xp, saved.hp = record.level, record.xp, record.hp
		else
			data.animals[record.id] = {
				speciesId = record.speciesId,
				size = record.size,
				growth = record.growth,
				slot = record.slot :: number,
				origin = record.origin,
				level = record.level,
				xp = record.xp,
				hp = record.hp,
			}
		end
	end
end

-- Removes a stolen animal from the victim's save: directly when they are in
-- this server, otherwise through a profile message delivered when they load.
local function forgetAnimal(userId: number, animalId: string)
	local victim = Players:GetPlayerByUserId(userId)
	local data = victim and PlayerDataService.Get(victim)
	if data then
		data.animals[animalId] = nil
		return
	end
	task.spawn(function()
		if not PlayerDataService.SendMessage(userId, { kind = "AnimalStolen", animalId = animalId }) then
			warn(`[HomeService] could not record theft of {animalId} from {userId}`)
		end
	end)
end

local function setIncomeLabel(record: AnimalRecord)
	local model = record.model
	local root = model and model.PrimaryPart
	if not model or not root then
		return
	end
	local gui = root:FindFirstChild("IncomeLabel") :: BillboardGui?
	if not gui then
		local newGui = Instance.new("BillboardGui")
		newGui.Name = "IncomeLabel"
		newGui.Size = UDim2.fromOffset(160, 44)
		newGui.StudsOffsetWorldSpace = Vector3.new(0, model:GetExtentsSize().Y / 2 + 1.5, 0)
		newGui.MaxDistance = 60
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromRGB(255, 230, 90)
		label.TextStrokeTransparency = 0.2
		label.Parent = newGui
		newGui.Parent = root
		gui = newGui
	end
	(gui :: BillboardGui).Enabled = true
	local species = Config.Species[record.speciesId]
	local perSecond = AnimalMath.ValuePerSecond(record.speciesId, record.size, record.growth)
	local label = (gui :: BillboardGui):FindFirstChild("Text") :: TextLabel
	label.Text = `{species.displayName}\n+{Format.Short(perSecond)}/s`
end

local function refreshIncome(player: Player)
	local total = 0
	for _, record in slotsByPlayer[player] or {} do
		if record.state == "InBase" then -- equipped pets keep their slot but earn nothing
			total += AnimalMath.ValuePerSecond(record.speciesId, record.size, record.growth)
		end
	end
	local multiplier = player:GetAttribute("IncomeMultiplier") -- research
	PlayerStateService.SetIncomePerSecond(
		player,
		total * (if typeof(multiplier) == "number" then multiplier else 1)
	)
end

local function findFreePad(player: Player, preferred: number?): BasePart?
	local plot = BaseService.GetPlot(player)
	local slots = slotsByPlayer[player]
	if not plot or not slots then
		return nil
	end
	local pads = BaseService.GetSlots(plot, slotCount(player))
	for _, pad in pads do
		if pad:GetAttribute("SlotIndex") == preferred and not slots[preferred :: number] then
			return pad
		end
	end
	for _, pad in pads do
		if not slots[pad:GetAttribute("SlotIndex") :: number] then
			return pad
		end
	end
	return nil
end

local function countLoose(player: Player): number
	local count = 0
	for _, record in AnimalService.All() do
		if record.ownerUserId == player.UserId and (record.state == "Loose" or record.state == "Carried") then
			count += 1
		end
	end
	return count
end

local placedHooks: { (Player, AnimalRecord) -> () } = {}

-- Puts an owned animal in its owner's base on a slot (the slot is only a
-- place in the base's capacity): it wanders in the plot's PetArea and earns.
local function placeInSlot(player: Player, record: AnimalRecord, pad: BasePart)
	local index = pad:GetAttribute("SlotIndex") :: number
	record.state = "InBase"
	record.ownerUserId = player.UserId
	record.slot = index
	if record.model then
		record.model:SetAttribute("OwnerUserId", player.UserId)
	end
	slotsByPlayer[player][index] = record
	local plot = BaseService.GetPlot(player)
	local area = plot and BaseService.GetPetArea(plot)
	if area then
		AnimalService.SetHomeArea(record, area)
	else
		AnimalService.ParkAt(record, pad.CFrame * CFrame.new(0, pad.Size.Y / 2, 0))
	end
	setIncomeLabel(record)
	for _, hook in placedHooks do
		hook(player, record)
	end
	saveAnimal(player, record)
end

-- Called whenever an animal is (re)placed in a base, e.g. to add prompts.
function HomeService.OnPlaced(hook: (Player, AnimalRecord) -> ())
	table.insert(placedHooks, hook)
end

-- Sends an animal that still holds its slot (an equipped pet) back into the base.
function HomeService.PlaceBack(player: Player, record: AnimalRecord): boolean
	local plot = BaseService.GetPlot(player)
	if not plot or not record.slot then
		return false
	end
	for _, pad in BaseService.GetSlots(plot, slotCount(player)) do
		if pad:GetAttribute("SlotIndex") == record.slot then
			placeInSlot(player, record, pad)
			refreshIncome(player)
			return true
		end
	end
	return false
end

function HomeService.RefreshIncome(player: Player)
	refreshIncome(player)
end

-- Picks a pet up from the base to release it by hand (concept v2): the owner
-- carries it out of the Safe Zone and drops it where it should grow
-- (CarryService). Walking back into the base puts it back. Counts as loose
-- from now on, so the loose limit is checked here.
function HomeService.PickUp(player: Player, record: AnimalRecord): boolean
	local slots = slotsByPlayer[player]
	if not slots or record.state ~= "InBase" or record.ownerUserId ~= player.UserId or not record.slot then
		return false
	end
	local data = PlayerDataService.Get(player)
	local limit = if data
		then ResearchMath.Value(data.research, "maxLoose", Config.Economy.maxLooseAnimals, os.time())
		else Config.Economy.maxLooseAnimals
	if countLoose(player) >= limit then
		NotifyService.Send(
			player,
			{ text = `You can only have {limit} pets loose at once.`, kind = "info", icon = "release" }
		)
		return false
	end
	if not CarryService.PickUp(player, record) then
		return false
	end
	slots[record.slot :: number] = nil
	local root = record.model and record.model.PrimaryPart
	if root then
		for _, name in { "PickUpPrompt", "EquipPrompt" } do
			local prompt = root:FindFirstChild(name)
			if prompt then
				prompt:Destroy()
			end
		end
		local label = root:FindFirstChild("IncomeLabel") :: BillboardGui?
		if label then
			label.Enabled = false
		end
	end
	refreshIncome(player)
	local species = Config.Species[record.speciesId]
	NotifyService.Send(player, {
		text = `Carry your {species.displayName} out of the Safe Zone and release it. It grows fastest in the {species.biome}.`,
		kind = "info",
		icon = "release",
	})
	return true
end

-- Brings an owned animal home (day reset, server shutdown). Returns false
-- when the owner is offline or the base is full.
function HomeService.ReturnToBase(record: AnimalRecord): boolean
	local owner = record.ownerUserId and Players:GetPlayerByUserId(record.ownerUserId)
	if not owner then
		return false
	end
	local pad = findFreePad(owner, record.slot)
	if not pad then
		return false
	end
	if record.carrier then
		CarryService.Take(record.carrier, record)
	end
	AnimalService.ReturnHome(record) -- fresh model, then park it
	placeInSlot(owner, record, pad)
	refreshIncome(owner)
	return true
end

local lastBringHomeAt: { [Player]: number } = {}

-- Owner pulls a loose (or being-stolen) animal back to base. The real
-- version is a cheap Developer Product; in the prototype it is free and
-- only works while debug is enabled (Studio).
function HomeService.BringHome(player: Player, animalId: unknown)
	if typeof(animalId) ~= "string" or #animalId > 64 then
		return
	end
	local now = os.clock()
	if now - (lastBringHomeAt[player] or 0) < 1 then
		return
	end
	lastBringHomeAt[player] = now
	if not (Config.Gameplay.teleportHome.debugFree and Config.Debug.enabled) then
		NotifyService.Send(player, { text = "Bring home is coming soon.", kind = "info" })
		return
	end
	local record = AnimalService.Get(animalId)
	if
		not record
		or record.ownerUserId ~= player.UserId
		or record.state == "InBase"
		or record.state == "Following"
	then
		return
	end
	local thief = record.carrier
	if HomeService.ReturnToBase(record) then
		local species = Config.Species[record.speciesId].displayName
		NotifyService.Send(
			player,
			{ text = `{species} is safe at home.`, kind = "success", icon = "bringhome" }
		)
		if thief and thief ~= player then
			NotifyService.Send(
				thief,
				{ text = `{player.DisplayName} pulled their {species} home!`, kind = "info" }
			)
		end
	else
		NotifyService.Send(player, { text = "Your base is full!", kind = "info" })
	end
end

-- Number of free slots in a player's base.
function HomeService.FreeSlots(player: Player): number
	local plot = BaseService.GetPlot(player)
	local slots = slotsByPlayer[player]
	if not plot or not slots then
		return 0
	end
	local free = 0
	for _, pad in BaseService.GetSlots(plot, slotCount(player)) do
		if not slots[pad:GetAttribute("SlotIndex") :: number] then
			free += 1
		end
	end
	return free
end

-- Takes a base pet out of its owner's base and save (it is being traded);
-- the caller hands it to its new owner with Receive.
function HomeService.GiveAway(player: Player, record: AnimalRecord): boolean
	local slots = slotsByPlayer[player]
	if not slots or record.ownerUserId ~= player.UserId or record.state ~= "InBase" or not record.slot then
		return false
	end
	slots[record.slot :: number] = nil
	record.slot = nil
	local data = PlayerDataService.Get(player)
	if data then
		data.animals[record.id] = nil
	end
	refreshIncome(player)
	return true
end

-- A pet won in a battle goes straight to a free slot. False when the base is full.
function HomeService.Receive(player: Player, record: AnimalRecord): boolean
	local pad = findFreePad(player, nil)
	if not pad then
		return false
	end
	placeInSlot(player, record, pad)
	refreshIncome(player)
	IndexService.MarkCaught(player, record.speciesId)
	return true
end

-- Puts every carried animal on a free slot. Returns how many were placed.
function HomeService.DepositCarried(player: Player): number
	local placed = 0
	for _, record in CarryService.GetCarried(player) do
		local pad = findFreePad(player, nil)
		if not pad then
			NotifyService.Send(player, { text = "Your base is full!", kind = "info" })
			break -- base full: the player keeps carrying the rest
		end
		local previousOwner = record.ownerUserId
		CarryService.Take(player, record)
		placeInSlot(player, record, pad)
		placed += 1
		if previousOwner ~= player.UserId then
			IndexService.MarkCaught(player, record.speciesId) -- a new pet for this player
		end
		if previousOwner and previousOwner ~= player.UserId then
			forgetAnimal(previousOwner, record.id)
			local species = Config.Species[record.speciesId].displayName
			local victim = Players:GetPlayerByUserId(previousOwner)
			NotifyService.SendUserId(previousOwner, {
				text = `{player.DisplayName} stole your {species}!`,
				kind = "warning",
				icon = "theft",
			})
			NotifyService.Send(player, {
				text = `You stole {if victim then victim.DisplayName else "someone"}'s {species}!`,
				kind = "success",
			})
		end
	end
	if placed > 0 then
		refreshIncome(player)
	end
	return placed
end

function HomeService.GetSlots(player: Player): { [number]: AnimalRecord }
	return slotsByPlayer[player] or {}
end

local function onPlayerAdded(player: Player)
	slotsByPlayer[player] = {}
	player:GetAttributeChangedSignal("InOwnBase"):Connect(function()
		if player:GetAttribute("InOwnBase") == true then
			HomeService.DepositCarried(player)
		end
	end)
end

-- Runs after the final save snapshot: base animals leave with their owner.
-- Loose ones stay in this server and can still be stolen (OPEN #1).
local function onReleasing(player: Player)
	lastBringHomeAt[player] = nil
	for _, record in slotsByPlayer[player] or {} do
		AnimalService.Remove(record)
	end
	slotsByPlayer[player] = nil
end

-- Save loaded: rebuild the base, then pay offline income.
local function onLoaded(player: Player, data: Types.PlayerData)
	if not slotsByPlayer[player] then
		return
	end
	for id, saved in data.animals do
		local record = AnimalService.Restore(id, saved, player.UserId)
		if
			record
			and record.state ~= "InBase"
			and not record.carrier
			and record.model
			and not record.roamFree
		then
			local isLooseHere = record.slot ~= nil -- rejoined while it was loose in this server
			local pad = if isLooseHere then nil else findFreePad(player, saved.slot)
			if pad then
				placeInSlot(player, record, pad)
			elseif not isLooseHere then
				record.slot = saved.slot
				AnimalService.ReturnHome(record) -- no room: it waits loose for the next reset
			end
		end
	end
	refreshIncome(player)

	local away = os.time() - data.lastOnlineAt
	if data.lastOnlineAt > 0 and away > 60 then
		local seconds = math.min(away, Config.Economy.offlineIncomeMaxHours * 3600)
		local perSecond = 0
		for _, saved in data.animals do
			perSecond += AnimalMath.ValuePerSecond(saved.speciesId, saved.size, saved.growth)
		end
		local percent = ResearchMath.Value(
			data.research,
			"offlineIncomePercent",
			Config.Economy.offlineIncomePercent,
			os.time()
		)
		local multiplier = ResearchMath.Value(data.research, "incomeMultiplier", 1, os.time())
		local earned = perSecond * multiplier * percent * seconds
		if earned > 0 then
			PlayerStateService.AddCash(player, earned)
			NotifyService.Send(player, {
				text = `While you were away your animals earned ${Format.Short(earned)}!`,
				kind = "success",
				icon = "offline",
			})
		end
	end
end

-- Keep growth and slot of owned animals current in the save.
local function onBeforeSave(player: Player, data: Types.PlayerData)
	for id, saved in data.animals do
		local record = AnimalService.Get(id)
		if record and record.ownerUserId == player.UserId then
			saved.growth = record.growth
			saved.slot = record.slot or saved.slot
			saved.level, saved.xp, saved.hp = record.level, record.xp, record.hp
		end
	end
end

-- An animal of ours was stolen in another server while we were away.
local function onMessage(player: Player, data: Types.PlayerData, message: Types.ProfileMessage)
	if message.kind ~= "AnimalStolen" then
		return
	end
	local saved = data.animals[message.animalId]
	data.animals[message.animalId] = nil
	local record = AnimalService.Get(message.animalId)
	if record and record.ownerUserId == player.UserId then
		local slots = slotsByPlayer[player]
		if slots and record.slot and slots[record.slot] == record then
			slots[record.slot] = nil
		end
		AnimalService.Remove(record)
		refreshIncome(player)
	end
	if saved then
		NotifyService.Send(player, {
			text = `Your {Config.Species[saved.speciesId].displayName} was stolen while you were away!`,
			kind = "warning",
			icon = "theft",
		})
	end
end

function HomeService.Start()
	Remotes.Get("TeleportHome").OnServerEvent:Connect(HomeService.BringHome)
	Players.PlayerAdded:Connect(onPlayerAdded)
	PlayerDataService.OnLoaded(onLoaded)
	PlayerDataService.OnBeforeSave(onBeforeSave)
	PlayerDataService.OnMessage(onMessage)
	PlayerDataService.OnReleasing(onReleasing)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	local tick = Config.Economy.incomeTickSeconds
	task.spawn(function()
		while true do
			task.wait(tick)
			for player in slotsByPlayer do
				local state = PlayerStateService.Get(player)
				if state and state.incomePerSecond > 0 then
					PlayerStateService.AddCash(player, state.incomePerSecond * tick)
				end
			end
		end
	end)
end

return HomeService
