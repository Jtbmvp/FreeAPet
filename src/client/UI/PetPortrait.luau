--!strict
-- A 3D portrait of a species for the UI: a ViewportFrame holding a copy of
-- its art (ReplicatedStorage.Assets.Animals), seen from the front-left.
-- Silhouette mode draws it black, for Index entries not seen yet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PetPortrait = {}

function PetPortrait.New(speciesId: string, silhouette: boolean?): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(190, 190, 200)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-0.5, -1, 0.6)
	if silhouette then
		viewport.ImageColor3 = Color3.new(0, 0, 0)
		viewport.ImageTransparency = 0.15
	end

	local species = Config.Species[speciesId]
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local animals = assets and assets:FindFirstChild("Animals")
	local art = species and animals and animals:FindFirstChild(species.modelName)
	if not art or not art:IsA("Model") then
		return viewport
	end
	local model = art:Clone()
	model.Parent = viewport

	local centre, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	-- Pets face -Z: look at the front, a little from the left and above.
	local direction = Vector3.new(-0.55, 0.3, -1).Unit
	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 0.85
	camera.CFrame = CFrame.lookAt(centre.Position + direction * distance, centre.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

return PetPortrait
