--!strict
-- One look for every GUI: "stud style". Chunky square-ish frames with a
-- thick black outline and a lighter inner border, saturated colours with a
-- tiled stud texture and diagonal stripes, white cartoon text with a black
-- outline. Windows have a coloured header with an icon badge and a red X.
-- Everything animates: windows pop in and out, buttons grow on hover and
-- squash on press, menu buttons' stripes drift.
-- Build GUIs through these helpers instead of styling by hand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Sfx = require(ReplicatedStorage.Shared.Sfx)

local UITheme = {}

UITheme.font = Enum.Font.FredokaOne

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Colour pairs { top, bottom } by kind. The old names (info, warning,
-- success, action, disabled) map onto the stud palette.
local KINDS: { [string]: { Color3 } } = {
	green = { rgb(92, 224, 74), rgb(34, 164, 46) },
	blue = { rgb(64, 178, 255), rgb(24, 104, 214) },
	red = { rgb(255, 72, 72), rgb(196, 22, 34) },
	orange = { rgb(255, 196, 64), rgb(250, 120, 18) },
	yellow = { rgb(255, 228, 72), rgb(214, 170, 20) },
	pink = { rgb(255, 92, 196), rgb(212, 30, 140) },
	purple = { rgb(176, 98, 255), rgb(118, 46, 214) },
	grey = { rgb(150, 154, 166), rgb(92, 96, 108) },
	dark = { rgb(70, 70, 78), rgb(44, 44, 50) },
}

UITheme.colors = {
	outline = rgb(18, 18, 22), -- black line art
	text = Color3.new(1, 1, 1),
	panelTop = rgb(70, 70, 78), -- window body
	panelBottom = rgb(44, 44, 50),
	panelBorder = rgb(108, 108, 116), -- the lighter inner border
	cash = rgb(110, 240, 70),
	gold = rgb(255, 214, 60),
	speed = rgb(70, 200, 255),
	info = KINDS.blue,
	warning = KINDS.red,
	success = KINDS.green,
	action = KINDS.orange,
	disabled = KINDS.grey,
	green = KINDS.green,
	blue = KINDS.blue,
	red = KINDS.red,
	orange = KINDS.orange,
	yellow = KINDS.yellow,
	pink = KINDS.pink,
	purple = KINDS.purple,
	grey = KINDS.grey,
	dark = KINDS.dark,
	-- research tree categories (tints the white hexagon tile)
	research = {
		Economy = rgb(70, 205, 85),
		Defense = rgb(55, 165, 235),
		Utility = rgb(175, 75, 215),
		Locked = rgb(85, 90, 108),
	} :: { [string]: Color3 },
}

UITheme.outlineThickness = 3
UITheme.cornerRadius = 6

-- Decorations (studs, inner border, shade) live in a Folder so list and
-- grid layouts inside the frame never move them around.
local function decor(parent: GuiObject): Folder
	local folder = parent:FindFirstChild("Decor")
	if folder and folder:IsA("Folder") then
		return folder
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "Decor"
	newFolder.Parent = parent
	return newFolder
end

local function colorsOf(kind: string?): { Color3 }
	return if kind then (UITheme.colors :: any)[kind] or KINDS.dark else KINDS.dark
end

function UITheme.Corner(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or UITheme.cornerRadius)
	corner.Parent = parent
end

function UITheme.Outline(parent: GuiObject, thickness: number?, color: Color3?)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or UITheme.outlineThickness
	stroke.Color = color or UITheme.colors.outline
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
end

function UITheme.Gradient(parent: GuiObject, top: Color3, bottom: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = 90
	gradient.Parent = parent
end

-- A soft white band along the top (glossy look).
function UITheme.Shine(parent: GuiObject, height: number?)
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.8
	shine.BorderSizePixel = 0
	shine.Position = UDim2.fromOffset(4, 3)
	shine.Size = UDim2.new(1, -8, 0, height or 8)
	shine.ZIndex = (parent.ZIndex or 1) + 1
	UITheme.Corner(shine, 3)
	shine.Parent = parent
end

-- The tiled stud texture over a frame (needs the uploaded "stud_tile"; in
-- Studio a local preview). Without it the frame stays a plain gradient.
function UITheme.Studs(parent: GuiObject, tileSize: number?, transparency: number?)
	local id = UITheme.IconId("stud_tile")
	if not id then
		return
	end
	local studs = Instance.new("ImageLabel")
	studs.Name = "Studs"
	studs.BackgroundTransparency = 1
	studs.Image = id
	studs.ScaleType = Enum.ScaleType.Tile
	studs.TileSize = UDim2.fromOffset(tileSize or 26, tileSize or 26)
	studs.ImageTransparency = transparency or 0
	studs.Size = UDim2.fromScale(1, 1)
	studs.ZIndex = parent.ZIndex
	studs.Parent = decor(parent)
	local corner = parent:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = studs
	end
end

-- The lighter inner border every stud frame has.
function UITheme.InnerBorder(parent: GuiObject, color: Color3?, inset: number?)
	local border = Instance.new("Frame")
	border.Name = "InnerBorder"
	border.BackgroundTransparency = 1
	border.Position = UDim2.fromOffset(inset or 3, inset or 3)
	border.Size = UDim2.new(1, -2 * (inset or 3), 1, -2 * (inset or 3))
	border.ZIndex = parent.ZIndex
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = color or Color3.new(1, 1, 1)
	stroke.Transparency = if color then 0 else 0.55
	stroke.Parent = border
	UITheme.Corner(border, math.max(0, UITheme.cornerRadius - 2))
	border.Parent = decor(parent)
end

-- Depth (from the Figma kit): a darker lip along the bottom and a thin
-- highlight along the top, like a moulded plastic button.
local function lipColor(colors: { Color3 }): Color3
	return colors[2]:Lerp(Color3.new(0, 0, 0), 0.25)
end
function UITheme.Lip(parent: GuiObject, colors: { Color3 })
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.BorderSizePixel = 0
	lip.BackgroundColor3 = lipColor(colors)
	lip.AnchorPoint = Vector2.new(0, 1)
	lip.Position = UDim2.fromScale(0, 1)
	lip.Size = UDim2.new(1, 0, 0, 5)
	lip.ZIndex = parent.ZIndex
	UITheme.Corner(lip, UITheme.cornerRadius)
	lip.Parent = decor(parent)
	local shine = Instance.new("Frame")
	shine.Name = "Highlight"
	shine.BorderSizePixel = 0
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.65
	shine.Position = UDim2.fromOffset(6, 3)
	shine.Size = UDim2.new(1, -12, 0, 3)
	shine.ZIndex = parent.ZIndex
	UITheme.Corner(shine, 2)
	shine.Parent = decor(parent)
end

-- Diagonal stripes in two shades of a colour (the menu buttons' look).
-- Animated stripes drift slowly (see the loop at the end of this module).
local drifting: { UIGradient } = {}
function UITheme.Stripes(parent: GuiObject, colors: { Color3 }, animated: boolean?): UIGradient
	local light = colors[1]:Lerp(Color3.new(1, 1, 1), 0.18)
	local base = colors[1]
	local points = {}
	local stripes = 9
	for i = 0, stripes - 1 do
		local from = i / stripes
		local to = (i + 1) / stripes
		local color = if i % 2 == 0 then base else light
		table.insert(points, ColorSequenceKeypoint.new(from, color))
		table.insert(points, ColorSequenceKeypoint.new(math.min(1, to - 0.001), color))
	end
	points[#points] = ColorSequenceKeypoint.new(1, points[#points].Value)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Stripes"
	gradient.Color = ColorSequence.new(points)
	gradient.Rotation = 45
	gradient.Parent = parent
	if animated and RunService:IsClient() then
		table.insert(drifting, gradient)
	end
	-- Darker towards the bottom.
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.BackgroundColor3 = colors[2]
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = parent.ZIndex
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.45, 0.85),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	fade.Parent = shade
	local corner = parent:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = shade
	end
	shade.Parent = decor(parent)
	return gradient
end

-- A stud frame. kind = nil for the dark window body; a colour kind
-- ("green", "blue"... or "info", "warning", "success", "action") for a
-- coloured panel.
function UITheme.Panel(kind: string?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	local colors = colorsOf(kind)
	UITheme.Corner(frame)
	UITheme.Gradient(frame, colors[1], colors[2])
	UITheme.Outline(frame)
	UITheme.Studs(frame, 28, if kind then 0.15 else 0.55)
	UITheme.InnerBorder(frame, if kind then nil else UITheme.colors.panelBorder)
	return frame
end

-- White cartoon text with a black outline.
function UITheme.Label(text: string, size: number, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = UITheme.font
	label.Text = text
	label.TextSize = size
	label.TextColor3 = color or UITheme.colors.text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = math.max(1.5, size / 9)
	stroke.Color = UITheme.colors.outline
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return label
end

-- Text that shrinks to fit its box, but never grows past `max`.
function UITheme.FitText(label: TextLabel, max: number)
	label.TextScaled = true
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 12
	constraint.MaxTextSize = math.max(12, max)
	constraint.Parent = label
end

-- Changes a Panel/Button's colours (e.g. to grey it out).
function UITheme.Recolor(frame: GuiObject, colors: { Color3 })
	for _, gradient in frame:GetChildren() do
		if gradient:IsA("UIGradient") and gradient.Name ~= "Stripes" then
			gradient.Color = ColorSequence.new(colors[1], colors[2])
		end
	end
	local folder = frame:FindFirstChild("Decor")
	local lip = folder and folder:FindFirstChild("Lip")
	if lip and lip:IsA("Frame") then
		lip.BackgroundColor3 = lipColor(colors)
	end
end

-- A stud button with a centred, fitting label.
-- kind = "green" | "blue" | "red" | "orange" | ... (or the old names).
function UITheme.Button(kind: string, size: UDim2, text: string?): (TextButton, TextLabel)
	local button = Instance.new("TextButton")
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.BorderSizePixel = 0
	button.Size = size
	local colors = colorsOf(kind)
	UITheme.Corner(button)
	UITheme.Gradient(button, colors[1], colors[2])
	UITheme.Outline(button)
	UITheme.Studs(button, 22, 0.2)
	UITheme.InnerBorder(button)
	UITheme.Lip(button, colors)
	local label = UITheme.Label(text or "", 22)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	UITheme.FitText(label, 22)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = label
	label.Parent = button
	UITheme.Pressable(button)
	return button, label
end

-- Buttons grow a little on hover and squash when pressed (client only).
function UITheme.Pressable(button: GuiButton, hoverScale: number?)
	if not RunService:IsClient() then
		return
	end
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local hover = false
	local function to(value: number, time: number?)
		TweenService:Create(scale, TweenInfo.new(time or 0.1, Enum.EasingStyle.Quad), { Scale = value })
			:Play()
	end
	button.MouseEnter:Connect(function()
		hover = true
		to(hoverScale or 1.05)
	end)
	button.MouseLeave:Connect(function()
		hover = false
		to(1)
	end)
	button.MouseButton1Down:Connect(function()
		to(0.9, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(
			scale,
			TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = if hover then hoverScale or 1.05 else 1 }
		):Play()
	end)
	button.Activated:Connect(function()
		Sfx.Play("click")
	end)
end

-- A square menu button: striped colour, studs, icon on top, name below.
-- The icon sways on hover. iconKey can be an uploaded UI icon or an emoji.
function UITheme.MenuButton(iconKey: string, name: string, kind: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	button.BorderSizePixel = 0
	button.Size = UDim2.fromOffset(88, 88)
	local colors = colorsOf(kind)
	UITheme.Corner(button, 5)
	UITheme.Stripes(button, colors, true)
	UITheme.Outline(button)
	UITheme.Studs(button, 22, 0.35)
	UITheme.InnerBorder(button)
	UITheme.Lip(button, colors)

	local icon: GuiObject
	local image = UITheme.Icon(iconKey, 60)
	if image then
		icon = image
	else
		local emoji = Instance.new("TextLabel")
		emoji.BackgroundTransparency = 1
		emoji.Text = iconKey
		emoji.TextScaled = true
		emoji.Size = UDim2.fromOffset(52, 52)
		icon = emoji
	end
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.42)
	icon.ZIndex = 4
	icon.Parent = button

	local label = UITheme.Label(name, 20)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -2)
	label.Size = UDim2.new(1, -4, 0, 24)
	label.ZIndex = 5
	UITheme.FitText(label, 20)
	label.Parent = button

	UITheme.Pressable(button, 1.08)
	if RunService:IsClient() then
		button.MouseEnter:Connect(function()
			local sway = TweenService:Create(
				icon,
				TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true),
				{ Rotation = 10 }
			)
			icon.Rotation = -10
			sway:Play()
			sway.Completed:Once(function()
				TweenService:Create(icon, TweenInfo.new(0.1), { Rotation = 0 }):Play()
			end)
		end)
	end
	return button
end

export type Window = {
	frame: Frame,
	body: Frame,
	title: TextLabel,
	close: TextButton,
	isOpen: () -> boolean,
	open: () -> (),
	shut: () -> (),
	onClosed: (callback: () -> ()) -> (),
}

-- A window: coloured header with an icon badge sticking out on the left,
-- the title, and a red X; under it the dark stud body. Pops in with a
-- bounce and shrinks away when closed.
function UITheme.Window(parent: Instance, title: string, iconKey: string, kind: string, size: Vector2): Window
	local frame = Instance.new("Frame")
	frame.Name = title
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.52)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	frame.Parent = parent

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = Color3.new(1, 1, 1)
	header.Size = UDim2.new(1, -66, 0, 58)
	header.Position = UDim2.fromOffset(0, 0)
	header.ZIndex = 2
	local colors = colorsOf(kind)
	UITheme.Corner(header, 4)
	UITheme.Gradient(header, colors[1], colors[2])
	UITheme.Outline(header)
	UITheme.Studs(header, 24, 0.2)
	UITheme.InnerBorder(header)
	header.Parent = frame

	local titleLabel = UITheme.Label(title, 34)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Position = UDim2.fromOffset(88, 0)
	titleLabel.Size = UDim2.new(1, -96, 1, 0)
	titleLabel.ZIndex = 4
	UITheme.FitText(titleLabel, 34)
	titleLabel.Parent = header

	local badge = UITheme.Icon(iconKey, 84)
	if badge then
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.fromOffset(38, 22)
		badge.ZIndex = 6
		badge.Parent = frame
	end

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = ""
	close.AutoButtonColor = false
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(60, 58)
	close.BackgroundColor3 = Color3.new(1, 1, 1)
	close.ZIndex = 2
	UITheme.Corner(close, 4)
	UITheme.Gradient(close, KINDS.red[1], KINDS.red[2])
	UITheme.Outline(close)
	UITheme.Studs(close, 20, 0.15)
	UITheme.InnerBorder(close)
	local x = UITheme.Label("X", 40)
	x.Size = UDim2.fromScale(1, 1)
	x.ZIndex = 4
	x.Parent = close
	UITheme.Pressable(close, 1.1)
	close.Parent = frame

	local body = UITheme.Panel(nil)
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, 64)
	body.Size = UDim2.new(1, 0, 1, -64)
	body.Parent = frame
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(14, 14)
	content.Size = UDim2.new(1, -28, 1, -28)
	content.ZIndex = 3
	content.Parent = body

	local opened = false
	local closedCallbacks: { () -> () } = {}
	local window: Window
	window = {
		frame = frame,
		body = content,
		title = titleLabel,
		close = close,
		isOpen = function()
			return opened
		end,
		open = function()
			if opened then
				return
			end
			opened = true
			frame.Visible = true
			scale.Scale = 0.55
			frame.Rotation = -3
			TweenService
				:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				})
				:Play()
			TweenService
				:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Rotation = 0,
				})
				:Play()
			Sfx.Play("open")
		end,
		shut = function()
			if not opened then
				return
			end
			opened = false
			local shrink = TweenService:Create(
				scale,
				TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Scale = 0.7 }
			)
			shrink:Play()
			shrink.Completed:Once(function()
				if not opened then
					frame.Visible = false
				end
			end)
			for _, callback in closedCallbacks do
				task.spawn(callback)
			end
		end,
		onClosed = function(callback: () -> ())
			table.insert(closedCallbacks, callback)
		end,
	}
	close.Activated:Connect(window.shut)
	return window
end

-- A horizontal slider 0..1 (green fill, white knob). Returns the frame and
-- a setter; onChange fires while dragging.
function UITheme.Slider(initial: number, onChange: (number) -> ()): (Frame, (number) -> ())
	local track = Instance.new("Frame")
	track.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
	track.Size = UDim2.fromOffset(200, 30)
	UITheme.Corner(track, 4)
	UITheme.Outline(track)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.Size = UDim2.fromScale(initial, 1)
	UITheme.Corner(fill, 3)
	UITheme.Gradient(fill, KINDS.green[1], KINDS.green[2])
	fill.Parent = track
	local knob = Instance.new("TextButton")
	knob.Text = ""
	knob.AutoButtonColor = false
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(initial, 0.5)
	knob.Size = UDim2.fromOffset(30, 44)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.ZIndex = 3
	UITheme.Corner(knob, 4)
	UITheme.Gradient(knob, KINDS.green[1], KINDS.green[2])
	UITheme.Outline(knob)
	UITheme.InnerBorder(knob)
	knob.Parent = track

	local value = initial
	local function set(newValue: number)
		value = math.clamp(newValue, 0, 1)
		fill.Size = UDim2.fromScale(value, 1)
		knob.Position = UDim2.fromScale(value, 0.5)
	end
	if RunService:IsClient() then
		local UserInputService = game:GetService("UserInputService")
		local dragging = false
		local function fromInput(input: InputObject)
			local x = (input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
			set(x)
			onChange(value)
		end
		local function begin(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = true
				fromInput(input)
			end
		end
		knob.InputBegan:Connect(begin)
		track.InputBegan:Connect(begin)
		UserInputService.InputChanged:Connect(function(input)
			if
				dragging
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				fromInput(input)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragging = false
			end
		end)
	end
	return track, set
end

-- An on/off switch (green ON, grey OFF) that slides.
function UITheme.Toggle(initial: boolean, onChange: (boolean) -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(110, 44)
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	UITheme.Corner(button, 4)
	UITheme.Gradient(button, KINDS.green[1], KINDS.green[2])
	UITheme.Outline(button)
	UITheme.InnerBorder(button)
	local label = UITheme.Label("", 22)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	label.Parent = button
	UITheme.Pressable(button)
	local on = initial
	local function show()
		label.Text = if on then "ON" else "OFF"
		UITheme.Recolor(button, if on then KINDS.green else KINDS.grey)
	end
	show()
	button.Activated:Connect(function()
		on = not on
		show()
		onChange(on)
	end)
	return button
end

-- Returns the asset id for an icon key, or nil when it is not uploaded yet.
-- In Studio (debug on) a missing id falls back to a local preview copy made
-- by scripts/studio-icon-preview.sh; players never get that fallback.
function UITheme.IconId(key: string): string?
	local id = Config.UI.icons[key]
	if id == nil then
		return nil
	end
	if id ~= "" then
		return id
	end
	return if Config.Debug.enabled then `rbxasset://freeapet/{key}.png` else nil
end

-- An ImageLabel for an icon key, or nil when the icon is not uploaded yet.
function UITheme.Icon(key: string, size: number): ImageLabel?
	local id = UITheme.IconId(key)
	if not id then
		return nil
	end
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = id
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Size = UDim2.fromOffset(size, size)
	return icon
end

-- Drifting stripes: one cheap loop for every animated menu button.
if RunService:IsClient() then
	task.spawn(function()
		while true do
			local offset = (os.clock() * 0.06) % (2 / 9)
			for i = #drifting, 1, -1 do
				local gradient = drifting[i]
				if gradient.Parent then
					gradient.Offset = Vector2.new(offset, 0)
				else
					table.remove(drifting, i)
				end
			end
			task.wait(1 / 30)
		end
	end)
end

return UITheme
