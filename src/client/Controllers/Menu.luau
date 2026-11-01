--!strict
-- The main menu: a two-column grid of square stud buttons on the left edge
-- (Pets, Index, Research, Trade, Settings). Each opens its own window; only
-- one window is open at a time. Window contents are modules in Client.UI
-- with Mount(container, api) -> { Show, Hide }. The running research's
-- countdown sits on the Research button. Key T opens Pets, gamepad B closes.
-- The menu hides during battles.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UITheme = require(ReplicatedStorage.Shared.UITheme)
local PetVisibility = require(script.Parent.PetVisibility)
local UI = script.Parent.Parent.UI
local IndexTab = require(UI.IndexTab)
local InventoryTab = require(UI.InventoryTab)
local ResearchTab = require(UI.ResearchTab)
local SettingsTab = require(UI.SettingsTab)
local TradeTab = require(UI.TradeTab)

type TabHandle = { Show: () -> (), Hide: () -> () }

local Menu = {}

local ENTRIES = {
	{ id = "Pets", icon = "paw", kind = "orange", module = InventoryTab, size = Vector2.new(680, 500) },
	{ id = "Index", icon = "research", kind = "blue", module = IndexTab, size = Vector2.new(620, 500) },
	{ id = "Research", icon = "upgrade", kind = "pink", module = ResearchTab, size = Vector2.new(720, 560) },
	{ id = "Trade", icon = "trade", kind = "green", module = TradeTab, size = Vector2.new(680, 520) },
	{ id = "Settings", icon = "settings", kind = "grey", module = SettingsTab, size = Vector2.new(520, 500) },
}

function Menu.Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "Menu"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Everything scales with the screen (phones get a smaller menu).
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local viewport = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X / 1150, viewport.Y / 720), 0.5, 1.3)
	end
	rescale()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Left button grid. On touch-only devices the money block sits top-left
	-- (the thumbstick owns the bottom-left), so the grid goes under it.
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local shownAt = if touchOnly then UDim2.fromOffset(12, 220) else UDim2.new(0, 12, 0.42, 0)
	local grid = Instance.new("Frame")
	grid.Name = "Buttons"
	grid.BackgroundTransparency = 1
	grid.AnchorPoint = if touchOnly then Vector2.zero else Vector2.new(0, 0.5)
	grid.Position = shownAt
	grid.Size = UDim2.fromOffset(196, 300)
	grid.Parent = gui
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(88, 88)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	-- "Show pets" toggle above the buttons (in Decor so the grid layout skips it).
	local extras = Instance.new("Folder")
	extras.Name = "Decor"
	extras.Parent = grid
	local showPets, showLabel = UITheme.Button("green", UDim2.fromOffset(196, 46), "Show pets: ON")
	showPets.Position = UDim2.fromOffset(0, -56)
	showPets.Parent = extras
	showPets.Activated:Connect(function()
		local on = not PetVisibility.IsShown()
		PetVisibility.SetShown(on)
		showLabel.Text = if on then "Show pets: ON" else "Show pets: OFF"
		UITheme.Recolor(showPets, if on then UITheme.colors.green else UITheme.colors.grey)
	end)

	local windows: { [string]: UITheme.Window } = {}
	local handles: { [string]: TabHandle } = {}
	local current: string? = nil

	-- Lets other HUD parts (the leaderboard) step aside while a window is open.
	local function announce()
		player:SetAttribute("MenuOpen", current ~= nil)
	end
	local function open(id: string)
		if current and current ~= id then
			windows[current].shut()
		end
		current = id
		windows[id].open()
		handles[id].Show()
		announce()
	end
	local function closeAll()
		if current then
			windows[current].shut()
		end
	end
	local api = { Open = open }

	local researchTimer: TextLabel? = nil
	for order, entry in ENTRIES do
		local button = UITheme.MenuButton(entry.icon, entry.id, entry.kind)
		button.LayoutOrder = order
		button.Parent = grid
		button.Activated:Connect(function()
			if current == entry.id and windows[entry.id].isOpen() then
				windows[entry.id].shut()
			else
				open(entry.id)
			end
		end)

		local window = UITheme.Window(gui, entry.id, entry.icon, entry.kind, entry.size)
		-- In the space right of the menu buttons.
		window.frame.Position = UDim2.new(0.5, 100, 0.53, 0)
		window.onClosed(function()
			handles[entry.id].Hide()
			if current == entry.id then
				current = nil
				announce()
			end
		end)
		windows[entry.id] = window
		handles[entry.id] = (entry.module :: any).Mount(window.body, api)

		if entry.id == "Research" then
			-- Countdown pill on the button while a research runs.
			local pill = UITheme.Label("", 16, UITheme.colors.gold)
			pill.AnchorPoint = Vector2.new(0.5, 0.5)
			pill.Position = UDim2.new(0.5, 0, 0, 2)
			pill.Size = UDim2.fromOffset(84, 20)
			pill.ZIndex = 8
			pill.Parent = button
			researchTimer = pill
		end
	end

	ContextActionService:BindAction("OpenPets", function(_, state)
		if state == Enum.UserInputState.Begin then
			if current == "Pets" then
				closeAll()
			else
				open("Pets")
			end
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.T)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.ButtonB and not processed then
			closeAll()
		end
	end)

	-- Battles take the whole screen.
	player:GetAttributeChangedSignal("InBattle"):Connect(function()
		local inBattle = player:GetAttribute("InBattle") == true
		if inBattle then
			closeAll()
		end
		TweenService:Create(grid, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
			Position = if inBattle then shownAt - UDim2.fromOffset(242, 0) else shownAt,
		}):Play()
	end)

	gui.Parent = player:WaitForChild("PlayerGui")

	-- Menu buttons slide in one after the other.
	for index, button in grid:GetChildren() do
		if button:IsA("GuiButton") then
			local buttonScale = button:FindFirstChildOfClass("UIScale")
			if buttonScale then
				buttonScale.Scale = 0
				task.delay(0.05 * index, function()
					TweenService:Create(
						buttonScale,
						TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{ Scale = 1 }
					):Play()
				end)
			end
		end
	end

	task.spawn(function()
		while true do
			if researchTimer then
				researchTimer.Text = ResearchTab.TimerText()
			end
			task.wait(0.5)
		end
	end)
end

return Menu
