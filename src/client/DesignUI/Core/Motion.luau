-- Motion: todas as animações (TweenService). Easings equivalentes aos cubic-bezier do design.
--   Back  = cubic-bezier(.2,.9,.3,1.2)   (pop, toasts, tabs)
--   Out   = cubic-bezier(.3,.7,.3,1)     (barras)
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Motion = { Reduced = false }
pcall(function() Motion.Reduced = GuiService.ReducedMotionEnabled end)

local S, D = Enum.EasingStyle, Enum.EasingDirection
local EASE = {
	Back = { S.Back, D.Out }, Out = { S.Cubic, D.Out }, Quart = { S.Quart, D.Out },
	Quad = { S.Quad, D.Out }, QuadIO = { S.Quad, D.InOut }, In = { S.Quad, D.In },
	Linear = { S.Linear, D.Out }, Sine = { S.Sine, D.InOut },
}

function Motion.info(t, ease, rep, rev, delay)
	local e = EASE[ease or "Quad"]
	return TweenInfo.new(t, e[1], e[2], rep or 0, rev or false, delay or 0)
end

function Motion.tween(inst, t, props, ease, delay)
	if Motion.Reduced and t > 0.15 then t = 0.15 end
	local tw = TweenService:Create(inst, Motion.info(t, ease, 0, false, delay), props)
	tw:Play()
	return tw
end

-- Tween infinito vai-e-vem (bob, pulse). Devolve o tween (Cancel para parar).
function Motion.loop(inst, props, half, ease)
	if Motion.Reduced then return nil end
	local tw = TweenService:Create(inst, Motion.info(half, ease or "Sine", -1, true), props)
	tw:Play()
	return tw
end

function Motion.spin(inst, period)
	if Motion.Reduced then return nil end
	local tw = TweenService:Create(inst, TweenInfo.new(period or 0.8, S.Linear, D.Out, -1), { Rotation = 360 })
	tw:Play()
	return tw
end

-- popIn: scale .6 -> 1.035 -> 1 (0.45s) + fade. `sc` = UIScale, `group` = CanvasGroup.
function Motion.popIn(sc, group, dur)
	dur = dur or 0.45
	if Motion.Reduced then
		sc.Scale = 1
		group.GroupTransparency = 1
		Motion.tween(group, 0.15, { GroupTransparency = 0 })
		return
	end
	sc.Scale = 0.6
	group.GroupTransparency = 1
	Motion.tween(group, dur * 0.55, { GroupTransparency = 0 }, "Quad")
	local t1 = Motion.tween(sc, dur * 0.55, { Scale = 1.035 }, "Quad")
	t1.Completed:Once(function()
		Motion.tween(sc, dur * 0.45, { Scale = 1 }, "QuadIO")
	end)
end

-- cardIn: fade + scale .94 -> 1 (0.4s), com atraso por índice.
function Motion.cardIn(group, delay)
	local sc = group:FindFirstChild("CardScale") or Instance.new("UIScale")
	sc.Name = "CardScale"
	sc.Parent = group
	if Motion.Reduced then return end
	sc.Scale = 0.94
	group.GroupTransparency = 1
	Motion.tween(group, 0.4, { GroupTransparency = 0 }, "Quad", delay or 0)
	Motion.tween(sc, 0.4, { Scale = 1 }, "Quad", delay or 0)
end

-- bump: 1 -> peak (40%) -> 1
function Motion.bump(sc, peak, t)
	if Motion.Reduced then return end
	t = t or 0.4
	local tw = Motion.tween(sc, t * 0.4, { Scale = peak or 1.06 }, "Quad")
	tw.Completed:Once(function() Motion.tween(sc, t * 0.6, { Scale = 1 }, "Quad") end)
end

-- shake: 0 -> -a -> +a -> -a -> +a -> 0 (0.4s)
function Motion.shake(gui, amp)
	if Motion.Reduced then return end
	amp = amp or 5
	local base = gui.Position
	task.spawn(function()
		for _, dx in ipairs({ -amp, amp, -amp, amp, 0 }) do
			local tw = TweenService:Create(gui, TweenInfo.new(0.08, S.Linear), { Position = base + UDim2.fromOffset(dx, 0) })
			tw:Play()
			tw.Completed:Wait()
		end
		gui.Position = base
	end)
end

-- shine: faixa brilhante que varre o botão. `host` deve ser o Face (clipa).
function Motion.shine(host, period, delay)
	if Motion.Reduced then return nil end
	local bar = Instance.new("Frame")
	bar.Name = "Shine"
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Size = UDim2.new(0.16, 0, 1.5, 0)
	bar.Position = UDim2.new(-0.3, 0, 0.5, 0)
	bar.Rotation = 14
	bar.ZIndex = 3
	bar.Active = false
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = bar
	bar.Parent = host
	task.spawn(function()
		task.wait(delay or 0)
		while bar.Parent do
			bar.Position = UDim2.new(-0.3, 0, 0.5, 0)
			local tw = TweenService:Create(bar, TweenInfo.new(period * 0.45, S.Sine, D.InOut), { Position = UDim2.new(1.3, 0, 0.5, 0) })
			tw:Play()
			tw.Completed:Wait()
			task.wait(period * 0.55)
		end
	end)
	return bar
end

local active = setmetatable({}, { __mode = "k" })
-- countTo: contador animado (cash, XP)
function Motion.countTo(label, from, to, dur, fmt)
	fmt = fmt or tostring
	if active[label] then active[label]:Cancel() end
	if Motion.Reduced or from == to then label.Text = fmt(to) return end
	local nv = Instance.new("NumberValue")
	nv.Value = from
	nv.Changed:Connect(function(v) label.Text = fmt(v) end)
	local tw = TweenService:Create(nv, TweenInfo.new(dur or 0.35, S.Quad, D.Out), { Value = to })
	active[label] = tw
	tw:Play()
	tw.Completed:Once(function(st)
		if st == Enum.PlaybackState.Completed then label.Text = fmt(to) end
		nv:Destroy()
	end)
end

return Motion
