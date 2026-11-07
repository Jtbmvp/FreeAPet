-- Notices: small text at the top of the screen that leaves on its own, for everything that asks
-- nothing of the player. Newest on top, so the oldest line leaves without moving the others.
-- Push(text, tone, fallbackTone). Held(): keep lines waiting. Dock(y): where the first line sits.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sfx = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sfx"))
local Core = script.Parent.Parent.Core
local Html = require(Core.Html)
local Motion = require(Core.Motion)

local Notices = {}
Notices.__index = Notices

-- Fits between the HUD's left column and the leaderboard.
local WIDTH = 1040
local TEXT_SIZE, STROKE = 30, 7
local MAX_LINES, MAX_WAITING = 3, 3
local SECONDS, WARNING_SECONDS = 3, 4.5
local FADE_IN, FADE_OUT = 0.16, 0.3
local HOLD_POLL = 0.25

local WHITE = "ffffff"
Notices.Tones = {
	info = WHITE,
	success = "8cf06a",
	cash = "8cf06a",
	warning = "ffb04a",
	locked = "c9ccd2",
	rare = "ffe066",
	research = "ff9ad4",
}

function Notices.new(stage)
	local self = setmetatable({ Held = nil, _lines = {}, _waiting = {}, _order = 0 }, Notices)
	self.Root = Html.make("Frame", stage, {
		Name = "Notices",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(960, 118),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 8,
	})
	Html.make("UIListLayout", self.Root, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	return self
end

function Notices:Dock(y)
	self.Root.Position = UDim2.fromOffset(960, y)
end

function Notices:_expireLater(line)
	line.run += 1
	local run = line.run
	task.delay(line.seconds, function()
		if run == line.run then
			self:_remove(line)
		end
	end)
end

function Notices:_remove(line)
	local index = table.find(self._lines, line)
	if not index then
		return
	end
	table.remove(self._lines, index)
	line.run += 1
	Motion.tween(line.stroke, FADE_OUT, { Transparency = 1 })
	Motion.tween(line.label, FADE_OUT, { TextTransparency = 1 }).Completed:Once(function()
		line.label:Destroy()
	end)
end

function Notices:_show(item)
	if #self._lines >= MAX_LINES then
		local oldest = table.remove(self._lines, 1)
		oldest.run += 1
		oldest.label:Destroy()
	end
	self._order -= 1
	local label = Html.label(self.Root, {
		name = "Notice",
		text = item.text,
		ts = TEXT_SIZE,
		stroke = STROKE,
		color = item.color,
		wrap = true,
		size = UDim2.fromOffset(WIDTH, 0),
		auto = "Y",
		order = self._order,
	})
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local scale = Html.make("UIScale", label, { Scale = 0.85 })
	label.TextTransparency, stroke.Transparency = 1, 1
	Motion.tween(label, FADE_IN, { TextTransparency = 0 })
	Motion.tween(stroke, FADE_IN, { Transparency = 0 })
	Motion.tween(scale, FADE_IN * 1.5, { Scale = 1 }, "Back")
	local line = { text = item.text, label = label, stroke = stroke, scale = scale, seconds = item.seconds, n = 1, run = 0 }
	table.insert(self._lines, line)
	self:_expireLater(line)
	Sfx.Play("notify")
end

function Notices:_pump()
	if #self._waiting == 0 or self._polling then
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
	for _, item in self._waiting do
		self:_show(item)
	end
	table.clear(self._waiting)
end

function Notices:Push(text, tone, fallbackTone)
	if type(text) ~= "string" or text == "" then
		return
	end
	-- The same message again counts on its line and stays a little longer.
	for _, line in self._lines do
		if line.text == text then
			line.n += 1
			line.label.Text = text .. "  x" .. line.n
			Motion.bump(line.scale, 1.1, 0.2)
			self:_expireLater(line)
			return
		end
	end
	for _, item in self._waiting do
		if item.text == text then
			return
		end
	end
	table.insert(self._waiting, {
		text = text,
		color = Notices.Tones[tone] or Notices.Tones[fallbackTone] or WHITE,
		seconds = if tone == "warning" or fallbackTone == "warning" then WARNING_SECONDS else SECONDS,
	})
	if #self._waiting > MAX_WAITING then
		table.remove(self._waiting, 1)
	end
	self:_pump()
end

return Notices
