-- TradeRoom: 6 slots por lado, os teus pets em baixo, Ready / Confirm, contagem 3-2-1.
-- SetState({ partner, mine = {{id,name,lv}}, theirs = {{name,lv}}, myPets = {{id,name,lv,inTrade}},
--            ready, pReady, conf, pConf, note, noteColor })
-- Sinais: AddPet(id), RemovePet(id), ReadyToggled(), ConfirmPressed(), CancelPressed()
-- ShowCount(title, text, color, big) / HideCount()
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Kit = require(Core.Kit)
local Motion = require(Core.Motion)
local Signal = require(Core.Signal)

local C, G, hex = Theme.Colors, Theme.Grad, Theme.hex
local V2 = Vector2.new

local TradeRoom = {}

function TradeRoom.new(stage)
	local self = Kit.panel(stage, { Name = "TradeRoom", Title = "Trade with …", TitleSize = 24, Grad = G.GreenC, Icon = "trade" })
	self.AddPet, self.RemovePet, self.ReadyToggled, self.ConfirmPressed, self.CancelPressed = Signal.new(), Signal.new(), Signal.new(), Signal.new(), Signal.new()
	self.ManualClose = true -- closing asks the server to cancel; TradeUpdate then closes the panel
	self.CloseRequested:Connect(function() self.CancelPressed:Fire() end)

	local pill = Kit.make("Frame", self.Right, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32), BackgroundColor3 = C.Black, BackgroundTransparency = 0.6, LayoutOrder = 1 })
	Kit.corner(pill, 8)
	Kit.stroke(pill, C.Outline, 3)
	Kit.pad(pill, 8, 0, 8, 0)
	self._status = Kit.label(pill, { TS = 14, Font = "Title", Auto = "X", Size = UDim2.new(0, 0, 1, 0) })

	local body = self.Body
	local sides = Kit.make("Frame", body, { Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 150) })
	Kit.list(sides, "H", 10)
	local function side(title, color, order)
		local f = Kit.make("Frame", sides, { Size = UDim2.new(0.5, -5, 1, 0), BackgroundColor3 = C.White, BackgroundTransparency = 0.96, LayoutOrder = order })
		Kit.corner(f, 8)
		Kit.stroke(f, color, 3)
		Kit.label(f, { Text = title, TS = 18, Stroke = 2.2, X = "Left", Pos = UDim2.fromOffset(8, 4), Size = UDim2.new(0.5, 0, 0, 22) })
		local st = Kit.label(f, { TS = 13, Font = "Title", Color = C.Muted, X = "Right", Pos = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(0.5, -8, 0, 22) })
		local grid = Kit.make("Frame", f, { Position = UDim2.fromOffset(8, 30), Size = UDim2.new(1, -16, 1, -38) })
		Kit.grid(grid, UDim2.new(1 / 3, -4, 0, 52), 6)
		return grid, st
	end
	self._mineGrid, self._mineSt = side("You give", hex("3382D6"), 1)
	self._theirGrid, self._theirSt = side("They give", hex("F7962B"), 2)

	Kit.label(body, { Text = "Your pets · tap to add (max 6)", TS = 13, Color = C.Muted, X = "Left", Pos = UDim2.fromOffset(12, 162), Size = UDim2.new(1, -24, 0, 16) })
	local mine = Kit.make("ScrollingFrame", body, { Position = UDim2.fromOffset(10, 180), Size = UDim2.new(1, -20, 0, 62), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ScrollBarThickness = 3 })
	Kit.list(mine, "H", 8)
	self._mine = mine

	local foot = Kit.make("Frame", body, { AnchorPoint = V2(0, 1), Position = UDim2.new(0, 10, 1, -8), Size = UDim2.new(1, -20, 0, 46) })
	self._note = Kit.label(foot, { TS = 13, Font = "Body", Color = C.Muted, X = "Left", Wrap = true, Size = UDim2.new(1, -330, 1, 0) })
	local btns = Kit.make("Frame", foot, { AnchorPoint = V2(1, 0), Position = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 46) })
	Kit.list(btns, "H", 8, "Right", "Center")
	local cancel = Kit.button(btns, { Size = UDim2.fromOffset(96, 44), Grad = G.Red, Text = "Cancel", TS = 18, Order = 1, HitPad = 0 })
	self._ready = Kit.button(btns, { Size = UDim2.fromOffset(112, 44), Grad = G.GreenB, Text = "Ready", TS = 18, Order = 2, HitPad = 0 })
	self._confirm = Kit.button(btns, { Size = UDim2.fromOffset(116, 44), Grad = G.Grey, Text = "Confirm", TS = 18, Order = 3, HitPad = 0 })
	cancel.Activated:Connect(function() self.CancelPressed:Fire() end)
	self._ready.Activated:Connect(function() self.ReadyToggled:Fire() end)
	self._confirm.Activated:Connect(function() self.ConfirmPressed:Fire() end)

	-- Overlay de contagem
	local ov = Kit.make("Frame", self.Group, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = hex("05080E"), BackgroundTransparency = 0.4, Visible = false, ZIndex = 20 })
	local ovTitle = Kit.label(ov, { TS = 22, Stroke = 3, Pos = UDim2.fromScale(0, 0.18), Size = UDim2.new(1, 0, 0, 30), Z = 2 })
	local ovNum = Kit.label(ov, { TS = 100, Stroke = 8, Pos = UDim2.fromScale(0, 0.3), Size = UDim2.new(1, 0, 0, 120), Z = 2 })
	local numSc = Instance.new("UIScale")
	numSc.Parent = ovNum
	function self:ShowCount(title, text, color, big)
		ov.Visible = true
		ovTitle.Text, ovNum.Text, ovNum.TextColor3 = title, text, color or C.White
		ovNum.TextSize = big and 90 or 100
		numSc.Scale = 2.4
		ovNum.TextTransparency = 1
		Motion.tween(numSc, 0.4, { Scale = 1 }, "Quad")
		Motion.tween(ovNum, 0.2, { TextTransparency = 0 })
	end
	function self:HideCount() ov.Visible = false end

	local function slot(parent, i, p, mine)
		local f = Kit.make("TextButton", parent, { LayoutOrder = i, BackgroundColor3 = C.White, BackgroundTransparency = p and 0 or 0.97 })
		Kit.corner(f, 8)
		if p then
			Kit.grad(f, mine and G.Blue or G.Orange)
			Kit.stroke(f, C.Outline, 3)
			Kit.label(f, { Text = p.name, TS = 14, Stroke = 1.8, Pos = UDim2.fromOffset(2, 8), Size = UDim2.new(1, -4, 0, 18) })
			Kit.label(f, { Text = "Lv " .. p.lv, TS = 13, Color = C.Gold, Stroke = 1.6, Pos = UDim2.fromOffset(2, 28), Size = UDim2.new(1, -4, 0, 16) })
			if mine then f.Activated:Connect(function() self.RemovePet:Fire(p.id) end) end
		else
			local s = Kit.stroke(f, C.White, 2)
			s.Transparency = 0.75
		end
	end

	function self:SetState(s)
		if s.partner then self.Title.Text = "Trade with " .. s.partner end
		for _, g in ipairs({ self._mineGrid, self._theirGrid }) do for _, c in ipairs(g:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end end
		for i = 1, 6 do
			slot(self._mineGrid, i, s.mine and s.mine[i], true)
			slot(self._theirGrid, i, s.theirs and s.theirs[i], false)
		end
		for _, c in ipairs(self._mine:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		local full = s.mine and #s.mine >= 6
		for i, p in ipairs(s.myPets or {}) do
			local dis = p.inTrade or full
			local f = Kit.make("TextButton", self._mine, { Size = UDim2.fromOffset(92, 50), BackgroundColor3 = C.White, BackgroundTransparency = dis and 0.5 or 0, LayoutOrder = i })
			Kit.corner(f, 8)
			Kit.grad(f, p.inTrade and G.Grey or G.Blue)
			Kit.stroke(f, C.Outline, 3)
			Kit.label(f, { Text = p.name, TS = 13, Stroke = 1.8, Pos = UDim2.fromOffset(2, 8), Size = UDim2.new(1, -4, 0, 18) })
			Kit.label(f, { Text = "Lv " .. p.lv, TS = 12, Color = C.Gold, Pos = UDim2.fromOffset(2, 28), Size = UDim2.new(1, -4, 0, 16) })
			f.Activated:Connect(function() if not dis then self.AddPet:Fire(p.id) end end)
		end
		local pn = s.partner or "Partner"
		self._status.Text = s.pConf and (pn .. " confirmed ✓") or s.pReady and (pn .. " is ready ✓") or (pn .. " is choosing…")
		self._status.TextColor3 = s.pReady and C.Cash or C.White
		if self._pulse then self._pulse:Cancel() self._pulse = nil end
		self._status.TextTransparency = 0
		if not s.pReady then self._pulse = Motion.loop(self._status, { TextTransparency = 0.45 }, 0.7) end
		self._mineSt.Text = s.conf and "Confirmed ✓" or s.ready and "Ready ✓" or "Choosing…"
		self._mineSt.TextColor3 = s.ready and C.Cash or C.Muted
		self._theirSt.Text = s.pConf and "Confirmed ✓" or s.pReady and "Ready ✓" or "Choosing…"
		self._theirSt.TextColor3 = s.pReady and C.Cash or C.Muted
		self._note.Text, self._note.TextColor3 = s.note or "", s.noteColor or C.Muted
		self._ready:SetText(s.ready and "Unready" or "Ready")
		self._ready:SetGrad(s.ready and G.Grey or G.GreenB)
		local both = s.ready and s.pReady
		self._confirm:SetText(s.conf and "Confirmed" or "Confirm")
		self._confirm:SetGrad(both and G.Gold or G.Grey)
		self._confirm:SetEnabled(both and not s.conf)
		self._confirm:SetOpacity(both and 1 or 0.6)
	end
	return self
end

return TradeRoom
