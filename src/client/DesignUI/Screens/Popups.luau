-- Popups: the only notices that take the screen: a trade request and the offline earnings.
-- A compact card with no light effects; everything else is a Notices line.
-- Push(kind, { text, duration, onAction }). Held(): pause the queue.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sfx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sfx"))
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Html = require(Core.Html)
local Motion = require(Core.Motion)
local Juice = require(Core.Juice)

local G = Theme.Grad
local INK2 = Html.INK2
local V2 = Vector2.new

local Popups = {}
Popups.__index = Popups

local CARD_W, HEAD_H, BODY_H, FOOT_H = 820, 112, 146, 112
local CARD_H = 6 + HEAD_H + BODY_H + FOOT_H + 6
local FOOT_W = CARD_W - 12
local PRIMARY_W, LATER_W, BUTTON_H, BUTTON_Y, BUTTON_GAP = 300, 240, 88, 2, 24
local ICON_SIZE = 176
local DIM_ALPHA = 0.6
local HOLD_POLL = 0.25
-- A tap on the backdrop right after the pop-in is almost always a stray one.
local TAP_GRACE = 0.4

-- action: the card waits for an answer, and the answer stops being valid when its time runs out.
Popups.Kinds = {
	trade = { title = "Trade request", icon = "trade", grad = G.Blue, action = "Accept", duration = 15 },
	offline = { title = "Welcome back!", icon = "offline_income", grad = G.Green, duration = 8 },
}

function Popups.new(stage, dim)
	local self = setmetatable({ Held = nil, _queue = {}, _run = 0, _current = nil }, Popups)
	self._dim = dim
	local icons = {}
	for _, kind in Popups.Kinds do
		table.insert(icons, kind.icon)
	end
	Juice.preload(stage, icons)
	local root = Html.make("Frame", stage, { Name = "Popup", Size = UDim2.fromOffset(1920, 1080), Visible = false, ZIndex = 5 })
	self.Root = root

	local holder = Html.make("Frame", root, { Name = "Holder", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromOffset(960, 540), Size = UDim2.fromOffset(CARD_W, CARD_H), ZIndex = 2 })
	local pop = Html.make("UIScale", holder)
	self._holder, self._pop = holder, pop
	self._host = Html.make("CanvasGroup", root, { Name = "PopFade", Size = UDim2.fromOffset(1920, 1080), Visible = false, ZIndex = 2 })

	Html.box(holder, { name = "Shadow", y = 8, size = UDim2.fromScale(1, 1), bg = Html.INK, alpha = 0.7, r = 12, z = 0 })
	local face = Html.box(holder, { name = "Face", size = UDim2.fromScale(1, 1), bg = Html.GLASS, alpha = 0.97, r = 12, z = 1 })
	local head = Html.box(face, { name = "Head", x = 6, y = 6, w = FOOT_W, h = HEAD_H, grad = G.Blue, z = 1, clip = true })
	self._head = head
	Html.studs(head)
	Html.box(head, { name = "Line", pos = UDim2.new(0, 0, 1, -5), size = UDim2.new(1, 0, 0, 5), bg = INK2, z = 3 })
	self._title = Html.label(head, { name = "Title", text = "", ts = 60, font = "Num", stroke = 11, strokeColor = INK2, x = 170, y = 0, w = FOOT_W - 186, h = HEAD_H - 5, ax = "Left", z = 4 })
	self._text = Html.label(face, {
		name = "Text", text = "", ts = 36, font = "Title", stroke = 7, strokeColor = INK2, wrap = true, x = 30, y = 6 + HEAD_H, w = CARD_W - 60, h = BODY_H, z = 3, lineHeight = 1.05,
	})

	-- Footer: one primary button, plus "Later" when the card asks for an answer.
	local foot = Html.make("Frame", face, { Name = "Foot", Position = UDim2.fromOffset(6, CARD_H - FOOT_H - 6), Size = UDim2.fromOffset(FOOT_W, FOOT_H), ZIndex = 3 })
	local function button(text, grad, w)
		return Html.plate(foot, {
			name = text, y = BUTTON_Y, w = w, h = BUTTON_H, grad = grad, b = 5, bc = INK2, r = 10, sh = 5, hi = 4, lo = 7, gloss = false, shine = false,
			text = text, ts = 40, font = "Num", stroke = 8, strokeColor = INK2, press = 4, pressScale = 0.98, hitY = 14,
		})
	end
	self._primary = button("Continue", G.GreenB, PRIMARY_W)
	self._later = button("Later", G.Grey, LATER_W)
	self._later.Root.Position = UDim2.fromOffset((FOOT_W - PRIMARY_W - LATER_W - BUTTON_GAP) / 2, BUTTON_Y)
	self._primary.Activated:Connect(function()
		self:_confirm()
	end)
	self._later.Activated:Connect(function()
		self:_close()
	end)

	-- Time left: drains along the card's lower edge.
	local track = Html.box(face, { name = "Timer", pos = UDim2.new(0, 6, 1, -14), size = UDim2.new(1, -12, 0, 8), bg = INK2, alpha = 0.8, z = 4 })
	self._timer = Html.box(track, { name = "Fill", size = UDim2.fromScale(1, 1), bg = "ffffff", alpha = 0.7 })
	Html.box(face, { name = "Border", size = UDim2.fromScale(1, 1), r = 12, b = 6, bc = INK2, z = 8 })

	-- The icon sits on the card's corner and breaks its outline, like the panels' big icons.
	local iconRoot = Html.make("Frame", holder, { Name = "IconRoot", AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromOffset(78, 46), Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE), ZIndex = 4 })
	self._iconScale = Html.make("UIScale", iconRoot)
	self._icon = Html.icon(iconRoot, "trade", { name = "Icon", w = ICON_SIZE, h = ICON_SIZE, rot = -8 })
	Html.bob(self._icon, 2.4, 5)

	dim.Activated:Connect(function()
		local current = self._current
		if current and not current.action and os.clock() - current.shownAt > TAP_GRACE then
			self:_close()
		end
	end)
	return self
end

function Popups:Push(kind, o)
	local d = Popups.Kinds[kind]
	if not d then
		return
	end
	o = o or {}
	local text = o.text or ""
	local duration = o.duration or d.duration
	local current = self._current
	-- The same request again only gives the card its time back.
	if current and current.title == d.title and current.text == text then
		current.left = duration
		return
	end
	for _, queued in self._queue do
		if queued.title == d.title and queued.text == text then
			return
		end
	end
	table.insert(self._queue, {
		title = d.title,
		text = text,
		icon = d.icon,
		grad = d.grad,
		action = d.action,
		onAction = o.onAction,
		duration = duration,
		-- A card waiting behind a battle keeps counting: the server drops the request at that moment.
		expiresAt = if d.action then os.clock() + duration else nil,
	})
	self:_pump()
end

function Popups:_pump()
	if self._current or self._polling or #self._queue == 0 then
		return
	end
	if self.Held and self.Held() then
		self._polling = true
		task.delay(HOLD_POLL, function()
			self._polling = false
			self:_pump()
		end)
		return
	end
	local item = table.remove(self._queue, 1)
	if item.expiresAt and os.clock() >= item.expiresAt then
		self:_pump()
		return
	end
	self:_show(item)
end

function Popups:_show(item)
	self._run += 1
	local run = self._run
	self._current = item
	item.shownAt = os.clock()
	item.left = if item.expiresAt then item.expiresAt - item.shownAt else item.duration
	Sfx.Play("notify")

	self._title.Text, self._text.Text = item.title, item.text
	Html.grad(self._head, item.grad[1], item.grad[2])
	self._icon.Image = Html.Icons[item.icon] or ""
	self._timer.Size = UDim2.fromScale(math.clamp(item.left / item.duration, 0, 1), 1)
	self._later.Root.Visible = item.action ~= nil
	self._primary:SetText(item.action or "Continue")
	local primaryX = if item.action then (FOOT_W - PRIMARY_W - LATER_W - BUTTON_GAP) / 2 + LATER_W + BUTTON_GAP else (FOOT_W - PRIMARY_W) / 2
	self._primary.Root.Position = UDim2.fromOffset(primaryX, BUTTON_Y)

	self.Root.Visible = true
	self._dim.Visible = true
	Motion.tween(self._dim, 0.25, { BackgroundTransparency = DIM_ALPHA })
	self._holder.Parent = self.Root
	Html.popIn(self._holder, self._pop, self._host, 0.3, 0.8)
	if Motion.Reduced then
		self._iconScale.Scale = 1
	else
		self._iconScale.Scale = 0.4
		Motion.tween(self._iconScale, 0.35, { Scale = 1 }, "Back", 0.05)
	end
	self:_bindKeys()

	task.spawn(function()
		local last = os.clock()
		while run == self._run and self._current == item do
			task.wait()
			local now = os.clock()
			item.left -= now - last
			last = now
			if run == self._run then
				self._timer.Size = UDim2.fromScale(math.clamp(item.left / item.duration, 0, 1), 1)
			end
			if item.left <= 0 then
				if run == self._run and self._current == item then
					self:_close()
				end
				return
			end
		end
	end)
end

function Popups:_confirm()
	local item = self._current
	if not item then
		return
	end
	if item.onAction then
		item.onAction()
	end
	self:_close()
end

function Popups:_close()
	if not self._current then
		return
	end
	self._current = nil
	self._run += 1
	local run = self._run
	self:_unbindKeys()
	Motion.tween(self._pop, 0.14, { Scale = 0.9 }, "In")
	if #self._queue == 0 then
		Motion.tween(self._dim, 0.18, { BackgroundTransparency = 1 })
	end
	task.delay(0.15, function()
		if run ~= self._run or self._current then
			return
		end
		self.Root.Visible = false
		if #self._queue == 0 then
			self._dim.Visible = false
		end
		self:_pump()
	end)
end

function Popups:_bindKeys()
	ContextActionService:BindActionAtPriority("FreeAPetPopup", function(_, state, input)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA then
			self:_confirm()
		else
			self:_close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 2, Enum.KeyCode.Return, Enum.KeyCode.ButtonA, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
end

function Popups:_unbindKeys()
	ContextActionService:UnbindAction("FreeAPetPopup")
end

return Popups
