--!strict
-- Forest hazard (OPEN #7): fog that thickens with the player's Forest
-- exposure. Only this client's Lighting changes, so other players still
-- see the world normally. Leaving the Forest eases back to the defaults.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local ForestFog = {}

function ForestFog.Start()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0
		atmosphere.Parent = Lighting
	end
	local atmo = atmosphere :: Atmosphere
	local player = Players.LocalPlayer
	local fog = Config.Exposure.hazards.LowVisibility.fog

	local defaults = {
		density = atmo.Density,
		haze = atmo.Haze,
		offset = atmo.Offset,
		color = atmo.Color,
		decay = atmo.Decay,
	}
	local amount = 0 -- 0 = defaults, 1 = full fog

	RunService.RenderStepped:Connect(function(dt)
		-- Follows the Forest meter even after leaving the Forest, so the fog
		-- fades out as the meter drains instead of vanishing.
		local exposure = player:GetAttribute("Exposure_Forest")
		local goal = if typeof(exposure) == "number" then math.clamp(exposure / fog.fullAt, 0, 1) else 0
		if goal == 0 and amount == 0 then
			return -- clear weather: leave Lighting alone
		end
		amount += (goal - amount) * math.min(1, dt * 2)
		if goal == 0 and amount < 0.001 then
			amount = 0
		end

		atmo.Density = defaults.density + (fog.maxDensity - defaults.density) * amount
		atmo.Haze = defaults.haze + (fog.maxHaze - defaults.haze) * amount
		atmo.Offset = defaults.offset * (1 - amount)
		atmo.Color = defaults.color:Lerp(fog.color, amount)
		atmo.Decay = defaults.decay:Lerp(fog.color, amount)
	end)
end

return ForestFog
