--!strict
-- Each area has its own light: the plaza neutral and bright, the forest a
-- little cooler and greener, the desert warm. Eases the colour correction
-- (Lighting.FreeAPetColor) when the player's Zone attribute changes. Only
-- this client's Lighting changes; the fog of the forest hazard is separate
-- (ForestFog) and stacks on top.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ZoneMood = {}

type Mood = { tint: Color3, saturation: number, contrast: number, brightness: number }

local MOODS: { [string]: Mood } = {
	Base = { tint = Color3.fromRGB(255, 250, 242), saturation = 0.04, contrast = 0.12, brightness = 0 },
	Forest = { tint = Color3.fromRGB(238, 252, 244), saturation = 0.02, contrast = 0.14, brightness = -0.02 },
	Desert = { tint = Color3.fromRGB(255, 238, 214), saturation = 0.06, contrast = 0.1, brightness = 0.03 },
}

function ZoneMood.Start()
	local correction = Lighting:FindFirstChild("FreeAPetColor")
	if not correction or not correction:IsA("ColorCorrectionEffect") then
		return
	end
	local player = Players.LocalPlayer
	local current: Tween? = nil
	local function apply()
		local zone = player:GetAttribute("Zone")
		local mood = MOODS[if typeof(zone) == "string" then zone else "Base"] or MOODS.Base
		if current then
			current:Cancel()
		end
		local tween = TweenService:Create(correction, TweenInfo.new(2.5, Enum.EasingStyle.Sine), {
			TintColor = mood.tint,
			Saturation = mood.saturation,
			Contrast = mood.contrast,
			Brightness = mood.brightness,
		})
		current = tween
		tween:Play()
	end
	player:GetAttributeChangedSignal("Zone"):Connect(apply)
	apply()
end

return ZoneMood
