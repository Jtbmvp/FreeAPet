--!strict
-- Exposure bar at the top centre, stud style. Hidden at 0; turns red and
-- pulses from the warning threshold so nobody gets expelled by surprise.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local ExposureHud = {}

local HAZARDS = {
	Heat = {
		label = "HEAT",
		icon = "heat",
		top = Color3.fromRGB(255, 205, 70),
		bottom = Color3.fromRGB(255, 120, 20),
	},
	LowVisibility = {
		label = "DARKNESS",
		icon = "darkness",
		top = Color3.fromRGB(150, 140, 255),
		bottom = Color3.fromRGB(80, 60, 200),
	},
}
local DANGER_TOP, DANGER_BOTTOM = Color3.fromRGB(255, 95, 80), Color3.fromRGB(190, 35, 45)

function ExposureHud.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "ExposureHud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Name = "Bar"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 20, 0, 12)
	frame.Size = UDim2.fromOffset(300, 34)
	frame.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	frame.Visible = false
	UITheme.Corner(frame, 5)
	UITheme.Outline(frame)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	UITheme.Corner(fill, 4)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = fill
	UITheme.Shine(fill)
	UITheme.Studs(fill, 22, 0.25)
	fill.Parent = frame
	UITheme.InnerBorder(frame)

	local label = UITheme.Label("", 18)
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 4
	label.Parent = frame

	local icons: { [string]: ImageLabel } = {}
	for hazardId, style in HAZARDS do
		local icon = UITheme.Icon(style.icon, 54)
		if icon then
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.new(0, -6, 0.5, 0)
			icon.ZIndex = 5
			icon.Visible = false
			icon.Parent = frame
			icons[hazardId] = icon
		end
	end

	frame.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	RunService.RenderStepped:Connect(function()
		local value = player:GetAttribute("Exposure")
		local hazardId = player:GetAttribute("ExposureHazard")
		local style = typeof(hazardId) == "string" and HAZARDS[hazardId]
		if typeof(value) ~= "number" or value < 0.5 or not style then
			frame.Visible = false
			return
		end
		frame.Visible = true
		for id, icon in icons do
			icon.Visible = id == hazardId
		end
		fill.Size = UDim2.fromScale(value / Config.Exposure.maxValue, 1)
		label.Text = `{style.label} {math.floor(value)}%`

		local danger = value >= Config.Exposure.warningAt
		if danger then
			local pulse = (math.sin(os.clock() * 8) + 1) / 2
			gradient.Color =
				ColorSequence.new(style.top:Lerp(DANGER_TOP, pulse), style.bottom:Lerp(DANGER_BOTTOM, pulse))
		else
			gradient.Color = ColorSequence.new(style.top, style.bottom)
		end
	end)
end

return ExposureHud
