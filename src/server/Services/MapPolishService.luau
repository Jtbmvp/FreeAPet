--!strict
-- Runtime touches on the imported mesh map (Workspace.Map.Art) that keep the
-- original import untouched and reversible:
--   * floor colours get the denser stud textures of Config.MapTextures
--     (uploaded ids; in Studio a local preview while an id is empty).
-- Mesh folders are named after their material ("SafeZone_plaza_lawn",
-- sometimes with a ".001" suffix).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local MapPolishService = {}

local function textureFor(folder: string): string?
	local id = Config.MapTextures[folder]
	if id == nil then
		return nil
	end
	if id ~= "" then
		return id
	end
	return if RunService:IsStudio() and Config.Debug.enabled
		then `rbxasset://freeapet/map/{folder}.png`
		else nil
end

function MapPolishService.Start()
	local art = Workspace:WaitForChild("Map"):WaitForChild("Art")
	local swapped = 0
	for _, part in art:GetDescendants() do
		if part:IsA("MeshPart") and part.Parent then
			local folder = (part.Parent.Name:gsub("%.%d+$", ""))
			local texture = textureFor(folder)
			if texture then
				part.TextureID = texture
				swapped += 1
			end
		end
	end
	if swapped > 0 then
		print(`[MapPolish] denser floor textures on {swapped} meshes`)
	end
end

return MapPolishService
