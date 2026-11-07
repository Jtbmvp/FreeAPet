--!strict
-- Tablet > Index: every species in the game, grouped by biome. Not seen yet
-- = black silhouette and "???"; seen = shown; caught = shown with a count.
-- The counters at the top track the collection.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local PetPortrait = require(script.Parent.PetPortrait)
local TabletData = require(script.Parent.TabletData)

local IndexTab = {}

type Card = {
	frame: Frame,
	portraitHolder: Frame,
	name: TextLabel,
	status: TextLabel,
	stroke: UIStroke,
	shown: string?, -- "silhouette" | "full": what the portrait currently is
}

function IndexTab.Mount(container: Frame)
	local summary = UITheme.Label("", 20)
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Size = UDim2.new(1, 0, 0, 28)
	UITheme.FitText(summary, 20)
	summary.Parent = container

	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 34)
	list.Size = UDim2.new(1, 0, 1, -34)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = UITheme.colors.outline
	list.Parent = container
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = list

	-- One section per biome, nearest first; species by rarity inside.
	local biomes = {}
	for _, biome in Config.Biomes do
		table.insert(biomes, biome)
	end
	table.sort(biomes, function(a, b)
		return a.order < b.order
	end)

	-- UI grouping only; never added to Config.Biomes/wild spawns.
	table.insert(biomes, 1, { id = "Starters", displayName = "Starters" })
	local cards: { [string]: Card } = {}
	for biomeOrder, biome in biomes do
		local header = UITheme.Label(biome.displayName, 24, UITheme.colors.gold)
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Size = UDim2.new(1, 0, 0, 28)
		header.LayoutOrder = biomeOrder * 2 - 1
		header.Parent = list

		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Size = UDim2.new(1, -8, 0, 0)
		row.LayoutOrder = biomeOrder * 2
		row.Parent = list
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(130, 164)
		grid.CellPadding = UDim2.fromOffset(10, 10)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = row

		for id, species in Config.Species do
			if species.biome == biome.id or (biome.id == "Starters" and species.starter) then
				local rarity = Config.Rarities[species.rarity]
				local frame = Instance.new("Frame")
				frame.Name = id
				frame.LayoutOrder = rarity.order
				frame.BackgroundColor3 = UITheme.colors.outline
				frame.BackgroundTransparency = 0.4
				UITheme.Corner(frame)
				local stroke = Instance.new("UIStroke")
				stroke.Thickness = 3
				stroke.Parent = frame
				local portraitHolder = Instance.new("Frame")
				portraitHolder.BackgroundTransparency = 1
				portraitHolder.Position = UDim2.fromOffset(10, 6)
				portraitHolder.Size = UDim2.fromOffset(110, 96)
				portraitHolder.Parent = frame
				local badge = UITheme.Icon(string.lower(rarity.id), 30)
				if badge then
					badge.Position = UDim2.fromOffset(4, 4)
					badge.ZIndex = 3
					badge.Parent = frame
				end
				local name = UITheme.Label("", 17)
				name.Position = UDim2.fromOffset(4, 104)
				name.Size = UDim2.new(1, -8, 0, 24)
				UITheme.FitText(name, 17)
				name.Parent = frame
				local status = UITheme.Label("", 15)
				status.Position = UDim2.fromOffset(4, 132)
				status.Size = UDim2.new(1, -8, 0, 22)
				UITheme.FitText(status, 15)
				status.Parent = frame
				frame.Parent = row
				cards[id] = {
					frame = frame,
					portraitHolder = portraitHolder,
					name = name,
					status = status,
					stroke = stroke,
					shown = nil,
				}
			end
		end
	end

	local function refresh()
		local data = TabletData.Get()
		if not data then
			summary.Text = "Loading..."
			return
		end
		local total, seenCount, caughtCount = 0, 0, 0
		for id, card in cards do
			local species = Config.Species[id]
			local rarity = Config.Rarities[species.rarity]
			local entry = data.index[id]
			local seen = entry ~= nil and entry.seen == true
			local caught = entry and entry.caught or 0
			total += 1
			seenCount += if seen then 1 else 0
			caughtCount += if caught > 0 then 1 else 0

			local want = if seen then "full" else "silhouette"
			if card.shown ~= want then
				card.portraitHolder:ClearAllChildren()
				local portrait = PetPortrait.New(id, not seen)
				portrait.Size = UDim2.fromScale(1, 1)
				portrait.Parent = card.portraitHolder
				card.shown = want
			end
			card.name.Text = if seen then species.displayName else "???"
			card.stroke.Color = if seen then rarity.color else UITheme.colors.research.Locked
			if caught > 0 then
				card.status.Text = `Caught x{caught}`
				card.status.TextColor3 = UITheme.colors.cash
			elseif seen then
				card.status.Text = "Seen"
				card.status.TextColor3 = Color3.fromRGB(190, 205, 235)
			else
				card.status.Text = "Not seen yet"
				card.status.TextColor3 = Color3.fromRGB(140, 150, 175)
			end
		end
		summary.Text = `Caught {caughtCount}/{total}  ·  Seen {seenCount}/{total}`
	end

	return {
		Show = refresh,
		Hide = function() end,
	}
end

return IndexTab
