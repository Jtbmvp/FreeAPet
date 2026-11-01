--!strict
-- Builds the physical model of an animal. Uses the real art from
-- ReplicatedStorage.Assets.Animals.<modelName> when it exists, otherwise a
-- placeholder. Either way the result is a Model with an invisible
-- HumanoidRootPart (welded to every visual part) and a Humanoid, so the
-- rest of the code never depends on the art.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PetAnimations = require(ReplicatedStorage.Shared.PetAnimations)

local AnimalFactory = {}

-- Placeholder look per species: body color, accent color, body size.
local PLACEHOLDERS: { [string]: { body: Color3, accent: Color3, size: Vector3 } } = {
	AcornSquirrel = {
		body = Color3.fromRGB(190, 110, 50),
		accent = Color3.fromRGB(120, 70, 30),
		size = Vector3.new(2.5, 2.5, 3),
	},
	HoppingMushroom = {
		body = Color3.fromRGB(230, 60, 60),
		accent = Color3.fromRGB(245, 240, 220),
		size = Vector3.new(3, 3, 3),
	},
	BranchDeer = {
		body = Color3.fromRGB(170, 120, 75),
		accent = Color3.fromRGB(90, 60, 35),
		size = Vector3.new(3, 4, 5),
	},
	RunningCactus = {
		body = Color3.fromRGB(80, 170, 80),
		accent = Color3.fromRGB(240, 120, 170),
		size = Vector3.new(2.5, 3.5, 2.5),
	},
	BallScorpion = {
		body = Color3.fromRGB(60, 50, 50),
		accent = Color3.fromRGB(230, 170, 60),
		size = Vector3.new(3.5, 2, 3.5),
	},
	SunCamel = {
		body = Color3.fromRGB(245, 225, 190),
		accent = Color3.fromRGB(255, 190, 60),
		size = Vector3.new(3.5, 4.5, 5.5),
	},
}

local function newPart(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Plastic
	part.TopSurface = Enum.SurfaceType.Studs
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.Massless = true
	return part
end

local function buildPlaceholder(speciesId: string): Model
	local look = PLACEHOLDERS[speciesId]
		or { body = Color3.new(1, 1, 1), accent = Color3.new(0, 0, 0), size = Vector3.new(3, 3, 3) }
	local model = Instance.new("Model")

	local body = newPart("Body", look.size, look.body)
	body.Parent = model

	local headSize = Vector3.one * math.min(look.size.X, look.size.Y) * 0.7
	local head = newPart("Head", headSize, look.body)
	head.CFrame = CFrame.new(0, look.size.Y * 0.35, -(look.size.Z / 2 + headSize.Z * 0.35))
	head.Parent = model

	for _, side in { -1, 1 } do
		local eye = newPart("Eye", Vector3.new(0.35, 0.35, 0.1), Color3.new(0.05, 0.05, 0.05))
		eye.Material = Enum.Material.SmoothPlastic
		eye.CFrame = head.CFrame
			* CFrame.new(side * headSize.X * 0.25, headSize.Y * 0.15, -headSize.Z / 2 - 0.05)
		eye.Parent = model
	end

	local accent = newPart("Accent", Vector3.new(look.size.X * 0.6, 0.4, look.size.Z * 0.6), look.accent)
	accent.CFrame = CFrame.new(0, look.size.Y / 2 + 0.2, 0)
	accent.Parent = model

	return model
end

local function newBone(name: string, cframe: CFrame): Part
	local bone = Instance.new("Part")
	bone.Name = name
	bone.Size = Vector3.one * 0.1
	bone.CFrame = cframe
	bone.Transparency = 1
	bone.CanCollide = false
	bone.CanQuery = false
	bone.CanTouch = false
	bone.Massless = true
	return bone
end

-- The importer keeps the art's jnt_* hierarchy but no joints. Rebuild them
-- from the exported rig (PetAnimations): a RootPart, one invisible bone per
-- joint linked by Motor6Ds named after the joint, and every art part welded to
-- the bone of its nearest jnt_* ancestor. Clients then animate the Motor6Ds.
local function addJoints(model: Model, speciesId: string)
	local data = PetAnimations.Get(speciesId)
	if not data or model:FindFirstChild("RootPart") then
		return
	end
	local pivot = model:GetPivot()
	local root = newBone("RootPart", pivot * PetAnimations.ToCFrame(data.root))
	root.Parent = model

	local bones: { [string]: BasePart } = { RootPart = root }
	for _, joint in data.joints do
		local parentBone = bones[joint.parent]
		if parentBone then
			local bone = newBone(`Bone_{joint.name}`, pivot * PetAnimations.ToCFrame(joint.frame))
			bone.Parent = model
			local motor = Instance.new("Motor6D")
			motor.Name = joint.name
			motor.Part0 = parentBone
			motor.Part1 = bone
			motor.C0 = parentBone.CFrame:ToObjectSpace(bone.CFrame)
			motor.Parent = bone
			bones[joint.name] = bone
		end
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.Name:match("^Bone_") and part ~= root then
			local holder = part.Parent
			while holder and holder ~= model and not bones[holder.Name] do
				holder = holder.Parent
			end
			local bone = if holder and holder ~= model then bones[holder.Name] else root
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = bone
			weld.Part1 = part
			weld.Parent = part
		end
	end
end

-- Attaches the art to a new invisible root (sized to the art) and adds a
-- Humanoid. Art from the 3D Importer comes rigged: every piece hangs off its
-- "RootPart" through a Motor6D, so only that part is welded and the motors
-- stay free for animations. Other art has every part welded to the root.
local function rig(model: Model): Model
	-- Keep only the pivot's position: a rotated pivot (Roblox borrows a
	-- part's rotation when a model has none) would tip the animal over.
	model.WorldPivot = CFrame.new(model:GetPivot().Position)
	local artRoot = model:FindFirstChild("RootPart")
	local rigged = artRoot ~= nil
		and artRoot:IsA("BasePart")
		and model:FindFirstChildWhichIsA("Motor6D", true) ~= nil

	local center, bounds = model:GetBoundingBox()
	if rigged then
		-- The importer's RootPart is a fixed-size block; measure the art alone.
		(artRoot :: BasePart).Transparency = 1
		local parts = {}
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part ~= artRoot then
				table.insert(parts, part)
			end
		end
		local holder = Instance.new("Model")
		for _, part in parts do
			part.Parent = holder
		end
		center, bounds = holder:GetBoundingBox()
		for _, part in parts do
			part.Parent = model
		end
		holder:Destroy()
	end

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(bounds.X, bounds.Y, bounds.Z)
	root.CFrame = center
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model
	model.PrimaryPart = root

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			if not rigged or part == artRoot then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = Config.Gameplay.spawning.wanderSpeed
	humanoid.Parent = model

	return model
end

function AnimalFactory.Build(speciesId: string): Model
	local species = Config.Species[speciesId]
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local animals = assets and assets:FindFirstChild("Animals")
	local art = animals and animals:FindFirstChild(species.modelName)

	local model = if art and art:IsA("Model") then art:Clone() else buildPlaceholder(speciesId)
	model.Name = species.displayName
	if art then
		addJoints(model, speciesId)
	end
	rig(model)
	-- Normalise the art to the species height; AnimalService scales on top of
	-- this (size and growth) through the BaseScale attribute.
	local artHeight = (model.PrimaryPart :: BasePart).Size.Y
	local baseScale = if artHeight > 0 then species.heightStuds / artHeight else 1
	model:ScaleTo(baseScale)
	model:SetAttribute("BaseScale", baseScale)
	return model
end

return AnimalFactory
