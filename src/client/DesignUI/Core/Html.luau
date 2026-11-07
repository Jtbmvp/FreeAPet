-- Html: primitives that reproduce the CSS of "FreeAPet HUD (offline).html" in its own units
-- (1920x1080 canvas under one UIScale). Sizes passed here are the CSS values, unchanged.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Core = script.Parent
local Theme = require(Core.Theme)
local Motion = require(Core.Motion)
local Signal = require(Core.Signal)
local Icons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("HudImages"))

local Html = { Icons = Icons }

local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local INK, INK2 = Color3.fromHex("15171c"), Color3.fromHex("0d1119")
Html.INK, Html.INK2 = INK, INK2
-- Panel glass: the HTML's rgba(0,0,0,.55) over its dark blurred world reads as this colour.
-- Using it directly keeps panels equally dark over the game's bright world.
Html.GLASS = Color3.fromHex("16181d")
Html.GLASS_ALPHA = 0.92

-- CSS font-size -> TextSize. Measured against the HTML's text widths in Studio:
-- Montserrat needs the line-height factor; Fredoka One is narrower than Fredoka 700.
local FACTOR = { Title = 1.215, Bold = 1.2, Body = 1.215, Medium = 1.215, Num = 1.12 }
local FONT_FAMILY_NUM = "rbxasset://fonts/families/FredokaOne.json"
Html.NUM_FAMILY = FONT_FAMILY_NUM

local function color(c)
	return if typeof(c) == "string" then Color3.fromHex(c) else c
end
Html.color = color

function Html.make(class, parent, props)
	local i = Instance.new(class)
	if i:IsA("GuiObject") then
		i.BorderSizePixel = 0
		i.BackgroundTransparency = 1
	end
	if props then
		for k, v in pairs(props) do
			i[k] = v
		end
	end
	i.Parent = parent
	return i
end
local make = Html.make

local function place(i, o)
	if o.pos then
		i.Position = o.pos
	elseif o.x or o.y then
		i.Position = UDim2.fromOffset(o.x or 0, o.y or 0)
	end
	if o.size then
		i.Size = o.size
	elseif o.w or o.h then
		i.Size = UDim2.fromOffset(o.w or 0, o.h or 0)
	end
	if o.anchor then
		i.AnchorPoint = o.anchor
	end
	if o.z then
		i.ZIndex = o.z
	end
	if o.order then
		i.LayoutOrder = o.order
	end
	if o.name then
		i.Name = o.name
	end
	if o.visible ~= nil then
		i.Visible = o.visible
	end
	if o.auto then
		i.AutomaticSize = Enum.AutomaticSize[o.auto]
	end
	if o.rot then
		i.Rotation = o.rot
	end
end

function Html.corner(i, r)
	if r and r ~= 0 then
		local c = Instance.new("UICorner")
		c.CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, r)
		c.Parent = i
		return c
	end
end

function Html.border(i, width, c)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.BorderStrokePosition = Enum.BorderStrokePosition.Inner
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Thickness = width
	s.Color = color(c or INK)
	s.Parent = i
	return s
end

function Html.grad(i, c1, c2, rot)
	local g = i:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	g.Color = ColorSequence.new(color(c1), color(c2))
	g.Rotation = rot or 90
	g.Parent = i
	i.BackgroundColor3 = WHITE
	i.BackgroundTransparency = 0
	return g
end

-- box: div with bg/gradient, radius and an inner border (CSS box-sizing: border-box).
function Html.box(parent, o)
	local f = make(o.class or "Frame", parent)
	place(f, o)
	if o.bg then
		f.BackgroundColor3 = color(o.bg)
		f.BackgroundTransparency = 1 - (o.alpha or 1)
	end
	if o.grad then
		Html.grad(f, o.grad[1], o.grad[2], o.grad[3])
	end
	if o.r then
		Html.corner(f, o.r)
	end
	if o.b then
		Html.border(f, o.b, o.bc)
	end
	if o.clip then
		f.ClipsDescendants = true
	end
	return f
end

-- label: o.text, o.ts (CSS font-size), o.font, o.color, o.stroke (CSS -webkit-text-stroke width).
function Html.label(parent, o)
	local fontName = o.font or "Title"
	local ts = (o.ts or 20) * (FACTOR[fontName] or 1.215)
	local fit = 1
	if ts > 100 then
		fit = ts / 100 -- TextSize caps at 100: larger text scales with a UIScale
		ts = 100
	end
	local t = make("TextLabel", parent, {
		Name = o.name or "Label",
		Text = o.text or "",
		FontFace = Theme.Fonts[fontName],
		TextSize = math.round(ts),
		TextColor3 = color(o.color or WHITE),
		TextXAlignment = Enum.TextXAlignment[o.ax or "Center"],
		TextYAlignment = Enum.TextYAlignment[o.ay or "Center"],
		TextWrapped = o.wrap or false,
		RichText = o.rich or false,
		Size = if o.auto then UDim2.new() else UDim2.fromScale(1, 1),
	})
	if o.lineHeight then
		t.LineHeight = o.lineHeight
	end
	place(t, { pos = o.pos, x = o.x, y = o.y, w = o.w, h = o.h, size = o.size, anchor = o.anchor, z = o.z, order = o.order, visible = o.visible, auto = o.auto, rot = o.rot })
	if fit > 1 then
		local sc = Instance.new("UIScale")
		sc.Scale = fit
		sc.Parent = t
		if o.w or o.h then
			t.Size = UDim2.fromOffset((o.w or 0) / fit, (o.h or 0) / fit)
		end
	end
	if o.stroke then
		local s = Instance.new("UIStroke")
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.Thickness = o.stroke / 2 / fit
		s.Color = color(o.strokeColor or INK)
		s.Parent = t
	end
	return t
end

function Html.icon(parent, key, o)
	local i = make("ImageLabel", parent, { Name = "Icon", Image = Icons[key] or "", ScaleType = Enum.ScaleType.Fit })
	place(i, o)
	return i
end

function Html.studs(parent, r)
	local s = make("ImageLabel", parent, {
		Name = "Studs",
		Image = Icons.stud,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(40, 40),
		Size = UDim2.fromScale(1, 1),
	})
	Html.corner(s, r)
	return s
end

-- gloss: the design's linear-gradient(110deg, transparent a, white b, transparent c, white d).
function Html.gloss(parent, w, h, stops, alpha, r)
	alpha = alpha or stops[5] or 0.3
	local L = w * 0.9397 + h * 0.342
	local e = 0.0005
	local t = 1 - alpha
	local a, b, c, d = stops[1] / L, stops[2] / L, stops[3] / L, math.min(stops[4] / L, 0.99)
	local f = make("Frame", parent, {
		Name = "Gloss",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
	})
	Html.corner(f, r)
	local g = Instance.new("UIGradient")
	g.Rotation = 20
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(a - e, 1),
		NumberSequenceKeypoint.new(a, t),
		NumberSequenceKeypoint.new(b, t),
		NumberSequenceKeypoint.new(b + e, 1),
		NumberSequenceKeypoint.new(c - e, 1),
		NumberSequenceKeypoint.new(c, t),
		NumberSequenceKeypoint.new(d, t),
		NumberSequenceKeypoint.new(d + e, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	return f
end

-- shine: @keyframes shine, translateX(-160%) -> translateX(520%) during 45% of the period.
-- travel: how far right the bar must go to leave the host (defaults to the HTML's 520%).
function Html.shine(host, width, period, alpha, delay, travel)
	if Motion.Reduced then
		return nil
	end
	local finish = math.max(5.2 * width, travel or 0)
	local bar = make("Frame", host, {
		Name = "Shine",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.new(0, width, 1.4, 0),
		Position = UDim2.new(0, -1.6 * width, 0.5, 0),
		Rotation = 22,
		ZIndex = 8,
	})
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 1 - alpha),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = bar
	task.spawn(function()
		task.wait(delay or 0)
		while bar.Parent do
			bar.Position = UDim2.new(0, -1.6 * width, 0.5, 0)
			local tw = TweenService:Create(
				bar,
				TweenInfo.new(period * 0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Position = UDim2.new(0, finish, 0.5, 0) }
			)
			tw:Play()
			tw.Completed:Wait()
			task.wait(period * 0.55)
		end
	end)
	return bar
end

-- plate: the design's 3D button. o: w, h, grad, b, bc, r, sh (outer shadow), shc, sha, hi, hia, lo, loa,
-- stud (default true), gloss = {a,b,c,d,alpha}, shine = {width,period,alpha,delay}, text, ts, stroke, font,
-- press (px), pressScale, hit (min tap size in canvas units), hitX/hitY overrides.
-- Every plate carries the Shop's gloss and shine by default; pass false to opt out.
function Html.plate(parent, o)
	local w, h = o.w, o.h
	local b, r = o.b or 4, o.r or 8
	local sh = if o.sh == nil then 5 else o.sh
	local root = make("Frame", parent, { Name = o.name or "Plate", Size = UDim2.fromOffset(w, h) })
	place(root, { pos = o.pos, x = o.x, y = o.y, anchor = o.anchor, z = o.z, order = o.order })
	local body = make("Frame", root, {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	})
	local pressScale = make("UIScale", body)
	if sh > 0 then
		Html.box(body, { name = "Shadow", y = sh, w = w, h = h, bg = o.shc or INK, alpha = o.sha or 1, r = r, z = 0 })
	end
	local c1, c2 = (o.grad or Theme.Grad.Green)[1], (o.grad or Theme.Grad.Green)[2]
	local face = Html.box(body, { name = "Face", w = w, h = h, grad = { c1, c2 }, r = r, z = 1 })
	local ir = math.max(r - b, 0)
	local clip = make("Frame", face, {
		Name = "Clip",
		Position = UDim2.fromOffset(b, b),
		Size = UDim2.new(1, -2 * b, 1, -2 * b),
		ClipsDescendants = true,
		ZIndex = 1,
	})
	if o.stud ~= false then
		Html.studs(clip, ir)
	end
	local innerW, innerH = w - 2 * b, h - 2 * b
	local glossStops = o.gloss
	if glossStops == nil then
		-- The Shop's stripes (22, 40, 50, 60 on its 96px face), kept proportional to the height.
		glossStops = { innerH * 0.23, innerH * 0.42, innerH * 0.52, innerH * 0.63, 0.3 }
	end
	if glossStops then
		Html.gloss(clip, innerW, innerH, glossStops, glossStops[5] or 0.3, ir).ZIndex = 2
	end
	if o.hi ~= 0 then
		Html.box(clip, {
			name = "Hi",
			w = w - 2 * b,
			h = o.hi or 5,
			bg = WHITE,
			alpha = o.hia or 0.35,
			z = 3,
		})
	end
	if o.lo ~= 0 then
		local lo = o.lo or 7
		Html.box(clip, {
			name = "Lo",
			pos = UDim2.new(0, 0, 1, -lo),
			w = w - 2 * b,
			h = lo,
			bg = BLACK,
			alpha = o.loa or 0.2,
			z = 3,
		})
	end
	local shineSpec = o.shine
	if shineSpec == nil then
		-- The Shop's sweep: a bar half as wide as the face, every 4.2 s, out of phase between buttons.
		shineSpec = { math.max(innerH * 0.5, 20), 4.2, 0.5 }
	end
	local shineBar = nil
	if shineSpec then
		shineBar = Html.shine(clip, shineSpec[1], shineSpec[2], shineSpec[3], shineSpec[4] or math.random() * shineSpec[2], innerW + shineSpec[1])
	end
	Html.box(face, { name = "Border", w = w, h = h, r = r, b = b, bc = o.bc or INK, z = 5 })
	local content = make("Frame", face, { Name = "Content", Size = UDim2.fromScale(1, 1), ZIndex = 6 })
	local label
	if o.text then
		label = Html.label(content, {
			text = o.text,
			ts = o.ts or 30,
			stroke = o.stroke,
			font = o.font,
			strokeColor = o.strokeColor,
			name = "Text",
		})
	end
	local dim = Html.box(face, {
		name = "Dim",
		w = w,
		h = h,
		r = r,
		bg = BLACK,
		alpha = 0,
		z = 7,
	})
	local tap = o.hit or 122
	local padX = o.hitX or math.max(0, (tap - w) / 2)
	local padY = o.hitY or math.max(0, (tap - h) / 2)
	local hit = make("TextButton", root, {
		Name = "Hit",
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromOffset(-padX, -padY),
		Size = UDim2.new(1, 2 * padX, 1, 2 * padY),
		ZIndex = 20,
	})
	local self = {
		Root = root,
		Body = body,
		Face = face,
		Content = content,
		Label = label,
		Hit = hit,
		Clip = clip,
		Activated = Signal.new(),
		Enabled = true,
	}
	local pressPx, pressTo = o.press or 4, o.pressScale or 1
	local function up()
		Motion.tween(body, 0.12, { Position = UDim2.fromScale(0.5, 0.5) })
		Motion.tween(pressScale, 0.12, { Scale = 1 })
	end
	hit.InputBegan:Connect(function(i)
		local t = i.UserInputType
		if self.Enabled and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) then
			Motion.tween(body, 0.12, { Position = UDim2.new(0.5, 0, 0.5, pressPx) })
			Motion.tween(pressScale, 0.12, { Scale = pressTo })
		end
	end)
	hit.InputEnded:Connect(up)
	hit.MouseEnter:Connect(function()
		if self.Enabled then
			Motion.tween(pressScale, 0.14, { Scale = 1.04 }, "Back")
		end
	end)
	hit.MouseLeave:Connect(up)
	hit.Activated:Connect(function()
		if self.Enabled then
			self.Activated:Fire()
		end
	end)
	function self:SetText(text)
		if label then
			label.Text = text
		end
	end
	function self:SetGrad(pair)
		Html.grad(face, pair[1], pair[2])
	end
	function self:SetEnabled(on)
		self.Enabled = on
		-- A button that can't be pressed doesn't invite a press.
		if shineBar then
			shineBar.Visible = on
		end
	end
	function self:SetOpacity(op)
		dim.BackgroundTransparency = op
	end
	function self:SetVisible(v)
		root.Visible = v
	end
	return self
end

-- closeX: red text-X button from the panel headers.
function Html.closeX(parent, o)
	return Html.plate(parent, {
		name = "Close",
		x = o.x,
		y = o.y,
		w = o.w or 82,
		h = o.h or o.w or 82,
		grad = o.grad or { "f0625c", "cf3934" },
		b = 5,
		r = o.r or 8,
		sh = 0,
		stud = false,
		hi = o.hi or 5,
		lo = o.lo or 6,
		text = "X",
		ts = o.ts or 52,
		stroke = o.stroke or 8,
		font = o.font,
		press = 0,
		pressScale = 0.9,
		z = o.z or 3,
	})
end

-- bar: track with an inner border and a highlighted fill.
function Html.bar(parent, o)
	local b = o.b or 3
	local track = Html.box(parent, {
		name = o.name or "Bar",
		x = o.x,
		y = o.y,
		w = o.w,
		h = o.h,
		pos = o.pos,
		size = o.size,
		bg = o.bg or "26272b",
		r = o.r or 8,
		b = b,
		bc = o.bc or INK,
		order = o.order,
	})
	local inner = make("Frame", track, {
		Name = "Inner",
		Position = UDim2.fromOffset(b, b),
		Size = UDim2.new(1, -2 * b, 1, -2 * b),
		ClipsDescendants = true,
	})
	local fill = Html.box(inner, { name = "Fill", size = UDim2.fromScale(o.pct or 0, 1), grad = o.grad })
	if o.hi ~= 0 then
		Html.box(fill, { name = "Hi", size = UDim2.new(1, 0, 0, o.hi or 4), bg = WHITE, alpha = 0.35 })
	end
	local self = { Root = track, Fill = fill }
	function self:SetPct(p, t)
		p = math.clamp(p, 0, 1)
		if t and t > 0 then
			Motion.tween(fill, t, { Size = UDim2.fromScale(p, 1) }, "Out")
		else
			fill.Size = UDim2.fromScale(p, 1)
		end
	end
	return self
end

-- bob: @keyframes bob (translateY 0 -> -9px -> 0).
function Html.bob(gui, period, amount)
	local p = gui.Position
	return Motion.loop(gui, { Position = p + UDim2.fromOffset(0, -(amount or 9)) }, period / 2)
end

-- popIn: @keyframes popIn with the opacity carried by a temporary canvas-sized CanvasGroup.
function Html.popIn(root, sc, host, dur, from)
	dur = dur or 0.45
	if Motion.Reduced then
		sc.Scale = 1
		return
	end
	local stage = root.Parent
	sc.Scale = from or 0.6
	if host then
		host.GroupTransparency = 1
		host.Visible = true
		root.Parent = host
		Motion.tween(host, dur * 0.55, { GroupTransparency = 0 }, "Quad").Completed:Once(function()
			root.Parent = stage
			host.Visible = false
		end)
	end
	Motion.tween(sc, dur * 0.55, { Scale = 1.035 }, "Quad").Completed:Once(function()
		Motion.tween(sc, dur * 0.23, { Scale = 0.99 }, "QuadIO").Completed:Once(function()
			Motion.tween(sc, dur * 0.22, { Scale = 1 }, "QuadIO")
		end)
	end)
end

-- panel: the design's window. o: name, x, y, w, h (nil = auto height), grad, icon, gap, title, titleFont,
-- anchor ("center" default | "topright"). Fields: Root, Group, Header, Body, Left, Title, CloseRequested.
function Html.panel(parent, o)
	local w, h = o.w, o.h
	local self = { CloseRequested = Signal.new(), Opened = Signal.new() }
	local topRight = o.origin == "topright"
	local root = make("Frame", parent, {
		Name = o.name,
		AnchorPoint = if topRight then Vector2.new(1, 0) else Vector2.new(0.5, 0.5),
		Position = if topRight
			then UDim2.fromOffset(o.x + w, o.y)
			else UDim2.fromOffset(o.x + w / 2, o.y + h / 2),
		Size = UDim2.fromOffset(w, h),
		Visible = false,
		ZIndex = o.z or Theme.Z.Panel,
	})
	local sc = make("UIScale", root)
	local host = make("CanvasGroup", parent, {
		Name = o.name .. "Fade",
		Size = UDim2.fromOffset(1920, 1080),
		ZIndex = o.z or Theme.Z.Panel,
		Visible = false,
	})
	if o.shadow ~= false then
		self.Shadow = Html.box(root, {
			name = "Shadow",
			y = 10,
			size = UDim2.fromScale(1, 1),
			bg = INK,
			alpha = 0.6,
			r = 8,
			z = 0,
		})
	end
	local group = Html.box(root, {
		name = "Group",
		size = UDim2.fromScale(1, 1),
		bg = Html.GLASS,
		alpha = Html.GLASS_ALPHA,
		r = 8,
		z = 1,
	})
	Html.box(group, { name = "Border", size = UDim2.fromScale(1, 1), r = 8, b = 6, bc = INK2, z = 8 })
	local header = Html.box(group, {
		name = "Header",
		x = 6,
		y = 6,
		size = UDim2.new(1, -12, 0, 108),
		grad = o.grad,
		z = 2,
	})
	Html.studs(header)
	Html.box(header, { name = "Line", pos = UDim2.new(0, 0, 1, -6), size = UDim2.new(1, 0, 0, 6), bg = INK2 })
	local left = make("Frame", header, {
		Name = "Left",
		Position = UDim2.fromOffset(230, 0),
		Size = UDim2.new(1, -230, 1, -6),
		ZIndex = 2,
	})
	local list = make("UIListLayout", left, {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, o.gap or 18),
	})
	self.List = list
	self.Title = Html.label(left, {
		name = "Title",
		text = o.title or "",
		ts = 68,
		font = o.titleFont or "Num",
		stroke = 11,
		strokeColor = INK2,
		auto = "XY",
		ax = "Left",
		order = 0,
	})
	local body = make("Frame", group, {
		Name = "Body",
		Position = UDim2.fromOffset(6, 114),
		Size = UDim2.new(1, -12, 1, -120),
		ZIndex = 3,
	})
	if o.icon then
		Html.icon(root, o.icon, {
			name = "BigIcon",
			-- The HTML's 270px icons carry about 15% margin; the game's icons fill their image,
			-- so 230px keeps the same centre and visual size without covering the first card.
			x = (o.iconAt and o.iconAt[1] or -54) + 6,
			y = (o.iconAt and o.iconAt[2] or -72) + 2,
			w = 216,
			h = 216,
			rot = -14,
			z = 5,
		})
	end
	self.Root, self.Group, self.Header, self.Body, self.Left, self.Scale = root, group, header, body, left, sc
	function self:Open()
		root.Visible = true
		Html.popIn(root, sc, host, o.popDur or 0.45)
		self.Opened:Fire()
	end
	function self:Close()
		root.Visible = false
	end
	return self
end

return Html
