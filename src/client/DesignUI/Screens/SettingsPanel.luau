-- Settings: from the HTML's "Painel Settings" (720 wide, rows 100 high), but it opens right under
-- the gear and grows out of it. SetRows({ {key, label, value}, ... }). Signal: Changed(key, value)
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Html = require(Core.Html)
local Signal = require(Core.Signal)

local C, G = Theme.Colors, Theme.Grad
local GEAR_GAP = 8

local SettingsPanel = {}

function SettingsPanel.new(stage)
	local self = Html.panel(stage, { name = "Settings", x = 1120, y = 80, w = 720, h = 414, grad = G.Grey, icon = "settings", title = "Settings", origin = "topright", popDur = 0.4 })
	self.Changed = Signal.new()
	-- x, y: the gear's lower right corner on the canvas; the panel hangs from it.
	function self:Dock(x, y)
		self.Root.Position = UDim2.fromOffset(x, y + GEAR_GAP)
	end
	-- No fade group here: its 1920x1080 canvas would clip a panel docked past the stage on wide screens.
	function self:Open()
		self.Root.Visible = true
		Html.popIn(self.Root, self.Scale, nil, 0.3, 0.5)
		self.Opened:Fire()
	end
	local close = Html.closeX(self.Header, { x = 626, y = 16, w = 70, ts = 44, stroke = 7, lo = 0 })
	close.Activated:Connect(function()
		self.CloseRequested:Fire()
	end)
	local list = Html.make("Frame", self.Body, { Name = "List", Position = UDim2.fromOffset(22, 22), Size = UDim2.new(1, -44, 1, -44) })
	Html.make("UIListLayout", list, { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder })

	function self:SetRows(rows)
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for i, r in rows do
			local f = Html.box(list, { name = r.key, w = 664, h = 100, bg = C.Dark, alpha = 0.32, r = 8, b = 4, order = i })
			Html.label(f, { text = r.label, ts = 40, stroke = 8, x = 28, y = 25, w = 410, h = 49, ax = "Left" })
			local val = r.value
			local b = Html.plate(f, {
				x = 442, y = 16, w = 200, h = 68, grad = if val then G.Green else G.RedBtn, stud = false,
				b = 4, r = 10, sh = 4, hi = 4, lo = 6, text = if val then "ON" else "OFF", ts = 34, stroke = 7, hitY = 16,
			})
			b.Activated:Connect(function()
				val = not val
				b:SetText(if val then "ON" else "OFF")
				b:SetGrad(if val then G.Green else G.RedBtn)
				self.Changed:Fire(r.key, val)
			end)
		end
		Html.label(list, { text = "Lista de opções a confirmar pelo Chefe.", ts = 18, font = "Body", color = C.Muted2, size = UDim2.new(1, 0, 0, 22), ax = "Left", order = 99 })
		-- Panel height follows the rows: 12 border + 108 header + 44 padding + rows + note.
		local h = 12 + 108 + 44 + #rows * 114 + 22
		self.Root.Size = UDim2.fromOffset(720, h)
	end
	return self
end

return SettingsPanel
