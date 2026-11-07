--!strict
-- Tablet > Research: the research tree, nodes as hexagons (colour = category). Tapping a hexagon selects it; the bar
-- at the bottom shows what it does and the Research button, so a stray tap
-- never spends cash. Locked hexagons (no researched neighbour) are grey.
-- Read-only view of the player attributes set by ResearchService; the only
-- thing it sends is "StartResearch" (the server checks everything).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ResearchMath = require(ReplicatedStorage.Shared.ResearchMath)
local ProgressionMath = require(ReplicatedStorage.Shared.ProgressionMath)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local ResearchTab = {}

local HEX_RADIUS = 78 -- centre to corner, in canvas pixels
local HEX_GAP = 1.06 -- spacing between hexagon centres, relative to the radius
local SQRT3 = math.sqrt(3)

type Tile = {
	nodeId: string,
	fill: GuiObject,
	icon: ImageLabel?,
	level: TextLabel,
	price: TextLabel,
	lock: ImageLabel?,
	selection: UIStroke?,
	highlight: ImageLabel?,
}

-- Centre of a pointy-top hexagon at axial (q, r).
local function hexCentre(hex: { number }): Vector2
	local radius = HEX_RADIUS * HEX_GAP
	return Vector2.new(radius * SQRT3 * (hex[1] + hex[2] / 2), radius * 1.5 * hex[2])
end

local function buildTile(nodeId: string, canvas: Frame, origin: Vector2, onSelect: (string) -> ()): Tile
	local node = Config.Research[nodeId]
	local centre = hexCentre(node.hex) - origin
	-- The tile images are square with the hexagon 500/512 of their height.
	local size = HEX_RADIUS * 2 * 512 / 500

	local button = Instance.new("TextButton")
	button.Name = nodeId
	button.Text = ""
	button.BackgroundTransparency = 1
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromOffset(centre.X, centre.Y)
	button.Size = UDim2.fromOffset(HEX_RADIUS * SQRT3, HEX_RADIUS * 2)
	button.Parent = canvas
	button.Activated:Connect(function()
		onSelect(nodeId)
	end)

	local fill: GuiObject
	local fillId, frameId = UITheme.IconId("hex_fill"), UITheme.IconId("hex_frame")
	local selection: UIStroke? = nil
	local highlight: ImageLabel? = nil
	if fillId and frameId then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = fillId
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromOffset(size, size)
		image.Parent = button
		local frame = image:Clone()
		frame.Image = frameId
		frame.ZIndex = 2
		frame.Parent = button
		-- Selected: the frame turns gold.
		highlight = frame
		fill = image
	else
		-- No tile art uploaded yet (published game): a rounded tile instead.
		local tile = Instance.new("Frame")
		tile.BackgroundColor3 = Color3.new(1, 1, 1)
		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Position = UDim2.fromScale(0.5, 0.5)
		tile.Size = UDim2.fromScale(0.92, 0.8)
		UITheme.Corner(tile, 22)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 5
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Parent = tile
		tile.Parent = button
		fill = tile
		selection = stroke
	end

	local level = UITheme.Label("", 18)
	level.AnchorPoint = Vector2.new(0.5, 0)
	level.Position = UDim2.fromScale(0.5, 0.17)
	level.Size = UDim2.new(0.7, 0, 0, 18)
	level.ZIndex = 3
	level.Parent = button

	local icon = UITheme.Icon(node.icon, 54)
	if icon then
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.43)
		icon.ZIndex = 3
		icon.Parent = button
	end

	local name = UITheme.Label(node.displayName, 16)
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.fromScale(0.5, 0.6)
	name.Size = UDim2.new(0.86, 0, 0, 18)
	name.ZIndex = 3
	UITheme.FitText(name, 16)
	name.Parent = button

	local price = UITheme.Label("", 15, UITheme.colors.gold)
	price.AnchorPoint = Vector2.new(0.5, 0)
	price.Position = UDim2.fromScale(0.5, 0.73)
	price.Size = UDim2.new(0.8, 0, 0, 16)
	price.ZIndex = 3
	UITheme.FitText(price, 15)
	price.Parent = button

	local lock = UITheme.Icon("locked", 30)
	if lock then
		lock.AnchorPoint = Vector2.new(1, 0)
		lock.Position = UDim2.fromScale(0.85, 0.12)
		lock.ZIndex = 4
		lock.Parent = button
	end

	return {
		nodeId = nodeId,
		fill = fill,
		icon = icon,
		level = level,
		price = price,
		lock = lock,
		selection = selection,
		highlight = highlight,
	}
end

-- Rebuild the saved progress shape from the player's attributes, for ResearchMath.
local function progress(): { [string]: any }
	local player = Players.LocalPlayer
	local result = {}
	local active = player:GetAttribute("ResearchActive")
	local finishesAt = player:GetAttribute("ResearchFinishesAt")
	for id in Config.Research do
		local level = player:GetAttribute(`Research_{id}`)
		local entry: any = { level = if typeof(level) == "number" then level else 0 }
		if id == active and typeof(finishesAt) == "number" then
			entry.activeLevel = entry.level + 1
			entry.finishesAt = finishesAt
		end
		result[id] = entry
	end
	return result
end

-- Time left on the running research ("" when none), for the HUD.
function ResearchTab.TimerText(): string
	local now = Workspace:GetServerTimeNow()
	local activeId, finishesAt = ResearchMath.Active(progress(), now)
	return if activeId and finishesAt then Format.Duration(finishesAt - now) else ""
end

function ResearchTab.Mount(container: Frame)
	local alive = true
	local connections: { RBXScriptConnection } = {}
	local function listen(signal: RBXScriptSignal, callback: any)
		local connection = signal:Connect(callback)
		table.insert(connections, connection)
	end
	local player = Players.LocalPlayer
	local panel = container
	local visible = false

	-- Tree area: the canvas is scaled to fit whatever space the panel has.
	local treeArea = Instance.new("Frame")
	treeArea.Name = "Tree"
	treeArea.BackgroundTransparency = 1
	treeArea.ClipsDescendants = true
	treeArea.Size = UDim2.new(1, 0, 1, -124)
	treeArea.Parent = panel

	local minimum, maximum = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	for _, node in Config.Research do
		local centre = hexCentre(node.hex)
		minimum = minimum:Min(centre)
		maximum = maximum:Max(centre)
	end
	local margin = Vector2.new(HEX_RADIUS * SQRT3 / 2, HEX_RADIUS) * 1.08
	local origin = minimum - margin
	local canvasSize = maximum - minimum + margin * 2

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(canvasSize.X, canvasSize.Y)
	canvas.Parent = treeArea
	local canvasScale = Instance.new("UIScale")
	canvasScale.Parent = canvas
	local function fitCanvas()
		-- Unscaled pixels: the tablet's ScreenGui has a UIScale.
		local gui = container:FindFirstAncestorWhichIsA("ScreenGui")
		local scale = gui and gui:FindFirstChildOfClass("UIScale")
		local area = treeArea.AbsoluteSize / (if scale then scale.Scale else 1)
		if area.X > 0 and area.Y > 0 then
			canvasScale.Scale = math.min(area.X / canvasSize.X, area.Y / canvasSize.Y, 1.25)
		end
	end
	listen(treeArea:GetPropertyChangedSignal("AbsoluteSize"), fitCanvas)

	-- Details bar: the selected node.
	local details = Instance.new("Frame")
	details.Name = "Details"
	details.AnchorPoint = Vector2.new(0.5, 1)
	details.Position = UDim2.fromScale(0.5, 1)
	details.Size = UDim2.new(1, 0, 0, 110)
	details.BackgroundColor3 = UITheme.colors.outline
	details.BackgroundTransparency = 0.45
	UITheme.Corner(details)
	details.Parent = panel

	local detailIconHolder = Instance.new("Frame")
	detailIconHolder.BackgroundTransparency = 1
	detailIconHolder.Position = UDim2.fromOffset(10, 19)
	detailIconHolder.Size = UDim2.fromOffset(72, 72)
	detailIconHolder.Parent = details

	local detailTitle = UITheme.Label("", 24)
	detailTitle.TextXAlignment = Enum.TextXAlignment.Left
	detailTitle.Position = UDim2.fromOffset(92, 10)
	detailTitle.Size = UDim2.new(1, -290, 0, 28)
	UITheme.FitText(detailTitle, 24)
	detailTitle.Parent = details

	local detailEffect = UITheme.Label("", 18)
	detailEffect.TextXAlignment = Enum.TextXAlignment.Left
	detailEffect.Position = UDim2.fromOffset(92, 42)
	detailEffect.Size = UDim2.new(1, -290, 0, 22)
	UITheme.FitText(detailEffect, 18)
	detailEffect.Parent = details

	local detailNote = UITheme.Label("", 16, UITheme.colors.gold)
	detailNote.TextXAlignment = Enum.TextXAlignment.Left
	detailNote.Position = UDim2.fromOffset(92, 70)
	detailNote.Size = UDim2.new(1, -290, 0, 20)
	UITheme.FitText(detailNote, 16)
	detailNote.Parent = details

	local action, actionText = UITheme.Button("action", UDim2.fromOffset(180, 64))
	action.Name = "Research"
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -14, 0.5, 0)
	action.Parent = details

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(1, 0.5)
	bar.Position = UDim2.new(1, -14, 0.5, 0)
	bar.Size = UDim2.fromOffset(180, 34)
	bar.BackgroundColor3 = UITheme.colors.outline
	bar.Visible = false
	UITheme.Corner(bar, 10)
	UITheme.Outline(bar)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.Size = UDim2.fromScale(0, 1)
	UITheme.Gradient(fill, UITheme.colors.info[1], UITheme.colors.info[2])
	UITheme.Corner(fill, 10)
	fill.Parent = bar
	local barText = UITheme.Label("", 18)
	barText.Size = UDim2.fromScale(1, 1)
	barText.ZIndex = 3
	barText.Parent = bar
	bar.Parent = details

	-- State
	local selected: string? = nil
	local tiles: { Tile } = {}
	local refresh: () -> ()

	local function selectNode(nodeId: string)
		selected = nodeId
		detailIconHolder:ClearAllChildren()
		local icon = UITheme.Icon(Config.Research[nodeId].icon, 72)
		if icon then
			icon.Parent = detailIconHolder
		end
		refresh()
	end

	for nodeId in Config.Research do
		table.insert(tiles, buildTile(nodeId, canvas, origin, selectNode))
	end

	action.Activated:Connect(function()
		if selected and player:GetAttribute("DataLoaded") == true then
			local rank = ResearchMath.LevelOf(progress(), selected, Workspace:GetServerTimeNow()) + 1
			local level = player:GetAttribute("PlayerLevel")
			if typeof(level) ~= "number" or level < ProgressionMath.ResearchLevel(selected, rank) then
				return
			end
			Remotes.Get("StartResearch"):FireServer(selected)
		end
	end)

	function refresh()
		if not visible then
			return
		end
		local now = Workspace:GetServerTimeNow()
		local state = progress()
		local activeId, finishesAt = ResearchMath.Active(state, now)
		local cash = player:GetAttribute("Cash")
		cash = if typeof(cash) == "number" then cash else 0

		for _, tile in tiles do
			local node = Config.Research[tile.nodeId]
			local level = ResearchMath.LevelOf(state, tile.nodeId, now)
			local playerLevel = player:GetAttribute("PlayerLevel")
			local unlocked = typeof(playerLevel) == "number"
				and playerLevel >= ProgressionMath.ResearchLevel(tile.nodeId, level + 1)
				and ResearchMath.IsUnlocked(state, tile.nodeId, now)
			local nextLevel = node.levels[level + 1]
			local color = if unlocked
				then UITheme.colors.research[node.category]
				else UITheme.colors.research.Locked
			if tile.fill:IsA("ImageLabel") then
				tile.fill.ImageColor3 = color
			else
				tile.fill.BackgroundColor3 = color
			end
			local isSelected = tile.nodeId == selected
			if tile.highlight then
				tile.highlight.ImageColor3 = if isSelected then UITheme.colors.gold else Color3.new(1, 1, 1)
			end
			if tile.selection then
				tile.selection.Color = if isSelected then UITheme.colors.gold else Color3.new(1, 1, 1)
			end
			if tile.icon then
				tile.icon.ImageTransparency = if unlocked then 0 else 0.55
			end
			if tile.lock then
				tile.lock.Visible = not unlocked
			end
			tile.level.Text = `{level}/{#node.levels}`
			if activeId == tile.nodeId and finishesAt then
				tile.price.Text = Format.Duration(finishesAt - now)
			elseif nextLevel then
				tile.price.Text = `${Format.Short(nextLevel.cost)}`
			else
				tile.price.Text = "MAX"
			end
		end

		-- Details of the selected node
		details.Visible = selected ~= nil
		if not selected then
			return
		end
		local node = Config.Research[selected]
		local level = ResearchMath.LevelOf(state, selected, now)
		local unlocked = ResearchMath.IsUnlocked(state, selected, now)
		local playerLevel = player:GetAttribute("PlayerLevel")
		local required = ProgressionMath.ResearchLevel(selected, level + 1)
		local nextLevel = node.levels[level + 1]
		detailTitle.Text = `{node.displayName}  ·  Lv {level}/{#node.levels}`
		detailEffect.Text = if nextLevel
			then `{ResearchMath.Describe(selected, level)}  >  {ResearchMath.Describe(selected, level + 1)}`
			else ResearchMath.Describe(selected, level)

		local researching = activeId == selected
		bar.Visible = researching
		action.Visible = not researching
		if researching and finishesAt and nextLevel then
			local duration = ResearchMath.Duration(state, selected, level + 1, now)
			fill.Size = UDim2.fromScale(math.clamp(1 - (finishesAt - now) / duration, 0.04, 1), 1)
			barText.Text = Format.Duration(finishesAt - now)
			detailNote.Text = "Researching..."
			return
		end
		if not nextLevel then
			actionText.Text = "MAX"
			UITheme.Recolor(action, UITheme.colors.disabled)
			detailNote.Text = "Fully researched!"
		elseif typeof(playerLevel) ~= "number" or player:GetAttribute("DataLoaded") ~= true then
			actionText.Text = "Loading..."
			UITheme.Recolor(action, UITheme.colors.disabled)
			detailNote.Text = "Waiting for your save."
		elseif playerLevel < required then
			actionText.Text = `Player Lv {required}`
			UITheme.Recolor(action, UITheme.colors.disabled)
			detailNote.Text =
				`Reach player level {required} for this rank. Existing research keeps its effects.`
		elseif not unlocked then
			actionText.Text = "Locked"
			UITheme.Recolor(action, UITheme.colors.disabled)
			detailNote.Text = "Research a hexagon next to this one first."
		elseif activeId then
			actionText.Text = "Busy"
			UITheme.Recolor(action, UITheme.colors.disabled)
			detailNote.Text = `{Config.Research[activeId].displayName} is being researched.`
		else
			local duration = ResearchMath.Duration(state, selected, level + 1, now)
			actionText.Text = `Research  ${Format.Short(nextLevel.cost)}`
			UITheme.Recolor(
				action,
				if cash >= nextLevel.cost then UITheme.colors.action else UITheme.colors.warning
			)
			detailNote.Text = `Takes {Format.Duration(duration)}. Keeps going while you are offline.`
		end
	end

	for id in Config.Research do
		listen(player:GetAttributeChangedSignal(`Research_{id}`), refresh)
	end
	for _, name in { "ResearchActive", "ResearchFinishesAt", "Cash", "PlayerLevel", "DataLoaded" } do
		listen(player:GetAttributeChangedSignal(name), refresh)
	end
	task.spawn(function()
		while alive do
			task.wait(0.5)
			if not alive then
				break
			end
			refresh() -- countdowns
		end
	end)

	return {
		Destroy = function()
			alive = false
			visible = false
			for _, connection in connections do
				connection:Disconnect()
			end
		end,
		Show = function()
			visible = true
			fitCanvas()
			if not selected then
				-- Start on the node being researched, or the first root.
				local active = player:GetAttribute("ResearchActive")
				selectNode(if typeof(active) == "string" then active else "IncomeBoost")
			else
				refresh()
			end
		end,
		Hide = function()
			visible = false
		end,
	}
end

return ResearchTab
