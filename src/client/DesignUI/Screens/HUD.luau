-- HUD: 1:1 from "FreeAPet HUD (offline).html" (1920x1080 canvas). Values are the HTML's CSS.
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Html = require(Core.Html)
local Motion = require(Core.Motion)
local Signal = require(Core.Signal)
local Layout = require(Core.Layout)

local C, G = Theme.Colors, Theme.Grad
local INK, INK2 = Html.INK, Html.INK2
local V2 = Vector2.new

local HUD = {}
HUD.__index = HUD

local function money(n)
	return "$" .. tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end
local function clock(s)
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
HUD.Money, HUD.Clock = money, clock

local PROX = {
	["Battle"] = { grad = G.Battle, icon = "battle", label = "Battle", hint = "Wild ·" },
	["Catch"] = { grad = G.Catch, icon = "capsule", label = "Catch", hint = "In battle ·" },
	["Heal team"] = { grad = G.Heal, icon = "heal", label = "Heal team", hint = "" },
	["Blocked"] = { grad = G.Grey, icon = "lock", label = "Battle", hint = "Wild ·", blocked = true, note = "Can't battle inside the Safe Zone" },
	["Out of range"] = { grad = G.Grey, icon = "battle", label = "Get closer", hint = "Too far ·", blocked = true, note = "Walk closer to interact" },
}

-- Tile geometry inside the 272px nav column at left:36 top:250.
local TILES = {
	-- wave: the shine runs down the column instead of hitting every tile at once.
	{ key = "pets", label = "Pets", x = 36, y = 344, grad = G.Orange, ts = 24, wave = 0 },
	{ key = "index", label = "Index", x = 180, y = 344, grad = G.Blue, ts = 24, wave = 0.3 },
	{ key = "research", label = "Research", x = 36, y = 488, grad = G.Pink, ts = 20, wave = 0.6 },
	{ key = "trade", label = "Trade", x = 180, y = 488, grad = G.GreenC, ts = 24, wave = 0.9 },
}

function HUD.new(stage)
	local self = setmetatable({}, HUD)
	for _, n in { "Base", "Pets", "Index", "Research", "Trade", "Shop", "Settings", "News", "Action", "ActionNext", "ActionPress", "LevelBar", "LeaderboardToggled" } do
		self[n] = Signal.new()
	end
	local g = Html.make("Frame", stage, { Name = "HUD", Size = UDim2.fromOffset(1920, 1080), ZIndex = Theme.Z.HUD })
	self._fade = Html.make("CanvasGroup", stage, { Name = "HUDFade", Size = UDim2.fromOffset(1920, 1080), ZIndex = Theme.Z.HUD, Visible = false })
	self.Group, self.Root, self._stage = g, g, stage
	self._cash, self._lv = 0, nil
	self._over = 0
	self.BoardOpen = true

	-- Settings: right:16 top:12, grown to 64x64 so the bigger icon reads.
	-- The only button in the HUD without the gloss and shine: it stays out of the way.
	local st = Html.plate(g, {
		name = "SettingsBtn", x = 1840, y = 12, w = 64, h = 64, grad = { "6e6f73", "47484c" }, stud = false, b = 4, r = 9, sh = 3, hi = 3, lo = 4,
		gloss = false, shine = false, press = 3, pressScale = 0.92, hitX = 28, hitY = 18,
	})
	self._settingsBtn = st
	Html.icon(st.Content, "settings", { x = -4, y = -4, w = 72, h = 72 })
	st.Activated:Connect(function()
		self.Settings:Fire()
	end)

	-- Base: left:50% top:22 320x84
	local base = Html.plate(g, {
		name = "Base", x = 800, y = 22, w = 320, h = 84, grad = G.Green, b = 5, r = 8, sh = 6, hi = 5, lo = 8,
		gloss = { 26, 46, 58, 70, 0.32 }, shine = { 60, 3.6, 0.55 }, text = "Base", ts = 48, stroke = 8, press = 5, pressScale = 0.98, hitY = 19,
	})
	self._baseBtn = base
	base.Activated:Connect(function()
		self.Base:Fire()
	end)

	-- Player level: left:36 top:250 272x76
	local lv = Html.box(g, { name = "LevelBar", x = 36, y = 250, w = 272, h = 76, bg = "000000", alpha = 0.55, r = 10, b = 4, bc = INK2 })
	local badge = Html.box(lv, { name = "Badge", x = 10, y = 9, w = 58, h = 58, grad = { "ffd75a", "f0aa1c" }, r = UDim.new(0.5, 0), z = 1 })
	Html.studs(badge, UDim.new(0.5, 0))
	Html.box(badge, { name = "Border", w = 58, h = 58, r = UDim.new(0.5, 0), b = 4, bc = INK2, z = 2 })
	self.LvNum = Html.label(badge, { text = "1", ts = 28, font = "Num", stroke = 6, strokeColor = INK2, z = 3 })
	self._lvScale = Html.make("UIScale", badge)
	local xpRow = Html.make("Frame", lv, { Name = "XpRow", Position = UDim2.fromOffset(78, 16), Size = UDim2.fromOffset(178, 23) })
	Html.make("UIListLayout", xpRow, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	self.LvText = Html.label(xpRow, { text = "LEVEL 1", ts = 19, font = "Num", stroke = 4, strokeColor = INK2, auto = "XY", ax = "Left", order = 1 })
	self.XpText = Html.label(xpRow, { text = "0 / 100 XP", ts = 19, font = "Num", stroke = 4, strokeColor = INK2, auto = "XY", ax = "Right", order = 2 })
	self.XpBar = Html.bar(lv, { x = 78, y = 44, w = 178, h = 16, grad = { "ffe066", "f0b81c" }, bc = INK2, r = 8 })
	local lvHit = Html.make("TextButton", lv, { Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = 5 })
	lvHit.Activated:Connect(function()
		self.LevelBar:Fire()
	end)

	-- Navigation tiles: 128x128, gap 16
	self.Tiles = {}
	for _, d in TILES do
		local b = Html.plate(g, {
			name = d.key, x = d.x, y = d.y, w = 128, h = 128, grad = d.grad, b = 4, r = 10, sh = 5, hi = 5, lo = 7,
			shine = { 58, 4.2, 0.5, d.wave }, press = 4, pressScale = 0.96, hit = 128,
		})
		b.IconImage = Html.icon(b.Content, d.key, { x = -6, y = -24, w = 140, h = 140 })
		b.NameLabel = Html.label(b.Content, {
			name = "Name", text = d.label, ts = d.ts, stroke = 6, x = 0, y = d.ts == 24 and 89 or 94, w = 128, h = d.ts == 24 and 29 or 24,
		})
		local lock = Html.box(b.Content, { name = "Lock", x = 4, y = 4, w = 120, h = 120, bg = C.Locked, alpha = 0.9, r = 6, visible = false, z = 3 })
		Html.icon(lock, "lock", { x = 19, y = 2, w = 82, h = 82 })
		b.LockText = Html.label(lock, { text = "Lv 5", ts = 24, font = "Num", stroke = 5, strokeColor = INK2, x = 0, y = 80, w = 120, h = 30 })
		b.LockFrame = lock
		b.Activated:Connect(function()
			self[d.label]:Fire()
		end)
		self.Tiles[d.key] = b
	end
	local chip = Html.box(self.Tiles.research.Root, {
		name = "Timer", pos = UDim2.fromOffset(132, -6), anchor = V2(1, 0), h = 34, w = 0, auto = "X", bg = C.Gold, r = 10, b = 3, visible = false, z = 8,
	})
	Html.make("UIPadding", chip, { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
	self.TimerLabel = Html.label(chip, { text = "0:00", ts = 20, color = INK, size = UDim2.new(0, 0, 1, 0), auto = "X" })
	self.TimerChip = chip

	-- Shop: span 2, 272x104
	local shop = Html.plate(g, {
		name = "shop", x = 36, y = 632, w = 272, h = 104, grad = G.Red, b = 4, r = 10, sh = 5, hi = 5, lo = 7,
		gloss = { 22, 40, 50, 60, 0.3 }, shine = { 50, 2.6, 0.6, 1.2 }, press = 4, pressScale = 0.97, hit = 104,
	})
	local shopIcon = Html.icon(shop.Content, "shop", { x = 8, y = -30, w = 132, h = 132 })
	Html.bob(shopIcon, 2.6)
	Html.label(shop.Content, { name = "Name", text = "Shop", ts = 42, stroke = 8, x = 139, y = 26, w = 118, h = 52 })
	-- Only the Shop stays in motion: it breathes and its icon rocks on top of the shared shine.
	Motion.loop(Html.make("UIScale", shop.Root), { Scale = 1.035 }, 0.9)
	shopIcon.Rotation = -6
	Motion.loop(shopIcon, { Rotation = 6 }, 1.3)
	shop.Activated:Connect(function()
		self.Shop:Fire()
	end)
	self.Tiles.shop = shop

	-- Cash block: left:36 bottom:36
	-- The bob tweens the icon's own Position, so the pin has to move a holder around it.
	local cashHolder = Html.make("Frame", g, { Name = "CashHolder", Position = UDim2.fromOffset(16, 797), Size = UDim2.fromOffset(136, 136) })
	local cashIcon = Html.icon(cashHolder, "cash", { name = "CashIcon", x = 0, y = 0, w = 136, h = 136 })
	Html.bob(cashIcon, 3)
	-- Every layer of the amount lives in one block, so the pin and the pulse carry them together.
	local cashBlock = Html.make("Frame", g, { Name = "CashBlock", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(152, 870), Size = UDim2.fromOffset(900, 130) })
	self._cashPulse = Html.make("UIScale", cashBlock, { Scale = 1 })
	local cashDepth = Html.label(cashBlock, { name = "CashDepth", text = "$0", ts = 108, font = "Num", color = Color3.fromRGB(20, 99, 47), stroke = 14, x = 0, y = 7, w = 900, h = 130, ax = "Left" })
	self.CashLabel = Html.label(cashBlock, { name = "Cash", text = "$0", ts = 108, font = "Num", stroke = 12, x = 0, y = 0, w = 900, h = 130, ax = "Left" })
	Html.make("UIGradient", self.CashLabel, {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(226, 255, 176)),
			ColorSequenceKeypoint.new(0.5, C.Cash),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(44, 176, 62)),
		}),
	})
	-- The shine layer hugs the text, so the sweep crosses the amount whatever its length.
	local cashGleam = Html.label(cashBlock, { name = "CashGleam", text = "$0", ts = 108, font = "Num", x = 0, y = 0, w = 900, h = 130, ax = "Left", visible = not Motion.Reduced })
	cashGleam.AutomaticSize = Enum.AutomaticSize.X
	cashGleam.Size = UDim2.fromOffset(0, cashGleam.Size.Y.Offset)
	local gleam = Html.make("UIGradient", cashGleam, {
		Rotation = 20,
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.15),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
	if not Motion.Reduced then
		local sweep = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 4)
		game:GetService("TweenService"):Create(gleam, sweep, { Offset = Vector2.new(1, 0) }):Play()
	end
	self.CashLabel:GetPropertyChangedSignal("Text"):Connect(function()
		cashDepth.Text = self.CashLabel.Text
		cashGleam.Text = self.CashLabel.Text
	end)
	self.RateLabel = Html.label(g, { name = "Rate", text = "+$0.00/s", ts = 36, font = "Num", color = Color3.fromRGB(205, 255, 190), stroke = 7, x = 152, y = 926, w = 500, h = 43, ax = "Left" })
	local dayRow = Html.make("Frame", g, { Name = "DayRow", Position = UDim2.fromOffset(36, 981), Size = UDim2.fromOffset(800, 63) })
	Html.make("UIListLayout", dayRow, {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 16),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	Html.label(dayRow, { name = "DayLabel", text = "DAY ENDS IN", ts = 32, color = C.Gold, stroke = 7, auto = "XY", order = 1 })
	self.DayLabel = Html.label(dayRow, { name = "Day", text = "0:00", ts = 52, font = "Num", stroke = 9, auto = "XY", order = 2 })
	local speed = Html.box(dayRow, { name = "Speed", w = 0, h = 62, auto = "X", bg = "2c2c2e", r = 8, b = 4, order = 3 })
	Html.make("UIPadding", speed, { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 18) })
	Html.make("UIListLayout", speed, {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	Html.icon(speed, "speed", { w = 58, h = 58, order = 1 })
	self.SpeedLabel = Html.label(speed, { text = "—", ts = 30, auto = "XY", order = 2 })

	-- Boosts: small and quiet in the corner, labels on the same line as the News button's base.
	local friendsIcon = Html.icon(g, "friends", { name = "Friends", x = 1622, y = 938, w = 84, h = 84 })
	self.FriendLabel = Html.label(g, { name = "FriendPct", text = "—", ts = 26, color = C.Cash, stroke = 6, x = 1616, y = 1018, w = 96, h = 32 })
	local plusIcon = Html.icon(g, "plus", { name = "Plus", x = 1714, y = 938, w = 84, h = 84 })
	self.PlusLabel = Html.label(g, { name = "PlusPct", text = "—", ts = 26, color = C.Cash, stroke = 6, x = 1708, y = 1018, w = 96, h = 32 })
	-- The paper stays inside its plate, so the button reads as a button; the dot rides its corner.
	local news = Html.plate(g, {
		name = "News", x = 1812, y = 982, w = 72, h = 72, grad = G.Blue, stud = false, b = 4, r = 10, sh = 4, hi = 3, lo = 4, press = 4, pressScale = 0.96, hit = 122,
	})
	Html.icon(news.Content, "news", { x = 7, y = 7, w = 58, h = 58 })
	Html.box(news.Root, { name = "Dot", x = 54, y = -8, w = 26, h = 26, bg = C.Badge, r = UDim.new(0.5, 0), b = 3, z = 2 })
	news.Activated:Connect(function()
		self.News:Fire()
	end)

	self:_buildLeaderboard(g)
	self:_buildAction(g)

	-- Desktop, laptop and TV: every group touches the screen edge it belongs to, whatever the
	-- aspect ratio. wall = its distance from that edge on the 1920x1080 canvas.
	self._pins = {}
	local function pin(inst, sx, sy, wallX, wallY)
		if inst then
			table.insert(self._pins, { inst = inst, base = inst.Position, sx = sx, sy = sy, wallX = wallX or 0, wallY = wallY or 0 })
		end
	end
	pin(st.Root, 1, -1, 16, 12)
	pin(base.Root, 0, -1, 0, 22)
	pin(lv, -1, 0, 36)
	for _, key in { "pets", "index", "research", "trade", "shop" } do
		pin(self.Tiles[key].Root, -1, 0, 36)
	end
	for _, item in { cashHolder, cashBlock, self.RateLabel, dayRow } do
		pin(item, -1, 1, 36, 36)
	end
	for _, item in { friendsIcon, self.FriendLabel, plusIcon, self.PlusLabel, news.Root } do
		pin(item, 1, 1, 36, 26)
	end
	-- The action prompt keeps its distance from the bottom but is not pulled to the wall.
	pin(self._action, 0, 1, 0, Layout.EDGE)
	return self
end

function HUD:_buildLeaderboard(g)
	-- Collapsed tab: right:0 top:80 60x62
	local tab = Html.box(g, { name = "LbTab", x = 1860, y = 80, w = 60, h = 62, bg = "28282a", alpha = 0.9, r = 10, b = 4, bc = INK2, visible = false, clip = true })
	Html.icon(tab, "trophy", { x = 3, y = 4, w = 54, h = 54 })
	Html.shine(tab, 26, 4.2, 0.5, 0.4, 86)
	local tabHit = Html.make("TextButton", tab, { Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(-30, -30), Size = UDim2.new(1, 30, 1, 60), ZIndex = 5 })
	-- Open panel: right:16 top:80 420px wide
	local panel = Html.make("Frame", g, { Name = "Leaderboard", Position = UDim2.fromOffset(1484, 80), Size = UDim2.fromOffset(420, 306), ZIndex = 8 })
	self._lbPanel = panel
	Html.box(panel, { name = "Shadow", y = 6, size = UDim2.fromScale(1, 1), bg = INK, alpha = 0.6, r = 9, z = 0 })
	local face = Html.box(panel, { name = "Face", size = UDim2.fromScale(1, 1), bg = "28282a", alpha = 0.82, r = 9, z = 1 })
	Html.box(face, { name = "Border", size = UDim2.fromScale(1, 1), r = 9, b = 4, z = 6 })
	local pad = Html.make("Frame", face, { Name = "Pad", Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8) })
	Html.make("UIListLayout", pad, { SortOrder = Enum.SortOrder.LayoutOrder })
	local head = Html.box(pad, { class = "TextButton", name = "Head", w = 412, h = 54, grad = { "6e6f73", "535457" }, order = 1 })
	head.Text = ""
	head.AutoButtonColor = false
	Html.gloss(head, 412, 54, { 16, 30, 38, 46, 0.25 })
	head.ClipsDescendants = true
	Html.shine(head, 28, 4.2, 0.5, 2, 440)
	Html.icon(head, "trophy", { x = 8, y = 1, w = 52, h = 52, z = 2 })
	Html.label(head, { text = "Leaderboard", ts = 28, stroke = 6, x = 66, y = 10, w = 240, h = 34, ax = "Left", z = 2 })
	local keyChip = Html.box(head, { name = "Key", x = 362, y = 10, w = 36, h = 34, bg = "e6e8ec", r = 8, b = 3, z = 2 })
	self.LbKey = Html.label(keyChip, { text = "▼", ts = 14, color = INK })
	self.LbKey.FontFace = Font.fromName("Arimo", Enum.FontWeight.Bold)
	local rows = Html.make("Frame", pad, { Name = "Rows", Size = UDim2.fromOffset(412, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	Html.make("UIPadding", rows, { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 8) })
	Html.make("UIListLayout", rows, { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
	self._lbRows = rows
	local over, overY, pinned = 0, 0, false
	local open = true
	local function apply(animated)
		-- right:16 on the phone; on the wall everywhere else.
		local openX = if pinned then 1484 + over + 16 - Layout.EDGE else 1484
		local y = if pinned then 80 - overY - (12 - Layout.EDGE) else 80
		local panelX = open and openX or (1920 + over + 24)
		local tabX = open and (1920 + over) or (1920 + over - 60)
		if animated then
			panel.Visible = true
			tab.Visible = true
			Motion.tween(panel, Theme.T.Leaderboard, { Position = UDim2.fromOffset(panelX, y) }, "Back")
			Motion.tween(tab, 0.3, { Position = UDim2.fromOffset(tabX, y) }, "Back")
		else
			panel.Position = UDim2.fromOffset(panelX, y)
			tab.Position = UDim2.fromOffset(tabX, y)
			panel.Visible = open
			tab.Visible = not open
		end
	end
	local function setOpen(v)
		open = v
		apply(true)
		self.LeaderboardToggled:Fire(v)
	end
	self.SetLeaderboardOpen = function(_, v)
		setOpen(v)
	end
	self._applyBoard = function(x, y, isPinned)
		over, overY, pinned = x, y, isPinned
		apply(false)
	end
	tabHit.Activated:Connect(function()
		setOpen(true)
	end)
	head.Activated:Connect(function()
		setOpen(false)
	end)
	apply(false)
end

-- rows = { {name, lv, rate, me}, ... }. Grid: 1fr 64px 120px, gap 10, padding 0 12.
function HUD:SetLeaderboard(rows)
	for _, c in self._lbRows:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local hdr = Html.make("Frame", self._lbRows, { Size = UDim2.fromOffset(396, 20), LayoutOrder = 0 })
	Html.label(hdr, { text = "Player", ts = 17, font = "Bold", color = C.Muted2, x = 12, y = 0, w = 168, h = 20, ax = "Left" })
	Html.label(hdr, { text = "Lv", ts = 17, font = "Bold", color = C.Muted2, x = 190, y = 0, w = 64, h = 20 })
	Html.label(hdr, { text = "Cash/s", ts = 17, font = "Bold", color = C.Muted2, x = 264, y = 0, w = 120, h = 20, ax = "Right" })
	self._lbPanel.Size = UDim2.fromOffset(420, 98 + 52 * #rows)
	for i, r in rows do
		local f = Html.box(self._lbRows, {
			name = "Row", w = 396, h = 46, order = i, r = 10,
			bg = r.me and C.Gold or C.Dark, alpha = r.me and 0.22 or 0.35, b = r.me and 3 or nil, bc = C.Gold,
		})
		Html.label(f, { text = r.name, ts = 24, font = "Body", x = 12, y = 0, w = 168, h = 46, ax = "Left" })
		local lv = Html.box(f, { name = "Lv", x = 199, y = 8, w = 46, h = 30, grad = { "ffd75a", "f0aa1c" }, r = 6, b = 3, bc = Html.INK2 })
		Html.label(lv, { text = tostring(r.lv), ts = 20, font = "Num", color = Html.INK2 })
		Html.label(f, { text = "$" .. string.format("%.2f", r.rate) .. "/s", ts = 24, color = C.Cash, x = 264, y = 0, w = 120, h = 46, ax = "Right" })
	end
end

function HUD:_buildAction(g)
	-- left:50% bottom:150: button 380x96 at y 834, label pill above it.
	local root = Html.make("Frame", g, { Name = "Action", Size = UDim2.fromOffset(1920, 1080), Visible = false })
	local pill = Html.box(root, { name = "Pill", pos = UDim2.fromOffset(960, 824), anchor = V2(0.5, 1), h = 52, w = 0, auto = "X", bg = C.Dark, alpha = 0.75, r = 8, b = 4 })
	Html.make("UIPadding", pill, { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) })
	Html.make("UIListLayout", pill, {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	self.ProxHint = Html.label(pill, { text = "", ts = 24, font = "Body", color = C.Muted, auto = "XY", order = 1 })
	self.ProxTarget = Html.label(pill, { text = "", ts = 26, auto = "XY", order = 2 })
	local wrap = Html.make("Frame", root, { Name = "BtnWrap", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromOffset(960, 882), Size = UDim2.fromOffset(380, 96) })
	self._pulse = Html.make("UIScale", wrap)
	self.ActionBtn = Html.plate(wrap, {
		name = "ActionBtn", w = 380, h = 96, grad = G.Battle, stud = false, b = 5, r = 10, sh = 6, hi = 6, hia = 0.32, lo = 9, loa = 0.22,
		shine = { 56, 3.2, 0.45 }, press = 5, pressScale = 0.98, hit = 122,
	})
	local content = self.ActionBtn.Content
	Html.make("UIListLayout", content, {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 18),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	self.ActionIcon = Html.icon(content, "battle", { w = 104, h = 104, order = 1 })
	self.ActionLabel = Html.label(content, { text = "Battle", ts = 44, stroke = 8, auto = "XY", order = 2 })
	function self.ActionBtn:SetText(t)
		self.Label.Text = t
	end
	self.ActionBtn.Label = self.ActionLabel
	self.ActionBtn.Hit.InputBegan:Connect(function(i)
		local t = i.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			self.ActionPress:Fire()
		end
	end)
	self.ActionBtn.Activated:Connect(function()
		if not self._blocked then
			self.Action:Fire()
		end
	end)
	self.ActionNote = Html.label(root, { text = "", ts = 24, stroke = 5, x = 560, y = 942, w = 800, h = 30 })
	self.NextBtn = Html.plate(root, {
		name = "Next", x = 840, y = 700, w = 240, h = 58, grad = G.Blue, stud = false, b = 4, r = 8, sh = 4, hi = 4, lo = 5,
		text = "Next target", ts = 24, stroke = 5, hitY = 20,
	})
	self.NextBtn.Root.Visible = false
	self.NextBtn.Activated:Connect(function()
		self.ActionNext:Fire()
	end)
	self._action = root
end

-- ========= API =========
-- overX/overY: canvas units the viewport extends past the 1920x1080 stage on each side.
-- pinned is false only on touch-only devices, where the safe inset is welcome.
function HUD:SetOverscan(overX, overY, pinned)
	overX, overY = overX or 0, overY or 0
	self._over, self._overY = overX, overY
	self._applyBoard(overX, overY, pinned)
	for _, p in self._pins do
		local dx = if pinned and p.sx ~= 0 then p.sx * (overX + p.wallX - Layout.EDGE) else 0
		local dy = if pinned and p.sy ~= 0 then p.sy * (overY + p.wallY - Layout.EDGE) else 0
		p.inst.Position = p.base + UDim2.fromOffset(dx, dy)
	end
	-- The fade group is what would clip the pinned edges during a fade: it covers the whole viewport.
	self._fade.Position = UDim2.fromOffset(-overX, -overY)
	self._fade.Size = UDim2.fromOffset(1920 + 2 * overX, 1080 + 2 * overY)
end

-- The gear's lower right corner on the canvas, wherever the pin put it.
function HUD:SettingsCorner()
	local position = self._settingsBtn.Root.Position
	local size = self._settingsBtn.Root.Size
	return position.X.Offset + size.X.Offset, position.Y.Offset + size.Y.Offset
end

-- Bottom of the Base button on the canvas: the notices read right below it.
function HUD:BaseBottom()
	local root = self._baseBtn.Root
	return root.Position.Y.Offset + root.Size.Y.Offset
end

function HUD:SetCash(v, bump)
	Motion.countTo(self.CashLabel, self._cash, v, 0.3, money)
	if bump and not Motion.Reduced then
		Motion.tween(self._cashPulse, 0.12, { Scale = 1.05 }, "Quad").Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				Motion.tween(self._cashPulse, 0.24, { Scale = 1 }, "Quad")
			end
		end)
	end
	self._cash = v
end

function HUD:SetRate(r)
	self.RateLabel.Text = r and ("+$" .. string.format("%.2f", r) .. "/s") or "—/s"
end
function HUD:SetDay(s)
	self.DayLabel.Text = clock(s)
end
function HUD:SetFriendBoost(pct)
	self.FriendLabel.Text = pct and ("+" .. pct .. "%") or "—"
end
function HUD:SetPlusBoost(pct)
	self.PlusLabel.Text = pct and ("+" .. pct .. "%") or "—"
end
function HUD:SetSpeed(v)
	self.SpeedLabel.Text = v and tostring(math.round(v)) or "—"
end

-- Reparents only for the duration of the fade; a newer fade takes over from an older one.
function HUD:Fade(show, t)
	self._fadeId = (self._fadeId or 0) + 1
	local id, g, fade = self._fadeId, self.Group, self._fade
	g.Visible = true
	g.Parent = fade
	g.Position = UDim2.fromOffset(self._over or 0, self._overY or 0)
	fade.Visible = true
	Motion.tween(fade, t, { GroupTransparency = show and 0 or 1 }).Completed:Once(function()
		if id ~= self._fadeId then
			return
		end
		g.Parent = self._stage
		g.Position = UDim2.new()
		fade.Visible = false
		g.Visible = show
	end)
end
function HUD:SetShown(show)
	self._fadeId = (self._fadeId or 0) + 1
	self.Group.Parent = self._stage
	self.Group.Position = UDim2.new()
	self._fade.Visible = false
	self._fade.GroupTransparency = show and 0 or 1
	self.Group.Visible = show
end
function HUD:SetActionNext(text)
	self.NextBtn.Root.Visible = text ~= nil
	if text then
		self.NextBtn:SetText(text)
	end
end

function HUD:SetPlayerLevel(lv, ratio, text)
	self.LvNum.Text = tostring(lv)
	self.LvText.Text = "LEVEL " .. lv
	self.XpText.Text = text
	if self._lv and lv > self._lv then
		if not Motion.Reduced then
			Motion.tween(self._lvScale, 0.2, { Scale = 1.2 }, "Quad").Completed:Once(function()
				Motion.tween(self._lvScale, 0.3, { Scale = 1 }, "Quad")
			end)
		end
		self.XpBar:SetPct(0)
	end
	self._lv = lv
	self.XpBar:SetPct(ratio, Theme.T.Bar)
end

-- req = { research = 3, trade = 15 } (required level), level = current player level
function HUD:SetLocks(level, req)
	for key, need in req do
		local t = self.Tiles[key]
		local locked = level < need
		t.LockFrame.Visible = locked
		t.LockText.Text = "Lv " .. need
		t.NameLabel.Visible = not locked
		-- The big icon pokes out of the tile, so the lock has to replace it, not cover it.
		t.IconImage.Visible = not locked
	end
end

function HUD:ShakeTile(key)
	Motion.shake(self.Tiles[key].Root, 10)
end

function HUD:SetResearchTimer(secs)
	self.TimerChip.Visible = secs ~= nil
	if secs then
		self.TimerLabel.Text = clock(secs)
	end
end

-- kind: "Battle" | "Catch" | "Heal team" | "Blocked" | "Out of range" | nil (hides)
function HUD:SetProximity(kind, target)
	local p = kind and PROX[kind]
	self._action.Visible = p ~= nil
	if not p then
		return
	end
	self._blocked = p.blocked == true
	self.ActionBtn:SetGrad(p.grad)
	self.ActionIcon.Image = Html.Icons[p.icon] or ""
	self.ActionLabel.Text = p.label
	self.ProxHint.Text, self.ProxHint.Visible = p.hint, p.hint ~= ""
	self.ProxTarget.Text = target or ""
	self.ActionNote.Text = p.note or ""
	if self._pulseTw then
		self._pulseTw:Cancel()
		self._pulseTw = nil
	end
	self._pulse.Scale = 1
	if not p.blocked then
		self._pulseTw = Motion.loop(self._pulse, { Scale = 1.07 }, 1.1)
	end
end

return HUD
