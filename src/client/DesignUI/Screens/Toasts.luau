-- Toasts: at most 4, slide-in 0.5 s, auto-dismiss (except with an action). CSS from the HTML's toast block.
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Html = require(Core.Html)
local Motion = require(Core.Motion)
local Signal = require(Core.Signal)

local C = Theme.Colors
local Toasts = {}
Toasts.__index = Toasts

-- icon = key in HudImages
Toasts.Kinds = {
	rare = { color = "4199FF", icon = "pets", title = "Rare of the day", text = "Branch Deer · spawns in Forest" },
	trade = { color = "4199FF", icon = "trade", title = "Trade request", text = "Ana_Builds wants to trade", action = "Accept" },
	lockR = { color = "8C8D91", icon = "lock", title = "Research locked", text = "Reach Player Lv 3 to unlock" },
	lockT = { color = "8C8D91", icon = "lock", title = "Trade locked", text = "Reach Player Lv 5 to unlock" },
	plvup = { color = "F0AA1C", icon = "star", title = "Level up!", text = "You reached a new Player level" },
	ok = { color = "5FBF10", icon = "trophy", title = "Done!", text = "Action completed" },
	code = { color = "5FBF10", icon = "trophy", title = "Code redeemed", text = "Reward added" },
	research = { color = "FF7CC8", icon = "research", title = "Research complete", text = "Level up! Open Research to see it" },
	bought = { color = "5FBF10", icon = "capsule", title = "Purchased", text = "+1 Pet Capsule" },
	best = { color = "5FBF10", icon = "pets", title = "Equipped best", text = "Top 3 pets by Cash/s" },
	sold = { color = "5FBF10", icon = "cash", title = "Pet sold", text = "Cash added to your total" },
	unlock = { color = "5FBF10", icon = "research", title = "Upgrade unlocked", text = "New research revealed nearby" },
}

function Toasts.new(stage)
	local self = setmetatable({ Action = Signal.new(), _n = 0, _live = {} }, Toasts)
	self.Column = Html.make("Frame", stage, {
		Name = "Toasts",
		Position = UDim2.fromOffset(1444, 150),
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = Theme.Z.Toasts,
	})
	Html.make("UIListLayout", self.Column, { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder })
	self:Dock("hud", true)
	return self
end

-- Position from the HTML: toastLeft/toastTop/toastW for each state.
function Toasts:Dock(state, lbOpen)
	if state == "research" then
		self.Column.Position, self.Column.Size = UDim2.fromOffset(1520, 380), UDim2.fromOffset(360, 0)
	elseif state == "panel" then
		self.Column.Position, self.Column.Size = UDim2.fromOffset(16, 560), UDim2.fromOffset(240, 0)
	else
		self.Column.Position, self.Column.Size = UDim2.fromOffset(1444, if lbOpen then 400 else 150), UDim2.fromOffset(460, 0)
	end
end

function Toasts:Push(kind, o)
	o = o or {}
	local d = Toasts.Kinds[kind] or Toasts.Kinds.ok
	local color = Color3.fromHex(o.color or d.color)
	local title, text, action = o.title or d.title, o.text or d.text, o.action or d.action
	self._n += 1
	local id = self._n
	local holder = Html.make("Frame", self.Column, { Name = "Toast" .. id, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = id })
	local card = Html.box(holder, {
		name = "Card", size = UDim2.new(1, 0, 0, 0), auto = "Y", pos = UDim2.new(1.3, 0, 0, 0), bg = C.Toast, alpha = 0.94, r = 9, b = 4,
	})
	Html.box(card, { name = "Bar", x = 4, y = 4, size = UDim2.new(0, 6, 1, -8), bg = color })
	local row = Html.make("Frame", card, { Name = "Row", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	Html.make("UIPadding", row, { PaddingLeft = UDim.new(0, 20), PaddingTop = UDim.new(0, 16), PaddingRight = UDim.new(0, 18), PaddingBottom = UDim.new(0, 16) })
	Html.make("UIListLayout", row, {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	Html.icon(row, o.icon or d.icon, { w = 64, h = 64, order = 1 })
	local col = Html.make("Frame", row, {
		Name = "Text",
		Size = UDim2.new(1, if action then -240 else -78, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
	})
	Html.make("UIListLayout", col, { SortOrder = Enum.SortOrder.LayoutOrder })
	Html.label(col, { text = title, ts = 24, ax = "Left", wrap = true, size = UDim2.new(1, 0, 0, 0), auto = "Y", order = 1 })
	Html.label(col, { text = text, ts = 20, font = "Medium", color = "d4d7dc", ax = "Left", wrap = true, size = UDim2.new(1, 0, 0, 0), auto = "Y", order = 2 })
	local t = { Id = id, Holder = holder, Card = card, Kind = kind }
	if action then
		local b = Html.plate(row, { w = 142, h = 56, grad = Theme.Grad.Green, stud = false, b = 4, r = 10, sh = 4, hi = 4, hia = 0.3, lo = 0, text = action, ts = 26, stroke = 5, hitY = 33, hitX = 10, order = 3 })
		local sc = Html.make("UIScale", b.Root)
		Motion.loop(sc, { Scale = 1.07 }, 0.55)
		b.Activated:Connect(function()
			self:Dismiss(id)
			if o.onAction then
				o.onAction()
			end
			self.Action:Fire(kind, id)
		end)
	end
	table.insert(self._live, t)
	Motion.tween(card, Theme.T.Toast, { Position = UDim2.new() }, "Back")
	if #self._live > 4 then
		self:Dismiss(self._live[1].Id)
	end
	if not action then
		task.delay(o.duration or 6, function()
			self:Dismiss(id)
		end)
	end
	return id
end

function Toasts:Dismiss(id)
	for i, t in self._live do
		if t.Id == id then
			table.remove(self._live, i)
			Motion.tween(t.Card, 0.25, { Position = UDim2.new(1.3, 0, 0, 0) }, "In").Completed:Once(function()
				t.Holder:Destroy()
			end)
			return
		end
	end
end

return Toasts
