--!strict
-- "Release here" button, shown while the player carries one of their own
-- pets (attribute CarryingOwn). Outside the Safe Zone it asks the server to
-- drop the pet at the player's feet; inside it is grey and explains why.
-- Keyboard G and gamepad X do the same as tapping it.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local ReleaseButton = {}

function ReleaseButton.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "ReleaseButton"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local viewport = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X, viewport.Y) / 720, 0.7, 1.3)
	end
	rescale()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- The holder pops in when the button appears (the button's own UIScale
	-- is for hover and press).
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -24)
	holder.Size = UDim2.fromOffset(300, 76)
	holder.Parent = gui
	local pop = Instance.new("UIScale")
	pop.Parent = holder

	local button, label = UITheme.Button("green", UDim2.fromScale(1, 1), "")
	button.Name = "Release"
	button.Parent = holder
	label.Position = UDim2.fromOffset(70, 0)
	label.Size = UDim2.new(1, -76, 1, 0)
	UITheme.FitText(label, 26)

	local icon = UITheme.Icon("release", 58)
	if icon then
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 10, 0.5, 0)
		icon.ZIndex = 4
		icon.Parent = button
	end

	local function inSafeZone(): boolean
		return player:GetAttribute("Zone") == "Base" or player:GetAttribute("InSafeZone") == true
	end

	local function refresh()
		local carrying = player:GetAttribute("CarryingOwn")
		local shown = typeof(carrying) == "number" and carrying > 0
		if shown and not gui.Enabled then
			pop.Scale = 0.3
			TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
		gui.Enabled = shown
		local blocked = inSafeZone()
		UITheme.Recolor(button, if blocked then UITheme.colors.disabled else UITheme.colors.success)
		local keyHint = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
			then ""
			else " (G)"
		label.Text = if blocked then "Leave the Safe Zone to release" else `Release here{keyHint}`
	end

	local function release()
		if gui.Enabled and not inSafeZone() then
			Remotes.Get("ReleaseCarried"):FireServer()
		end
	end
	button.Activated:Connect(release)
	ContextActionService:BindAction("ReleasePet", function(_, state)
		if state == Enum.UserInputState.Begin then
			release()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.G, Enum.KeyCode.ButtonX)

	for _, name in { "CarryingOwn", "Zone", "InSafeZone" } do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()
	gui.Parent = player:WaitForChild("PlayerGui")
end

return ReleaseButton
