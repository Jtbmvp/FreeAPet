-- UIManager: abre/fecha ecrãs, escurece e desfoca o mundo, esconde o HUD, trata Esc / B.
local Lighting = game:GetService("Lighting")
local ContextActionService = game:GetService("ContextActionService")
local Core = script.Parent
local Theme = require(Core.Theme)
local Motion = require(Core.Motion)
local Signal = require(Core.Signal)

local UIManager = {}
UIManager.__index = UIManager

-- env: { Dim = TextButton (backdrop), Hud = HUD, Screens = { nome = ecrã } }
-- Cada ecrã expõe: Open(), Close(), CloseRequested (Signal), opcional NoDim / NoBlur.
function UIManager.new(env)
	local self = setmetatable({ Screens = env.Screens, Hud = env.Hud, Dim = env.Dim, Current = nil, Opened = Signal.new(), Closed = Signal.new() }, UIManager)
	local blur = Instance.new("BlurEffect")
	blur.Name = "FreeAPetBlur"
	blur.Size = 0
	blur.Parent = Lighting
	self.Blur = blur
	for _, scr in pairs(env.Screens) do
		scr.CloseRequested:Connect(function() if not scr.ManualClose then self:Close() end end)
	end
	return self
end

function UIManager:_hud(show)
	if show and self.ShouldShowHud and not self.ShouldShowHud() then return end
	self.Hud:Fade(show, Theme.T.Fade)
end

function UIManager:Open(name)
	if self.Current == name then return end
	local scr = self.Screens[name]
	if not scr then return end
	local wasOpen = self.Current ~= nil
	if wasOpen then self.Screens[self.Current]:Close() end
	self.Current = name
	scr:Open()
	if not scr.NoDim then
		self.Dim.Visible = true
		Motion.tween(self.Dim, Theme.T.Fade, { BackgroundTransparency = 0.7 })
	else
		self.Dim.Visible = false
	end
	Motion.tween(self.Blur, Theme.T.Blur, { Size = scr.NoBlur and 0 or 12 })
	if not wasOpen then self:_hud(false) end
	ContextActionService:BindActionAtPriority("FreeAPetClose", function(_, state)
		if state == Enum.UserInputState.Begin and not (scr.BlockClose) then
			if scr.ManualClose then scr.CloseRequested:Fire() else self:Close() end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	self.Opened:Fire(name)
end

function UIManager:Close()
	local name = self.Current
	if not name then return end
	self.Screens[name]:Close()
	self.Current = nil
	ContextActionService:UnbindAction("FreeAPetClose")
	local dim = self.Dim
	Motion.tween(dim, 0.2, { BackgroundTransparency = 1 }).Completed:Once(function()
		if not self.Current then dim.Visible = false end
	end)
	Motion.tween(self.Blur, Theme.T.Blur, { Size = 0 })
	self:_hud(true)
	self.Closed:Fire(name)
end

return UIManager
