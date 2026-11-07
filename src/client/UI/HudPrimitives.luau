--!strict
-- Native approximation of the supplied HUD: dark outlines, Fredoka, saturated raised faces.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Images = require(ReplicatedStorage.Shared.Config.HudImages)
local Feedback = require(script.Parent.HudFeedback)
local P = {}
P.colors = {
	Pets = Color3.fromRGB(247, 150, 43),
	Index = Color3.fromRGB(47, 166, 230),
	Research = Color3.fromRGB(214, 71, 154),
	Trade = Color3.fromRGB(68, 185, 68),
	Shop = Color3.fromRGB(214, 63, 59),
	Leaderboard = Color3.fromRGB(108, 109, 113),
	Settings = Color3.fromRGB(108, 109, 113),
	panel = Color3.fromRGB(32, 34, 40),
	gold = Color3.fromRGB(255, 210, 60),
}
function P.Frame(parent: Instance, name: string, color: Color3?, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or P.colors.panel
	f.BackgroundTransparency = transparency or 0
	f.Parent = parent
	return f
end
function P.Round(object: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = object
end
function P.Stroke(object: GuiObject, thickness: number?, color: Color3?)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color or Color3.fromRGB(13, 17, 25)
	s.Thickness = thickness or 3
	s.Parent = object
	return s
end
function P.Text(parent: Instance, name: string, text: string, size: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = text
	l.TextSize = math.max(12, size or 18)
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = Color3.new(1, 1, 1)
	l.BackgroundTransparency = 1
	l.TextStrokeColor3 = Color3.fromRGB(13, 17, 25)
	l.TextStrokeTransparency = 0.15
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end
function P.Image(parent: Instance, key: string): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = key
	i.BackgroundTransparency = 1
	i.Image = Images[key] or ""
	i.ScaleType = Enum.ScaleType.Fit
	i.Parent = parent
	return i
end
-- The export's tiny repeated stud relief is reconstructed natively; no missing texture id.
function P.Studs(parent: GuiObject)
	local holder = P.Frame(parent, "StudRelief", nil, 1)
	holder.Size = UDim2.fromScale(1, 1)
	holder.ClipsDescendants = true
	local marks = {}
	for i = 1, 48 do
		local mark = P.Frame(holder, "Stud", Color3.new(1, 1, 1), 0.88)
		P.Round(mark, 2)
		marks[i] = mark
	end
	local function place()
		local width, height = holder.AbsoluteSize.X, holder.AbsoluteSize.Y
		local columns = math.max(1, math.ceil(width / 30))
		for i, mark in marks do
			local x, y = ((i - 1) % columns) * 30 + 7, math.floor((i - 1) / columns) * 24 + 4
			mark.Position = UDim2.fromOffset(x, y)
			mark.Size = UDim2.fromOffset(18, 6)
			mark.Visible = x + 18 <= width and y + 6 <= height
		end
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()
end
function P.Button(parent: Instance, name: string, label: string, color: Color3?, icon: string?)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	b.Selectable = true
	P.Round(b)
	P.Stroke(b)
	P.Studs(b)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, (color or P.colors.Trade):Lerp(Color3.new(1, 1, 1), 0.23)),
		ColorSequenceKeypoint.new(1, color or P.colors.Trade),
	})
	g.Rotation = 90
	g.Parent = b
	local feedbackFace = P.Frame(b, "Feedback", Color3.new(1, 1, 1), 1)
	feedbackFace.Size = UDim2.fromScale(1, 1)
	P.Round(feedbackFace)
	local lip = P.Frame(b, "Lip", Color3.new(0, 0, 0), 0.7)
	lip.Size = UDim2.new(1, -8, 0, 5)
	lip.Position = UDim2.new(0, 4, 1, -8)
	local l = P.Text(b, "Label", label, 18)
	l.Size = UDim2.new(1, -12, 1, -8)
	l.Position = UDim2.fromOffset(6, 2)
	if icon then
		local i = P.Image(b, icon)
		i.Size = UDim2.new(1, -8, 0.72, 0)
		i.Position = UDim2.fromOffset(4, -3)
		l.Position = UDim2.new(0, 4, 0.72, -2)
		l.Size = UDim2.new(1, -8, 0.28, 0)
	end
	local focus = Instance.new("Frame")
	focus.Name = "Focus"
	focus.BackgroundTransparency = 1
	focus.Size = UDim2.new(1, 8, 1, 8)
	focus.Position = UDim2.fromOffset(-4, -4)
	P.Round(focus)
	P.Stroke(focus, 3, P.colors.gold)
	focus.Visible = false
	focus.Parent = b
	b.SelectionGained:Connect(function()
		focus.Visible = true
	end)
	b.SelectionLost:Connect(function()
		focus.Visible = false
	end)
	b.Parent = parent
	Feedback.Bind(b, feedbackFace, lip)
	return b, l
end
function P.Recolor(button: GuiButton, color: Color3)
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.23), color)
	end
end
function P.Place(object: GuiObject, r: { x: number, y: number, w: number, h: number })
	object.Position = UDim2.fromOffset(r.x, r.y)
	object.Size = UDim2.fromOffset(r.w, r.h)
end
function P.Bar(parent: Instance, name: string, color: Color3?)
	local track = P.Frame(parent, name, Color3.fromRGB(28, 28, 32))
	P.Round(track)
	P.Stroke(track, 2)
	local fill = P.Frame(track, "Fill", color or Color3.fromRGB(64, 178, 255))
	P.Round(fill)
	fill.Size = UDim2.fromScale(0, 1)
	return track, fill
end
function P.MotionAllowed(): boolean
	return not GuiService.ReducedMotionEnabled
end
return P
