--!strict
-- Catching and carrying. The server validates every catch (distance,
-- capacity, state); the ProximityPrompt only expresses the intent.
-- Carried animals ride above the carrier's head.
-- Releasing (concept v2): the owner carries a base pet anywhere outside the
-- Safe Zone and drops it there ("ReleaseCarried"); it grows where it lands.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BattleMath = require(ReplicatedStorage.Shared.BattleMath)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ResearchMath = require(ReplicatedStorage.Shared.ResearchMath)
local AnimalService = require(script.Parent.AnimalService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ZoneService = require(script.Parent.ZoneService)

type AnimalRecord = AnimalService.AnimalRecord

local CarryService = {}

local carriedByPlayer: { [Player]: { AnimalRecord } } = {}
local lastWarningAt: { [string]: number } = {}

local WARNING_COOLDOWN = 5

local function ownerName(userId: number): string
	local owner = Players:GetPlayerByUserId(userId)
	return if owner then owner.DisplayName else "someone"
end

local function bringHomeAction(record: AnimalRecord)
	if Config.Gameplay.teleportHome.debugFree and Config.Debug.enabled then
		return { label = "Bring home (DEBUG FREE)", animalId = record.id }
	end
	return nil
end

-- Someone else started holding the prompt on an owned loose animal.
local function warnOwner(thief: Player, record: AnimalRecord)
	local ownerId = record.ownerUserId
	if record.state ~= "Loose" or not ownerId or ownerId == thief.UserId or BattleMath.Enabled() then
		return -- with battles on, BattleService tells the owner when the battle starts
	end
	local now = os.clock()
	if now - (lastWarningAt[record.id] or 0) < WARNING_COOLDOWN then
		return
	end
	lastWarningAt[record.id] = now
	local species = Config.Species[record.speciesId].displayName
	NotifyService.SendUserId(ownerId, {
		text = `{thief.DisplayName} is stealing your {species}!`,
		kind = "warning",
		icon = "theft",
		action = bringHomeAction(record),
	})
end

local function getCapacity(player: Player): number
	local capacity = player:GetAttribute("CarryCapacity")
	return if typeof(capacity) == "number" then capacity else Config.Gameplay.carry.startingCapacity
end

local function updateCount(player: Player)
	local carried = carriedByPlayer[player] or {}
	local own = 0
	for _, record in carried do
		if record.ownerUserId == player.UserId then
			own += 1
		end
	end
	player:SetAttribute("CarryCount", #carried)
	player:SetAttribute("CarryingOwn", own) -- the client shows the Release button
end

local function attach(player: Player, record: AnimalRecord, stackIndex: number)
	local model = record.model
	local character = player.Character
	local characterRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not model or not characterRoot then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
	end
	local prompt = model.PrimaryPart and model.PrimaryPart:FindFirstChild("CatchPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Enabled = false
	end
	local root = model.PrimaryPart :: BasePart
	root.CanCollide = false
	root.Massless = true

	local animalHeight = model:GetExtentsSize().Y
	local height = 3 + animalHeight / 2 + (stackIndex - 1) * animalHeight
	model:PivotTo(characterRoot.CFrame * CFrame.new(0, height, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Name = "CarryWeld"
	weld.Part0 = characterRoot
	weld.Part1 = root
	weld.Parent = root
end

local function startCarrying(player: Player, record: AnimalRecord)
	local carried = carriedByPlayer[player] or {}
	record.state = "Carried"
	record.carrier = player
	table.insert(carried, record)
	carriedByPlayer[player] = carried
	attach(player, record, #carried)
	updateCount(player)
end

local battleHandler: ((Player, AnimalRecord) -> ())? = nil

-- With battles on, wild pets and other players' loose pets are fought
-- (BattleService) instead of grabbed.
function CarryService.SetBattleHandler(handler: (Player, AnimalRecord) -> ())
	battleHandler = handler
end

-- Tells the owner and the thief that an owned pet was taken.
local function announceGrab(player: Player, record: AnimalRecord)
	local ownerId = record.ownerUserId
	if ownerId and ownerId ~= player.UserId then
		local species = Config.Species[record.speciesId].displayName
		NotifyService.SendUserId(ownerId, {
			text = `{player.DisplayName} took your {species}! It's theirs once it reaches their base.`,
			kind = "warning",
			icon = "theft",
			action = bringHomeAction(record),
		})
		NotifyService.Send(player, {
			text = `You took {ownerName(ownerId)}'s {species}! Carry it to your base!`,
			kind = "success",
		})
	end
end

local function tryCatch(player: Player, record: AnimalRecord)
	if record.state ~= "Wild" and record.state ~= "Loose" then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local characterRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local model = record.model
	if not humanoid or humanoid.Health <= 0 or not characterRoot or not model or not model.PrimaryPart then
		return
	end
	local shieldLeft = (record.shieldUntil or 0) - os.time()
	if record.state == "Loose" and record.ownerUserId ~= player.UserId and shieldLeft > 0 then
		NotifyService.Send(player, {
			text = `This pet is shielded for {Format.Duration(shieldLeft)}.`,
			kind = "info",
			icon = "shield",
		})
		return
	end
	local stolen = record.state == "Loose" and record.ownerUserId ~= player.UserId
	if battleHandler and (record.state == "Wild" or stolen) then
		battleHandler(player, record)
		return
	end
	local distance = (characterRoot.Position - model.PrimaryPart.Position).Magnitude
		- AnimalService.Radius(model)
	if distance > Config.Gameplay.capture.maxDistance then
		return
	end
	local carried = carriedByPlayer[player] or {}
	if #carried >= getCapacity(player) then
		NotifyService.Send(
			player,
			{ text = "Your hands are full! Take it to your base first.", kind = "info", icon = "carry" }
		)
		return
	end

	if record.state == "Wild" and not record.origin then
		record.origin = {
			ownerUserId = player.UserId,
			ownerName = player.DisplayName,
			capturedAt = os.time(),
			place = ZoneService.ZoneAt(characterRoot.Position),
		}
	end
	startCarrying(player, record)
	announceGrab(player, record)
end

-- The winner of a battle against someone's loose pet takes it (BattleService
-- made sure their hands are free). Carried pets can't be taken from them.
function CarryService.TakeWon(player: Player, record: AnimalRecord)
	startCarrying(player, record)
	announceGrab(player, record)
end

-- The owner picks up one of their base pets to release it (HomeService
-- checks ownership and the loose limit). False when their hands are full.
function CarryService.PickUp(player: Player, record: AnimalRecord): boolean
	if #(carriedByPlayer[player] or {}) >= getCapacity(player) then
		NotifyService.Send(player, {
			text = "Your hands are full! Release or drop off what you carry first.",
			kind = "info",
			icon = "carry",
		})
		return false
	end
	startCarrying(player, record)
	return true
end

-- Drops the last own pet the player carries at their feet, outside the
-- Safe Zone. It becomes Loose there, with the Release Shield if researched.
local function releaseCarried(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local carried = carriedByPlayer[player]
	if not root or not carried then
		return
	end
	local record: AnimalRecord? = nil
	for i = #carried, 1, -1 do
		if carried[i].ownerUserId == player.UserId then
			record = carried[i]
			break
		end
	end
	if not record then
		return
	end
	local position = root.Position
	if ZoneService.ZoneAt(position) == "Base" or ZoneService.InAnyBase(position) then
		NotifyService.Send(
			player,
			{ text = "Leave the Safe Zone to release your pet.", kind = "info", icon = "release" }
		)
		return
	end

	CarryService.Take(player, record)
	local data = PlayerDataService.Get(player)
	local shield = if data then ResearchMath.Value(data.research, "releaseShieldSeconds", 0, os.time()) else 0
	record.shieldUntil = if shield > 0 then os.time() + shield else nil
	AnimalService.DropAt(record, position + root.CFrame.LookVector * 4 - Vector3.new(0, 2.5, 0))

	local species = Config.Species[record.speciesId]
	local home = ZoneService.ZoneAt(position) == species.biome
	NotifyService.Send(player, {
		text = if home
			then `{species.displayName} released in its home biome: it grows fast here. Anyone can steal it!`
			else `{species.displayName} released. It grows faster in the {species.biome}. Anyone can steal it!`,
		kind = "info",
		icon = "release",
	})
end

-- Every carried animal goes back to its home biome (disconnect, death).
function CarryService.ReturnAllHome(player: Player)
	local carried = carriedByPlayer[player]
	carriedByPlayer[player] = nil
	if carried then
		for _, record in carried do
			AnimalService.ReturnHome(record)
		end
	end
	if player.Parent then
		updateCount(player)
	end
end

function CarryService.GetCarried(player: Player): { AnimalRecord }
	return table.clone(carriedByPlayer[player] or {})
end

-- Removes an animal from the carrier without touching its model; the
-- caller decides where it goes next (base slot, released...).
function CarryService.Take(player: Player, record: AnimalRecord): boolean
	local carried = carriedByPlayer[player]
	local index = carried and table.find(carried, record)
	if not carried or not index then
		return false
	end
	table.remove(carried, index)
	record.carrier = nil
	local model = record.model
	local weld = model and model.PrimaryPart and model.PrimaryPart:FindFirstChild("CarryWeld")
	if weld then
		weld:Destroy()
	end
	updateCount(player)
	return true
end

function CarryService.Start()
	AnimalService.SetCaptureHandler(tryCatch)
	Remotes.Get("ReleaseCarried").OnServerEvent:Connect(releaseCarried)
	AnimalService.SetHoldBeganHandler(warnOwner)

	local function onPlayerAdded(player: Player)
		updateCount(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.Died:Connect(function()
				CarryService.ReturnAllHome(player)
			end)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(CarryService.ReturnAllHome)
end

return CarryService
