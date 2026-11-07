-- Index: 1:1 from the HTML's "Painel Index" (left:270 top:130 1380x850).
-- SetEntries(list): { speciesId, name, group, rarity, state = "c" | "s" | "u" }
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Html = require(Core.Html)
local Motion = require(Core.Motion)
local Portrait = require(script.Parent.Parent.Parent.UI.PetPortrait)

local INK2 = Html.INK2
local G = Theme.Grad
local TINT = {
	Common = { Color3.fromRGB(235, 235, 235), 0.25 },
	Uncommon = { Color3.fromRGB(80, 200, 60), 0.25 },
	Rare = { Color3.fromRGB(60, 140, 255), 0.25 },
	Neutral = { Color3.fromRGB(230, 200, 150), 0.25 },
}
local GROUP_GRAD = { Forest = G.Forest, Desert = G.Desert, All = G.Cyan }
-- Starters have no biome: they are listed under All, without a tab of their own.
local NO_TAB = "Neutral"
local STATE_TEXT = { c = "Caught", s = "Seen", u = "Not found" }
local CARD_W, CARD_H = 253, 330

local IndexPanel = {}

function IndexPanel.new(stage)
	local self = Html.panel(stage, { name = "Index", x = 270, y = 130, w = 1380, h = 850, grad = { "3a9cf5", "2787e0" }, icon = "index", title = "Index", titleFont = "Bold", shadow = false, iconAt = { -60, -78 } })
	self.Count = Html.label(self.Header, { text = "0 / 0", ts = 56, font = "Bold", stroke = 10, strokeColor = INK2, pos = UDim2.fromOffset(1244, 51), anchor = Vector2.new(1, 0.5), w = 400, h = 68, ax = "Right", z = 3 })
	local close = Html.closeX(self.Header, { x = 1272, y = 9, w = 84, r = 4, hi = 4, lo = 0, ts = 56, stroke = 9, font = "Bold", grad = { "e8423b", "c92a24" } })
	close.Activated:Connect(function()
		self.CloseRequested:Fire()
	end)
	self._tab, self._entries = "All", {}

	local tabs = Html.make("Frame", self.Body, { Name = "Tabs", Position = UDim2.fromOffset(18, 16), Size = UDim2.fromOffset(1332, 70) })
	local scroll = Html.make("ScrollingFrame", self.Body, {
		Name = "Grid",
		Position = UDim2.fromOffset(18, 102),
		Size = UDim2.fromOffset(1332, 628),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 14,
		ScrollBarImageColor3 = Color3.fromHex("8a8d93"),
	})
	Html.make("UIPadding", scroll, { PaddingBottom = UDim.new(0, 18) })
	Html.make("UIGridLayout", scroll, {
		CellSize = UDim2.fromOffset(CARD_W, CARD_H),
		CellPadding = UDim2.fromOffset(16, 16),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	local bobs = {}
	local function render()
		for _, b in bobs do
			b:Cancel()
		end
		table.clear(bobs)
		for _, c in scroll:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local n = 0
		for _, e in self._entries do
			if self._tab == "All" or e.group == self._tab then
				n += 1
				local known = e.state ~= "u"
				local tint = TINT[e.rarity] or TINT.Common
				local f = Html.box(scroll, { name = "Card" .. n, order = n, bg = "ffffff", r = 3 })
				local g = Instance.new("UIGradient")
				g.Rotation = 90
				if known then
					g.Color = ColorSequence.new(Color3.new(1, 1, 1), tint[1])
					g.Transparency = NumberSequence.new(0.5, tint[2])
				else
					g.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
						ColorSequenceKeypoint.new(0.45, Color3.new(0, 0, 0)),
						ColorSequenceKeypoint.new(1, tint[1]),
					})
					g.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.7),
						NumberSequenceKeypoint.new(0.45, 0.85),
						NumberSequenceKeypoint.new(1, tint[2]),
					})
				end
				g.Parent = f
				Html.box(f, { name = "Border", w = CARD_W, h = CARD_H, r = 3, b = 4, bc = INK2, z = 5 })
				local art = Portrait.New(e.speciesId, not known)
				art.Position, art.Size, art.ZIndex, art.Parent = UDim2.fromOffset(32, 56), UDim2.fromOffset(190, 190), 2, f
				if known then
					local bob = Html.bob(art, 3)
					if bob then
						table.insert(bobs, bob)
					end
				end
				Html.label(f, { text = known and e.name or "???", ts = 31, font = "Bold", stroke = 8, strokeColor = INK2, x = 4, y = 10, w = CARD_W - 8, h = 38, z = 3 })
				Html.label(f, { text = e.rarity, ts = 38, font = "Bold", stroke = 8, strokeColor = INK2, x = 0, y = 255, w = CARD_W, h = 38, z = 3 })
				Html.label(f, { text = STATE_TEXT[e.state], ts = 19, font = "Bold", stroke = 4, strokeColor = INK2, x = 0, y = 295, w = CARD_W, h = 23, z = 3 })
				if self._animate and not Motion.Reduced then
					local sc = Html.make("UIScale", f, { Scale = 0.94 })
					Motion.tween(sc, 0.4, { Scale = 1 }, "Quad", (n - 1) * 0.03)
				end
			end
		end
		self._animate = false
	end

	local function buildTabs()
		for _, c in tabs:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local names, seen = { "All" }, { All = true }
		for _, e in self._entries do
			if not seen[e.group] and e.group ~= NO_TAB then
				seen[e.group] = true
				table.insert(names, e.group)
			end
		end
		local count = #names
		local w = (1332 - 12 * (count - 1)) / count
		for i, name in names do
			local on = name == self._tab
			local x = (i - 1) * (w + 12)
			if on then
				Html.box(tabs, { name = "Ring", x = x - 4, y = -7, w = w + 8, h = 78, bg = "ffffff", r = 8 })
			end
			local b = Html.plate(tabs, {
				name = name, x = x, y = if on then -3 else 0, w = w, h = 70, grad = GROUP_GRAD[name] or G.Cyan,
				b = 5, bc = INK2, r = 4, sh = on and 6 or 4, shc = "000000", sha = 0.35, hi = 0, lo = 0,
				text = name, ts = 38, font = "Bold", stroke = 8, strokeColor = INK2, hitY = 26, z = 2,
			})
			b.Activated:Connect(function()
				self._tab = name
				buildTabs()
				render()
			end)
		end
	end

	function self:SetEntries(list)
		self._entries = list
		local caught = 0
		for _, e in list do
			if e.state == "c" then
				caught += 1
			end
		end
		self.Count.Text = caught .. " / " .. #list
		buildTabs()
		render()
	end
	return self
end

return IndexPanel
