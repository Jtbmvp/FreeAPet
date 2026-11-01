--!strict
-- Studio-only overlay showing the player's plot and zone attributes.

local Players = game:GetService("Players")

local DebugHud = {}

function DebugHud.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "DebugHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100

	local label = Instance.new("TextLabel")
	label.Name = "Info"
	label.Position = UDim2.fromOffset(12, 60) -- top-left under Roblox's buttons: the corners hold the HUD
	label.Size = UDim2.fromOffset(220, 86)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.4
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 14
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
	player:GetAttributeChangedSignal("InBattle"):Connect(function()
		label.Visible = player:GetAttribute("InBattle") ~= true
	end)
end

return DebugHud
