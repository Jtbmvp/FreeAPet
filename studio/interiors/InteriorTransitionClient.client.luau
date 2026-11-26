-- InteriorTransitionClient (StarterPlayerScripts, outside the Client folder): entry / exit
-- animation for the interior doors (igloo, castle). Purely visual: InteriorDoorsServer validates
-- and teleports; this script only reacts to ReplicatedStorage.InteriorDoorsRemotes.Transition:
--   ("start", info)   lock controls, walk a few steps to the door, push the camera in, fade to
--                     black and show the room name (entering) while the server teleports
--   ("arrived", cf)   camera back behind the character at the new spot, fade in, unlock
--   ("cancel")        fade straight back in
-- Never stays black: everything is undone after MAX_BLACK seconds or on respawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer

local MAX_BLACK = 4 -- seconds from "start" after which we restore no matter what
local FONT_TITLE = Font.fromName("Montserrat", Enum.FontWeight.Heavy)
local FONT_SUB = Font.fromName("Montserrat", Enum.FontWeight.Bold)
local ICONS = { Igloo = "❄️", Castle = "🏰", Cabin = "🏠", Pyramid = "☀️" } -- emoji: plain symbol glyphs render as boxes
local TINT = { -- colour of the thin line under the title
	Igloo = Color3.fromRGB(150, 215, 255),
	Castle = Color3.fromRGB(255, 205, 90),
	Cabin = Color3.fromRGB(230, 150, 80),
	Pyramid = Color3.fromRGB(245, 196, 49),
}

-- timings per direction (seconds)
local T = {
	enter = { walk = true, cam = 0.9, fadeAt = 0.3, fade = 0.45, fadeIn = 0.6 },
	leave = { walk = true, cam = 0.55, fadeAt = 0.1, fade = 0.35, fadeIn = 0.45 },
}

local controls = nil
task.spawn(function()
	local scripts = player:WaitForChild("PlayerScripts")
	local mod = scripts:WaitForChild("PlayerModule", 20)
	if mod then
		local ok, pm = pcall(require, mod)
		if ok and pm and pm.GetControls then
			controls = pm:GetControls()
		end
	end
end)

---------------------------------------------------------------- UI
local gui = Instance.new("ScreenGui")
gui.Name = "InteriorTransitionGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 200
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false

local black = Instance.new("Frame")
black.Name = "Black"
black.Size = UDim2.fromScale(1, 1)
black.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
black.BackgroundTransparency = 1
black.BorderSizePixel = 0
black.Parent = gui

-- soft vignette: four edge bands that darken before the full fade
local vignette = {}
for i, spec in
	{
		{ UDim2.fromScale(1, 0.35), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, 0.35), UDim2.fromScale(0, 0.65), -90 },
		{ UDim2.fromScale(0.3, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(0.3, 1), UDim2.fromScale(0.7, 0), 180 },
	}
do
	local f = Instance.new("Frame")
	f.Name = "Vignette" .. i
	f.Size = spec[1]
	f.Position = spec[2]
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	local g = Instance.new("UIGradient")
	g.Rotation = spec[3]
	g.Transparency = NumberSequence.new(0, 1)
	g.Parent = f
	f.Parent = gui
	vignette[i] = f
end

local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.fromOffset(560, 200)
card.BackgroundTransparency = 1
card.ZIndex = 5
card.Parent = gui
local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local function label(name, text, font, size, y, h)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, y)
	l.Size = UDim2.new(1, 0, 0, h)
	l.FontFace = font
	l.Text = text
	l.TextSize = size
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextTransparency = 1
	l.ZIndex = 6
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(20, 22, 40)
	s.Thickness = 3
	s.Transparency = 1
	s.Parent = l
	l.Parent = card
	return l, s
end

local icon, iconStroke = label("Icon", "", FONT_TITLE, 52, 0, 60)
local title, titleStroke = label("Title", "", FONT_TITLE, 56, 64, 66)
local sub, subStroke = label("Sub", "", FONT_SUB, 20, 168, 26)
sub.TextColor3 = Color3.fromRGB(205, 215, 235)
local line = Instance.new("Frame")
line.Name = "Line"
line.AnchorPoint = Vector2.new(0.5, 0)
line.Position = UDim2.new(0.5, 0, 0, 140)
line.Size = UDim2.fromOffset(0, 4)
line.BorderSizePixel = 0
line.BackgroundTransparency = 1
line.ZIndex = 6
Instance.new("UICorner").Parent = line
line.Parent = card

gui.Parent = player:WaitForChild("PlayerGui")

-- load the fonts / glyphs now, so the first title is not blank while the font streams in
task.spawn(function()
	icon.Text = "❄️🏰🏠☀️"
	title.Text = "Forgotten Castle Igloo Wood Cabin Pyramid Temple"
	sub.Text = "ENTERING"
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ icon, title, sub })
	end)
end)

local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(
		obj,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)
	tw:Play()
	return tw
end

local function setCardAlpha(a, t)
	for _, l in { icon, title, sub } do
		tween(l, t, { TextTransparency = a })
	end
	for _, s in { iconStroke, titleStroke, subStroke } do
		tween(s, t, { Transparency = a })
	end
	tween(line, t, { BackgroundTransparency = a })
end

---------------------------------------------------------------- state
local session = 0 -- bumps on every start; stale callbacks compare against it
local active = false
local phase = "idle" -- "out" (fading to black) / "black" / "in"
local promptsWere = true
local camTween: Tween? = nil
local cardShownAt = 0
local MIN_TITLE = 0.65 -- seconds the room name stays on the black screen

local function lockControls(on: boolean)
	if controls then
		pcall(function()
			if on then
				controls:Disable()
			else
				controls:Enable()
			end
		end)
	end
end

local function restore(id: number, arrivedCf: CFrame?)
	if id ~= session or not active or phase == "in" then
		return
	end
	phase = "in"
	local cam = workspace.CurrentCamera
	if camTween then
		camTween:Cancel()
		camTween = nil
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if root and arrivedCf then
		-- wait (briefly) until the server's move has replicated
		local t0 = os.clock()
		while (root.Position - arrivedCf.Position).Magnitude > 6 and os.clock() - t0 < 1 do
			task.wait()
		end
	end
	if root then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
		local focus = root.Position + Vector3.new(0, 1.5, 0)
		cam.CFrame = CFrame.lookAt(focus - flat * 12 + Vector3.new(0, 4.5, 0), focus + flat * 4)
	end
	if hum then
		cam.CameraSubject = hum
	end
	cam.CameraType = Enum.CameraType.Custom
	local spec = T.enter
	tween(black, spec.fadeIn, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for _, v in vignette do
		tween(v, spec.fadeIn + 0.3, { BackgroundTransparency = 1 })
	end
	setCardAlpha(1, spec.fadeIn * 0.7)
	tween(cardScale, spec.fadeIn, { Scale = 1.06 })
	lockControls(false)
	ProximityPromptService.Enabled = promptsWere
	task.delay(spec.fadeIn + 0.35, function()
		if id == session then
			active = false
			phase = "idle"
			gui.Enabled = false
		end
	end)
end

local function start(info)
	if active or type(info) ~= "table" then
		return
	end
	session += 1
	local id = session
	active = true
	phase = "out"
	local spec = if info.enter then T.enter else T.leave
	local lead = tonumber(info.lead) or 0.8

	promptsWere = ProximityPromptService.Enabled
	ProximityPromptService.Enabled = false
	lockControls(true)

	-- reset the overlay
	gui.Enabled = true
	black.BackgroundTransparency = 1
	for _, v in vignette do
		v.BackgroundTransparency = 1
	end
	setCardAlpha(1, 0)
	cardScale.Scale = 0.9
	line.Size = UDim2.fromOffset(0, 4)
	local roomKey = info.room
	icon.Text = (info.enter and ICONS[roomKey]) or ""
	title.Text = (info.enter and info.title) or ""
	sub.Text = info.enter and "ENTERING" or ""
	line.BackgroundColor3 = TINT[roomKey] or Color3.fromRGB(255, 255, 255)
	sub.Position = UDim2.new(0.5, 0, 0, 150)

	local cam = workspace.CurrentCamera
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local door = typeof(info.door) == "Vector3" and info.door or nil

	if root and door then
		local away = Vector3.new(root.Position.X - door.X, 0, root.Position.Z - door.Z)
		away = if away.Magnitude > 0.1 then away.Unit else -root.CFrame.LookVector
		-- a few steps towards the door (stop short of it)
		if hum and spec.walk then
			local dist = Vector3.new(root.Position.X - door.X, 0, root.Position.Z - door.Z).Magnitude
			local stopAt = math.min(dist, 3)
			local goal = Vector3.new(door.X, root.Position.Y, door.Z) + away * stopAt
			hum:MoveTo(goal)
		end
		-- camera: from wherever it is to a low shot behind the player, looking at the door
		local doorFocus = Vector3.new(door.X, math.max(door.Y, root.Position.Y) + 0.5, door.Z)
		local camPos = doorFocus + away * 11 + Vector3.new(0, 3, 0)
		cam.CameraType = Enum.CameraType.Scriptable
		camTween = tween(
			cam,
			spec.cam,
			{ CFrame = CFrame.lookAt(camPos, doorFocus) },
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		)
	end

	for _, v in vignette do
		tween(v, spec.fadeAt + 0.1, { BackgroundTransparency = 0.25 })
	end
	task.delay(spec.fadeAt, function()
		if id ~= session or phase ~= "out" then
			return
		end
		tween(black, spec.fade, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		task.delay(spec.fade, function()
			if id ~= session or phase ~= "out" then
				return
			end
			phase = "black"
			cardShownAt = os.clock()
			if info.enter then
				setCardAlpha(0, 0.3)
				tween(cardScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
				tween(line, 0.45, { Size = UDim2.fromOffset(220, 4) })
			end
		end)
	end)

	-- safety net: never stuck in black
	task.delay(math.max(MAX_BLACK, lead + 1.5), function()
		restore(id, nil)
	end)
end

local remotes = ReplicatedStorage:WaitForChild("InteriorDoorsRemotes", 60)
local remote = remotes and remotes:WaitForChild("Transition", 30) :: RemoteEvent?
if not remote then
	warn("[InteriorTransition] remote not found; doors will teleport without animation")
	return
end

remote.OnClientEvent:Connect(function(kind, payload)
	if kind == "start" then
		start(payload)
	elseif kind == "arrived" then
		local id = session
		local cf = typeof(payload) == "CFrame" and payload or nil
		task.spawn(function()
			-- the screen must be black first, and the room name must stay up for a beat
			local t0 = os.clock()
			while id == session and phase == "out" and os.clock() - t0 < 1 do
				task.wait()
			end
			if title.Text ~= "" then
				local left = MIN_TITLE - (os.clock() - cardShownAt)
				if left > 0 then
					task.wait(left)
				end
			else
				task.wait(0.1)
			end
			restore(id, cf)
		end)
	elseif kind == "cancel" then
		restore(session, nil)
	end
end)

player.CharacterAdded:Connect(function()
	if active then
		restore(session, nil)
	end
end)
