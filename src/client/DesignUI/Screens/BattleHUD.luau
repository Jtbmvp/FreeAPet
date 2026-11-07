-- BattleHUD: cartas dos pets, prompt, menu (Attack/Bag/Switch/Run), sub-vistas, números de dano e animação da cápsula.
-- O mundo 3D (pets) é tratado fora; aqui só há âncoras (FoeAnchor / MeAnchor) para números e cápsula.
-- Sinais: Attack(j), Throw(), Switch(i), Run(), ViewChanged(view)
local TweenService = game:GetService("TweenService")
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Kit = require(Core.Kit)
local Motion = require(Core.Motion)
local Signal = require(Core.Signal)

local C, G, hex = Theme.Colors, Theme.Grad, Theme.hex
local V2 = Vector2.new

local ATTACK_GRAD = { G.Red, Theme.pair("FFB853", "F08A1C"), G.Blue, G.Purple }

local BattleHUD = {}

local function hpGrad(a, b) local r = a / math.max(1, b) return r > 0.5 and G.HpGood or r > 0.2 and G.HpMid or G.HpLow end

function BattleHUD.new(stage)
	local self = { Attack = Signal.new(), Throw = Signal.new(), Switch = Signal.new(), Run = Signal.new(), ViewChanged = Signal.new(), _view = "menu", _bag = 3 }
	local root = Kit.make("Frame", stage, { Name = "Battle", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = Theme.Z.Battle })
	self.Root = root
	self.FoeAnchor = Kit.make("Frame", root, { Name = "FoeAnchor", Position = UDim2.fromScale(0.72, 0.41), Size = UDim2.new() })
	self.MeAnchor = Kit.make("Frame", root, { Name = "MeAnchor", Position = UDim2.fromScale(0.34, 0.6), Size = UDim2.new() })

	local function card(anchor, pos)
		local f = Kit.make("Frame", root, { Size = UDim2.fromOffset(236, 0), AutomaticSize = Enum.AutomaticSize.Y, AnchorPoint = anchor, Position = pos, BackgroundColor3 = hex("14161C"), BackgroundTransparency = 0.16 })
		Kit.corner(f, 10)
		Kit.stroke(f, C.Outline, 3)
		Kit.pad(f, 9, 6, 9, 6)
		Kit.list(f, "V", 4)
		return f
	end
	local function head(parent)
		local r = Kit.make("Frame", parent, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1 })
		local name = Kit.label(r, { TS = 17, Stroke = 2.4, X = "Left", Size = UDim2.new(1, -60, 1, 0) })
		local lv = Kit.chip(r, "Lv 1", { H = 20, TS = 13 })
		lv.AnchorPoint, lv.Position = V2(1, 0.5), UDim2.new(1, 0, 0.5, 0)
		return r, name, lv
	end

	-- Cartas
	local foe = card(V2(0, 0), UDim2.fromOffset(8, 8))
	local fr, fName, fLv = head(foe)
	self._foeTag = Kit.chip(fr, "WILD", { H = 18, TS = 12, PadX = 5, Grad = Theme.pair("FF7A4A", "FF7A4A"), Color = C.White, Stroke = 1.6 })
	self._foeTag.Position = UDim2.new(1, -52, 0.5, 0)
	self._foeTag.AnchorPoint = V2(1, 0.5)
	fName.Size = UDim2.new(1, -112, 1, 0)
	self.FoeHp = Kit.bar(foe, { Size = UDim2.new(1, 0, 0, 14), Grad = G.HpGood, Radius = 7, Border = 3, Order = 2 })
	self.FoeHpText = Kit.label(foe, { TS = 12, Font = "Title", X = "Right", Size = UDim2.new(1, 0, 0, 14), Order = 3 })
	self._foeCard, self._fName, self._fLv = foe, fName, fLv

	local me = card(V2(0, 1), UDim2.new(0, 8, 1, -8))
	local mr, mName, mLv = head(me)
	mName.Size = UDim2.new(1, -112, 1, 0)
	local pips = Kit.make("Frame", mr, { AnchorPoint = V2(1, 0.5), Position = UDim2.new(1, -52, 0.5, 0), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 12) })
	Kit.list(pips, "H", 4, "Right", "Center")
	self.MeHp = Kit.bar(me, { Size = UDim2.new(1, 0, 0, 14), Grad = G.HpGood, Radius = 7, Border = 3, Order = 2 })
	local xr = Kit.make("Frame", me, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 3 })
	Kit.label(xr, { Text = "XP", TS = 12, Color = C.Xp, X = "Left", Size = UDim2.fromOffset(18, 16) })
	self.MeXp = Kit.bar(xr, { Size = UDim2.new(1, -112, 0, 8), Pos = UDim2.new(0, 22, 0.5, -4), Grad = G.Xp, Radius = 4, Border = 2 })
	self.MeHpText = Kit.label(xr, { TS = 12, Font = "Title", X = "Right", Anchor = V2(1, 0), Pos = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(86, 16) })
	self._meCard, self._mName, self._mLv, self._pips = me, mName, mLv, pips

	-- Prompt
	local prompt = Kit.make("Frame", root, { AnchorPoint = V2(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), BackgroundColor3 = hex("14161C"), BackgroundTransparency = 0.12 })
	Kit.corner(prompt, 9)
	Kit.stroke(prompt, C.Outline, 3)
	Kit.pad(prompt, 14, 6, 14, 6)
	self.Prompt = Kit.label(prompt, { TS = 16, Font = "Title", Auto = "XY", Size = UDim2.new(), Wrap = false })
	self._prompt = prompt

	-- Ações (CanvasGroup para esbater quando ocupado)
	local act = Kit.make("CanvasGroup", root, { Name = "Actions", AnchorPoint = V2(1, 1), Position = UDim2.new(1, -8, 1, -4), Size = UDim2.fromOffset(340, 0), AutomaticSize = Enum.AutomaticSize.Y })
	Kit.pad(act, 4, 4, 4, 12)
	Kit.list(act, "V", 6)
	self._act = act
	local blocker = Kit.make("TextButton", root, { Name = "Blocker", AnchorPoint = V2(1, 1), Position = UDim2.new(1, -8, 1, -4), Size = UDim2.fromOffset(340, 230), ZIndex = 50, Visible = false })

	local sub = Kit.make("Frame", act, { Name = "SubHead", Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 1, Visible = false })
	self._back = Kit.button(sub, { Size = UDim2.fromOffset(92, 42), Grad = G.Grey, Text = "◂ Back", TS = 17, Stroke = 2.2, HitPad = 2 })
	self._subTitle = Kit.label(sub, { TS = 17, Stroke = 2.2, X = "Left", Pos = UDim2.fromOffset(104, 0), Size = UDim2.new(1, -104, 1, -3) })
	self._back.Activated:Connect(function() self:ShowView("menu") self.ViewChanged:Fire("menu") end)

	local function views() return act:FindFirstChild("Views") end
	local menu = Kit.make("Frame", act, { Name = "Menu", Size = UDim2.new(1, 0, 0, 126), LayoutOrder = 2 })
	Kit.grid(menu, UDim2.new(0.5, -4, 0, 58), 8)
	self._menuBtns = {}
	for i, d in ipairs({ { "Attack", "sword", G.Red, "attack" }, { "Bag x3", "bag", G.Blue, "bag" }, { "Switch", "switch", G.GreenB, "switch" }, { "Run", "movement_speed", G.Purple, "run" } }) do
		local h = Kit.make("Frame", menu, { LayoutOrder = i })
		local b = Kit.button(h, { Size = UDim2.new(1, 0, 1, -4), Grad = d[3], Icon = d[2], IconSize = 44, Text = d[1], TS = 22, Stroke = 2.8, HitPad = 0, Gap = 4 })
		b.Activated:Connect(function()
			if d[4] == "run" then self.Run:Fire() else self:ShowView(d[4]) self.ViewChanged:Fire(d[4]) end
		end)
		self._menuBtns[d[4]] = b
	end

	local attackV = Kit.make("Frame", act, { Name = "Attack", Size = UDim2.new(1, 0, 0, 122), LayoutOrder = 3, Visible = false })
	Kit.grid(attackV, UDim2.new(0.5, -4, 0, 56), 8)
	local bagV = Kit.make("Frame", act, { Name = "Bag", Size = UDim2.new(1, 0, 0, 84), BackgroundColor3 = hex("14161C"), BackgroundTransparency = 0.12, LayoutOrder = 3, Visible = false })
	Kit.corner(bagV, 10)
	Kit.stroke(bagV, C.Outline, 3)
	local cap = Kit.icon(bagV, "capsule", { Size = UDim2.fromOffset(68, 68), Pos = UDim2.fromOffset(4, 8) })
	Motion.loop(cap, { Position = UDim2.fromOffset(4, 2) }, 1.3)
	Kit.label(bagV, { Text = "Pet Capsule", TS = 18, Stroke = 2.4, X = "Left", Pos = UDim2.fromOffset(74, 8), Size = UDim2.fromOffset(130, 22) })
	self._capText = Kit.label(bagV, { TS = 12, Font = "Body", Color = hex("D4D8DE"), X = "Left", Pos = UDim2.fromOffset(74, 31), Size = UDim2.fromOffset(130, 16) })
	Kit.label(bagV, { Text = "Weaker pets are easier to catch", TS = 12, Font = "Body", Color = hex("A4AAB3"), X = "Left", Y = "Top", Wrap = true, Pos = UDim2.fromOffset(74, 48), Size = UDim2.fromOffset(130, 32) })
	self._throw = Kit.button(bagV, { Size = UDim2.fromOffset(110, 56), Anchor = V2(1, 0.5), Pos = UDim2.new(1, -10, 0.5, -2), Grad = G.Blue, Text = "Throw", TS = 20, Shine = 3, HitPad = 0 })
	self._throw.Activated:Connect(function() self.Throw:Fire() end)
	local switchV = Kit.make("Frame", act, { Name = "Switch", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Visible = false })
	Kit.list(switchV, "V", 6)
	self._views = { menu = menu, attack = attackV, bag = bagV, switch = switchV }
	self._blocker = blocker

	-- API de dados -----------------------------------------------------
	function self:SetFoe(f) -- { name, tag, tagColor (par), lv, hp, max }
		self._fName.Text, self._fLv:FindFirstChildOfClass("TextLabel").Text = f.name, "Lv " .. f.lv
		self._foeTag:FindFirstChildOfClass("TextLabel").Text = f.tag or "WILD"
		if f.tagGrad then Kit.grad(self._foeTag, f.tagGrad) end
		self.FoeHp:SetGrad(hpGrad(f.hp, f.max))
		self.FoeHp:SetPct(f.hp / f.max, 0.7, "Out")
		self.FoeHpText.Text = f.hp .. " / " .. f.max .. " HP"
		self._foe = f
	end
	function self:SetMe(m) -- { name, lv, hp, max, xpPct (0-1), pips = { {alive, active}, ... } }
		self._mName.Text, self._mLv:FindFirstChildOfClass("TextLabel").Text = m.name, "Lv " .. m.lv
		self.MeHp:SetGrad(hpGrad(m.hp, m.max))
		self.MeHp:SetPct(m.hp / m.max, 0.7, "Out")
		self.MeXp:SetPct(m.xpPct or 0, 0.6, "Out")
		self.MeHpText.Text = m.hp .. " / " .. m.max .. " HP"
		for _, c in ipairs(self._pips:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
		for i, p in ipairs(m.pips or {}) do
			local d = Kit.make("Frame", self._pips, { Size = UDim2.fromOffset(12, 12), BackgroundColor3 = p.alive and hex("7AE860") or hex("5C5D61"), BackgroundTransparency = 0, LayoutOrder = i })
			Kit.corner(d, UDim.new(0.5, 0))
			Kit.stroke(d, p.active and C.White or C.Outline, p.active and 2.5 or 2)
		end
	end
	function self:SetPrompt(text)
		if self.Prompt.Text == text then return end
		self.Prompt.Text = text
		self._prompt.Position = UDim2.new(0.5, 0, 0, -50)
		Motion.tween(self._prompt, 0.45, { Position = UDim2.new(0.5, 0, 0, 8) }, "Back")
	end
	function self:SetBagCount(n)
		self._bag = n
		self._menuBtns.bag:SetText("Bag x" .. n)
	end
	function self:SetBag(caps, cash, price) -- cartão do Bag
		self._capText.Text = caps > 0 and ("You have " .. caps) or ("None left · $" .. tostring(math.floor(cash)))
		price = price or 0
		self._throw:SetText(caps > 0 and "Throw" or ("Buy & throw $" .. price))
		self._throw:SetEnabled(caps > 0 or cash >= price)
		self._throw:SetGrad((caps > 0 or cash >= price) and G.Blue or G.Grey)
	end
	function self:SetMoves(moves) -- { {name, power, uses, max}, ... }
		for _, c in ipairs(attackV:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		for j, m in ipairs(moves) do
			local ok = m.uses == nil or m.uses > 0
			local h = Kit.make("Frame", attackV, { LayoutOrder = j })
			local b = Kit.button(h, { Size = UDim2.new(1, 0, 1, -4), Grad = ok and ATTACK_GRAD[j] or G.Grey, HitPad = 0 })
			b.Content.Size = UDim2.new(1, -16, 1, 0)
			local col = Kit.make("Frame", b.Content, { AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new(), BackgroundTransparency = 1 })
			Kit.list(col, "V", 0, "Center")
			Kit.label(col, { Text = m.name, TS = 19, Stroke = 2.4, Auto = "XY", Size = UDim2.new(), Order = 1 })
			Kit.label(col, { Text = ok and ((m.power > 0 and ("Power " .. m.power .. " · ") or "Heal · ") .. (m.max and (tostring(m.uses) .. "/" .. m.max .. " uses") or "")) or "No uses left", TS = 12, Stroke = 1.6, Auto = "XY", Size = UDim2.new(), Order = 2 })
			b:SetEnabled(ok)
			b:SetOpacity(ok and 1 or 0.6)
			b.Activated:Connect(function() self.Attack:Fire(j) end)
		end
	end
	function self:SetTeam(team) -- { {name, lv, hp, max, active}, ... }
		for _, c in ipairs(switchV:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		for i, t in ipairs(team) do
			local dead = t.hp <= 0
			local r = Kit.make("TextButton", switchV, { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = hex("14161C"), BackgroundTransparency = dead and 0.45 or 0.1, LayoutOrder = i })
			Kit.corner(r, 8)
			Kit.stroke(r, t.active and C.Gold or C.Outline, 3)
			Kit.label(r, { Text = t.name, TS = 15, Stroke = 2, X = "Left", Pos = UDim2.fromOffset(8, 3), Size = UDim2.new(0.5, -10, 0, 18) })
			local chip = Kit.chip(r, "Lv " .. t.lv, { H = 16, TS = 11, PadX = 4 })
			chip.Position = UDim2.fromOffset(8, 24)
			local hb = Kit.bar(r, { Size = UDim2.new(0, 84, 0, 10), Pos = UDim2.new(0.5, -4, 0, 8), Grad = hpGrad(t.hp, t.max), Radius = 5, Border = 2 })
			hb:SetPct(t.hp / t.max)
			Kit.label(r, { Text = t.hp .. " / " .. t.max .. " HP", TS = 12, Font = "Body", Color = hex("D4D8DE"), Pos = UDim2.new(0.5, -4, 0, 21), Size = UDim2.fromOffset(84, 16) })
			local stc = Kit.make("Frame", r, { AnchorPoint = V2(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(60, 22), BackgroundColor3 = t.active and C.Gold or dead and hex("8C8D91") or hex("7AE860"), BackgroundTransparency = 0 })
			Kit.corner(stc, 6)
			Kit.stroke(stc, C.Outline, 2)
			Kit.label(stc, { Text = t.active and "Active" or dead and "Fainted" or "Ready", TS = 12, Color = C.Outline })
			r.Activated:Connect(function() if not t.active and not dead then self.Switch:Fire(i) end end)
		end
	end

	-- Vistas --------------------------------------------------------------
	local TITLES = { attack = "Choose an attack", bag = "Bag", switch = "Switch to…" }
	function self:ShowView(v, opts)
		opts = opts or {}
		self._view = v
		for name, f in pairs(self._views) do f.Visible = name == v end
		sub.Visible = v ~= "menu"
		self._back:SetVisible(not opts.forced)
		self._subTitle.Text = opts.title or TITLES[v] or ""
		if opts.forced then self._subTitle.Position = UDim2.fromOffset(0, 0) self._subTitle.Size = UDim2.new(1, 0, 1, -3)
		else self._subTitle.Position = UDim2.fromOffset(104, 0) self._subTitle.Size = UDim2.new(1, -104, 1, -3) end
	end
	function self:SetBusy(b)
		self._blocker.Visible = b
		Motion.tween(act, 0.25, { GroupTransparency = b and 0.55 or 0 })
	end

	function self:Show()
		root.Visible = true
		foe.Position = UDim2.fromOffset(-260, 8)
		me.Position = UDim2.new(0, 8, 1, 160)
		act.Position = UDim2.new(1, 380, 1, -4)
		Motion.tween(foe, 0.55, { Position = UDim2.fromOffset(8, 8) }, "Back")
		Motion.tween(me, 0.55, { Position = UDim2.new(0, 8, 1, -8) }, "Back")
		Motion.tween(act, 0.5, { Position = UDim2.new(1, -8, 1, -4) }, "Back")
		self:ShowView("menu")
	end
	function self:Hide() root.Visible = false end

	-- Efeitos ------------------------------------------------------------
	-- kind: "dmg" (vermelho) | "heal" (verde, prefixa +)
	function self:Damage(who, v, kind)
		local anchor = who == "foe" and self.FoeAnchor or self.MeAnchor
		local heal = kind == "heal"
		local lbl = Kit.label(anchor, { Text = (heal and "+" or "") .. v, TS = who == "foe" and 40 or 46, Color = heal and C.Cash or hex("FF5040"), Stroke = 5, Anchor = V2(0.5, 0.5), Pos = UDim2.fromOffset(0, -40), Size = UDim2.fromOffset(100, 50), Z = 5 })
		local us = Instance.new("UIScale")
		us.Scale = 0.5
		us.Parent = lbl
		local st = lbl:FindFirstChildOfClass("UIStroke")
		Motion.tween(us, 0.18, { Scale = 1.3 }, "Back")
		Motion.tween(lbl, 0.18, { Position = UDim2.fromOffset(0, -55) })
		task.delay(0.18, function()
			Motion.tween(us, 0.72, { Scale = 1 })
			Motion.tween(lbl, 0.72, { Position = UDim2.fromOffset(0, -90), TextTransparency = 1 })
			Motion.tween(st, 0.72, { Transparency = 1 })
		end)
		task.delay(0.95, function() lbl:Destroy() end)
		if not heal then
			local b = Kit.icon(anchor, "star", { Size = UDim2.fromOffset(40, 40), Anchor = V2(0.5, 0.5), Pos = UDim2.fromOffset(0, 0), Z = 4 })
			Motion.tween(b, 0.5, { Size = UDim2.fromOffset(110, 110), Rotation = 50, ImageTransparency = 1 })
			task.delay(0.55, function() b:Destroy() end)
		end
	end

	-- Cápsula: arco 0.75s, abana 3x (2.2s), depois caught (estrelas) ou break (0.35s). cb(result) no fim.
	function self:PlayCapsule(result, cb)
		task.spawn(function()
			local f = Kit.make("Frame", self.FoeAnchor, { Size = UDim2.fromOffset(48, 48), AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromOffset(-300, 160), Rotation = -600, BackgroundTransparency = 1, ZIndex = 6 })
			local img = Kit.icon(f, "capsule", { Size = UDim2.fromScale(1, 1) })
			local function wait(tw) tw.Completed:Wait() end
			wait(Motion.tween(f, 0.375, { Position = UDim2.fromOffset(-150, -85), Rotation = -240 }, "Quad"))
			wait(Motion.tween(f, 0.375, { Position = UDim2.fromOffset(0, 0), Rotation = 0 }, "In"))
			local keys = { { 8, -24 }, { 16, 20 }, { 24, -6 }, { 30, 0 }, { 40, -24 }, { 48, 20 }, { 56, -6 }, { 62, 0 }, { 72, -20 }, { 80, 16 }, { 88, -4 }, { 100, 0 } }
			local prev = 0
			for _, k in ipairs(keys) do
				wait(TweenService:Create(f, TweenInfo.new((k[1] - prev) / 100 * 2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Rotation = k[2] }))
				f.Rotation = k[2]
				prev = k[1]
			end
			if result == "caught" then
				for i, o in ipairs({ { -38, -44, 32 }, { 36, -50, 26 }, { 40, 30, 22 } }) do
					local s = Kit.icon(self.FoeAnchor, "star", { Size = UDim2.fromOffset(o[3], o[3]), Anchor = V2(0.5, 0.5), Pos = UDim2.fromOffset(o[1], o[2]), Z = 7 })
					Motion.tween(s, 1, { Size = UDim2.fromOffset(o[3] * 1.4, o[3] * 1.4), Rotation = 180, ImageTransparency = 1 }, "Quad", i * 0.2)
					task.delay(1.4, function() s:Destroy() end)
				end
				task.wait(0.9)
			else
				Motion.tween(f, 0.35, { Size = UDim2.fromOffset(86, 86) }, "Quad")
				Motion.tween(img, 0.35, { ImageTransparency = 1 }, "Quad")
				task.wait(0.4)
			end
			f:Destroy()
			if cb then cb(result) end
		end)
	end
	function self:SetPermissions(attacker, wild)
		self._menuBtns.bag:SetEnabled(attacker and wild)
		self._menuBtns.switch:SetEnabled(attacker)
		self._menuBtns.run:SetEnabled(attacker)
	end
	return self
end

return BattleHUD
