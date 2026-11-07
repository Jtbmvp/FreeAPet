--!strict
-- Studio-only overlay showing the player's plot and zone attributes.

local Players = game:GetService("Players")

local DebugHud = {}

function DebugHud.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "DebugHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1 -- always under the HUD, so it can never cover a button

	local label = Instance.new("TextLabel")
	label.Name = "Info"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.42, 0, 1, -4) -- bottom centre: between the thumbstick and the action button
	label.Size = UDim2.fromOffset(170, 62)
	label.Active = false
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.4
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 10
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	local function refresh()
		label.Text = string.format(
			" DEBUG\n Plot: %s\n Zone: %s\n Safe: %s  Own base: %s\n Carrying: %s",
			tostring(player:GetAttribute("PlotIndex")),
			tostring(player:GetAttribute("Zone")),
			tostring(player:GetAttribute("InSafeZone")),
			tostring(player:GetAttribute("InOwnBase")),
			tostring(player:GetAttribute("CarryCount"))
		)
	end
	player.AttributeChanged:Connect(refresh)
	refresh()
	-- Out of the way of the battle buttons.
	local function visibility()
		label.Visible = player:GetAttribute("InBattle") ~= true and player:GetAttribute("MenuOpen") ~= true
	end
	player:GetAttributeChangedSignal("InBattle"):Connect(visibility)
	player:GetAttributeChangedSignal("MenuOpen"):Connect(visibility)
end

return DebugHud
