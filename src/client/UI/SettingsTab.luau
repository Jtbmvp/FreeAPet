--!strict
-- Settings window: music and sound volume, whether the name/cash labels
-- above pets show, and the battle intro length and camera shake. Local to this player for now (not saved between visits).
-- The volumes drive the sound groups, so they work as soon as sound is on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Sfx = require(ReplicatedStorage.Shared.Sfx)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local BattleSettings = require(script.Parent.Parent.Battle.BattleSettings)

local SettingsTab = {}

local PET_LABELS = { IncomeLabel = true, LooseLabel = true }

local function row(parent: Instance, order: number, title: string): Frame
	local frame = UITheme.Panel("dark")
	frame.Size = UDim2.new(1, 0, 0, 62)
	frame.LayoutOrder = order
	frame.Parent = parent
	local label = UITheme.Label(title, 26)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Position = UDim2.fromOffset(16, 0)
	label.Size = UDim2.fromScale(0.45, 1)
	label.ZIndex = 4
	UITheme.FitText(label, 26)
	label.Parent = frame
	return frame
end

function SettingsTab.Mount(container: Frame)
	local alive = true
	local watcher: RBXScriptConnection? = nil
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	local sliders = { { "Music", "Music" }, { "Sound VFX", "SFX" } }
	for order, entry in sliders do
		local frame = row(container, order, entry[1])
		local group = Sfx.Group(entry[2])
		local start = group.Volume
		local track = UITheme.Slider(math.clamp(start, 0, 1), function(value)
			group.Volume = value
		end)
		track.AnchorPoint = Vector2.new(1, 0.5)
		track.Position = UDim2.new(1, -24, 0.5, 0)
		track.Size = UDim2.new(0.48, 0, 0, 30)
		track.ZIndex = 4
		track.Parent = frame
	end

	local labels = row(container, 3, "Pet labels")
	local showLabels = true
	local function apply(gui: Instance)
		if gui:IsA("BillboardGui") and PET_LABELS[gui.Name] then
			gui.Enabled = showLabels
		end
	end
	local toggle = UITheme.Toggle(true, function(on)
		showLabels = on
		local animals = Workspace:FindFirstChild("Animals")
		if animals then
			for _, gui in animals:GetDescendants() do
				apply(gui)
			end
		end
	end)
	toggle.AnchorPoint = Vector2.new(1, 0.5)
	toggle.Position = UDim2.new(1, -24, 0.5, 0)
	toggle.ZIndex = 4
	toggle.Parent = labels
	task.spawn(function()
		local animals = Workspace:WaitForChild("Animals", 15)
		if not alive or not animals then
			return
		end
		watcher = animals.DescendantAdded:Connect(function(gui)
			if not showLabels then
				task.defer(apply, gui)
			end
		end)
	end)

	-- Battle presentation.
	local battleToggles = {
		{ "Short battle intro", "shortIntro" },
		{ "Camera shake", "cameraShake" },
	}
	for index, entry in battleToggles do
		local frame = row(container, 3 + index, entry[1])
		local key = entry[2]
		local switch = UITheme.Toggle((BattleSettings :: any)[key], function(on)
			(BattleSettings :: any)[key] = on
		end)
		switch.AnchorPoint = Vector2.new(1, 0.5)
		switch.Position = UDim2.new(1, -24, 0.5, 0)
		switch.ZIndex = 4
		switch.Parent = frame
	end

	local note =
		UITheme.Label("Sound is off for now: it comes in a later update.", 16, Color3.fromRGB(190, 195, 205))
	note.Size = UDim2.new(1, 0, 0, 24)
	note.LayoutOrder = 10
	UITheme.FitText(note, 16)
	note.Parent = container

	return {
		Destroy = function()
			alive = false
			if watcher then
				watcher:Disconnect()
			end
		end,
		Show = function() end,
		Hide = function() end,
	}
end

return SettingsTab
