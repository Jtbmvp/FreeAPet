-- Trade lobby: 1:1 from the HTML's "Painel Trade lobby" (left:500 top:170 920x720).
-- SetPlayers(list): { name, userId, rate, color, waiting, buttonText }. Empty list = "No one to trade with".
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Html = require(Core.Html)
local Motion = require(Core.Motion)
local Signal = require(Core.Signal)

local C, G = Theme.Colors, Theme.Grad
local INK = Html.INK

local TradeLobby = {}

function TradeLobby.new(stage)
	local self = Html.panel(stage, { name = "TradeLobby", x = 500, y = 170, w = 920, h = 720, grad = G.GreenC, icon = "trade", title = "Trade" })
	self.TradeRequested, self.TradeCancelled = Signal.new(), Signal.new()
	Html.label(self.Left, { text = "Players in server", ts = 30, stroke = 6, auto = "XY", order = 1 })
	local close = Html.closeX(self.Header, { x = 814, y = 10 })
	close.Activated:Connect(function()
		self.CloseRequested:Fire()
	end)

	local scroll = Html.make("ScrollingFrame", self.Body, {
		Name = "List",
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 14,
		ScrollBarImageColor3 = Color3.fromHex("8a8d93"),
	})
	Html.make("UIPadding", scroll, { PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 24), PaddingTop = UDim.new(0, 24), PaddingBottom = UDim.new(0, 24) })
	Html.make("UIListLayout", scroll, { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder })

	local empty = Html.make("Frame", self.Body, { Name = "Empty", Size = UDim2.fromScale(1, 1), Visible = false })
	local ring = Html.box(empty, { name = "Ring", x = 379, y = 130, w = 150, h = 150, r = UDim.new(0.5, 0) })
	Html.make("UIStroke", ring, { Thickness = 5, Color = Color3.new(1, 1, 1), Transparency = 0.65, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, BorderStrokePosition = Enum.BorderStrokePosition.Inner })
	local q = Html.label(ring, { text = "?", ts = 72 })
	q.TextTransparency = 0.6
	Html.label(empty, { text = "No one to trade with", ts = 40, stroke = 8, x = 0, y = 296, w = 908, h = 49 })
	Html.label(empty, { text = "You're the only player in this server.", ts = 24, font = "Body", color = C.Muted, x = 0, y = 361, w = 908, h = 30 })

	function self:SetPlayers(list)
		for _, c in scroll:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		empty.Visible, scroll.Visible = #list == 0, #list > 0
		for i, p in list do
			local f = Html.box(scroll, { name = "Player" .. i, w = 860, h = 104, bg = C.Dark, alpha = 0.4, r = 9, b = 4, order = i })
			local sc = Html.make("UIScale", f)
			local av = Html.box(f, { name = "Avatar", x = 20, y = 16, w = 72, h = 72, bg = p.color, r = UDim.new(0.5, 0), b = 4 })
			Html.label(av, { text = string.sub(p.name, 1, 1), ts = 32, stroke = 6 })
			Html.label(f, { text = p.name, ts = 30, x = 110, y = 18, w = 480, h = 37, ax = "Left" })
			Html.label(f, { text = if p.rate then "$" .. string.format("%.2f", p.rate) .. "/s" else "—", ts = 22, font = "Body", color = C.Cash, x = 110, y = 55, w = 480, h = 27, ax = "Left" })
			if p.waiting then
				local spin = Html.box(f, { name = "Spin", x = 500, y = 40, w = 24, h = 24, r = UDim.new(0.5, 0) })
				local st = Html.make("UIStroke", spin, { Thickness = 4, Color = C.Gold, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, BorderStrokePosition = Enum.BorderStrokePosition.Inner })
				Html.make("UIGradient", st, {
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(0.74, 0),
						NumberSequenceKeypoint.new(0.75, 1),
						NumberSequenceKeypoint.new(1, 1),
					}),
				})
				Motion.spin(spin, 0.8)
				Html.label(f, { text = "Waiting…", ts = 22, color = C.Gold, x = 534, y = 38, w = 120, h = 28, ax = "Left" })
			end
			local b = Html.plate(f, {
				name = "Trade", x = 650, y = 17, w = 190, h = 70, grad = if p.waiting then G.RedBtn else G.Blue, stud = false,
				b = 4, r = 8, sh = 4, hi = 4, lo = 6, text = if p.waiting then "Cancel" else (p.buttonText or "Trade"), ts = 30, stroke = 6, hitY = 16,
			})
			b.Activated:Connect(function()
				if p.waiting then
					self.TradeCancelled:Fire(p.userId)
				else
					self.TradeRequested:Fire(p.userId)
				end
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

return TradeLobby
