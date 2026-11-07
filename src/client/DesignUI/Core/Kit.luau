-- Kit: construtores de widgets com o estilo FreeAPet (contornos, studs, gradientes, sombra 3D).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Core = script.Parent
local Theme = require(Core.Theme)
local Motion = require(Core.Motion)
local Signal = require(Core.Signal)
local Html = require(Core.Html)
local Icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("HudImages"))

local C, Fonts = Theme.Colors, Theme.Fonts
local WHITE, BLACK, ZERO = Color3.new(1, 1, 1), Color3.new(0, 0, 0), Vector2.new(0, 0)
local Kit = { Icons = Icons }

local GUI = { Frame = true, CanvasGroup = true, ScrollingFrame = true, TextLabel = true, TextButton = true, ImageLabel = true, TextBox = true }
local DEFAULTS = {
	Frame = { BackgroundTransparency = 1 },
	CanvasGroup = { BackgroundTransparency = 1 },
	ScrollingFrame = { BackgroundTransparency = 1, ScrollBarThickness = 4, ScrollBarImageColor3 = Color3.fromHex("8A8D93"), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y },
	TextLabel = { BackgroundTransparency = 1, Text = "" },
	TextButton = { BackgroundTransparency = 1, Text = "", AutoButtonColor = false },
	ImageLabel = { BackgroundTransparency = 1 },
	TextBox = { BackgroundTransparency = 1, Text = "", ClearTextOnFocus = false },
}

function Kit.make(class, parent, props)
	local i = Instance.new(class)
	if GUI[class] then i.BorderSizePixel = 0 end
	local d = DEFAULTS[class]
	if d then for k, v in pairs(d) do i[k] = v end end
	if props then for k, v in pairs(props) do i[k] = v end end
	i.Parent = parent
	return i
end

function Kit.corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = typeof(r) == "UDim" and r or UDim.new(0, r or 6)
	c.Parent = inst
	return c
end

function Kit.stroke(inst, color, thick, mode)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border
	s.Color = color or C.Outline
	s.Thickness = thick or 3
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = inst
	return s
end

-- Gradiente vertical (Rotation 90 = topo -> fundo). `pair` = {Color3, Color3}
function Kit.grad(inst, pair, rot)
	local g = inst:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	g.Color = ColorSequence.new(pair[1], pair[2])
	g.Rotation = rot or 90
	g.Parent = inst
	if inst:IsA("Frame") or inst:IsA("TextButton") or inst:IsA("CanvasGroup") then inst.BackgroundColor3 = WHITE end
	return g
end

function Kit.pad(inst, l, t, r, b)
	local p = Instance.new("UIPadding")
	p.PaddingLeft, p.PaddingTop, p.PaddingRight, p.PaddingBottom = UDim.new(0, l or 0), UDim.new(0, t or 0), UDim.new(0, r or 0), UDim.new(0, b or 0)
	p.Parent = inst
	return p
end

function Kit.list(inst, dir, gap, ha, va)
	local l = Instance.new("UIListLayout")
	l.FillDirection = dir == "H" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, gap or 0)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = Enum.HorizontalAlignment[ha or "Left"]
	l.VerticalAlignment = Enum.VerticalAlignment[va or "Top"]
	l.Parent = inst
	return l
end

function Kit.grid(inst, cell, gap, gapY)
	local g = Instance.new("UIGridLayout")
	g.CellSize = cell
	g.CellPadding = UDim2.fromOffset(gap or 0, gapY or gap or 0)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = inst
	return g
end

-- TextLabel com contorno (UIStroke Contextual, cor #0D1119).
-- o: Text, TS (tamanho), Color, Stroke (px, nil = sem), Font ("Title"/"Body"/"Label"), Size, Pos, Anchor,
--    X ("Left"/"Center"/"Right"), Y, Wrap, Auto ("X"/"Y"/"XY"), Order, Z, Rich, Name
function Kit.label(parent, o)
	local auto = o.Auto and Enum.AutomaticSize[o.Auto] or Enum.AutomaticSize.None
	local t = Kit.make("TextLabel", parent, {
		Name = o.Name or "Label", Text = o.Text or "", FontFace = Fonts[o.Font or "Title"], TextSize = o.TS or 16,
		TextColor3 = o.Color or WHITE, Size = o.Size or UDim2.fromScale(1, 1), Position = o.Pos or UDim2.new(),
		AnchorPoint = o.Anchor or ZERO, TextXAlignment = Enum.TextXAlignment[o.X or "Center"],
		TextYAlignment = Enum.TextYAlignment[o.Y or "Center"], TextWrapped = o.Wrap or false, AutomaticSize = auto,
		LayoutOrder = o.Order or 0, ZIndex = o.Z or 1, RichText = o.Rich or false,
	})
	if o.Stroke then Kit.stroke(t, o.StrokeColor or C.Outline, o.Stroke, Enum.ApplyStrokeMode.Contextual) end
	return t
end

function Kit.icon(parent, key, o)
	o = o or {}
	return Kit.make("ImageLabel", parent, {
		Name = o.Name or "Icon", Image = Icons[key] or "", ScaleType = Enum.ScaleType.Fit,
		Size = o.Size or UDim2.fromOffset(32, 32), Position = o.Pos or UDim2.new(), AnchorPoint = o.Anchor or ZERO,
		LayoutOrder = o.Order or 0, ZIndex = o.Z or 1, ImageTransparency = o.Transp or 0, Rotation = o.Rot or 0,
	})
end

function Kit.studs(parent, tile, radius)
	local s = Kit.make("ImageLabel", parent, {
		Name = "Studs", Size = UDim2.fromScale(1, 1), Image = Icons.stud, ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(tile or 24, tile or 24), ZIndex = 1,
	})
	if radius then Kit.corner(s, radius) end
	return s
end

-- Pressionar = UIScale encolhe (para botões sem sombra 3D)
function Kit.pressScale(hit, sc, to)
	hit.InputBegan:Connect(function(i)
		local t = i.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then Motion.tween(sc, 0.08, { Scale = to or 0.92 }) end
	end)
	local function up() Motion.tween(sc, 0.1, { Scale = 1 }) end
	hit.InputEnded:Connect(up)
	hit.MouseLeave:Connect(up)
end

-- Botão 3D: sombra, contorno, gradiente, studs, brilho, texto/ícone, press = desce `Shadow` px.
-- o: Size, Pos, Anchor, Grad, Radius, Border, Shadow, Studs, Tile, Text, TS, Stroke, Icon, IconSize, Gap, Shine (período), HitPad, Clip, Order, Z, Name
function Kit.button(parent, o)
	local sh = o.Shadow == nil and 3 or o.Shadow
	local bd = o.Border or 3
	local radius = o.Radius or 6
	local root = Kit.make("Frame", parent, {
		Name = o.Name or "Button", Size = o.Size or UDim2.fromOffset(100, 44), Position = o.Pos or UDim2.new(),
		AnchorPoint = o.Anchor or ZERO, LayoutOrder = o.Order or 0, ZIndex = o.Z or 1,
	})
	local shadow
	if sh > 0 then
		shadow = Kit.make("Frame", root, { Name = "Shadow", Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, sh + bd), BackgroundColor3 = C.Outline, BackgroundTransparency = 0 })
		Kit.corner(shadow, radius)
	end
	local face = Kit.make("Frame", root, { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0, ClipsDescendants = o.Clip ~= false })
	Kit.corner(face, radius)
	Kit.grad(face, o.Grad or Theme.Grad.Green)
	Kit.stroke(face, C.Outline, bd)
	if o.Studs ~= false then Kit.studs(face, o.Tile or 24, radius) end
	Kit.make("Frame", face, { Name = "Hi", Size = UDim2.new(1, 0, 0, o.Hi or 3), BackgroundColor3 = WHITE, BackgroundTransparency = 0.72 })
	Kit.make("Frame", face, { Name = "Lo", Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 1, -4), BackgroundColor3 = BLACK, BackgroundTransparency = 0.84 })
	-- The Shop's stripes; the sizes here are a 3:1 ratio because Kit buttons can be scale-sized.
	if o.Gloss ~= false then
		Html.gloss(face, 3, 1, { 0.23, 0.42, 0.52, 0.63 }, 0.3, radius)
	end
	local content = Kit.make("Frame", face, { Name = "Content", Size = UDim2.fromScale(1, 1) })
	Kit.list(content, "H", o.Gap or 6, "Center", "Center")
	local icon, label
	if o.Icon then
		local s = o.IconSize or 30
		icon = Kit.icon(content, o.Icon, { Size = UDim2.fromOffset(s, s), Order = 1 })
	end
	if o.Text then
		label = Kit.label(content, { Text = o.Text, TS = o.TS or 18, Stroke = o.Stroke or (o.TS or 18) * 0.13, Auto = "XY", Size = UDim2.new(), Order = 2, Font = o.Font })
	end
	local dim = Kit.make("Frame", face, { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 1, ZIndex = 4 })
	local hp = o.HitPad or 4
	local hit = Kit.make("TextButton", root, { Name = "Hit", Size = UDim2.new(1, hp * 2, 1, hp * 2), Position = UDim2.fromOffset(-hp, -hp), ZIndex = 10 })

	local self = { Root = root, Face = face, Shadow = shadow, Label = label, Icon = icon, Content = content, Hit = hit, Activated = Signal.new(), Enabled = true }
	local function down() if self.Enabled then Motion.tween(face, Theme.T.Press, { Position = UDim2.fromOffset(0, sh) }) end end
	local function up() Motion.tween(face, 0.1, { Position = UDim2.new() }) end
	hit.InputBegan:Connect(function(i)
		local t = i.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then down() end
	end)
	hit.InputEnded:Connect(up)
	hit.MouseLeave:Connect(up)
	hit.Activated:Connect(function() if self.Enabled then self.Activated:Fire() end end)

	function self:SetText(t) if label then label.Text = t end end
	function self:SetGrad(p) Kit.grad(face, p) end
	function self:SetIcon(k) if icon then icon.Image = Icons[k] or "" end end
	local shineBar = nil
	function self:SetEnabled(e)
		self.Enabled = e
		if shineBar then shineBar.Visible = e end
	end
	function self:SetOpacity(op) dim.BackgroundTransparency = 1 - (1 - op) * 0.7 end
	function self:SetVisible(v) root.Visible = v end
	if o.Shine ~= false then
		local period = o.Shine or 4.2
		shineBar = Motion.shine(face, period, o.ShineDelay or math.random() * period)
	end
	return self
end

-- Barra (HP, XP, progresso). o: Size, Pos, Anchor, Grad, Bg, Border, Radius, Pct, Order
function Kit.bar(parent, o)
	local root = Kit.make("Frame", parent, {
		Name = o.Name or "Bar", Size = o.Size, Position = o.Pos or UDim2.new(), AnchorPoint = o.Anchor or ZERO,
		BackgroundColor3 = o.Bg or C.Bar, BackgroundTransparency = 0, ClipsDescendants = true, LayoutOrder = o.Order or 0,
	})
	Kit.corner(root, o.Radius or 7)
	Kit.stroke(root, C.Outline, o.Border or 2)
	local fill = Kit.make("Frame", root, { Name = "Fill", Size = UDim2.fromScale(o.Pct or 0, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0 })
	Kit.corner(fill, o.Radius or 7)
	Kit.grad(fill, o.Grad or Theme.Grad.Xp)
	Kit.make("Frame", fill, { Name = "Hi", Size = UDim2.new(1, 0, 0.4, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 0.8 })
	local self = { Root = root, Fill = fill }
	function self:SetPct(p, t, ease)
		p = math.clamp(p, 0, 1)
		if t and t > 0 then Motion.tween(fill, t, { Size = UDim2.fromScale(p, 1) }, ease or "Out")
		else fill.Size = UDim2.fromScale(p, 1) end
	end
	function self:SetGrad(pr) Kit.grad(fill, pr) end
	return self
end

-- Chip "Lv N" dourado
function Kit.chip(parent, text, o)
	o = o or {}
	local f = Kit.make("Frame", parent, {
		Name = "Chip", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, o.H or 20),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0, LayoutOrder = o.Order or 0,
	})
	Kit.corner(f, o.Radius or 5)
	Kit.grad(f, o.Grad or Theme.Grad.Gold)
	Kit.stroke(f, C.Outline, o.Border or 2)
	Kit.pad(f, o.PadX or 6, 0, o.PadX or 6, 0)
	local l = Kit.label(f, { Text = text, TS = o.TS or 13, Color = o.Color or C.Outline, Size = UDim2.new(0, 0, 1, 0), Auto = "X", Stroke = o.Stroke, Font = o.Font })
	return f, l
end

-- Painel de ecrã inteiro (partilhado por Pets, Index, Shop, Trade, Settings...).
-- o: Name, Title, TitleSize, Grad, Icon, Z. Campos: Root, Group, Header, Body, Left, Right, Title, Close, CloseRequested
function Kit.panel(parent, o)
	local self = { Opened = Signal.new(), CloseRequested = Signal.new() }
	local root = Kit.make("Frame", parent, {
		Name = o.Name, Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Visible = false, ZIndex = o.Z or Theme.Z.Panel,
	})
	local sc = Instance.new("UIScale")
	sc.Parent = root
	local group = Kit.make("CanvasGroup", root, {
		Name = "Group", Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = BLACK, BackgroundTransparency = 0.45,
	})
	Kit.corner(group, 6)
	Kit.stroke(group, C.Outline, 4)
	local header = Kit.make("Frame", group, { Name = "Header", Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = WHITE, BackgroundTransparency = 0 })
	Kit.grad(header, o.Grad or Theme.Grad.Blue)
	Kit.studs(header, 24)
	Kit.make("Frame", header, { Name = "Line", Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 1, -4), BackgroundColor3 = C.Outline, BackgroundTransparency = 0 })
	local left = Kit.make("Frame", header, { Name = "Left", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 74, 0.5, -2), AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new() })
	Kit.list(left, "H", 8, "Left", "Center")
	local title = Kit.label(left, { Name = "Title", Text = o.Title or "", TS = o.TitleSize or 28, Stroke = 2.8, Auto = "XY", Size = UDim2.new(), Order = 0, Font = o.TitleFont })
	local right = Kit.make("Frame", header, { Name = "Right", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, -2), AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new() })
	Kit.list(right, "H", 8, "Right", "Center")
	local close = Kit.button(right, { Name = "Close", Size = UDim2.fromOffset(44, 44), Grad = Theme.Grad.Close, Radius = 4, Border = 3, Studs = false, Shadow = 0, Text = "X", TS = 26, Stroke = 2.6, Order = 99, HitPad = 0 })
	close.Activated:Connect(function() self.CloseRequested:Fire() end)
	local body = Kit.make("Frame", group, { Name = "Body", Size = UDim2.new(1, 0, 1, -52), Position = UDim2.fromOffset(0, 52) })
	if o.Icon then
		Kit.icon(root, o.Icon, { Name = "BigIcon", Size = UDim2.fromOffset(84, 84), Pos = UDim2.fromOffset(-2, -6), Rot = -14, Z = 5 })
	end
	self.Root, self.Group, self.Header, self.Body, self.Left, self.Right, self.Title, self.Close, self.Scale = root, group, header, body, left, right, title, close, sc
	function self:Open() root.Visible = true Motion.popIn(sc, group, Theme.T.Pop) self.Opened:Fire() end
	function self:Close() root.Visible = false end
	return self
end

-- Diálogo modal centrado. o: Name, Title, Grad, Width, Dismiss. Campos: Root, Body, Open, Close, Closed
function Kit.dialog(parent, o)
	local self = { Closed = Signal.new() }
	local root = Kit.make("Frame", parent, { Name = o.Name or "Dialog", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = Theme.Z.Modal })
	local dim = Kit.make("TextButton", root, { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("0A0C10"), BackgroundTransparency = 0.38 })
	local holder = Kit.make("Frame", root, { Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(o.Width or 340, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local sc = Instance.new("UIScale")
	sc.Parent = holder
	local card = Kit.make("CanvasGroup", holder, { Name = "Card", Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = BLACK, BackgroundTransparency = 0.25 })
	Kit.corner(card, 10)
	Kit.stroke(card, C.Outline, 4)
	Kit.list(card, "V", 0)
	local header = Kit.make("Frame", card, { Name = "Header", Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = WHITE, BackgroundTransparency = 0, LayoutOrder = 1 })
	Kit.grad(header, o.Grad or Theme.Grad.GreenB)
	Kit.studs(header, 24)
	local title = Kit.label(header, { Name = "Title", Text = o.Title or "", TS = 24, Stroke = 3 })
	local body = Kit.make("Frame", card, { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	Kit.pad(body, 14, 12, 14, 14)
	Kit.list(body, "V", 8, "Center")
	self.Root, self.Body, self.Title, self.Header = root, body, title, header
	function self:Open()
		root.Visible = true
		dim.BackgroundTransparency = 1
		Motion.tween(dim, 0.2, { BackgroundTransparency = 0.38 })
		Motion.popIn(sc, card, 0.35)
	end
	function self:Close() root.Visible = false end
	dim.Activated:Connect(function()
		if o.Dismiss ~= false then self:Close() self.Closed:Fire() end
	end)
	return self
end

return Kit
