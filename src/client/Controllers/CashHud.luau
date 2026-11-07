--!strict
-- Bottom-left money block, stud style: walk speed (shoe + number), cash
-- (bills icon + big green number that counts up smoothly) and income per
-- second. "+$" pops rise from the counter as cash comes in. Reads the
-- "Cash", "IncomePerSecond" and "WalkSpeed" attributes set by the server.
-- On touch-only devices it sits top-left so the thumbstick never covers it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local CashHud = {}

local function row(parent: Instance, order: number, iconKey: string, iconSize: number): (Frame, TextLabel)
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.Size = UDim2.fromOffset(0, 0)
	frame.LayoutOrder = order
	frame.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = frame
	local icon = UITheme.Icon(iconKey, iconSize)
	if icon then
		icon.Parent = frame
	end
	local text = UITheme.Label("", 20)
	text.AutomaticSize = Enum.AutomaticSize.XY
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.LayoutOrder = 1
	text.Parent = frame
	return frame, text
end

function CashHud.Start()
	if Config.UI.userHudEnabled then
		return
	end
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "CashHud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Name = "Money"
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.Size = UDim2.fromOffset(0, 0)
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = frame

	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	if touchOnly then
		frame.AnchorPoint = Vector2.new(0, 0)
		frame.Position = UDim2.fromOffset(16, 12)
	else
		frame.AnchorPoint = Vector2.new(0, 1)
		frame.Position = UDim2.new(0, 22, 1, -18)
	end

	local _, speed = row(frame, 1, "speed", 56)
	speed.TextSize = 34
	speed.TextColor3 = UITheme.colors.speed
	local cashRow, amount = row(frame, 2, "cash", 84)
	amount.TextSize = 56
	amount.TextColor3 = UITheme.colors.cash
	local _, perSecond = row(frame, 3, "", 0)
	perSecond.TextSize = 26
	cashRow.LayoutOrder = 2

	-- Scale with the screen so it stays readable on phones and big monitors.
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local camera = Workspace.CurrentCamera :: Camera
	local function rescale()
		scale.Scale =
			math.clamp(math.min(camera.ViewportSize.X / 1150, camera.ViewportSize.Y / 720), 0.55, 1.2)
	end
	rescale()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	gui.Parent = player:WaitForChild("PlayerGui")

	local shown = 0
	local function target(): number
		local value = player:GetAttribute("Cash")
		return if typeof(value) == "number" then value else 0
	end
	local function refreshPerSecond()
		local value = player:GetAttribute("IncomePerSecond")
		perSecond.Text = `Income: +${Format.Short(if typeof(value) == "number" then value else 0)}/s`
	end
	local function refreshSpeed()
		local value = player:GetAttribute("WalkSpeed")
		speed.Text =
			Format.Short(if typeof(value) == "number" then value else Config.Gameplay.player.walkSpeed)
	end
	player:GetAttributeChangedSignal("IncomePerSecond"):Connect(refreshPerSecond)
	player:GetAttributeChangedSignal("WalkSpeed"):Connect(refreshSpeed)
	refreshPerSecond()
	refreshSpeed()

	-- "+$" rising from the counter when cash comes in, and a little bump.
	local bump = Instance.new("UIScale")
	bump.Parent = amount
	local last = target()
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		local now = target()
		local gained = now - last
		last = now
		if gained <= 0 then
			return
		end
		bump.Scale = 1.12
		TweenService:Create(bump, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		local pop = UITheme.Label(`+${Format.Short(gained)}`, 30, UITheme.colors.cash)
		pop.AutomaticSize = Enum.AutomaticSize.XY
		pop.AnchorPoint = Vector2.new(0, 1)
		pop.Position = UDim2.fromOffset(
			amount.AbsolutePosition.X + amount.AbsoluteSize.X + 10,
			amount.AbsolutePosition.Y + 20
		)
		pop.Rotation = math.random(-8, 8)
		pop.Parent = gui
		local stroke = pop:FindFirstChildOfClass("UIStroke")
		TweenService:Create(pop, TweenInfo.new(1, Enum.EasingStyle.Quad), {
			Position = pop.Position - UDim2.fromOffset(0, 60),
			TextTransparency = 1,
		}):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(1), { Transparency = 1 }):Play()
		end
		task.delay(1, function()
			pop:Destroy()
		end)
	end)

	RunService.RenderStepped:Connect(function(dt)
		local goal = target()
		-- Ease towards the real value; snap when close.
		shown += (goal - shown) * math.min(1, dt * 8)
		if math.abs(goal - shown) < 0.005 then
			shown = goal
		end
		amount.Text = `${Format.Short(shown)}`
	end)
end

return CashHud
