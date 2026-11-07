--!strict
-- Day timer: time until the next rare spawn, in the bottom-right corner as a clock icon, a small title and the
-- time. The last 30 seconds pulse in red. On touch-only screens it sits
-- top-right instead, because the jump button owns the bottom-right.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local DayHud = {}

function DayHud.Start()
	if Config.UI.userHudEnabled then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DayHud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local holder = Instance.new("Frame")
	holder.Name = "Timer"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = if touchOnly then Vector2.new(1, 0) else Vector2.new(1, 1)
	holder.Position = if touchOnly then UDim2.new(1, -16, 0, 8) else UDim2.new(1, -22, 1, -16)
	holder.Size = UDim2.fromOffset(220, 76)
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	local camera = Workspace.CurrentCamera
	local function rescale()
		scale.Scale =
			math.clamp(math.min(camera.ViewportSize.X / 1150, camera.ViewportSize.Y / 720), 0.55, 1.2)
	end
	rescale()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local icon = UITheme.Icon("timer", 64)
	if icon then
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.fromScale(0, 0.5)
		icon.Parent = holder
	end
	local title = UITheme.Label("DAY ENDS IN", 20, UITheme.colors.gold)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(72, 4)
	title.Size = UDim2.new(1, -72, 0, 24)
	title.Parent = holder
	local time = UITheme.Label("--:--", 46)
	time.TextXAlignment = Enum.TextXAlignment.Left
	time.Position = UDim2.fromOffset(72, 26)
	time.Size = UDim2.new(1, -72, 0, 48)
	time.Parent = holder
	local pulse = Instance.new("UIScale")
	pulse.Parent = time

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	RunService.RenderStepped:Connect(function()
		if icon then
			icon.Rotation = math.sin(os.clock() * 2) * 6 -- a gentle tick-tock
		end
		local endsAt = Workspace:GetAttribute("DayEndsAt")
		if typeof(endsAt) ~= "number" then
			return
		end
		local left = math.max(0, math.floor(endsAt - Workspace:GetServerTimeNow()))
		time.Text = string.format("%02d:%02d", left // 60, left % 60)
		-- The last half minute pulses: a new rare spawn is approaching.
		local hurry = left <= 30
		pulse.Scale = if hurry then 1 + 0.08 * math.abs(math.sin(os.clock() * 5)) else 1
		time.TextColor3 = if hurry then Color3.fromRGB(255, 110, 100) else Color3.new(1, 1, 1)
	end)
end

return DayHud
