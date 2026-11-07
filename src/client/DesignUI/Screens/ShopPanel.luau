-- Shop + Codes: 1:1 from the HTML's "Painel Shop + Codes" (left:410 top:100 1100x880).
-- SetProducts(list): { id, name, sub, price, c1, c2, icon | placeholder, flagText, desc, owned, buyLabel, note, enabled }
-- Signals: BuyRequested(id), RedeemRequested(code). SetCodeState("idle"|"checking"|"ok"|"invalid"|"expired"|"used")
local TweenService = game:GetService("TweenService")
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Html = require(Core.Html)
local Motion = require(Core.Motion)
local Signal = require(Core.Signal)

local C, G = Theme.Colors, Theme.Grad
local INK = Html.INK
local V2 = Vector2.new

local CODE_MSG = {
	idle = { "Enter a code to get rewards", C.Muted },
	checking = { "Checking…", C.Gold },
	ok = { "✓ Code redeemed!", C.Cash },
	invalid = { "✗ Invalid code", C.Danger },
	expired = { "This code has expired", C.Warn },
	used = { "You already used this code", C.Warn },
}

local ShopPanel = {}

function ShopPanel.new(stage)
	local self = Html.panel(stage, { name = "Shop", x = 410, y = 100, w = 1100, h = 880, grad = G.Red, icon = "shop", title = "Shop!" })
	self.BuyRequested, self.RedeemRequested = Signal.new(), Signal.new()
	local jump = Html.plate(self.Header, {
		name = "JumpCodes", x = 790, y = 21, w = 186, h = 60, grad = G.Yellow, stud = false, b = 4, r = 8, sh = 4, hi = 4, hia = 0.4, lo = 0,
		text = "# Codes ↓", ts = 26, stroke = 6, press = 3, hitY = 31, z = 3,
	})
	local close = Html.closeX(self.Header, { x = 994, y = 10 })
	close.Activated:Connect(function()
		self.CloseRequested:Fire()
	end)

	-- Scroll: padding 24, gap 22, inner width 1040. Body origin is (416,214).
	local scroll = Html.make("ScrollingFrame", self.Body, {
		Name = "Scroll",
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 14,
		ScrollBarImageColor3 = Color3.fromHex("8a8d93"),
	})
	Html.make("UIPadding", scroll, { PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 24), PaddingTop = UDim.new(0, 24), PaddingBottom = UDim.new(0, 30) })
	Html.make("UIListLayout", scroll, { Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder })
	self._scroll = scroll

	-- Featured banner: 1040x200
	local holder = Html.make("Frame", scroll, { Name = "Featured", Size = UDim2.fromOffset(1040, 200), LayoutOrder = 1 })
	Html.box(holder, { name = "Shadow", y = 5, w = 1040, h = 200, bg = INK, r = 9, z = 0 })
	local ban = Html.box(holder, { name = "Face", w = 1040, h = 200, bg = "ffffff", r = 9, z = 1 })
	local bg = Instance.new("UIGradient")
	bg.Rotation = 10
	bg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("ffd23c")),
		ColorSequenceKeypoint.new(0.55, Color3.fromHex("ff8a3c")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("ff5a9e")),
	})
	bg.Parent = ban
	local banClip = Html.make("Frame", ban, { Name = "Clip", Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(1030, 190), ClipsDescendants = true })
	Html.studs(banClip, 4)
	Html.gloss(banClip, 1030, 190, { 30, 54, 66, 80, 0.3 }, 0.3, 4).ZIndex = 2
	Html.box(ban, { name = "Border", w = 1040, h = 200, r = 9, b = 5, z = 5 })
	local art = Html.box(ban, { name = "Art", x = 35, y = 25, w = 150, h = 150, r = 24, bg = "ffffff", alpha = 0, z = 3 })
	Html.bob(art, 2.8)
	Html.make("UIStroke", art, { Thickness = 4, Color = INK, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, BorderStrokePosition = Enum.BorderStrokePosition.Inner })
	Html.label(art, { text = "arte do\nproduto", ts = 18, font = "Body", color = INK })
	Html.label(ban, { text = "Featured product", ts = 44, stroke = 10, x = 211, y = 55, w = 560, h = 54, ax = "Left", z = 3 })
	Html.label(ban, { text = "Produto e preço por aprovar pelo Chefe", ts = 24, font = "Body", color = INK, x = 211, y = 116, w = 620, h = 29, ax = "Left", z = 3 })
	local price = Html.plate(ban, { x = 846, y = 64, w = 159, h = 72, grad = G.Grey, stud = false, b = 4, r = 8, sh = 5, hi = 4, lo = 0, text = "Soon", ts = 34, stroke = 7, press = 0, z = 3 })
	price:SetEnabled(false)
	local ptag = Html.box(ban, { name = "Tag", x = 860, y = 15, w = 163, h = 30, bg = "ffffff", r = 8, b = 3, z = 4 })
	Html.label(ptag, { text = "PLACEHOLDER", ts = 17, color = INK })

	-- Products: 3 columns, gap 18, 335x300
	local grid = Html.make("Frame", scroll, { Name = "Products", Size = UDim2.fromOffset(1040, 300), LayoutOrder = 2 })
	self._grid = grid

	-- Codes: 1040x284
	local codes = Html.box(scroll, { name = "Codes", w = 1040, h = 284, bg = C.Dark, alpha = 0.35, r = 9, order = 3 })
	local codesHead = Html.box(codes, { name = "Head", x = 5, y = 5, w = 1030, h = 64, grad = G.Yellow })
	Html.gloss(codesHead, 1030, 64, { 16, 30, 38, 46, 0.28 })
	Html.box(codesHead, { name = "Line", y = 60, w = 1030, h = 4, bg = INK, z = 2 })
	Html.label(codesHead, { text = "# Codes", ts = 36, stroke = 7, x = 22, y = 8, w = 600, h = 44, ax = "Left", z = 3 })
	Html.box(codes, { name = "Border", w = 1040, h = 284, r = 9, b = 5, z = 6 })
	local box = Html.box(codes, { class = "TextBox", name = "Input", x = 27, y = 91, w = 732, h = 76, bg = "262628", r = 8, b = 4, z = 2 })
	box.Text = ""
	box.ClearTextOnFocus = false
	box.FontFace = Theme.Fonts.Num
	box.TextSize = 36
	box.TextColor3 = Color3.new(1, 1, 1)
	box.PlaceholderText = "ENTER CODE…"
	box.PlaceholderColor3 = Color3.fromHex("8a8d93")
	box.TextXAlignment = Enum.TextXAlignment.Left
	Html.make("UIPadding", box, { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) })
	self._boxStroke = box:FindFirstChildOfClass("UIStroke")
	local redeem = Html.plate(codes, { name = "Redeem", x = 773, y = 91, w = 240, h = 76, grad = G.Green, stud = false, b = 4, r = 8, sh = 5, hi = 5, lo = 7, text = "Redeem", ts = 34, stroke = 7, hitY = 23, z = 2 })
	self.CodeMsg = Html.label(codes, { text = "", ts = 26, stroke = 5, x = 27, y = 185, w = 986, h = 32, ax = "Left", z = 2 })
	self.CodeHint = Html.label(codes, { text = "", ts = 18, font = "Medium", color = C.Muted2, x = 27, y = 235, w = 986, h = 22, ax = "Left", z = 2 })
	box:GetPropertyChangedSignal("Text"):Connect(function()
		local u = string.upper(box.Text)
		if u ~= box.Text then
			box.Text = u
		end
	end)
	local function submit()
		if self._state ~= "checking" and box.Text:gsub("%s", "") ~= "" then
			self.RedeemRequested:Fire(box.Text)
		end
	end
	redeem.Activated:Connect(submit)
	box.FocusLost:Connect(function(enter)
		if enter then
			submit()
		end
	end)
	jump.Activated:Connect(function()
		local y = codes.AbsolutePosition.Y - scroll.AbsolutePosition.Y
		local sc = stage:FindFirstChildOfClass("UIScale")
		y = y / (sc and sc.Scale or 1) * (sc and sc.Scale or 1) + scroll.CanvasPosition.Y - 24
		TweenService:Create(scroll, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { CanvasPosition = V2(0, math.max(0, y)) }):Play()
	end)

	function self:SetCodeState(st)
		self._state = st
		local m = CODE_MSG[st] or CODE_MSG.idle
		self.CodeMsg.Text, self.CodeMsg.TextColor3 = m[1], m[2]
		if self._boxStroke then
			self._boxStroke.Color = if st == "invalid" then C.Danger elseif st == "ok" then C.Cash else INK
		end
		redeem:SetText(if st == "checking" then "…" else "Redeem")
		redeem:SetGrad(if st == "checking" then G.Grey else G.Green)
		if st == "invalid" then
			Motion.shake(box, 10)
		end
	end
	self:SetCodeState("idle")
	-- Codes are structure only in this prototype: no input, no request, no reward.
	function self:SetCodesEnabled(on)
		box.TextEditable, box.Active = on, on
		box.PlaceholderText = if on then "ENTER CODE…" else "CODES UNAVAILABLE"
		redeem:SetEnabled(on)
		redeem:SetGrad(if on then G.Green else G.Grey)
		if not on then
			self._state = "checking"
			self.CodeMsg.Text, self.CodeMsg.TextColor3 = "Codes are not active yet. No rewards available.", C.Muted
		end
	end

	-- Product detail overlay: 560px wide at top:180
	local dlg = Html.make("Frame", self.Root, { Name = "ProductDialog", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10 })
	local dimBtn = Html.box(dlg, { class = "TextButton", name = "Dim", pos = UDim2.fromOffset(6, 114), size = UDim2.new(1, -12, 1, -120), bg = "0a0c10", alpha = 0.5 })
	dimBtn.Text = ""
	dimBtn.AutoButtonColor = false
	local card = Html.make("Frame", dlg, { Name = "Card", AnchorPoint = V2(0.5, 0), Position = UDim2.fromOffset(550, 186), Size = UDim2.fromOffset(560, 420) })
	local cardScale = Html.make("UIScale", card)
	Html.box(card, { name = "Shadow", y = 8, size = UDim2.fromScale(1, 1), bg = INK, r = 10, z = 0 })
	local face = Html.box(card, { name = "Face", size = UDim2.fromScale(1, 1), grad = { "5cb8ff", "2f86e8" }, r = 10, z = 1 })
	Html.box(face, { name = "Border", size = UDim2.fromScale(1, 1), r = 10, b = 5, z = 5 })
	self._dlgFace = face
	self._prodName = Html.label(face, { text = "", ts = 46, stroke = 9, x = 31, y = 31, w = 498, h = 56, z = 2 })
	self._owned = Html.label(face, { text = "", ts = 24, color = C.Gold, stroke = 5, x = 31, y = 99, w = 498, h = 30, z = 2 })
	self._desc = Html.label(face, { text = "", ts = 24, font = "Body", x = 31, y = 141, w = 498, h = 90, wrap = true, z = 2 })
	self._buy = Html.plate(face, { x = 31, y = 243, w = 498, h = 84, grad = G.Green, stud = false, b = 5, r = 9, sh = 5, hi = 5, lo = 8, shine = { 56, 3, 0.5 }, text = "Buy", ts = 38, stroke = 8, press = 5, hitY = 19, z = 3 })
	local noteBox = Html.box(face, { name = "Note", pos = UDim2.fromOffset(280, 344), anchor = V2(0.5, 0), w = 0, h = 26, auto = "X", bg = "ffffff", alpha = 0.8, r = 8, z = 2 })
	Html.make("UIPadding", noteBox, { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
	self._note = Html.label(noteBox, { text = "", ts = 18, color = INK, size = UDim2.new(0, 0, 1, 0), auto = "X" })
	self._noteBox = noteBox
	local dlgClose = Html.closeX(face, { x = 488, y = 12, w = 60, hi = 0, lo = 0, ts = 36, stroke = 6, z = 4 })
	local function closeDlg()
		dlg.Visible = false
	end
	dlgClose.Activated:Connect(closeDlg)
	dimBtn.Activated:Connect(closeDlg)
	self._buy.Activated:Connect(function()
		if self._cur then
			self.BuyRequested:Fire(self._cur)
		end
		closeDlg()
	end)

	local bobs = {}
	function self:SetProducts(list)
		for _, b in bobs do
			b:Cancel()
		end
		table.clear(bobs)
		for _, c in grid:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for i, p in list do
			local x = (i - 1) * (335 + 18)
			local f = Html.make("Frame", grid, { Name = "Product" .. i, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(335, 300) })
			local sc = Html.make("UIScale", f)
			Html.box(f, { name = "Shadow", y = 5, w = 335, h = 300, bg = INK, r = 9, z = 0 })
			local face2 = Html.box(f, { name = "Face", w = 335, h = 300, grad = { p.c1, p.c2 }, r = 9, z = 1 })
			Html.box(face2, { name = "Border", w = 335, h = 300, r = 9, b = 5, z = 5 })
			Html.label(face2, { text = p.name, ts = 32, stroke = 7, x = 0, y = 19, w = 335, h = 39, z = 2 })
			if p.icon then
				local ic = Html.icon(face2, p.icon, { x = 101, y = 63, w = 132, h = 132, z = 2 })
				local bob = Html.bob(ic, 2.4)
				if bob then
					table.insert(bobs, bob)
				end
			else
				local a = Html.box(face2, { name = "Art", x = 107, y = 66, w = 120, h = 114, r = 20, bg = "ffffff", alpha = 0, z = 2 })
				Html.make("UIStroke", a, { Thickness = 4, Color = INK, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, BorderStrokePosition = Enum.BorderStrokePosition.Inner })
				Html.label(a, { text = "arte", ts = 18, font = "Body", color = INK })
			end
			Html.label(face2, { text = p.sub or "", ts = 20, stroke = 5, x = 0, y = if p.icon then 206 else 188, w = 335, h = 24, z = 2 })
			local plateH = if p.icon then 42 else 59
			local pr = Html.plate(face2, { name = "Price", x = 19, y = 279 - plateH, w = 297, h = plateH, grad = if p.enabled then G.Green else G.Grey, stud = false, b = 4, r = 8, sh = 4, hi = 4, lo = 0, text = p.price, ts = 28, stroke = 6, press = 0, hit = 1, z = 2 })
			pr.Hit.Visible = false
			if p.flagText then
				local tag = Html.box(face2, { name = "Flag", pos = UDim2.fromOffset(323, 57), anchor = V2(1, 0), w = 0, h = 28, auto = "X", bg = "ffffff", r = 8, b = 3, rot = 6, z = 3 })
				Html.make("UIPadding", tag, { PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11) })
				Html.label(tag, { text = p.flagText, ts = 15, color = INK, size = UDim2.new(0, 0, 1, 0), auto = "X" })
			end
			local hit = Html.make("TextButton", f, { Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = 5, Visible = p.placeholder ~= true })
			hit.Activated:Connect(function()
				self._cur = p.id
				self._buy:SetEnabled(p.enabled == true)
				self._buy:SetGrad(if p.enabled then G.Green else G.Grey)
				self._buy:SetText(p.buyLabel or "Buy")
				self._prodName.Text = p.name
				Html.grad(face, p.c1, p.c2)
				self._owned.Text, self._desc.Text, self._note.Text = p.owned or "", p.desc or "", p.note or ""
				self._noteBox.Visible = (p.note or "") ~= ""
				dlg.Visible = true
				Html.popIn(card, cardScale, nil, 0.4)
			end)
			if self._animate and not Motion.Reduced then
				sc.Scale = 0.94
				Motion.tween(sc, 0.4, { Scale = 1 }, "Quad", (i - 1) * 0.06)
			end
		end
		self._animate = false
	end
	return self
end

return ShopPanel
