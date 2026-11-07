--!strict
-- Display pads and a persistent reserve share one animals dictionary. A full
-- base never releases an owned pet into the world or discards it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimalMath = require(ReplicatedStorage.Shared.AnimalMath)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local AnimalService = require(script.Parent.AnimalService)
local BaseService = require(script.Parent.BaseService)
local CarryService = require(script.Parent.CarryService)
local IndexService = require(script.Parent.IndexService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local ProgressionService = require(script.Parent.ProgressionService)

type AnimalRecord = AnimalService.AnimalRecord
local HomeService = {}
local slotsByPlayer: { [Player]: { [number]: AnimalRecord } } = {}
local placedHooks: { (Player, AnimalRecord) -> () } = {}

local function saveAnimal(player: Player, record: AnimalRecord, snapshot: Types.PlayerData?)
	local data = snapshot or PlayerDataService.Get(player)
	if not data or record.ownerUserId ~= player.UserId then
		return
	end
	local saved = data.animals[record.id] or { speciesId = record.speciesId, size = record.size, slot = 0 }
	saved.speciesId, saved.size = record.speciesId, record.size
	saved.slot = record.slot or 0
	saved.origin = saved.origin or record.origin
	saved.level, saved.xp, saved.hp = record.level, record.xp, record.hp
	saved.legacyScaleFloor, saved.legacyIncomeFloor = record.legacyScaleFloor, record.legacyIncomeFloor
	saved.location = if record.state == "InBase"
		then "Base"
		elseif record.state == "Following" then "Team"
		else "Inventory"
	saved.equipped = if record.state == "Following" then true else nil
	saved.away = nil
	data.animals[record.id] = saved
end

local function refreshIncome(player: Player)
	local total = 0
	for _, record in slotsByPlayer[player] or {} do
		if record.state == "InBase" then
			total += AnimalMath.ValuePerSecond(
				record.speciesId,
				record.size,
				record.level,
				record.legacyIncomeFloor
			)
		end
	end
	local multiplier = player:GetAttribute("IncomeMultiplier")
	PlayerStateService.SetIncomePerSecond(
		player,
		total * (if typeof(multiplier) == "number" then multiplier else 1)
	)
end

local function findFreePad(player: Player, preferred: number?): BasePart?
	local plot, slots, data =
		BaseService.GetPlot(player), slotsByPlayer[player], PlayerDataService.Get(player)
	if not plot or not slots or not data then
		return nil
	end
	local pads = BaseService.GetSlots(plot, data.baseSlots)
	for _, pad in pads do
		local index = pad:GetAttribute("SlotIndex") :: number
		if index == preferred and not slots[index] then
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

local function clearSlot(player: Player, record: AnimalRecord)
	local slots = slotsByPlayer[player]
	if slots and record.slot and slots[record.slot] == record then
		slots[record.slot] = nil
	end
	record.slot = nil
end

local function incomeLabel(record: AnimalRecord)
	local model = record.model
	local root = model and model.PrimaryPart
	if not root or not model then
		return
	end
	local old = root:FindFirstChild("IncomeLabel")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "IncomeLabel"
	gui.Size = UDim2.fromOffset(160, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, model:GetExtentsSize().Y / 2 + 1.5, 0)
	gui.MaxDistance = 60
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(255, 230, 90)
	label.TextStrokeTransparency = 0.2
	local value =
		AnimalMath.ValuePerSecond(record.speciesId, record.size, record.level, record.legacyIncomeFloor)
	label.Text = `{Config.Species[record.speciesId].displayName}\n+{Format.Short(value)}/s`
	label.Parent, gui.Parent = gui, root
end

local function placeInSlot(player: Player, record: AnimalRecord, pad: BasePart)
	record.state, record.ownerUserId = "InBase", player.UserId
	record.slot = pad:GetAttribute("SlotIndex") :: number
	slotsByPlayer[player][record.slot :: number] = record
	local plot = BaseService.GetPlot(player)
	local area = plot and BaseService.GetPetArea(plot)
	if area then
		AnimalService.SetHomeArea(record, area)
	else
		AnimalService.ParkAt(record, pad.CFrame * CFrame.new(0, pad.Size.Y / 2, 0))
	end
	local model = record.model
	if model then
		model:SetAttribute("OwnerUserId", player.UserId)
		model:SetAttribute("State", "InBase")
	end
	incomeLabel(record)
	for _, hook in placedHooks do
		hook(player, record)
	end
	saveAnimal(player, record)
end

function HomeService.OnPlaced(hook: (Player, AnimalRecord) -> ())
	table.insert(placedHooks, hook)
end

function HomeService.RefreshIncome(player: Player)
	for _, record in slotsByPlayer[player] or {} do
		if record.state == "InBase" then
			incomeLabel(record)
		end
	end
	refreshIncome(player)
end

function HomeService.FreeSlots(player: Player): number
	local plot, data = BaseService.GetPlot(player), PlayerDataService.Get(player)
	if not plot or not data then
		return 0
	end
	local free = 0
	for _, pad in BaseService.GetSlots(plot, data.baseSlots) do
		if not (slotsByPlayer[player] or {})[pad:GetAttribute("SlotIndex") :: number] then
			free += 1
		end
	end
	return free
end

-- Capacity is checked before an acquisition or charge. Legacy overflow remains
-- owned; the default reserve has no cap. Net trade delta can be negative.
function HomeService.CanAcquire(player: Player, delta: number?): boolean
	local data = PlayerDataService.Get(player)
	if not data then
		return false
	end
	local capacity = Config.Progression.inventoryCapacity
	if capacity <= 0 or (delta or 1) <= 0 then
		return true
	end
	local reserved = 0
	for _, saved in data.animals do
		if saved.location == "Inventory" then
			reserved += 1
		end
	end
	local pending = 0
	for _, record in CarryService.GetCarried(player) do
		if not record.ownerUserId then
			pending += 1
		end
	end
	return reserved + math.max(0, pending + (delta or 1) - HomeService.FreeSlots(player)) <= capacity
end

function HomeService.Store(player: Player, record: AnimalRecord): boolean
	if not PlayerDataService.Get(player) then
		return false
	end
	clearSlot(player, record)
	if record.carrier then
		CarryService.Take(record.carrier, record)
	end
	record.ownerUserId = player.UserId
	AnimalService.Store(record)
	saveAnimal(player, record)
	refreshIncome(player)
	return true
end

-- Unequip always succeeds to a valid pad or reserve, including a full base.
function HomeService.PlaceBack(player: Player, record: AnimalRecord): boolean
	if record.ownerUserId ~= player.UserId then
		return false
	end
	local preferred = record.slot
	clearSlot(player, record)
	local pad = findFreePad(player, preferred)
	if pad then
		placeInSlot(player, record, pad)
	else
		return HomeService.Store(player, record)
	end
	refreshIncome(player)
	return true
end

function HomeService.ReturnToBase(record: AnimalRecord): boolean
	local player = record.ownerUserId and Players:GetPlayerByUserId(record.ownerUserId)
	if not player or record.state == "Battling" then
		return false
	end
	if record.carrier then
		CarryService.Take(record.carrier, record)
	end
	return HomeService.PlaceBack(player, record)
end

-- Commit ownership without moving the arena model during capsule playback.
function HomeService.ReserveAcquisition(player: Player, record: AnimalRecord): boolean
	local data = PlayerDataService.Get(player)
	if not data or not PlayerDataService.IsReady(player) or data.animals[record.id] then
		return false
	end
	record.ownerUserId, record.slot = player.UserId, nil
	saveAnimal(player, record)
	IndexService.MarkCaught(player, record.speciesId)
	return true
end

-- Called only after a validated acquisition/transfer. Unexpected capacity
-- changes never discard an already-confirmed pet: reserve is the safety net.
function HomeService.Receive(player: Player, record: AnimalRecord): boolean
	local data = PlayerDataService.Get(player)
	if not data then
		return false
	end
	local isNew = data.animals[record.id] == nil
	record.ownerUserId = player.UserId
	local pad = findFreePad(player, nil)
	if pad then
		placeInSlot(player, record, pad)
	else
		HomeService.Store(player, record)
	end
	refreshIncome(player)
	if isNew then
		IndexService.MarkCaught(player, record.speciesId)
	end
	return true
end

function HomeService.SaveCaught(player: Player, record: AnimalRecord)
	saveAnimal(player, record)
	PlayerDataService.SaveNow(player)
end

function HomeService.GiveAway(player: Player, record: AnimalRecord): boolean
	local data = PlayerDataService.Get(player)
	if
		not data
		or record.ownerUserId ~= player.UserId
		or (record.state ~= "InBase" and record.state ~= "Inventory")
	then
		return false
	end
	clearSlot(player, record)
	data.animals[record.id] = nil
	refreshIncome(player)
	return true
end

function HomeService.DepositCarried(player: Player): number
	if not PlayerDataService.IsReady(player) then
		return 0
	end
	local count = 0
	for _, record in CarryService.GetCarried(player) do
		-- Only newly caught wild pets use transport. No owned release/theft path.
		if not record.ownerUserId or record.ownerUserId == player.UserId then
			CarryService.Take(player, record)
			if HomeService.Receive(player, record) then
				count += 1
				CarryService.ConfirmCapture(player, record)
			end
		end
	end
	if count > 0 then
		PlayerDataService.SaveNow(player)
	end
	return count
end

function HomeService.GetSlots(player: Player): { [number]: AnimalRecord }
	return slotsByPlayer[player] or {}
end

local function onLoaded(player: Player, data: Types.PlayerData)
	slotsByPlayer[player] = slotsByPlayer[player] or {}
	local ids = {}
	for id in data.animals do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local saved = data.animals[id]
		if saved.unavailableReason then
			continue
		end
		local record = AnimalService.Restore(id, saved, player.UserId)
		if record and record.ownerUserId ~= player.UserId then
			data.animals[id] = nil -- a confirmed live owner takes precedence over stale restore
		elseif record and not record.carrier and record.state ~= "Battling" then
			if saved.location == "Base" then
				local pad = findFreePad(player, saved.slot)
				if pad then
					placeInSlot(player, record, pad)
				else
					HomeService.Store(player, record)
				end
			elseif saved.location == "Team" then
				if saved.slot > 0 then
					record.slot = saved.slot
					slotsByPlayer[player][saved.slot] = record
				end
			else
				HomeService.Store(player, record)
			end
		end
	end
	refreshIncome(player)
	local earned = player:GetAttribute("OfflineCashAwarded")
	if typeof(earned) == "number" and earned > 0 then
		NotifyService.Send(player, {
			text = `While you were away your animals earned ${Format.Short(earned)}!`,
			kind = "success",
			icon = "offline",
		})
	end
end

local function onBeforeSave(player: Player, data: Types.PlayerData)
	for id in data.animals do
		local record = AnimalService.Get(id)
		if record and record.ownerUserId == player.UserId then
			saveAnimal(player, record, data)
		end
	end
end

local function onMessage(player: Player, data: Types.PlayerData, message: Types.ProfileMessage)
	if message.kind ~= "AnimalStolen" or type(message.animalId) ~= "string" then
		return
	end
	data.animals[message.animalId] = nil
	local record = AnimalService.Get(message.animalId)
	if record and record.ownerUserId == player.UserId then
		clearSlot(player, record)
		if record.carrier then
			CarryService.Take(record.carrier, record)
		end
		AnimalService.Remove(record)
		refreshIncome(player)
	end
end

local function onReleasing(player: Player)
	for _, record in AnimalService.All() do
		if record.ownerUserId ~= player.UserId then
			continue
		end
		if record.state == "Battling" then
			task.spawn(function()
				while AnimalService.Get(record.id) == record and record.state == "Battling" do
					task.wait(1)
				end
				if record.ownerUserId == player.UserId and not Players:GetPlayerByUserId(player.UserId) then
					AnimalService.Remove(record)
				end
			end)
		else
			if record.carrier then
				CarryService.Take(record.carrier, record)
			end
			AnimalService.Remove(record)
		end
	end
	slotsByPlayer[player] = nil
end

function HomeService.Start()
	CarryService.SetAcquisitionGuard(function(player)
		return HomeService.CanAcquire(player)
	end)
	ProgressionService.OnPetChanged(function(player, record)
		if record.state == "InBase" then
			incomeLabel(record)
		end
		refreshIncome(player)
	end)
	local function added(player: Player)
		slotsByPlayer[player] = {}
		player:GetAttributeChangedSignal("InOwnBase"):Connect(function()
			if player:GetAttribute("InOwnBase") == true then
				HomeService.DepositCarried(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(added)
	for _, player in Players:GetPlayers() do
		added(player)
	end
	PlayerDataService.OnPreparing(function(player, data)
		for id in data.animals do
			local record = AnimalService.Get(id)
			if record and record.ownerUserId ~= player.UserId then
				data.animals[id] = nil
			end
		end
	end)
	PlayerDataService.OnLoaded(onLoaded)
	PlayerDataService.OnBeforeSave(onBeforeSave)
	PlayerDataService.OnMessage(onMessage)
	PlayerDataService.OnReleasing(onReleasing)
	task.spawn(function()
		while true do
			task.wait(Config.Economy.incomeTickSeconds)
			for player in slotsByPlayer do
				local state = PlayerStateService.Get(player)
				if state and PlayerDataService.IsReady(player) and state.incomePerSecond > 0 then
					PlayerStateService.AddCash(
						player,
						state.incomePerSecond * Config.Economy.incomeTickSeconds
					)
				end
			end
		end
	end)
end

return HomeService
