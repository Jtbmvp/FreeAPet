--!strict
-- Hides what clutters a battle, only for the player in it
-- (docs/BATTLE-POLISH-PLAN.md §5.2): other pets, other players and small
-- props inside the ring (plus a margin) or in the battle camera's lines of
-- sight. Uses LocalTransparencyModifier and local Enabled flags, never
-- replicated properties, and puts everything back when the battle ends.
-- The current map's art is merged per material, so only its small separate
-- pieces can hide; props tagged "BattleHideable" (the new map) hide one by
-- one. Pets and players move, so they are checked again every second.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local BattleObstacles = {}

local TAG = "BattleHideable"
local MARGIN = 4 -- studs past the ring
local SIGHT_RADIUS = 3.5 -- studs around each camera line of sight
local SMALL_ART = 40 -- map art bigger than this is ground or a merged layer: never hidden
local MIN_ART_HEIGHT = 1.5 -- flatter art is floor: never hidden
local SWITCHED = { "BillboardGui", "SurfaceGui", "ParticleEmitter", "Beam", "Trail", "Light", "Highlight" }

local transparency: { [Instance]: number } = {} -- parts and decals: their LocalTransparencyModifier before
local switches: { [Instance]: boolean } = {} -- guis, emitters, lights: Enabled before
local nameTags: { [Humanoid]: Enum.HumanoidDisplayDistanceType } = {}
local keep: { [Instance]: boolean } = {}
local centre = Vector3.zero
local radius = 0
local sights: { { Vector3 } } = {} -- camera lines of sight: { from, to }
local generation = 0 -- bumped by Hide and Restore: stops the old re-check loop
local smallArt: { BasePart }? = nil

local function distanceToSegment(point: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local t = math.clamp((point - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (point - (a + ab * t)).Magnitude
end

-- Inside the ring (flat distance) or close to a camera line of sight.
local function obstructs(position: Vector3, size: Vector3): boolean
	local reach = size.Magnitude / 2
	local flat = Vector3.new(position.X - centre.X, 0, position.Z - centre.Z).Magnitude
	if flat - reach <= radius then
		return true
	end
	for _, line in sights do
		if distanceToSegment(position, line[1], line[2]) - reach <= SIGHT_RADIUS then
			return true
		end
	end
	return false
end

local function hideOne(item: Instance)
	if item:IsA("BasePart") or item:IsA("Decal") or item:IsA("Texture") then
		if transparency[item] == nil then
			local ok, before = pcall(function()
				return (item :: any).LocalTransparencyModifier
			end)
			if ok then
				transparency[item] = before
				pcall(function()
					(item :: any).LocalTransparencyModifier = 1
				end)
			end
		end
		return
	end
	if item:IsA("Humanoid") then
		if nameTags[item] == nil then
			nameTags[item] = item.DisplayDistanceType
			item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		return
	end
	for _, className in SWITCHED do
		if item:IsA(className) then
			if switches[item] == nil then
				switches[item] = (item :: any).Enabled;
				(item :: any).Enabled = false
			end
			return
		end
	end
end

local function hide(root: Instance)
	hideOne(root)
	for _, item in root:GetDescendants() do
		hideOne(item)
	end
end

local function consider(object: Instance)
	if keep[object] then
		return
	end
	if object:IsA("Model") then
		local cframe, size = object:GetBoundingBox()
		if obstructs(cframe.Position, size) then
			hide(object)
		end
	elseif object:IsA("BasePart") then
		if obstructs(object.Position, object.Size) then
			hide(object)
		end
	end
end

-- What moves: loose and wild pets, other players' team pets, other players.
local function scanMoving()
	local animals = Workspace:FindFirstChild("Animals")
	if animals then
		for _, model in animals:GetChildren() do
			consider(model)
		end
	end
	for _, other in Players:GetPlayers() do
		if other ~= Players.LocalPlayer and other.Character then
			consider(other.Character)
		end
	end
end

-- The map's small separate art pieces, collected once per session.
local function artPieces(): { BasePart }
	if smallArt then
		return smallArt
	end
	local found: { BasePart } = {}
	local map = Workspace:FindFirstChild("Map")
	for _, folderName in { "Art", "FX" } do
		local folder = map and map:FindFirstChild(folderName)
		for _, part in (folder and folder:GetDescendants() or {}) do
			if part:IsA("BasePart") then
				local size = part.Size
				if math.max(size.X, size.Y, size.Z) <= SMALL_ART and size.Y >= MIN_ART_HEIGHT then
					table.insert(found, part)
				end
			end
		end
	end
	smallArt = found
	return found
end

-- Hides the clutter around a battle at `arenaCentre`. `keepList`: the
-- fighters, our team and the people in the battle. `eye`: the gameplay
-- camera position; `targets`: what it looks at.
function BattleObstacles.Hide(
	arenaCentre: Vector3,
	keepList: { Instance? },
	eye: Vector3,
	targets: { Vector3 }
)
	BattleObstacles.Restore()
	generation += 1
	local mine = generation
	centre = arenaCentre
	radius = Config.Battle.arenaRadius + MARGIN
	table.clear(keep)
	for _, item in keepList do
		if item then
			keep[item] = true
		end
	end
	sights = {}
	for _, target in targets do
		table.insert(sights, { eye, target })
	end

	for _, part in artPieces() do
		consider(part)
	end
	for _, tagged in CollectionService:GetTagged(TAG) do
		consider(tagged)
	end
	scanMoving()
	task.spawn(function()
		while true do
			task.wait(1)
			if generation ~= mine then
				return
			end
			scanMoving()
		end
	end)
end

-- Puts back everything this module hid. Safe to call more than once.
function BattleObstacles.Restore()
	generation += 1
	for item, before in transparency do
		if item.Parent then
			pcall(function()
				(item :: any).LocalTransparencyModifier = before
			end)
		end
	end
	for item, before in switches do
		if item.Parent then
			(item :: any).Enabled = before
		end
	end
	for humanoid, before in nameTags do
		if humanoid.Parent then
			humanoid.DisplayDistanceType = before
		end
	end
	table.clear(transparency)
	table.clear(switches)
	table.clear(nameTags)
end

-- How many things are hidden right now (for tests).
function BattleObstacles.Count(): number
	local count = 0
	for _ in transparency do
		count += 1
	end
	return count
end

return BattleObstacles
