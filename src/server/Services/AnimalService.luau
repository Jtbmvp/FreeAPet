--!strict
-- Owns every animal that exists in the world: spawning wild animals in
-- their biome, wandering, and the catch ProximityPrompt. Other services
-- change an animal's state through this module.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimalMath = require(ReplicatedStorage.Shared.AnimalMath)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local BattleMath = require(ReplicatedStorage.Shared.BattleMath)
local AnimalFactory = require(script.Parent.Parent.Animals.AnimalFactory)

-- Following = equipped in its owner's battle team, walking behind them.
export type AnimalState = "Wild" | "Carried" | "Loose" | "InBase" | "Following" | "Battling"

export type AnimalRecord = {
	id: string,
	speciesId: string,
	size: number,
	growth: number,
	state: AnimalState,
	ownerUserId: number?,
	carrier: Player?,
	slot: number?, -- base slot index while InBase
	homeArea: BasePart,
	homePosition: Vector3,
	roamFree: boolean, -- dropped outside its spawn area: wanders near where it fell
	model: Model?,
	nextMoveAt: number,
	shieldUntil: number?, -- os.time(): a released pet nobody else can catch until then
	origin: Types.PetOrigin?, -- set when first caught from the wild
	level: number, -- battle level
	xp: number,
	hp: number?, -- battle health; nil = full
}

local AnimalService = {}

local records: { [string]: AnimalRecord } = {}
-- Spawn areas come from Workspace.Map.SpawnAreas. An area with a SpeciesId
-- attribute only spawns that species (Rare = true marks the hidden spot used
-- by the daily rare); areas without one take any species of their BiomeId.
local spawnAreasByBiome: { [string]: { BasePart } } = {}
local spawnAreasBySpecies: { [string]: { BasePart } } = {}
local rareAreasBySpecies: { [string]: { BasePart } } = {}
local animalsFolder: Folder
local rng = Random.new()
local captureHandler: ((Player, AnimalRecord) -> ())?
local holdBeganHandler: ((Player, AnimalRecord) -> ())?

local function rollSize(): number
	local economy = Config.Economy
	return economy.sizeMin + (economy.sizeMax - economy.sizeMin) * rng:NextNumber() ^ economy.sizeSkew
end

local function rollSpecies(biomeId: string): string?
	local total = 0
	local options = {}
	for id, species in Config.Species do
		if species.biome == biomeId then
			total += species.spawnWeight
			table.insert(options, { id = id, weight = species.spawnWeight })
		end
	end
	local pick = rng:NextNumber() * total
	for _, option in options do
		pick -= option.weight
		if pick <= 0 then
			return option.id
		end
	end
	return nil
end

local function randomPointIn(area: BasePart): Vector3
	local half = area.Size / 2
	local localPoint = Vector3.new(rng:NextNumber(-half.X, half.X), 0, rng:NextNumber(-half.Z, half.Z))
	return (area.CFrame * CFrame.new(localPoint)).Position
end

local function clampToArea(area: BasePart, point: Vector3): Vector3
	local localPoint = area.CFrame:PointToObjectSpace(point)
	local half = area.Size / 2
	local clamped =
		Vector3.new(math.clamp(localPoint.X, -half.X, half.X), 0, math.clamp(localPoint.Z, -half.Z, half.Z))
	return area.CFrame:PointToWorldSpace(clamped)
end

-- Horizontal half-size of an animal: prompts and range checks start at its
-- edge, so big animals are as easy to reach as small ones.
function AnimalService.Radius(model: Model): number
	local size = model:GetExtentsSize()
	return math.max(size.X, size.Z) / 2
end

local function addPrompt(record: AnimalRecord, model: Model)
	local species = Config.Species[record.speciesId]
	local rarity = Config.Rarities[species.rarity]
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CatchPrompt"
	prompt.ActionText = "Catch"
	prompt.ObjectText = `{species.displayName} ({rarity.id})`
	-- With battles on, the prompt starts a battle (or picks up your own pet): a short hold is enough.
	prompt.HoldDuration = if BattleMath.Enabled() then 0.4 else Config.Gameplay.capture.holdSeconds
	prompt.MaxActivationDistance = Config.Gameplay.capture.maxDistance - 2 + AnimalService.Radius(model)
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(player)
		if captureHandler then
			captureHandler(player, record)
		end
	end)
	prompt.PromptButtonHoldBegan:Connect(function(player)
		if holdBeganHandler then
			holdBeganHandler(player, record)
		end
	end)
end

-- Release Shield research: a see-through bubble while the pet cannot be
-- stolen. The rule itself is checked by CarryService; the bubble and the
-- ShieldUntil attribute only show it.
local function addShield(record: AnimalRecord, model: Model)
	local remaining = (record.shieldUntil or 0) - os.time()
	if remaining <= 0 or not record.ownerUserId then
		return
	end
	local root = model.PrimaryPart :: BasePart
	local size = model:GetExtentsSize()
	local bubble = Instance.new("Part")
	bubble.Name = "ShieldBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.one * (math.max(size.X, size.Y, size.Z) * 1.25)
	bubble.Material = Enum.Material.ForceField
	bubble.Color = Color3.fromRGB(120, 200, 255)
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CanTouch = false
	bubble.Massless = true
	bubble.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = bubble
	weld.Parent = bubble
	bubble.Parent = model
	model:SetAttribute("ShieldUntil", record.shieldUntil)
	task.delay(remaining, function()
		bubble:Destroy()
		if model.Parent then
			model:SetAttribute("ShieldUntil", nil)
		end
	end)
end

-- Model scale for the record: species height (set by the factory) x size x growth stage.
local function targetScale(record: AnimalRecord, model: Model): number
	local base = model:GetAttribute("BaseScale")
	return (if typeof(base) == "number" then base else 1) * record.size * AnimalMath.ScaleFor(record.growth)
end

-- Builds the model at the record's size and growth and puts it in the world.
local function createModel(record: AnimalRecord, cframe: CFrame): Model
	local model = AnimalFactory.Build(record.speciesId)
	model:ScaleTo(targetScale(record, model))
	model:SetAttribute("AnimalId", record.id)
	model:SetAttribute("SpeciesId", record.speciesId)
	model:SetAttribute("OwnerUserId", record.ownerUserId)
	model:PivotTo(cframe)
	addPrompt(record, model)
	addShield(record, model)
	model.Parent = animalsFolder
	local root = model.PrimaryPart :: BasePart
	root:SetNetworkOwner(nil)
	record.model = model
	return model
end

local function placeOnGround(position: Vector3, model: Model?): CFrame
	local height = if model then model:GetExtentsSize().Y / 2 else 2
	local yaw = rng:NextNumber(0, math.pi * 2)
	return CFrame.new(position.X, position.Y + height + 0.5, position.Z) * CFrame.Angles(0, yaw, 0)
end

local function pickArea(speciesId: string, rare: boolean?): BasePart?
	local areas = rare and rareAreasBySpecies[speciesId]
		or spawnAreasBySpecies[speciesId]
		or spawnAreasByBiome[Config.Species[speciesId].biome]
	if not areas or #areas == 0 then
		return nil
	end
	return areas[rng:NextInteger(1, #areas)]
end

function AnimalService.SpawnWild(biomeId: string, forcedSpeciesId: string?, rare: boolean?): AnimalRecord?
	local speciesId = forcedSpeciesId or rollSpecies(biomeId)
	local area = speciesId and pickArea(speciesId, rare)
	if not speciesId or not area then
		return nil
	end
	local position = randomPointIn(area)
	local record: AnimalRecord = {
		id = HttpService:GenerateGUID(false),
		speciesId = speciesId,
		size = rollSize(),
		growth = 0, -- wild animals are born as babies; they grow only when released
		state = "Wild",
		ownerUserId = nil,
		carrier = nil,
		slot = nil,
		homeArea = area,
		homePosition = position,
		roamFree = false,
		model = nil,
		nextMoveAt = 0,
		level = rng:NextInteger(BattleMath.WildLevelRange(speciesId)),
		xp = 0,
	}
	records[record.id] = record
	createModel(record, placeOnGround(position, nil))
	return record
end

-- Recreates an owned animal from its save (player joined). The caller
-- parks it on a slot. If it still exists here (the owner rejoined while it
-- was loose in this server) the live record is returned instead.
function AnimalService.Restore(id: string, saved: Types.SavedAnimal, ownerUserId: number): AnimalRecord?
	local speciesId = saved.speciesId
	local existing = records[id]
	if existing then
		return existing
	end
	local area = Config.Species[speciesId] and pickArea(speciesId)
	if not area then
		return nil
	end
	local record: AnimalRecord = {
		id = id,
		speciesId = speciesId,
		size = saved.size,
		growth = saved.growth,
		state = "Loose",
		ownerUserId = ownerUserId,
		carrier = nil,
		slot = nil,
		homeArea = area,
		homePosition = randomPointIn(area),
		roamFree = false,
		model = nil,
		nextMoveAt = 0,
		origin = saved.origin,
		level = saved.level or 1,
		xp = saved.xp or 0,
		hp = saved.hp,
	}
	records[id] = record
	createModel(record, placeOnGround(record.homePosition, nil))
	return record
end

-- Sends an animal back to where it lives in its biome (expulsion,
-- disconnect while carried). Wild animals stay wild; owned ones are Loose.
function AnimalService.ReturnHome(record: AnimalRecord)
	if record.model then
		record.model:Destroy()
		record.model = nil
	end
	record.carrier = nil
	record.state = if record.ownerUserId then "Loose" else "Wild"
	-- Back to a spawn area of its species: homeArea may still be the base's
	-- PetArea (SetHomeArea) after living in a base.
	record.homeArea = pickArea(record.speciesId) or record.homeArea
	record.homePosition = randomPointIn(record.homeArea)
	record.roamFree = false
	createModel(record, placeOnGround(record.homePosition, nil))
end

-- Drops an animal at a spot (released by hand, won in a full base). It is free to grab
-- at once: owned animals stay owned (Loose), wild ones become Wild again.
function AnimalService.DropAt(record: AnimalRecord, position: Vector3)
	if record.model then
		record.model:Destroy()
		record.model = nil
	end
	record.carrier = nil
	record.state = if record.ownerUserId then "Loose" else "Wild"
	record.homePosition = position
	record.roamFree = true
	record.nextMoveAt = os.clock() + 3
	createModel(record, placeOnGround(position, nil))
end

-- Gives an animal a new area to live in (its owner's base): it appears at
-- a random spot there and wanders inside it. Catching is switched off; the
-- caller sets the state.
function AnimalService.SetHomeArea(record: AnimalRecord, area: BasePart)
	local model = record.model
	if not model or not model.PrimaryPart then
		return
	end
	record.homeArea = area
	record.homePosition = randomPointIn(area)
	record.roamFree = false
	record.nextMoveAt = os.clock() + rng:NextNumber(0.5, 2)
	local root = model.PrimaryPart
	root.Anchored = false
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = true
	end
	local prompt = root:FindFirstChild("CatchPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Enabled = false
	end
	model:PivotTo(placeOnGround(record.homePosition, model))
end

-- Parks an animal at a fixed spot: no walking, no catching.
function AnimalService.ParkAt(record: AnimalRecord, standOn: CFrame)
	local model = record.model
	if not model or not model.PrimaryPart then
		return
	end
	local root = model.PrimaryPart
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
	end
	local prompt = root:FindFirstChild("CatchPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Enabled = false
	end
	root.Anchored = true
	model:PivotTo(standOn * CFrame.new(0, model:GetExtentsSize().Y / 2, 0))
end

-- Resizes the model to match the record's growth (used while it grows).
function AnimalService.Rescale(record: AnimalRecord)
	local model = record.model
	if model then
		local goal = targetScale(record, model)
		if math.abs(model:GetScale() - goal) > 0.005 then
			model:ScaleTo(goal)
			local prompt = model.PrimaryPart and model.PrimaryPart:FindFirstChild("CatchPrompt")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.MaxActivationDistance = Config.Gameplay.capture.maxDistance
					- 2
					+ AnimalService.Radius(model)
			end
		end
	end
end

function AnimalService.Remove(record: AnimalRecord)
	if record.model then
		record.model:Destroy()
	end
	records[record.id] = nil
end

function AnimalService.Get(id: string): AnimalRecord?
	return records[id]
end

function AnimalService.All(): { [string]: AnimalRecord }
	return records
end

function AnimalService.SetCaptureHandler(handler: (Player, AnimalRecord) -> ())
	captureHandler = handler
end

-- Called when someone starts holding the catch prompt (theft warning).
function AnimalService.SetHoldBeganHandler(handler: (Player, AnimalRecord) -> ())
	holdBeganHandler = handler
end

local function countWild(biomeId: string): number
	local count = 0
	for _, record in records do
		if record.state == "Wild" and Config.Species[record.speciesId].biome == biomeId then
			count += 1
		end
	end
	return count
end

local function wanderStep(now: number)
	local radius = Config.Gameplay.spawning.wanderRadius
	for _, record in records do
		local model = record.model
		local wanders = record.state == "Wild" or record.state == "Loose" or record.state == "InBase"
		if model and wanders and now >= record.nextMoveAt then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local offset =
					Vector3.new(rng:NextNumber(-radius, radius), 0, rng:NextNumber(-radius, radius))
				local goal = if record.roamFree
					then record.homePosition + offset * 0.25
					else clampToArea(record.homeArea, record.homePosition + offset)
				humanoid:MoveTo(goal)
			end
			record.nextMoveAt = now + rng:NextNumber(3, 7)
		end
	end
end

function AnimalService.Start()
	-- Each model shows its record's state ("State" attribute) so clients can
	-- tell base and team pets from wild and loose ones (Show pets toggle).
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, record in records do
				local model = record.model
				if model and model:GetAttribute("State") ~= record.state then
					model:SetAttribute("State", record.state)
				end
			end
		end
	end)
	local map = workspace:WaitForChild("Map")
	for _, area in map:WaitForChild("SpawnAreas"):GetChildren() do
		if area:IsA("BasePart") then
			local biomeId = area:GetAttribute("BiomeId") :: string
			local speciesId = area:GetAttribute("SpeciesId")
			if typeof(speciesId) == "string" then
				local byKind = if area:GetAttribute("Rare") then rareAreasBySpecies else spawnAreasBySpecies
				byKind[speciesId] = byKind[speciesId] or {}
				table.insert(byKind[speciesId], area)
			else
				spawnAreasByBiome[biomeId] = spawnAreasByBiome[biomeId] or {}
				table.insert(spawnAreasByBiome[biomeId], area)
			end
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "Animals"
	folder.Parent = workspace
	animalsFolder = folder

	-- Fill every biome up to its target, then keep it topped up.
	task.spawn(function()
		local target = Config.Gameplay.spawning.animalsPerBiome
		while true do
			for biomeId in Config.Biomes do
				for _ = countWild(biomeId) + 1, target do
					AnimalService.SpawnWild(biomeId)
				end
			end
			task.wait(Config.Gameplay.spawning.respawnSeconds)
		end
	end)

	task.spawn(function()
		while true do
			wanderStep(os.clock())
			task.wait(0.5)
		end
	end)
end

return AnimalService
