-- Pets: 1:1 from the HTML's "Painel Pets" (left:300 top:112 1320x836). Data via SetPets, intents via signals.
-- SetPets(list, maxTeam, maxPets, animate): { id, speciesId, stage, name, short, rarity, lv, starter, isEq, xp, xpNeed,
-- nextGain, stats = {{k,v}}, moves = {..}, teamText, canSell, reason }
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Html = require(Core.Html)
local Motion = require(Core.Motion)
local Signal = require(Core.Signal)
local Juice = require(Core.Juice)
local PetStage = require(Core.PetStage)
local Portrait = require(script.Parent.Parent.Parent.UI.PetPortrait)

local C, G = Theme.Colors, Theme.Grad
local INK = Html.INK
local V2 = Vector2.new
local CARD_W, CARD_H, GAP = 182, 240, 18
local TOP_W, TOP_H = 440, 236

local PetsPanel = {}

function PetsPanel.new(stage)
	local self = Html.panel(stage, { name = "Pets", x = 300, y = 112, w = 1320, h = 836, grad = G.Blue, icon = "pets", title = "Pets", gap = 16 })
	self.SelectPet, self.EquipToggle, self.EquipBest, self.SellConfirmed, self.SellRequested, self.SellCancelled =
		Signal.new(), Signal.new(), Signal.new(), Signal.new(), Signal.new(), Signal.new()
	self._cards, self._list, self.Selected, self._eqCount, self._maxTeam = {}, {}, nil, 0, 3
	self.CountLabel = Html.label(self.Left, { text = "", ts = 42, color = "ffe066", stroke = 9, auto = "XY", order = 1 })
	local teamHolder = Html.make("Frame", self.Left, { Name = "TeamHolder", Size = UDim2.fromOffset(0, 53), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
	Html.make("UIPadding", teamHolder, { PaddingLeft = UDim.new(0, 10) })
	local team = Html.box(teamHolder, { name = "Team", w = 0, h = 53, auto = "X", bg = C.Dark, alpha = 0.45, r = 8, b = 4 })
	Html.make("UIPadding", team, { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20) })
	Html.make("UIListLayout", team, {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	Html.label(team, { text = "Equipped", ts = 24, auto = "XY", order = 1 })
	self.TeamLabel = Html.label(team, { text = "0/3", ts = 30, color = C.Cash, auto = "XY", order = 2 })
	local best = Html.plate(self.Header, {
		name = "EquipBest", x = 953, y = 14, w = 245, h = 74, grad = G.Green, b = 5, r = 8, sh = 5, hi = 5, lo = 7,
		gloss = { 18, 32, 40, 48, 0.3 }, shine = { 50, 3.4, 0.5 }, text = "EQUIP BEST", ts = 32, font = "Num", stroke = 7, press = 5, hitY = 20, z = 3,
	})
	self.BestBtn = best
	best.Activated:Connect(function()
		self.EquipBest:Fire()
	end)
	local close = Html.closeX(self.Header, { x = 1214, y = 10 })
	close.Activated:Connect(function()
		self.CloseRequested:Fire()
	end)

	-- Body origin is (306,226): cards from x=336 y=256, detail at x=1152 y=248.
	local scroll = Html.make("ScrollingFrame", self.Body, {
		Name = "Grid",
		Position = UDim2.fromOffset(22, 22),
		Size = UDim2.fromOffset(802, 672),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 14,
		ScrollBarImageColor3 = Color3.fromHex("8a8d93"),
	})
	Html.make("UIPadding", scroll, { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 14) })
	Html.make("UIGridLayout", scroll, {
		CellSize = UDim2.fromOffset(CARD_W, CARD_H),
		CellPadding = UDim2.fromOffset(GAP, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	self._scroll = scroll

	-- Detail column: 440x672, border 4
	local d = Html.box(self.Body, { name = "Detail", x = 846, y = 22, w = 440, h = 672, bg = C.Dark, alpha = 0.35, r = 9 })
	local top = Html.box(d, { name = "Portrait", x = 0, y = 0, w = TOP_W, h = TOP_H, grad = { "d9c9a6", "a8916a" }, r = 9, z = 1, clip = true })
	self._portrait = top
	Html.box(d, { name = "PortraitLine", x = 0, y = TOP_H - 4, w = TOP_W, h = 4, bg = INK, z = 2 })
	-- The light behind the selected pet: turning rays, a soft pulse and the floor it stands on.
	local centre = UDim2.fromOffset(TOP_W / 2, TOP_H / 2)
	local rays = Juice.rays(top, { pos = centre, w = 620, color = "ffffff", alpha = 0.6, z = 1, period = 14 })
	local halo = Juice.glow(top, { pos = centre, w = 430, color = "ffffff", alpha = 0.95, z = 1, pulse = 0.3, period = 1.1 })
	Juice.glow(top, { pos = UDim2.fromOffset(TOP_W / 2, TOP_H - 22), w = 300, h = 54, color = "000000", alpha = 0.6, z = 1 })
	Juice.twinkle(top, TOP_W, TOP_H, {
		color = "ffffff",
		z = 3,
		keepGoing = function()
			return self.Root.Visible
		end,
	})
	local petRoot = Html.make("Frame", top, { Name = "Pet", Size = UDim2.fromOffset(TOP_W, TOP_H), ZIndex = 2 })
	local petPop = Html.make("UIScale", petRoot)
	-- Only for pets with no animated model yet: the portrait, kept alive with a breath.
	local art = Html.make("ImageLabel", petRoot, { Name = "Art", Position = UDim2.fromOffset(115, 12), Size = UDim2.fromOffset(210, 210), ScaleType = Enum.ScaleType.Fit, ZIndex = 1 })
	Html.bob(art, 3)
	Motion.loop(Html.make("UIScale", art), { Scale = 1.04 }, 1.2)
	local petStage = PetStage.new(petRoot, { name = "Stage", priority = true, aspect = TOP_W / TOP_H, z = 2 })
	self._starterTag = Html.box(top, { name = "Starter", pos = UDim2.fromOffset(428, 16), anchor = V2(1, 0), h = 36, w = 0, auto = "X", bg = C.Sand, r = 10, b = 3, rot = 4, z = 3 })
	Html.make("UIPadding", self._starterTag, { PaddingLeft = UDim.new(0, 15), PaddingRight = UDim.new(0, 15) })
	Html.label(self._starterTag, { text = "Neutral Starter", ts = 18, color = INK, size = UDim2.new(0, 0, 1, 0), auto = "X" })
	self._eqTag = Html.box(top, { name = "Equipped", x = 16, y = 16, h = 36, w = 130, bg = C.Ok, r = 10, b = 3, z = 3 })
	Html.label(self._eqTag, { text = "EQUIPPED", ts = 18, stroke = 4 })
	self.NameLabel = Html.label(d, { text = "", ts = 38, stroke = 8, x = 18, y = 244, w = 404, h = 56, z = 2 })
	self.NameLabel.TextScaled = true
	Html.make("UITextSizeConstraint", self.NameLabel, { MaxTextSize = 46 })
	self.InfoLabel = Html.label(d, { text = "", ts = 24, stroke = 5, x = 18, y = 306, w = 404, h = 30, z = 2 })
	Html.label(d, { text = "XP", ts = 20, color = C.Muted, x = 20, y = 340, w = 34, h = 26, ax = "Left", z = 2 })
	self.XpBar = Html.bar(d, { x = 62, y = 344, w = 205, h = 18, bg = "2c2c2e", grad = { "7ddcff", "3aa6f0" }, r = 9 })
	self.XpLabel = Html.label(d, { text = "", ts = 20, x = 276, y = 340, w = 146, h = 26, ax = "Right", z = 2 })
	self.NextLabel = Html.label(d, { text = "", ts = 19, font = "Bold", color = C.Muted, x = 18, y = 371, w = 404, h = 24, rich = true, z = 2 })
	local stats = Html.make("ScrollingFrame", d, {
		Name = "Stats",
		Position = UDim2.fromOffset(20, 406),
		Size = UDim2.fromOffset(416, 146),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = Color3.fromHex("8a8d93"),
		ZIndex = 2,
	})
	Html.make("UIListLayout", stats, { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder })
	self._stats = stats
	local foot = Html.box(d, { name = "Foot", pos = UDim2.fromOffset(0, 564), w = 440, h = 104, bg = C.Dark, alpha = 0.3, z = 2 })
	Html.box(foot, { name = "Line", w = 440, h = 4, bg = INK })
	self.EquipBtn = Html.plate(foot, { x = 20, y = 18, w = 225, h = 70, grad = G.Orange, stud = false, b = 4, r = 8, sh = 4, hi = 4, hia = 0.3, lo = 6, text = "Equip", ts = 30, stroke = 6, hitY = 20 })
	local sell = Html.plate(foot, { x = 257, y = 18, w = 163, h = 70, grad = G.RedBtn, stud = false, b = 4, r = 8, sh = 4, hi = 4, hia = 0.3, lo = 6, text = "Sell", ts = 30, stroke = 6, hitY = 20 })
	self.SellBtn = sell
	self.Reason = Html.label(foot, { text = "", ts = 19, font = "Body", color = C.Gold, x = 16, y = 96, w = 408, h = 24, visible = false })
	Html.box(d, { name = "Border", w = 440, h = 672, r = 9, b = 4, z = 9 })
	self.EquipBtn.Activated:Connect(function()
		if self.Selected then
			self.EquipToggle:Fire(self.Selected)
		end
	end)

	-- Sell confirmation: 600px wide, centred inside the panel
	local dlg = Html.make("Frame", self.Root, { Name = "SellDialog", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10 })
	local dimBtn = Html.box(dlg, { class = "TextButton", name = "Dim", size = UDim2.fromScale(1, 1), bg = "0a0c10", alpha = 0.62, r = 8 })
	dimBtn.Text = ""
	dimBtn.AutoButtonColor = false
	local card = Html.make("Frame", dlg, { Name = "Card", Size = UDim2.fromOffset(600, 430) })
	local cardScale = Html.make("UIScale", card)
	card.AnchorPoint = V2(0.5, 0.5)
	card.Position = UDim2.fromOffset(660, 418)
	Html.box(card, { name = "Shadow", y = 8, size = UDim2.fromScale(1, 1), bg = INK, r = 18, z = 0 })
	local face = Html.box(card, { name = "Face", size = UDim2.fromScale(1, 1), bg = Html.GLASS, alpha = 0.97, r = 18, z = 1 })
	local head = Html.box(face, { name = "Head", x = 5, y = 5, w = 590, h = 84, grad = G.Red, r = 13, z = 1 })
	Html.gloss(head, 590, 84, { 30, 54, 66, 80, 0.3 }, 0.3, 13)
	Html.box(head, { name = "Line", pos = UDim2.new(0, 0, 1, -5), size = UDim2.new(1, 0, 0, 5), bg = INK })
	Html.label(head, { text = "Sell pet?", ts = 46, stroke = 9, x = 0, y = 0, w = 590, h = 79, z = 2 })
	Html.box(face, { name = "Border", size = UDim2.fromScale(1, 1), r = 18, b = 5, z = 8 })
	self.SellName = Html.label(face, { text = "", ts = 34, stroke = 7, x = 30, y = 106, w = 540, h = 42, z = 2 })
	local valueRow = Html.make("Frame", face, { Name = "ValueRow", Position = UDim2.fromOffset(30, 146), Size = UDim2.fromOffset(540, 76), ZIndex = 2 })
	Html.make("UIListLayout", valueRow, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	Html.icon(valueRow, "cash", { w = 76, h = 76, order = 1 })
	self.SellValue = Html.label(valueRow, { text = "+$0", ts = 48, color = C.Cash, stroke = 9, auto = "XY", order = 2 })
	self.SellNote = Html.label(face, { text = "It will be unequipped first.", ts = 22, font = "Body", color = C.Gold, x = 30, y = 222, w = 540, h = 27, z = 2 })
	self.SellBreak = Html.label(face, { text = "", ts = 22, font = "Body", color = C.Muted, x = 30, y = 250, w = 540, h = 27, wrap = true, z = 2 })
	self.SellCaution = Html.label(face, { text = "This can't be undone.", ts = 22, font = "Body", color = C.Muted, x = 30, y = 278, w = 540, h = 27, wrap = true, z = 2 })
	local cancel = Html.plate(face, { x = 30, y = 322, w = 263, h = 76, grad = G.Grey, stud = false, b = 4, r = 8, sh = 4, hi = 4, hia = 0.3, lo = 6, text = "Cancel", ts = 32, stroke = 7, hitY = 16, z = 3 })
	local ok = Html.plate(face, { x = 307, y = 322, w = 263, h = 76, grad = G.RedBtn, stud = false, b = 4, r = 8, sh = 4, hi = 4, hia = 0.3, lo = 6, text = "Sell", ts = 32, stroke = 7, hitY = 16, z = 3 })
	local function closeSale()
		dlg.Visible = false
	end
	cancel.Activated:Connect(function()
		closeSale()
		self.SellCancelled:Fire()
	end)
	dimBtn.Activated:Connect(function()
		closeSale()
		self.SellCancelled:Fire()
	end)
	ok.Activated:Connect(function()
		self.SellConfirmed:Fire(self.Selected)
	end)
	-- The server owns the price: the dialog shows a quote state, never a local value.
	function self:SetSale(s)
		self.SellValue.Text = s.value or "…"
		self.SellBreak.Text = s.breakdown or ""
		self.SellCaution.Text = s.caution or "This can't be undone."
		ok:SetText(s.confirmText or "Sell")
		ok:SetEnabled(s.canConfirm == true)
		ok:SetGrad(if s.canConfirm then G.RedBtn else G.Grey)
		cancel:SetText(s.cancelText or "Cancel")
	end
	function self:CloseSale()
		closeSale()
	end
	function self:_get(id)
		for _, p in self._list do
			if p.id == id then
				return p
			end
		end
	end
	sell.Activated:Connect(function()
		local p = self:_get(self.Selected)
		if not p or p.canSell == false then
			return
		end
		self.SellName.Text = p.name .. " (Lv " .. p.lv .. ")"
		self.SellNote.Visible = p.isEq == true
		self:SetSale({ confirmText = "Check price" })
		dlg.Visible = true
		Html.popIn(card, cardScale, nil, 0.35)
		self.SellRequested:Fire(p.id)
	end)

	local function fillStats(p)
		for _, c in stats:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local grid = Html.make("Frame", stats, { Name = "Fields", Size = UDim2.new(1, -14, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
		Html.make("UIGridLayout", grid, { CellSize = UDim2.fromOffset(196, 63), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder })
		for i, s in p.stats or {} do
			local f = Html.box(grid, { w = 196, h = 63, bg = C.Dark, alpha = 0.45, r = 10, b = 3, order = i })
			Html.label(f, { text = s.k, ts = 17, font = "Body", color = C.Muted2, x = 13, y = 8, w = 176, h = 20, ax = "Left" })
			Html.label(f, { text = s.v, ts = 21, x = 13, y = 28, w = 176, h = 26, ax = "Left" })
		end
		Html.label(stats, { text = "Attacks", ts = 22, stroke = 5, size = UDim2.new(1, -14, 0, 27), ax = "Left", order = 2 })
		local moves = Html.make("Frame", stats, { Name = "Moves", Size = UDim2.new(1, -14, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3 })
		Html.make("UIGridLayout", moves, { CellSize = UDim2.fromOffset(196, 44), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder })
		for i, name in p.moves or {} do
			local m = Html.box(moves, { w = 196, h = 44, grad = { "6b6f77", "55585e" }, r = 10, order = i })
			Html.box(m, { name = "Hi", x = 3, y = 3, w = 190, h = 3, bg = "ffffff", alpha = 0.2 })
			Html.box(m, { name = "Border", w = 196, h = 44, r = 10, b = 3, z = 2 })
			Html.label(m, { text = name, ts = 20, z = 3 })
		end
	end

	function self:Select(id)
		local changed = self.Selected ~= id
		self.Selected = id
		for pid, c in self._cards do
			local on = pid == id
			c.Ring.Visible = on
			c.Glow.Visible = on
			c.Shadow.Visible = not on
			c.Face.Position = UDim2.fromOffset(0, if on then -4 else 0)
			c.Frame.ZIndex = if on then 2 else 1
			if on and changed and not Motion.Reduced then
				c.Scale.Scale = 0.9
				Motion.tween(c.Scale, 0.35, { Scale = 1 }, "Back")
			elseif not on then
				c.Scale.Scale = 1
			end
		end
		if changed then
			self:_markCard(self._cards[id])
		end
		local p = self:_get(id)
		if not p then
			return
		end
		local pair = Theme.Rarity[p.rarity] or Theme.Rarity.Common
		Html.grad(self._portrait, pair[1], pair[2])
		local light = pair[1]:Lerp(Color3.new(1, 1, 1), 0.65)
		rays.ImageColor3, halo.ImageColor3 = light, light
		Portrait.Update(art, p.speciesId, nil, p.stage)
		local animated = petStage:Set(p.speciesId, p.stage)
		art.Visible = not animated
		if changed and not Motion.Reduced then
			petPop.Scale = 0.55
			Motion.tween(petPop, 0.45, { Scale = 1 }, "Back")
			Juice.ripple(top, centre, { color = light, from = 60, to = 560, life = 0.55, alpha = 0.9, z = 3 })
			Juice.burst(top, centre, { color = light, count = 10, radius = 210, spark = 34, z = 3 })
		end
		self._starterTag.Visible = p.starter == true
		self._eqTag.Visible = p.isEq == true
		self.NameLabel.Text = p.name
		self.InfoLabel.Text = string.format("%s · Lv %d", p.starter and "Neutral Starter" or p.rarity, p.lv)
		self.InfoLabel.TextColor3 = pair[1]
		self.XpBar:SetPct(p.xp / p.xpNeed, 0.5)
		self.XpLabel.Text = string.format("%d / %d XP", p.xp, p.xpNeed)
		self.NextLabel.Text = if p.nextGain then 'Next level  <font color="#6ae454">' .. p.nextGain .. "</font>" else "Max level"
		if changed then
			fillStats(p)
		end
		local full = self._eqCount >= self._maxTeam
		local b = self.EquipBtn
		if p.isEq then
			b:SetText("Unequip")
			b:SetGrad(G.Orange)
			b:SetEnabled(true)
			b:SetOpacity(1)
		elseif full then
			b:SetText("Team full")
			b:SetGrad(G.Grey)
			b:SetEnabled(false)
			b:SetOpacity(0.75)
		else
			b:SetText("Equip")
			b:SetGrad(G.Green)
			b:SetEnabled(true)
			b:SetOpacity(1)
		end
		if p.teamText then
			b:SetText(p.teamText)
			b:SetGrad(G.Grey)
			b:SetEnabled(false)
			b:SetOpacity(0.75)
		end
		sell:SetEnabled(p.canSell ~= false)
		sell:SetGrad(if p.canSell ~= false then G.RedBtn else G.Grey)
		self.Reason.Text = p.reason or "Team is full (3/3) — unequip one first"
		local hasReason = p.reason ~= nil or ((not p.isEq) and full)
		self.Reason.Visible = hasReason
		foot.Position = UDim2.fromOffset(0, if hasReason then 537 else 564)
		foot.Size = UDim2.fromOffset(440, if hasReason then 131 else 104)
		stats.Size = UDim2.fromOffset(416, if hasReason then 119 else 146)
		self.SelectPet:Fire(id)
	end

	-- The selected card breathes its halo and carries a shine; only that one, so the rest stay calm.
	local markedTween, markedShine = nil, nil
	function self:_markCard(c)
		if markedTween then
			markedTween:Cancel()
			markedTween = nil
		end
		if markedShine then
			markedShine:Destroy()
			markedShine = nil
		end
		if not c then
			return
		end
		c.Glow.BackgroundTransparency = 0.25
		markedTween = Motion.loop(c.Glow, { BackgroundTransparency = 0.7 }, 0.8)
		markedShine = Html.make("Frame", c.Face, { Name = "Shine", Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(CARD_W - 8, CARD_H - 8), ClipsDescendants = true, ZIndex = 5 })
		Html.shine(markedShine, 50, 2.6, 0.5, 0.1, CARD_W + 40)
	end

	local function setStagesActive(on)
		petStage:SetActive(on)
		for _, c in self._cards do
			if c.Stage then
				c.Stage:SetActive(on)
			end
		end
	end
	local openPanel, closePanel = self.Open, self.Close
	function self:Open()
		openPanel(self)
		setStagesActive(true)
	end
	function self:Close()
		closePanel(self)
		setStagesActive(false)
	end

	function self:SetPets(list, maxTeam, maxPets, animate)
		self._list, self._maxTeam = list, maxTeam or 3
		self:_markCard(nil)
		for _, c in self._cards do
			if c.Stage then
				c.Stage:Destroy()
			end
			if c.Breath then
				c.Breath:Cancel()
			end
			c.Frame:Destroy()
		end
		self._cards = {}
		local eq = 0
		for i, p in list do
			if p.isEq then
				eq += 1
			end
			local pair = Theme.Rarity[p.rarity] or Theme.Rarity.Common
			local f = Html.make("Frame", self._scroll, { Name = "Pet" .. i, LayoutOrder = i })
			local sc = Html.make("UIScale", f)
			local halo = Html.box(f, { name = "Glow", x = -8, y = -12, w = CARD_W + 16, h = CARD_H + 16, bg = "ffd63a", alpha = 0.55, r = 16, z = -1, visible = false })
			local glow = Html.box(f, { name = "Ring", x = -5, y = -9, w = CARD_W + 10, h = CARD_H + 10, bg = "ffffff", r = 12, z = 0, visible = false })
			local drop = Html.box(f, { name = "Shadow", y = 4, w = CARD_W, h = CARD_H, bg = INK, r = 9, z = 0 })
			local face = Html.box(f, { name = "Face", w = CARD_W, h = CARD_H, grad = pair, r = 9, z = 1 })
			local strip = Html.box(face, { name = "Strip", x = 4, y = 4, w = CARD_W - 8, h = 42, grad = { "5c5c5e", "444446" }, z = 1 })
			Html.gloss(strip, CARD_W - 8, 42, { 8, 18, 24, 30, 0.18 })
			Html.box(strip, { name = "Line", y = 38, w = CARD_W - 8, h = 4, bg = INK, z = 2 })
			Html.label(strip, { text = p.short or p.name, ts = 19, stroke = 5, x = 0, y = 0, w = CARD_W - 8, h = 38, z = 3 })
			-- The portrait stands in until the live model is built; species with no model keep it, breathing.
			local pic = Portrait.New(p.speciesId, nil, p.stage)
			pic.Position, pic.Size, pic.ZIndex, pic.Parent = UDim2.fromOffset(16, 56), UDim2.fromOffset(CARD_W - 32, 130), 2, face
			local cardStage = PetStage.new(face, {
				pos = UDim2.fromOffset(6, 48),
				size = UDim2.fromOffset(CARD_W - 12, 152),
				aspect = (CARD_W - 12) / 152,
				z = 2,
				isVisible = function()
					local top0, height = scroll.AbsolutePosition.Y, scroll.AbsoluteSize.Y
					return f.AbsolutePosition.Y + f.AbsoluteSize.Y > top0 and f.AbsolutePosition.Y < top0 + height
				end,
			})
			local breath = nil
			if cardStage:Set(p.speciesId, p.stage) then
				cardStage.OnBuilt = function()
					pic.Visible = false
				end
				cardStage:SetActive(self.Root.Visible)
			else
				cardStage:Destroy()
				cardStage = nil
				breath = Motion.loop(Html.make("UIScale", pic), { Scale = 1.05 }, 1.2 + (i % 5) * 0.08)
			end
			Html.label(face, { text = "Lv " .. p.lv, ts = 21, stroke = 5, x = 12, y = 50, w = 120, h = 25, ax = "Left", z = 3 })
			Html.label(face, { text = p.starter and "Neutral Starter" or p.rarity, ts = 20, stroke = 5, x = 4, y = 204, w = CARD_W - 8, h = 24, z = 3 })
			if p.isEq then
				local mark = Html.box(face, { name = "Check", x = CARD_W - 48, y = 52, w = 38, h = 38, bg = C.Ok, r = UDim.new(0.5, 0), b = 4, z = 3 })
				Html.label(mark, { text = "✓", ts = 24, stroke = 5 })
			end
			Html.box(face, { name = "Border", w = CARD_W, h = CARD_H, r = 9, b = 4, z = 6 })
			local hit = Html.make("TextButton", f, { Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = 5 })
			hit.Activated:Connect(function()
				self:Select(p.id)
			end)
			self._cards[p.id] = { Frame = f, Ring = glow, Glow = halo, Shadow = drop, Face = face, Scale = sc, Stage = cardStage, Breath = breath }
			if animate and not Motion.Reduced then
				sc.Scale = 0.94
				Motion.tween(sc, 0.4, { Scale = 1 }, "Quad", (i - 1) * 0.04)
			end
		end
		self._eqCount = eq
		self.CountLabel.Text = if maxPets and maxPets > 0 then string.format("(%d/%d)", #list, maxPets) else string.format("(%d)", #list)
		self.TeamLabel.Text = string.format("%d/%d", eq, self._maxTeam)
		local keep = if self:_get(self.Selected) then self.Selected else (list[1] and list[1].id)
		self.Selected = nil
		if keep then
			self:Select(keep)
		end
		petStage:SetActive(self.Root.Visible)
	end
	return self
end

return PetsPanel
