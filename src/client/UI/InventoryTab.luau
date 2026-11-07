--!strict
-- Tablet > Inventory: a grid of the player's pets and, for the selected one,
-- its sheet (DESIGN-v2 §9): species, rarity, type, home biome, level, stage
-- and age, size, Cash/s, original owner, capture date and place, moves,
-- plus the button to add it to / send it home from the battle team.
-- Wide screens show the sheet beside the grid; narrow ones over it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local PetPortrait = require(script.Parent.PetPortrait)
local TabletData = require(script.Parent.TabletData)

type PetView = TabletData.PetView

local InventoryTab = {}

local SHEET_WIDTH = 310
local WIDE_AT = 640 -- container width (unscaled px) from which the sheet sits beside the grid

local STATES: { [string]: { text: string, color: Color3, order: number } } = {
	Following = { text = "Team", color = UITheme.colors.gold, order = 1 },
	InBase = { text = "In base", color = UITheme.colors.cash, order = 2 },
	Carried = { text = "Carried", color = Color3.fromRGB(120, 190, 255), order = 3 },
	Inventory = { text = "Stored", color = Color3.fromRGB(120, 190, 255), order = 4 },
	Battling = { text = "In battle", color = UITheme.colors.warning, order = 5 },
}

type Card = { frame: TextButton, state: TextLabel, stroke: UIStroke }

local function age(seconds: number): string
	if seconds >= 86400 then
		return `{seconds // 86400}d {(seconds % 86400) // 3600}h`
	end
	return Format.Duration(seconds)
end

local function row(parent: Instance, order: number): (TextLabel, TextLabel)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 22)
	holder.LayoutOrder = order
	holder.Parent = parent
	local key = UITheme.Label("", 16, Color3.fromRGB(190, 205, 235))
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.Size = UDim2.fromScale(0.42, 1)
	UITheme.FitText(key, 16)
	key.Parent = holder
	local value = UITheme.Label("", 16)
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Position = UDim2.fromScale(0.42, 0)
	value.Size = UDim2.fromScale(0.58, 1)
	UITheme.FitText(value, 16)
	value.Parent = holder
	return key, value
end

function InventoryTab.Mount(container: Frame)
	local selectedId: string? = nil
	local cards: { [string]: Card } = {}
	local latest: { [string]: PetView } = {}
	local now = 0
	local refresh: () -> ()

	local summary = UITheme.Label("", 18)
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Size = UDim2.new(1, 0, 0, 26)
	UITheme.FitText(summary, 18)
	summary.Parent = container

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(0, 32)
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollBarThickness = 8
	grid.ScrollBarImageColor3 = UITheme.colors.outline
	grid.Parent = container
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(118, 150)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingTop = UDim.new(0, 6)
	gridPadding.PaddingLeft = UDim.new(0, 6)
	gridPadding.Parent = grid

	local empty = UITheme.Label("No pets yet. Catch one in the Forest or the Desert!", 20)
	empty.Size = UDim2.new(1, 0, 0, 60)
	empty.Position = UDim2.fromOffset(0, 60)
	empty.TextWrapped = true
	empty.Visible = false
	empty.Parent = container

	-- Sheet
	local sheet = UITheme.Panel()
	sheet.Name = "Sheet"
	sheet.AnchorPoint = Vector2.new(1, 0)
	sheet.Position = UDim2.fromScale(1, 0)
	sheet.ZIndex = 5
	sheet.Visible = false
	sheet.Parent = container

	local back, _ = UITheme.Button("info", UDim2.fromOffset(44, 44), "<")
	back.Position = UDim2.fromOffset(8, 8)
	back.ZIndex = 8
	back.Parent = sheet

	local portraitHolder = Instance.new("Frame")
	portraitHolder.BackgroundTransparency = 1
	portraitHolder.AnchorPoint = Vector2.new(0.5, 0)
	portraitHolder.Position = UDim2.new(0.5, 0, 0, 8)
	portraitHolder.Size = UDim2.fromOffset(150, 130)
	portraitHolder.ZIndex = 6
	portraitHolder.Parent = sheet

	local title = UITheme.Label("", 26)
	title.Position = UDim2.fromOffset(10, 138)
	title.Size = UDim2.new(1, -20, 0, 30)
	UITheme.FitText(title, 26)
	title.Parent = sheet

	local rows = Instance.new("ScrollingFrame")
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.Position = UDim2.fromOffset(14, 172)
	rows.Size = UDim2.new(1, -28, 1, -172 - 76)
	rows.CanvasSize = UDim2.new()
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.ScrollBarThickness = 6
	rows.Parent = sheet
	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Padding = UDim.new(0, 4)
	rowsLayout.Parent = rows

	local fields: { [string]: TextLabel } = {}
	for order, name in
		{
			"Rarity",
			"Type",
			"Home biome",
			"Level",
			"Health",
			"Strength",
			"Stage",
			"Age",
			"Size",
			"Cash/s",
			"Original owner",
			"Caught",
			"Moves",
		}
	do
		local key, value = row(rows, order)
		key.Text = name
		fields[name] = value
	end

	local action, actionText = UITheme.Button("action", UDim2.new(1, -28, 0, 56))
	action.AnchorPoint = Vector2.new(0.5, 1)
	action.Position = UDim2.new(0.5, 0, 1, -12)
	action.Parent = sheet

	local function wide(): boolean
		-- Compare in unscaled pixels: the tablet's ScreenGui has a UIScale.
		local gui = container:FindFirstAncestorWhichIsA("ScreenGui")
		local scale = gui and gui:FindFirstChildOfClass("UIScale")
		return container.AbsoluteSize.X / (if scale then scale.Scale else 1) >= WIDE_AT
	end

	local function layoutSheet()
		local isWide = wide()
		-- Side by side only while a pet is picked; otherwise the grid takes it all.
		local beside = isWide and selectedId ~= nil
		back.Visible = not isWide
		if isWide then
			sheet.Size = UDim2.new(0, SHEET_WIDTH, 1, 0)
			grid.Size = if beside then UDim2.new(1, -SHEET_WIDTH - 12, 1, -32) else UDim2.new(1, 0, 1, -32)
			sheet.Visible = selectedId ~= nil
		else
			sheet.Size = UDim2.fromScale(1, 1)
			grid.Size = UDim2.new(1, 0, 1, -32)
			sheet.Visible = selectedId ~= nil
		end
		summary.Size = UDim2.new(1, if beside then -SHEET_WIDTH - 12 else 0, 0, 26)
	end
	container:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutSheet)

	local function showSheet(pet: PetView?)
		task.defer(layoutSheet) -- after the caller updates the selection
		if not pet then
			sheet.Visible = false
			return
		end
		local species = Config.Species[pet.speciesId]
		local rarity = Config.Rarities[species.rarity]
		local biome = species.biome and Config.Biomes[species.biome]
		title.Text = species.displayName
		title.TextColor3 = rarity.color
		fields["Rarity"].Text = rarity.id
		fields["Rarity"].TextColor3 = rarity.color
		fields["Type"].Text = if biome then biome.displayName else "Neutral"
		fields["Home biome"].Text = if biome then biome.displayName else "—"
		fields["Level"].Text = if pet.xpToNext == 0
			then `Lv {pet.level} MAX`
			else `Lv {pet.level}  ({pet.xp}/{pet.xpToNext} XP)`
		fields["Health"].Text = if pet.hp <= 0 then `Fainted (0/{pet.maxHp})` else `{pet.hp}/{pet.maxHp} HP`
		fields["Health"].TextColor3 = if pet.hp <= 0
			then Color3.fromRGB(255, 110, 100)
			else Color3.new(1, 1, 1)
		fields["Strength"].Text = tostring(pet.attack)
		fields["Stage"].Text = pet.stage .. (if pet.legacyAppearance then " (legacy size)" else "")
		fields["Size"].Text = string.format("x%.2f", pet.size)
		fields["Cash/s"].Text = if pet.state == "InBase"
			then `+${Format.Short(pet.cashPerSecond)}/s`
			else "$0 (only earns in the base)"
		local origin = pet.origin
		if origin then
			fields["Age"].Text = age(now - origin.capturedAt)
			fields["Original owner"].Text = origin.ownerName
			fields["Caught"].Text = `{os.date("%d %b %Y", origin.capturedAt)}, {origin.place}`
		else
			fields["Age"].Text = "Unknown"
			fields["Original owner"].Text = "Unknown"
			fields["Caught"].Text = "Before records"
		end
		fields["Moves"].Text = table.concat(pet.moves, ", ")

		if pet.state == "InBase" or pet.state == "Inventory" then
			actionText.Text = "Add to team"
			UITheme.Recolor(action, UITheme.colors.action)
		elseif pet.state == "Following" then
			actionText.Text = "Send home"
			UITheme.Recolor(action, UITheme.colors.info)
		else
			actionText.Text = "Out in the world"
			UITheme.Recolor(action, UITheme.colors.disabled)
		end
		layoutSheet()
	end

	local function selectPet(id: string?)
		selectedId = id
		portraitHolder:ClearAllChildren()
		local pet = id and latest[id]
		if pet then
			local portrait = PetPortrait.New(pet.speciesId, nil, pet.stage)
			portrait.Size = UDim2.fromScale(1, 1)
			portrait.ZIndex = 6
			portrait.Parent = portraitHolder
		end
		refresh()
	end

	back.Activated:Connect(function()
		selectPet(nil)
	end)
	action.Activated:Connect(function()
		local pet = selectedId and latest[selectedId]
		if pet and (pet.state == "InBase" or pet.state == "Inventory" or pet.state == "Following") then
			Remotes.Get("SetEquipped"):FireServer(pet.id, pet.state ~= "Following")
			TabletData.Invalidate()
			task.delay(0.4, refresh)
		end
	end)

	local function newCard(pet: PetView): Card
		local species = Config.Species[pet.speciesId]
		local frame = Instance.new("TextButton")
		frame.Name = pet.id
		frame.Text = ""
		frame.AutoButtonColor = true
		frame.BackgroundColor3 = UITheme.colors.outline
		frame.BackgroundTransparency = 0.4
		UITheme.Corner(frame)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
		local portrait = PetPortrait.New(pet.speciesId, nil, pet.stage)
		portrait.Position = UDim2.fromOffset(9, 6)
		portrait.Size = UDim2.fromOffset(100, 88)
		portrait.Parent = frame
		local name = UITheme.Label(species.displayName, 16)
		name.Position = UDim2.fromOffset(4, 96)
		name.Size = UDim2.new(1, -8, 0, 22)
		UITheme.FitText(name, 16)
		name.Parent = frame
		local state = UITheme.Label("", 15)
		state.Position = UDim2.fromOffset(4, 120)
		state.Size = UDim2.new(1, -8, 0, 20)
		UITheme.FitText(state, 15)
		state.Parent = frame
		frame.Parent = grid
		frame.Activated:Connect(function()
			selectPet(pet.id)
		end)
		return { frame = frame, state = state, stroke = stroke }
	end

	function refresh()
		local data = TabletData.Get()
		if not data then
			summary.Text = "Loading..."
			return
		end
		now = data.now
		local seen: { [string]: boolean } = {}
		local inBase, team, stored = 0, 0, 0
		for _, pet in data.pets do
			seen[pet.id] = true
			latest[pet.id] = pet
			local card = cards[pet.id] or newCard(pet)
			cards[pet.id] = card
			local portrait = card.frame:FindFirstChild("PetPortrait")
			if portrait and portrait:IsA("ImageLabel") then
				PetPortrait.Update(portrait, pet.speciesId, nil, pet.stage)
			end
			local state = STATES[pet.state] or STATES.InBase
			card.state.Text = state.text
			card.state.TextColor3 = state.color
			local rarity = Config.Rarities[Config.Species[pet.speciesId].rarity]
			card.stroke.Color = if pet.id == selectedId then UITheme.colors.gold else rarity.color
			-- Team first, then base (richest first), then pets out in the world.
			card.frame.LayoutOrder = state.order * 100000 - math.floor(pet.cashPerSecond * 100)
			if pet.state == "InBase" then
				inBase += 1
			elseif pet.state == "Following" then
				team += 1
			else
				stored += 1
			end
		end
		for id, card in cards do
			if not seen[id] then
				card.frame:Destroy()
				cards[id] = nil
				latest[id] = nil
			end
		end
		if selectedId and not latest[selectedId] then
			selectedId = nil
		end
		empty.Visible = #data.pets == 0
		summary.Text =
			`{inBase} in base  ·  Team {team}/{Config.Gameplay.team.maxEquipped}  ·  {stored} stored`
		local currentPet = selectedId and latest[selectedId]
		local portrait = portraitHolder:FindFirstChild("PetPortrait")
		if currentPet and portrait and portrait:IsA("ImageLabel") then
			PetPortrait.Update(portrait, currentPet.speciesId, nil, currentPet.stage)
		end
		showSheet(selectedId and latest[selectedId] or nil)
		layoutSheet()
	end

	local visible = false
	task.spawn(function()
		while true do
			task.wait(2)
			if visible then
				refresh()
			end
		end
	end)

	return {
		Show = function()
			visible = true
			layoutSheet()
			refresh()
		end,
		Hide = function()
			visible = false
		end,
	}
end

return InventoryTab
