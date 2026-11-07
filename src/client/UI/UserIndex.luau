--!strict
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Shared.Config)
local P = require(script.Parent.HudPrimitives)
local Portrait = require(script.Parent.PetPortrait)
local Data = require(script.Parent.TabletData)
local Index = {}
function Index.Mount(container: Frame, _api: any)
	local filter = "All"
	local visible = false
	local signature = ""
	local tabs = Instance.new("ScrollingFrame")
	tabs.Name = "Filters"
	tabs.BackgroundTransparency = 1
	tabs.BorderSizePixel = 0
	tabs.Size = UDim2.new(1, 0, 0, 48)
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.CanvasSize = UDim2.new()
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.ScrollBarThickness = 0
	tabs.Parent = container
	local flow = Instance.new("UIListLayout")
	flow.FillDirection = Enum.FillDirection.Horizontal
	flow.Padding = UDim.new(0, 8)
	flow.Parent = tabs
	local summary = P.Text(container, "Summary", "", 16)
	summary.Position = UDim2.fromOffset(0, 54)
	summary.Size = UDim2.new(1, 0, 0, 24)
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Species"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(0, 86)
	grid.Size = UDim2.new(1, 0, 1, -86)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ScrollBarThickness = 6
	grid.Selectable = true
	grid.Parent = container
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.Parent = grid
	local function reflow()
		local w = math.max(112, grid.AbsoluteSize.X - 8)
		local columns = math.max(1, math.floor((w + 12) / 160))
		layout.CellSize = UDim2.fromOffset(math.floor((w - (columns - 1) * 12) / columns), 174)
	end
	local function refresh()
		if not visible then
			return
		end
		local data = Data.Get()
		if not visible or not container.Parent then
			return
		end
		if not data then
			summary.Text = "Loading Index…"
			return
		end
		local ids = {}
		local parts = { filter }
		local caught = 0
		local total = 0
		for id, species in Config.Species do
			total += 1
			local entry = data.index[id]
			if entry and (entry.caught or 0) > 0 then
				caught += 1
			end
			if
				filter == "All"
				or species.biome == filter
				or (filter == "Starters" and species.rarity == "Starter")
			then
				table.insert(ids, id)
			end
			table.insert(parts, `{id}:{entry and entry.seen}:{entry and entry.caught}`)
		end
		table.sort(ids)
		table.sort(parts)
		summary.Text = `Caught {caught} / {total}`
		local nextSignature = table.concat(parts, ";")
		if nextSignature == signature then
			return
		end
		signature = nextSignature
		for _, child in grid:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, id in ids do
			local species = Config.Species[id]
			local entry = data.index[id]
			local seen = entry and entry.seen == true
			local count = if entry then entry.caught or 0 else 0
			local card = P.Frame(
				grid,
				id,
				if count > 0 then Color3.fromRGB(69, 183, 63) else Color3.fromRGB(62, 66, 74)
			)
			card.LayoutOrder = i
			P.Round(card)
			P.Stroke(card)
			local art = Portrait.New(id, not seen)
			art.Position = UDim2.fromOffset(8, 4)
			art.Size = UDim2.new(1, -16, 0, 112)
			art.Parent = card
			local name = P.Text(card, "Name", if seen then species.displayName else "???", 15)
			name.Position = UDim2.fromOffset(4, 116)
			name.Size = UDim2.new(1, -8, 0, 26)
			local status = P.Text(
				card,
				"Status",
				if count > 0 then `Caught x{count}` elseif seen then "Seen" else "Not seen yet",
				14
			)
			status.Position = UDim2.fromOffset(4, 146)
			status.Size = UDim2.new(1, -8, 0, 22)
		end
		reflow()
	end
	for _, name in { "All", "Forest", "Desert", "Starters" } do
		local b = P.Button(tabs, name, name, P.colors.Index)
		b.Size = UDim2.fromOffset(116, 48)
		b.NextSelectionDown = grid
		b.Activated:Connect(function()
			filter = name
			signature = ""
			grid.CanvasPosition = Vector2.zero
			refresh()
		end)
	end
	local resize = grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(reflow)
	return {
		Show = function()
			visible = true
			refresh()
		end,
		Refresh = refresh,
		Hide = function()
			visible = false
		end,
		Destroy = function()
			visible = false
			resize:Disconnect()
		end,
	}
end
return Index
