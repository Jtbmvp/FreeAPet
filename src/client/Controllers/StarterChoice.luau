--!strict
-- Independent first-entry chooser; does not edit the Nova-owned HUD broker.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Remotes = require(RS.Shared.Remotes)
local Input = game:GetService("UserInputService")
local StarterChoice = {}
function StarterChoice.Start()
	local Config = require(RS.Shared.Config)
	if Config.UI.userHudEnabled and Config.UI.designHudEnabled then
		return require(script.Parent.Parent.UI.DesignStarter).Start()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "StarterChoice"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Enabled = false
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0, 160)
	panel.BackgroundColor3 = Color3.fromRGB(28, 33, 48)
	panel.Active = true
	panel.SelectionGroup = true
	panel.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, 160)
	limit.Parent = panel
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 8)
	title.Size = UDim2.new(1, -24, 0, 40)
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextSize = 22
	title.Parent = panel
	local buttons: { TextButton } = {}
	local nextIndex = 0
	local waiting = false
	local previousFocus: GuiObject? = nil
	for index = 1, 3 do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1 / 3, -16, 0, 80)
		button.Position = UDim2.new((index - 1) / 3, 8, 0, 60)
		button.TextSize = 20
		button.TextColor3 = Color3.new(1, 1, 1)
		button.BackgroundColor3 = Color3.fromRGB(64, 85, 130)
		button.Parent = panel
		button.Activated:Connect(function()
			if waiting or not button.Visible then
				return
			end
			waiting = true
			title.Text = "Saving your starter…"
			for _, b in buttons do
				b.Active = false
				b.Selectable = false
			end
			Remotes.Get("ChooseStarter"):FireServer(nextIndex, button.Text)
		end)
		buttons[index] = button
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function render(snapshot: any)
		if not snapshot then
			return
		end
		local wasOpen = gui.Enabled
		gui.Enabled = snapshot.available or (snapshot.pending and waiting)
		nextIndex = snapshot.nextIndex
		waiting = snapshot.pending == true
		title.Text = if waiting then "Saving your starter…" else "Choose your free starter"
		for i, button in buttons do
			button.Visible = snapshot.choices[i] ~= nil
			button.Text = snapshot.choices[i] or ""
			button.Active = not waiting
			button.Selectable = not waiting
		end
		if gui.Enabled and not wasOpen then
			previousFocus = GuiService.SelectedObject
			if Input.PreferredInput == Enum.PreferredInput.Gamepad then
				GuiService.SelectedObject = buttons[1]
			end
		elseif wasOpen and not gui.Enabled then
			GuiService.SelectedObject = if previousFocus and previousFocus.Parent then previousFocus else nil
		end
	end
	Remotes.Get("StarterResult").OnClientEvent:Connect(function(result)
		if result.phase == "Committed" then
			render(result.snapshot)
		end
	end)
	-- One bounded read every 3s: supports level10/20 and late save reconciliation.
	while gui.Parent do
		local ok, snapshot = pcall(function()
			return Remotes.GetFunction("GetStarters"):InvokeServer()
		end)
		if ok then
			render(snapshot)
		end
		task.wait(3)
	end
end
return StarterChoice
