--!strict
-- Growth happens only while an owned animal is loose. Each second it gains
-- progress towards adult and its model grows a little: at full speed in its
-- home biome, slower anywhere else (Config.Economy.growthBiomeFactor), times
-- the owner's Fast Growth research.
-- A short-range label shows the owner and stage, so a big animal is easy
-- to spot up close without announcing it to the whole server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimalMath = require(ReplicatedStorage.Shared.AnimalMath)
local Config = require(ReplicatedStorage.Shared.Config)
local AnimalService = require(script.Parent.AnimalService)
local ZoneService = require(script.Parent.ZoneService)

type AnimalRecord = AnimalService.AnimalRecord

local GrowthService = {}

local TICK_SECONDS = 1
local LABEL_DISTANCE = 45

local ownerNames: { [number]: string } = {}

local function ownerName(userId: number): string
	local cached = ownerNames[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = if player then player.DisplayName else "Someone"
	ownerNames[userId] = name
	return name
end

-- Growth speed factor from where the pet stands.
local function biomeFactor(record: AnimalRecord): number
	local root = record.model and record.model.PrimaryPart
	local zone = if root then ZoneService.ZoneAt(root.Position) else "None"
	local factors = Config.Economy.growthBiomeFactor
	return if zone == Config.Species[record.speciesId].biome then factors.home else factors.other
end

local function updateLabel(record: AnimalRecord)
	local root = record.model and record.model.PrimaryPart
	if not root or not record.ownerUserId then
		return
	end
	local gui = root:FindFirstChild("LooseLabel") :: BillboardGui?
	if not gui then
		local newGui = Instance.new("BillboardGui")
		newGui.Name = "LooseLabel"
		newGui.Size = UDim2.fromOffset(190, 60)
		newGui.MaxDistance = LABEL_DISTANCE
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0.2
		label.Parent = newGui
		newGui.Parent = root
		gui = newGui
	end
	local stage = AnimalMath.StageFor(record.growth)
	local label = (gui :: BillboardGui):FindFirstChild("Text") :: TextLabel
	local owner = ownerName(record.ownerUserId :: number)
	local species = Config.Species[record.speciesId].displayName
	local percent = math.floor(record.growth * 100)
	local pace = if record.growth >= 1
		then "Fully grown"
		elseif biomeFactor(record) >= 1 then "Growing fast (home biome)"
		else "Growing slowly"
	label.Text = `{owner}'s {species}\n{stage.id} {percent}%\n{pace}`
	-- Above the pet, whatever its size (it grows).
	(gui :: BillboardGui).StudsOffsetWorldSpace =
		Vector3.new(0, (record.model :: Model):GetExtentsSize().Y / 2 + 1.5, 0)
end

function GrowthService.Grow(record: AnimalRecord, seconds: number)
	local rarity = Config.Rarities[Config.Species[record.speciesId].rarity]
	seconds *= biomeFactor(record)
	local owner = record.ownerUserId and Players:GetPlayerByUserId(record.ownerUserId)
	local multiplier = owner and owner:GetAttribute("GrowthMultiplier") -- research
	seconds *= if typeof(multiplier) == "number" then multiplier else 1
	record.growth = math.min(1, record.growth + seconds / rarity.timeToAdultSeconds)
	AnimalService.Rescale(record)
	updateLabel(record)
end

function GrowthService.Start()
	Players.PlayerAdded:Connect(function(player)
		ownerNames[player.UserId] = player.DisplayName
	end)

	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			for _, record in AnimalService.All() do
				if record.state == "Loose" and record.ownerUserId then
					if record.growth < 1 then
						GrowthService.Grow(record, TICK_SECONDS)
					else
						updateLabel(record)
					end
				end
			end
		end
	end)
end

return GrowthService
