-- Research: the HTML's "Research skill tree" (hex 210x242, step 216x188, default pan 250,110 zoom .74), animated.
-- SetState (partial): { cash, rate, nodes = { [slot] = {name, desc, level, max, cost, durationText, blocked} }, active = {id,left,total} | false }
-- Signals: ResearchRequested(slot), CloseRequested. A design slot with no server node stays "?".
-- All ambient motion runs from one frame loop that only exists while the screen is open.
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Html = require(Core.Html)
local Layout = require(Core.Layout)
local Motion = require(Core.Motion)
local Juice = require(Core.Juice)
local Signal = require(Core.Signal)
local Icons = Html.Icons

local C, G, hex = Theme.Colors, Theme.Grad, Theme.hex
local INK2 = Html.INK2
local V2 = Vector2.new

local HW, HH, SX, SY = 210, 242, 216, 188
local ZMIN, ZMAX = 0.5, 1.8
local PZ0 = { z = 0.74, x = 250, y = 110 }

-- Node scale spring: under-damped on purpose, so every change overshoots a little.
local SPRING_K, SPRING_C = 240, 19
local WAVE_EVERY, WAVE_SPEED, WAVE_WIDTH = 6.5, 1050, 170
local PARTICLES = 42
local FADE = 0.28

-- { row, u, id }: the design's honeycomb
local LAY = {
	{ 0, -1, "carry" }, { 0, 0, "bigger" }, { 0, 1, "offline" }, { 1, -1.5, "speed" }, { 1, -0.5, "accel" }, { 1, 0.5, "petxp" }, { 1, 1.5, "plxp" },
	{ 2, -1, "power" }, { 2, 0, "tough" }, { 2, 1, "capluck" }, { -1, -1.5, "dbl" }, { -1, -0.5, "bank" }, { -1, 0.5, "dream" }, { -1, 1.5, "auto" },
	{ 0, 2, "idle" }, { 1, -2.5, "sprint" }, { 1, 2.5, "mentor" }, { 2, -2, "crit" }, { 2, 2, "lucky" }, { 3, -1.5, "study" }, { 3, -0.5, "revive" },
	{ 3, 0.5, "fheal" }, { 3, 1.5, "radar" },
}
local ICO = {
	bigger = "bigger_income", offline = "offline_income", carry = "carry_capacity", speed = "movement_speed", accel = "accelerator", petxp = "star", plxp = "trophy",
	power = "sword", tough = "heal", capluck = "capsule", dbl = "carry_capacity", bank = "bigger_income", dream = "offline_income", auto = "cash", idle = "accelerator",
	sprint = "movement_speed", mentor = "pets", crit = "battle", lucky = "star", study = "research", revive = "heal", fheal = "heal", radar = "index",
}

local function money(n)
	return "$" .. tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end
local function clock(s)
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
local function centreOf(l)
	return 960 + l[2] * SX, 540 + (l[1] - 0.5) * SY
end

local ResearchTree = {}

function ResearchTree.new(stage)
	local self = { CloseRequested = Signal.new(), ResearchRequested = Signal.new(), UnlockRequested = Signal.new(), Nodes = {}, NoDim = true, NoBlur = true }
	local st = { cash = 0, rate = 0, nodes = {}, active = nil, selected = "bigger" }
	local stageScale = stage:FindFirstChildOfClass("UIScale")
	local over, overY = 0, 0
	local function sc()
		return stageScale and stageScale.Scale or 1
	end
	local function num(parent, o)
		o.font = "Num"
		o.strokeColor = o.strokeColor or INK2
		return Html.label(parent, o)
	end

	local root = Html.make("Frame", stage, { Name = "Research", Size = UDim2.fromOffset(1920, 1080), Visible = false, ZIndex = Theme.Z.Research })
	self.Root = root
	local host = Html.make("CanvasGroup", stage, { Name = "ResearchFade", Size = UDim2.fromOffset(1920, 1080), Visible = false, ZIndex = Theme.Z.Research })

	------------------------------------------------------------------ background
	local view = Html.box(root, { class = "TextButton", name = "View", x = -3000, y = -3000, w = 7920, h = 7080, bg = "08101c" })
	view.Text = ""
	view.AutoButtonColor = false
	view.ClipsDescendants = false
	-- Two slow lights instead of a static gradient: the room breathes.
	local auroraA = Juice.glow(view, { pos = UDim2.fromOffset(3920, 3470), w = 2600, h = 1900, color = "1c5a92", alpha = 0.75 })
	local auroraB = Juice.glow(view, { pos = UDim2.fromOffset(3920, 3550), w = 2000, h = 1500, color = "3f2a9c", alpha = 0.5 })
	local auroraC = Juice.glow(view, { pos = UDim2.fromOffset(3920, 3470), w = 1300, h = 1000, color = "2fc6f2", alpha = 0.22 })

	local particleLayer = Html.make("Frame", root, { Name = "Particles", Size = UDim2.fromOffset(1920, 1080), ZIndex = 2 })
	local particles = {}
	local PALETTE = { "7fe9ff", "ffffff", "9dff7a", "ffd23c", "c9a6ff" }
	for n = 1, PARTICLES do
		local bubble = n % 3 == 0
		local size = if bubble then math.random(14, 34) else math.random(14, 30)
		local img = Html.make("ImageLabel", particleLayer, {
			Name = "P",
			Image = if bubble then Icons.fx_ring else Icons.fx_sparkle,
			ImageColor3 = Html.color(PALETTE[(n % #PALETTE) + 1]),
			AnchorPoint = V2(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
		})
		particles[n] = {
			img = img,
			x = math.random() * 1920,
			y = math.random() * 1080,
			vy = if bubble then 26 + math.random() * 34 else 8 + math.random() * 16,
			sway = 10 + math.random() * 26,
			phase = math.random() * 6.28,
			rate = 0.5 + math.random() * 1.2,
			base = if bubble then 0.72 else 0.5,
			spin = if bubble then 0 else (math.random() - 0.5) * 60,
		}
	end

	local canvas = Html.make("Frame", root, { Name = "Canvas", Size = UDim2.new(), ZIndex = 3 })
	local scaler = Html.make("Frame", canvas, { Name = "Scaler", Size = UDim2.new() })
	local zoomSc = Html.make("UIScale", scaler)

	-- The board the nodes sit on: the same lattice as the nodes, plus a band of light that crosses it.
	local LATTICE_POS, LATTICE_SIZE = UDim2.fromOffset(960 - SX * 20, 446 - SY * 2 * 10), UDim2.fromOffset(SX * 40, SY * 2 * 20)
	Html.make("ImageLabel", scaler, {
		Name = "Lattice",
		Image = Icons.hex_lattice,
		ImageColor3 = hex("4ec3ff"),
		ImageTransparency = 0.84,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(SX, SY * 2),
		Position = LATTICE_POS,
		Size = LATTICE_SIZE,
	})
	local sweep = Html.make("ImageLabel", scaler, {
		Name = "LatticeSweep",
		Image = Icons.hex_lattice,
		ImageColor3 = hex("9ff2ff"),
		ImageTransparency = 0.2,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(SX, SY * 2),
		Position = LATTICE_POS,
		Size = LATTICE_SIZE,
	})
	local sweepGrad = Html.make("UIGradient", sweep, {
		Rotation = 25,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.46, 1),
			NumberSequenceKeypoint.new(0.5, 0.15),
			NumberSequenceKeypoint.new(0.54, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	------------------------------------------------------------------- pan & zoom
	local pan, zoom = V2(PZ0.x, PZ0.y), PZ0.z
	local zoomGoal = zoom
	local panVel = V2()
	local zoomLabel, zoomLabelScale
	local function apply()
		canvas.Position = UDim2.fromOffset(pan.X, pan.Y)
		zoomSc.Scale = zoom
		local text = math.floor(zoom * 100 + 0.5) .. "%"
		if zoomLabel.Text ~= text then
			zoomLabel.Text = text
		end
	end
	local function setZoom(z2)
		zoomGoal = math.clamp(z2, ZMIN, ZMAX)
		if Motion.Reduced then
			local c, k = V2(960, 540), zoomGoal / zoom
			pan, zoom = c - (c - pan) * k, zoomGoal
			apply()
		else
			Motion.bump(zoomLabelScale, 1.25, 0.25)
		end
	end
	local panGoal = nil
	local function resetView()
		zoomGoal, panGoal = PZ0.z, V2(PZ0.x, PZ0.y)
		panVel = V2()
	end

	local tracked, startPan, acc = nil, V2(), V2()
	local lastAt = 0
	local function beginPan(input)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
			return
		end
		tracked, startPan, acc, self._dragged = input, pan, V2(), false
		panGoal, panVel = nil, V2()
		lastAt = os.clock()
	end
	view.InputBegan:Connect(beginPan)
	UIS.InputChanged:Connect(function(input)
		if not root.Visible then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			setZoom(zoomGoal * (if input.Position.Z > 0 then 1.12 else 1 / 1.12))
		elseif
			tracked
			and (input == tracked or (tracked.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement))
		then
			acc += V2(input.Delta.X, input.Delta.Y)
			if acc.Magnitude > 6 then
				self._dragged = true
			end
			if self._dragged then
				local now = os.clock()
				local step = V2(input.Delta.X, input.Delta.Y) / sc()
				if now > lastAt then
					panVel = panVel:Lerp(step / math.max(now - lastAt, 1 / 120), 0.35)
				end
				lastAt = now
				pan = startPan + acc / sc()
				apply()
			end
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input == tracked then
			tracked = nil
			-- A flick keeps gliding; a still mouse at release stops dead.
			if os.clock() - lastAt > 0.06 or Motion.Reduced then
				panVel = V2()
			end
		end
	end)
	local base = zoom
	UIS.TouchPinch:Connect(function(_, scale, _, state)
		if not root.Visible then
			return
		end
		if state == Enum.UserInputState.Begin then
			base = zoomGoal
		elseif state == Enum.UserInputState.Change then
			setZoom(base * scale)
		end
	end)

	-------------------------------------------------------------------- node state
	local function derive(id)
		local sel = st.selected == id
		local d = { id = id, sel = sel }
		local n = st.nodes[id]
		if n then
			d.kind, d.lv, d.max, d.isMax = "lv", n.level, n.max, n.level >= n.max
			d.running = st.active ~= nil and st.active.id == id
			d.ready = not d.isMax and not d.running and not st.active and not n.blocked
			d.fill = if sel then G.NodeSel elseif d.isMax then G.NodeMax else G.NodeGreen
			d.rim = if sel or d.isMax then C.White else hex("224124")
			d.label, d.sub, d.subColor = n.name, d.lv .. "/" .. d.max, C.Gold
		else
			d.kind, d.fill, d.rim = "hidden", G.NodeHidden, if sel then C.White else hex("16141c")
		end
		return d
	end

	----------------------------------------------------------------------- nodes
	local fxLayer -- above the nodes, in canvas space
	local function kickNode(n, amount)
		if Motion.Reduced then
			return
		end
		n.v += amount
	end
	local function ripple(n, color, from, to)
		Juice.ripple(fxLayer, UDim2.fromOffset(n.cx, n.cy), { key = "hex_glow", aspect = 296 / 256, color = color, from = from or 340, to = to or 760, life = 0.65, alpha = 0.55, z = 2 })
	end

	for _, l in LAY do
		local id = l[3]
		local cx, cy = centreOf(l)
		local h = Html.make("Frame", scaler, { Name = id, AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(HW, HH) })
		local us = Html.make("UIScale", h)
		local function hexImg(name, inset, color)
			return Html.make("ImageLabel", h, {
				Name = name,
				Image = Icons.hex,
				ScaleType = Enum.ScaleType.Stretch,
				Position = UDim2.fromOffset(inset, inset),
				Size = UDim2.new(1, -2 * inset, 1, -2 * inset),
				ImageColor3 = color,
			})
		end
		local rays = Juice.image(h, "fx_rays", { w = HW * 2.2, color = C.Gold, alpha = 0.7, z = 0 })
		rays.Visible = false
		local glow = Juice.image(h, "hex_glow", { size = UDim2.new(1.9, 0, 1.9, 0), color = C.Cyan, alpha = 0.7, z = 0 })
		glow.Visible = false
		hexImg("Outline", 0, INK2)
		local rim = hexImg("Rim", 6, C.White)
		local fill = hexImg("Fill", 13, C.White)
		local fillGrad = Instance.new("UIGradient")
		fillGrad.Rotation = 90
		fillGrad.Parent = fill
		local sheen = hexImg("Sheen", 13, C.White)
		local sheenGrad = Instance.new("UIGradient")
		sheenGrad.Rotation = 90
		sheenGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.45, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.65, Color3.new(0, 0, 0)),
			ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0)),
		})
		sheenGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.86),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.7, 1),
			NumberSequenceKeypoint.new(1, 0.86),
		})
		sheenGrad.Parent = sheen
		-- The wave of light that crosses the board, and the flash on selection.
		local flash = hexImg("Flash", 13, C.White)
		flash.ImageTransparency = 1
		flash.ZIndex = 2
		local icon = Html.icon(h, ICO[id], { x = 43, y = 34, w = 124, h = 124, z = 3 })
		local label = num(h, { ts = 22, stroke = 5, x = -10, y = 150, w = HW + 20, h = 24, z = 3 })
		local sub = num(h, { ts = 22, stroke = 5, x = 0, y = 173, w = HW, h = 26, z = 3 })
		local q = num(h, { text = "?", ts = 110, stroke = 12, x = 0, y = 0, w = HW, h = HH, z = 3 })
		local pb = Html.bar(h, { x = 58, y = 196, w = 94, h = 12, bg = "1f2633", bc = INK2, grad = { "ffd23c", "ffd23c" }, r = 6, hi = 0 })
		pb.Root.ZIndex = 4
		local n = {
			Id = id, Frame = h, Scale = us, Glow = glow, Rays = rays, Rim = rim, Fill = fill, FillGrad = fillGrad, Flash = flash, Icon = icon,
			Label = label, Sub = sub, Q = q, Bar = pb,
			cx = cx, cy = cy, dist = (V2(cx, cy) - V2(960, 540)).Magnitude,
			s = 1, v = 0, hover = false, press = false, appearAt = 0, phase = math.random() * 6.28, flash = 0,
		}
		self.Nodes[id] = n
		local hit = Html.make("TextButton", h, { Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(30, 40), Size = UDim2.fromOffset(150, 162), ZIndex = 6 })
		hit.InputBegan:Connect(function(input)
			beginPan(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				n.press = true
			end
		end)
		hit.InputEnded:Connect(function(input)
			local t = input.UserInputType
			if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
				n.press = false
				if not self._dragged then
					self:Select(id)
				end
			end
		end)
		hit.MouseEnter:Connect(function()
			n.hover = true
			kickNode(n, 1.2)
		end)
		hit.MouseLeave:Connect(function()
			n.hover, n.press = false, false
		end)
	end
	fxLayer = Html.make("Frame", scaler, { Name = "Fx", Size = UDim2.new(), ZIndex = 7 })

	--------------------------------------------------------------------- tooltip
	-- width 400, padding 20 40 40, moves with the canvas
	local tip = Html.make("Frame", scaler, { Name = "Tip", Size = UDim2.fromOffset(400, 0), AutomaticSize = Enum.AutomaticSize.Y, ZIndex = 8 })
	local tipScale = Html.make("UIScale", tip)
	local tipGlow = Juice.image(tip, "fx_glow", { size = UDim2.new(1.7, 0, 1.7, 0), color = C.Cyan, alpha = 0.5, z = -1 })
	Html.box(tip, { name = "Ring", x = -3, y = -3, size = UDim2.new(1, 6, 1, 6), bg = INK2, r = 15, z = 0 })
	local tipFace = Html.box(tip, { name = "Face", size = UDim2.new(1, 0, 0, 0), auto = "Y", bg = "16161a", alpha = 0.96, r = 12, z = 1 })
	local tipStroke = Html.border(tipFace, 4, C.Cyan)
	Html.make("UIPadding", tipFace, { PaddingLeft = UDim.new(0, 44), PaddingRight = UDim.new(0, 44), PaddingTop = UDim.new(0, 24), PaddingBottom = UDim.new(0, 44) })
	Html.make("UIListLayout", tipFace, { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder })
	local tName = num(tipFace, { ts = 38, stroke = 6, size = UDim2.fromOffset(312, 46), order = 1 })
	local tNameScale = Html.make("UIScale", tName)
	local tDesc = num(tipFace, { ts = 22, color = "e4e8ee", wrap = true, size = UDim2.new(0, 312, 0, 0), auto = "Y", order = 2 })
	local tLine = num(tipFace, { ts = 22, size = UDim2.fromOffset(312, 28), order = 3 })
	local btnHolder = Html.make("Frame", tipFace, { Name = "BtnHolder", Size = UDim2.fromOffset(312, 84), LayoutOrder = 4 })
	local tBtn = Html.plate(btnHolder, {
		x = 0, y = 8, w = 312, h = 76, grad = G.GreenB, b = 4, bc = INK2, r = 6, sh = 0, hi = 4, hia = 0.22, lo = 6, loa = 0.18,
		text = "", ts = 36, font = "Num", stroke = 7, strokeColor = INK2, hitY = 23,
	})
	local tBtnScale = Html.make("UIScale", tBtn.Root)
	local prog = Html.box(tBtn.Clip, { name = "Progress", size = UDim2.new(0, 0, 1, 0), bg = "ffffff", alpha = 0.25, z = 4, visible = false })
	local act = function() end
	tBtn.Activated:Connect(function()
		act()
	end)
	local tipReady = false

	local function placeTip(animate)
		local l
		for _, entry in LAY do
			if entry[3] == st.selected then
				l = entry
			end
		end
		local cx, cy = centreOf(l)
		local tl, tt = cx + 150, cy + 80
		if cx > 1150 then
			tl = cx - 150 - 400
		end
		if cy > 640 then
			tt = cy - 80 - 290
		end
		local target = UDim2.fromOffset(tl, tt)
		if animate then
			Motion.tween(tip, 0.22, { Position = target }, "Back")
		else
			tip.Position = target
		end
	end

	local function updateTip()
		local d = derive(st.selected)
		local name, desc, line, lineColor, btn, grad, enabled, border = nil, nil, nil, C.Gold, "", G.GreenB, true, C.Cyan
		local running = false
		act = function() end
		if d.kind == "lv" then
			local n = st.nodes[d.id]
			name, desc = n.name, n.desc
			line = if d.isMax then "Level " .. d.max .. " · MAX" else "Lv " .. d.lv .. " → " .. (d.lv + 1) .. "  ·  " .. n.durationText
			if d.isMax then
				btn, grad, enabled = "MAX", G.Yellow, false
			elseif d.running then
				btn, grad, enabled, running = "Researching " .. clock(st.active.left), G.Blue, false, true
			elseif st.active then
				btn, grad, enabled = "Busy · " .. clock(st.active.left), G.Grey, false
			elseif n.blocked then
				btn, grad, enabled = n.blocked, G.Grey, false
			else
				btn = "Research " .. money(n.cost)
				act = function()
					self.ResearchRequested:Fire(d.id)
				end
			end
		else
			name, desc, line, lineColor = "???", "Not available yet.", "Coming in a future update", hex("8fa0b8")
			btn, grad, enabled, border = "Locked", G.Grey, false, hex("5a6170")
		end
		tName.Text, tDesc.Text, tLine.Text, tLine.TextColor3, tipStroke.Color = name, desc, line, lineColor, border
		tipGlow.ImageColor3 = border
		tBtn:SetText(btn)
		tBtn:SetGrad(grad)
		tBtn:SetEnabled(enabled or false)
		tipReady = enabled == true and d.kind == "lv" and not d.isMax
		prog.Visible = running
		if running then
			local pct = (st.active.total - st.active.left) / st.active.total
			Motion.tween(prog, 1, { Size = UDim2.new(pct, 0, 1, 0) }, "Linear")
		end
	end

	local chip, chipText, chipIcon, cashLabel, rateLabel, cashScale
	local chipShown = false

	local function refresh()
		for id, n in self.Nodes do
			local d = derive(id)
			n.d = d
			local hidden = d.kind == "hidden"
			n.Q.Visible, n.Icon.Visible, n.Label.Visible, n.Sub.Visible = hidden, not hidden, not hidden, not hidden
			n.Rim.ImageColor3 = d.rim
			n.FillGrad.Color = ColorSequence.new(d.fill[1], d.fill[2])
			if not hidden then
				n.Label.Text, n.Sub.Text, n.Sub.TextColor3 = d.label, d.sub, d.subColor
			end
			local showBar = d.kind == "lv" and d.running
			n.Bar.Root.Visible = showBar
			if showBar then
				n.Bar:SetPct((st.active.total - st.active.left) / st.active.total, 1)
			end
			n.Rays.Visible = d.running == true and not Motion.Reduced
		end
		local a = st.active
		if (a ~= nil) ~= chipShown then
			chipShown = a ~= nil
			chip.Visible = chipShown
			if chipShown then
				chip.Position = self._chipBase - UDim2.fromOffset(520, 0)
				Motion.tween(chip, 0.5, { Position = self._chipBase }, "Back")
			end
		end
		if a then
			local n = st.nodes[a.id]
			chipText.Text = (n and n.name or "???") .. " · " .. clock(a.left)
		end
		rateLabel.Text = "+$" .. string.format("%.2f", st.rate) .. "/s"
	end

	-- Moments worth a celebration: research started, and a level gained.
	local function celebrate(patch, before)
		if not before then
			return
		end
		local newActive = patch.active
		if newActive and (not before.active or before.active.id ~= newActive.id) then
			local n = self.Nodes[newActive.id]
			if n then
				kickNode(n, 5)
				n.flash = 0.8
				ripple(n, C.Cyan)
				Juice.burst(fxLayer, UDim2.fromOffset(n.cx, n.cy), { color = C.Cyan, count = 10, radius = 240, spark = 40, z = 3 })
			end
		end
		for id, node in patch.nodes or {} do
			local prev = before.nodes[id]
			if prev and node.level > prev.level then
				local n = self.Nodes[id]
				kickNode(n, 7)
				n.flash = 1
				ripple(n, C.Gold, 340, 980)
				task.delay(0.12, function()
					ripple(n, C.White, 340, 720)
				end)
				Juice.burst(fxLayer, UDim2.fromOffset(n.cx, n.cy), { color = C.Gold, count = 18, radius = 360, spark = 58, life = 0.95, z = 3 })
			end
		end
	end

	-------------------------------------------------------------- screen overlay
	local overlays = {}
	local function overlay(inst, sx, sy, wallX, wallY, from)
		local item = { inst = inst, design = inst.Position, sx = sx, sy = sy, wallX = wallX or 0, wallY = wallY or 0, from = from, base = inst.Position }
		table.insert(overlays, item)
		return item
	end
	local heading = num(root, { name = "Heading", text = "Your research keeps going while you're offline!", ts = 46, stroke = 8, x = 0, y = 34, w = 1920, h = 56, z = 7 })
	-- A gold highlight keeps travelling through the words.
	local headingGrad = Html.make("UIGradient", heading, {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.White),
			ColorSequenceKeypoint.new(0.44, C.White),
			ColorSequenceKeypoint.new(0.5, C.GoldLight),
			ColorSequenceKeypoint.new(0.56, C.White),
			ColorSequenceKeypoint.new(1, C.White),
		}),
	})
	overlay(heading, 0, -1, 0, 34, UDim2.fromOffset(0, -160))
	chip = Html.box(root, { name = "Active", x = 40, y = 34, w = 0, h = 66, auto = "X", bg = "0a0e16", alpha = 0.9, r = 10, b = 2, bc = "2a3344", z = 7, visible = false })
	Html.make("UIPadding", chip, { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 26) })
	Html.make("UIListLayout", chip, {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	chipIcon = Html.icon(chip, "research", { w = 68, h = 68, order = 1 })
	chipText = num(chip, { text = "", ts = 28, auto = "XY", order = 2 })
	local chipPin = overlay(chip, -1, -1, 40, 34)
	cashLabel = num(root, { name = "Cash", text = "$0", ts = 96, color = C.Cash, stroke = 11, x = 40, y = 894, w = 700, h = 100, ax = "Left", z = 7 })
	cashScale = cashLabel:FindFirstChildOfClass("UIScale")
	overlay(cashLabel, -1, 1, 40, 44, UDim2.fromOffset(-760, 0))
	rateLabel = num(root, { name = "Rate", text = "", ts = 34, stroke = 7, x = 40, y = 995, w = 370, h = 41, ax = "Left", z = 7 })
	overlay(rateLabel, -1, 1, 40, 44, UDim2.fromOffset(-500, 0))
	local hint = num(root, { name = "Hint", text = "Drag to move · Pinch or +/− to zoom", ts = 22, color = "8fa0b8", x = 1280, y = 1009, w = 600, h = 27, ax = "Right", z = 7 })
	overlay(hint, 1, 1, 40, 44, UDim2.fromOffset(700, 0))
	local exit = Html.plate(root, {
		name = "Exit", x = 790, y = 948, w = 340, h = 92, grad = { "ef4a44", "e23a34" }, b = 5, bc = INK2, r = 6, sh = 6, shc = "000000", sha = 0.35,
		hi = 4, hia = 0.2, lo = 6, loa = 0.18, text = "Exit", ts = 46, font = "Num", stroke = 8, strokeColor = INK2, hitY = 15, z = 7,
	})
	exit.Activated:Connect(function()
		self.CloseRequested:Fire()
	end)
	overlay(exit.Root, 0, 1, 0, 40, UDim2.fromOffset(0, 240))
	local function zbtn(text, y, ts, fn)
		local b = Html.plate(root, {
			name = "Zoom" .. y, x = 1812, y = y, w = 68, h = 68, grad = { "2a3344", "131925" }, stud = false, b = 3, bc = "3a475e", r = 10, sh = 3, shc = "000000", hi = 2, hia = 0.2, lo = 3,
			press = 3, pressScale = 0.9, hitX = 14, hitY = 6, z = 7,
			text = if text == "reset" then nil else text, ts = ts, font = "Num", strokeColor = INK2,
		})
		if text == "reset" then
			-- No Roblox font has the HTML's reset glyph: a ring with a gap and an arrow head.
			local ring = Html.box(b.Content, { name = "Ring", x = 19, y = 19, w = 30, h = 30, r = UDim.new(0.5, 0) })
			local stroke = Html.make("UIStroke", ring, { Thickness = 5, Color = C.White, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, BorderStrokePosition = Enum.BorderStrokePosition.Inner })
			Html.make("UIGradient", stroke, {
				Rotation = -60,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.3, 1),
					NumberSequenceKeypoint.new(0.31, 0),
					NumberSequenceKeypoint.new(1, 0),
				}),
			})
			Html.box(b.Content, { name = "Head", x = 16, y = 16, w = 12, h = 12, bg = C.White, rot = 45 })
		end
		b.Activated:Connect(fn)
		overlay(b.Root, 1, -1, 40, 34, UDim2.fromOffset(180, 0))
	end
	zbtn("+", 34, 40, function()
		setZoom(zoomGoal * 1.25)
	end)
	zbtn("−", 112, 40, function()
		setZoom(zoomGoal / 1.25)
	end)
	zbtn("reset", 190, 30, resetView)
	zoomLabel = num(root, { name = "ZoomPct", text = "74%", ts = 20, color = "8fa0b8", x = 1812, y = 268, w = 68, h = 24, z = 7 })
	zoomLabelScale = Html.make("UIScale", zoomLabel)
	overlay(zoomLabel, 1, -1, 40, 34, UDim2.fromOffset(180, 0))

	function self:SetOverscan(x, y, pinned)
		over, overY = x or 0, y or 0
		for _, item in overlays do
			local dx = if pinned and item.sx ~= 0 then item.sx * (over + item.wallX - Layout.EDGE) else 0
			local dy = if pinned and item.sy ~= 0 then item.sy * (overY + item.wallY - Layout.EDGE) else 0
			item.base = item.design + UDim2.fromOffset(dx, dy)
			item.inst.Position = item.base
		end
		self._chipBase = chipPin.base
		host.Position = UDim2.fromOffset(-over, -overY)
		host.Size = UDim2.fromOffset(1920 + 2 * over, 1080 + 2 * overY)
	end
	self._chipBase = chipPin.base

	--------------------------------------------------------------------- frame loop
	local connection = nil
	local openedAt = 0
	local waveAt = 0
	local shownCash = 0

	local function step(dt)
		dt = math.min(dt, 1 / 20)
		local t = os.clock()

		-- Camera: glide after a flick and ease to the zoom/reset goals.
		if not tracked then
			if panVel.Magnitude > 4 then
				pan += panVel * dt
				panVel *= math.exp(-5.5 * dt)
			else
				panVel = V2()
			end
		end
		if zoom ~= zoomGoal then
			local z2 = zoom + (zoomGoal - zoom) * math.min(1, dt * 12)
			if math.abs(z2 - zoomGoal) < 0.001 then
				z2 = zoomGoal
			end
			local c, k = V2(960, 540), z2 / zoom
			pan, zoom = c - (c - pan) * k, z2
		end
		if panGoal then
			pan = pan:Lerp(panGoal, math.min(1, dt * 12))
			if (pan - panGoal).Magnitude < 0.5 and zoom == zoomGoal then
				pan, panGoal = panGoal, nil
			end
		end
		apply()

		-- Background.
		auroraA.Position = UDim2.fromOffset(3920 + math.sin(t * 0.21) * 260, 3470 + math.cos(t * 0.17) * 170)
		auroraB.Position = UDim2.fromOffset(3920 - math.sin(t * 0.16 + 1) * 360, 3550 + math.sin(t * 0.13) * 220)
		auroraC.ImageTransparency = 0.78 + math.sin(t * 0.8) * 0.08
		sweepGrad.Offset = V2(((t * 0.055) % 1) * 0.7 - 0.35, 0)
		headingGrad.Offset = V2(((t * 0.3) % 1) * 2.4 - 1.2, 0)
		chipIcon.Rotation = math.sin(t * 3.2) * 9
		for _, p in particles do
			p.y -= p.vy * dt
			if p.y < -60 - overY then
				p.y = 1140 + overY
				p.x = -over + math.random() * (1920 + 2 * over)
			end
			p.img.Position = UDim2.fromOffset(p.x + math.sin(t * 0.7 + p.phase) * p.sway, p.y)
			p.img.ImageTransparency = p.base + (1 - p.base) * (0.5 + 0.5 * math.sin(t * p.rate + p.phase))
			if p.spin ~= 0 then
				p.img.Rotation = t * p.spin
			end
		end

		-- A ripple of light leaves the selected node every few seconds and crosses the board.
		if t - waveAt > WAVE_EVERY then
			waveAt = t
		end
		local reach = (t - waveAt) * WAVE_SPEED
		local origin = self.Nodes[st.selected]
		for _, n in self.Nodes do
			local d = n.d
			local wave = 0
			local toOrigin = (V2(n.cx, n.cy) - V2(origin.cx, origin.cy)).Magnitude
			local gap = (toOrigin - reach) / WAVE_WIDTH
			if math.abs(gap) < 2.2 then
				wave = math.exp(-gap * gap)
			end

			local target = 1
			if d then
				target = if d.sel then 1.07 else 1
				if d.running then
					target += math.sin(t * 4 + n.phase) * 0.015
				end
			end
			if n.hover then
				target += 0.07
			end
			if n.press then
				target -= 0.09
			end
			if t < n.appearAt then
				target = 0.001
			end
			target += wave * 0.035

			if Motion.Reduced then
				n.s = math.max(target, 0.001)
			else
				local accel = SPRING_K * (target - n.s) - SPRING_C * n.v
				n.v += accel * dt
				n.s = math.max(n.s + n.v * dt, 0.001)
			end
			n.Scale.Scale = n.s

			n.flash = math.max(0, n.flash - dt * 2.4)
			local light = math.max(wave * 0.2, n.flash * 0.75)
			n.Flash.ImageTransparency = 1 - light

			if d then
				local glowAlpha, glowColor = nil, nil
				if d.sel then
					glowAlpha, glowColor = 0.72 + math.sin(t * 3) * 0.2, C.Cyan
				elseif d.running then
					glowAlpha, glowColor = 0.7 + math.sin(t * 5) * 0.25, C.Gold
				elseif d.ready then
					glowAlpha, glowColor = 0.42 + math.sin(t * 2.4 + n.phase) * 0.2, C.Cash
				elseif d.isMax then
					glowAlpha, glowColor = 0.5 + math.sin(t * 1.8 + n.phase) * 0.15, C.GoldLight
				elseif n.hover then
					glowAlpha, glowColor = 0.45, C.White
				end
				n.Glow.Visible = glowAlpha ~= nil
				if glowAlpha then
					n.Glow.ImageTransparency = 1 - math.clamp(glowAlpha, 0, 1)
					n.Glow.ImageColor3 = glowColor
				end
				if d.running then
					n.Rays.Rotation = t * 45
				end
				if d.kind == "hidden" then
					n.Q.Rotation = math.sin(t * 1.4 + n.phase) * 5
					n.Q.TextTransparency = 0.25 + 0.2 * math.sin(t * 0.9 + n.phase)
				elseif d.sel or d.running or d.ready then
					n.Icon.Position = UDim2.fromOffset(43, 34 + math.sin(t * 2.2 + n.phase) * 5)
					n.Icon.Rotation = math.sin(t * 1.6 + n.phase) * 5
				else
					n.Icon.Position = UDim2.fromOffset(43, 34)
					n.Icon.Rotation = 0
				end
			end
		end

		-- The tooltip's light breathes, and the button calls for the press when it can be pressed.
		tipGlow.ImageTransparency = 0.72 + math.sin(t * 2.6) * 0.14
		tBtnScale.Scale = if tipReady then 1 + (0.5 + 0.5 * math.sin(t * 4)) * 0.035 else 1
	end

	local function setLoop(on)
		if on and not connection then
			connection = RunService.RenderStepped:Connect(function(dt)
				local ok, err = pcall(step, dt)
				if not ok then
					connection:Disconnect()
					connection = nil
					warn("Research animation stopped: " .. tostring(err))
				end
			end)
		elseif not on and connection then
			connection:Disconnect()
			connection = nil
		end
	end

	-- Fades the whole screen through a group sized to the viewport; runId cancels an older fade.
	local runId = 0
	local function fade(show, done)
		runId += 1
		local id = runId
		root.Parent = host
		root.Position = UDim2.fromOffset(over, overY)
		host.Visible = true
		host.GroupTransparency = if show then 1 else 0
		Motion.tween(host, if show then 0.32 else FADE, { GroupTransparency = if show then 0 else 1 }, "Quad").Completed:Once(function()
			if id ~= runId then
				return
			end
			root.Parent = stage
			root.Position = UDim2.new()
			host.Visible = false
			if done then
				done()
			end
		end)
	end

	function self:Select(id)
		if self._dragged then
			return
		end
		local changed = st.selected ~= id
		st.selected = id
		refresh()
		updateTip()
		placeTip(true)
		local n = self.Nodes[id]
		kickNode(n, if changed then 3.2 else 1.6)
		n.flash = 0.6
		ripple(n, C.Cyan)
		waveAt = os.clock()
		if Motion.Reduced then
			step(0)
		elseif changed then
			tipScale.Scale = 0.8
			Motion.tween(tipScale, 0.3, { Scale = 1 }, "Back")
			tNameScale.Scale = 0.7
			Motion.tween(tNameScale, 0.32, { Scale = 1 }, "Back", 0.04)
		end
	end

	function self:SetState(patch)
		local before = if self._live then { active = st.active, nodes = st.nodes } else nil
		for k, v in patch do
			st[k] = v
		end
		if patch.active == false then
			st.active = nil
		end
		if patch.cash then
			if patch.cash ~= shownCash then
				local grew = self._live and patch.cash > shownCash
				Motion.countTo(cashLabel, shownCash, patch.cash, 0.45, money)
				if grew and cashScale then
					local rest = cashScale.Scale
					if not Motion.Reduced then
						Motion.tween(cashScale, 0.12, { Scale = rest * 1.04 }, "Quad").Completed:Once(function()
							Motion.tween(cashScale, 0.2, { Scale = rest }, "Quad")
						end)
					end
				end
				shownCash = patch.cash
			end
		end
		celebrate(patch, before)
		refresh()
		updateTip()
		self._live = true
		if Motion.Reduced then
			step(0)
		end
	end

	function self:Open()
		root.Visible = true
		pan, zoom, zoomGoal, panVel, panGoal = V2(PZ0.x, PZ0.y), PZ0.z, PZ0.z, V2(), nil
		apply()
		refresh()
		updateTip()
		placeTip(false)
		self._live = false
		openedAt = os.clock()
		waveAt = openedAt + 0.7
		setLoop(not Motion.Reduced)
		fade(true)
		if Motion.Reduced then
			step(0)
			return
		end
		-- Nodes grow out of the centre in rings; the frame of the screen arrives around them.
		for _, n in self.Nodes do
			n.s, n.v = 0.001, 0
			n.appearAt = openedAt + 0.06 + n.dist / 1500
			n.flash = 0.7
		end
		for _, item in overlays do
			if item.from then
				item.inst.Position = item.base + item.from
				Motion.tween(item.inst, 0.55, { Position = item.base }, "Back", 0.12)
			end
		end
		tipScale.Scale = 0.3
		Motion.tween(tipScale, 0.42, { Scale = 1 }, "Back", 0.55)
	end

	function self:Close()
		tracked = nil
		for _, n in self.Nodes do
			n.appearAt = os.clock() + 10
			n.hover, n.press = false, false
		end
		fade(false, function()
			root.Visible = false
			setLoop(false)
		end)
	end
	apply()
	return self
end

return ResearchTree
