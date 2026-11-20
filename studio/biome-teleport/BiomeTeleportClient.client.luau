-- BiomeTeleportClient (StarterGui.BiomeTeleportGui): HUD button + biome travel panel.
-- Same look as the 1v1 button (StarterGui.MatchmakingGui). Every decision is made by
-- ServerScriptService.BiomeTeleportServer; this only asks and shows the answer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Core = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("DesignUI"):WaitForChild("Core")
local Theme = require(Core.Theme)
local Skin = require(Core.PvpSkin)

local player = Players.LocalPlayer
local gui = script.Parent :: ScreenGui
local Teleport = ReplicatedStorage:WaitForChild("BiomeTeleportRemotes"):WaitForChild("Teleport") :: RemoteEvent

local C = { Outline = Theme.Colors.Outline, Panel = Color3.fromRGB(16, 34, 52), Row = Color3.fromRGB(26, 52, 76),
	White = Theme.Colors.White, Muted = Theme.Colors.Muted, Gold = Theme.Colors.Gold, Red = Theme.Colors.Danger }
local G = Theme.Grad
local F = Theme.Fonts

local BIOMES = {
	{ id = "Lobby", name = "Lobby", emoji = "🏠", grad = G.Gold, maxX = 770 },
	{ id = "Forest", name = "Forest", emoji = "🌲", grad = G.Forest, maxX = 1060 },
	{ id = "Desert", name = "Desert", emoji = "🏜️", grad = G.Desert, maxX = 1308 },
	{ id = "Ice", name = "Ice", emoji = "❄️", grad = G.Heal, maxX = 1584 },
	{ id = "Kingdom", name = "Forgotten Kingdom", emoji = "🏰", grad = G.Purple, maxX = math.huge },
}

local canvas = Skin.Canvas(gui)
local function new(class: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	inst.Parent = props.Parent
	return inst
end
local function corner(r: number)
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end
local function stroke(t: number, col: Color3?)
	return new("UIStroke", { Thickness = t, Color = col or C.Outline, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function textStroke(t: number)
	return new("UIStroke", { Thickness = t, Color = C.Outline })
end
local function grad(pair)
	return new("UIGradient", { Color = ColorSequence.new(pair[1], pair[2]), Rotation = 90 })
end
local function text(props)
	props.BackgroundTransparency = 1
	props.TextScaled = props.TextScaled ~= false
	props.TextColor3 = props.TextColor3 or C.White
	props.FontFace = props.FontFace or F.Title
	local maxSize = props.MaxSize
	props.MaxSize = nil
	local l = new("TextLabel", props)
	if maxSize then
		new("UITextSizeConstraint", { MaxTextSize = maxSize, Parent = l })
	end
	return l
end
local function pressable(b: GuiButton)
	local scale = new("UIScale", { Parent = b })
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.05 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.94 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
end
local function button(parent: Instance, label: string, pair, size: UDim2, pos: UDim2, anchor: Vector2?): TextButton
	local b = new("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundColor3 = C.White, Size = size, Position = pos,
		AnchorPoint = anchor or Vector2.zero, Parent = parent,
	}, { corner(10), stroke(3), grad(pair) })
	local l = text({ Name = "Label", Text = label, Size = UDim2.new(1, -12, 1, -10), Position = UDim2.fromOffset(6, 5), MaxSize = 22, Parent = b, ZIndex = 2 })
	textStroke(2).Parent = l
	Skin.Plate(b)
	pressable(b)
	return b
end

--------------------------------------------------------------------------------------------
-- HUD button: right side, under the 1v1 button (which sits at the vertical centre)
--------------------------------------------------------------------------------------------
local hudButton = new("TextButton", {
	Name = "BiomeTeleportButton", Text = "", AutoButtonColor = false, BackgroundColor3 = C.White,
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0.5, 62), Size = UDim2.fromOffset(96, 96),
	Parent = canvas,
}, { corner(14), stroke(3), grad(G.Blue) })
pressable(hudButton)
Skin.Plate(hudButton)
local hudIcon = text({ Name = "Icon", Text = "🗺️", FontFace = F.Num, Size = UDim2.new(1, -20, 0, 50), Position = UDim2.fromOffset(10, 8), MaxSize = 48, ZIndex = 3, Parent = hudButton })
local hudLabel = text({ Name = "Label", Text = "Biomes", Size = UDim2.new(1, -8, 0, 24), Position = UDim2.new(0, 4, 1, -32), MaxSize = 22, ZIndex = 3, Parent = hudButton })
textStroke(2.5).Parent = hudLabel

--------------------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------------------
local dim = new("TextButton", {
	Name = "Dim", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5,
	Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 5, Parent = canvas,
})
local panel = new("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 400),
	BackgroundColor3 = C.Panel, ZIndex = 6, Parent = dim,
}, { corner(18), stroke(4) })
local panelScale = new("UIScale", { Parent = panel })
local header = new("Frame", { Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = C.White, ZIndex = 6, Parent = panel }, { corner(18), grad(G.Blue) })
new("Frame", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -18), BackgroundColor3 = G.Blue[2], BorderSizePixel = 0, ZIndex = 6, Parent = header })
Skin.Plate(header)
local title = text({ Text = "TRAVEL", Size = UDim2.new(1, -100, 0, 38), Position = UDim2.fromOffset(20, 12), MaxSize = 32, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = header })
textStroke(3).Parent = title
local close = button(header, "X", G.Close, UDim2.fromOffset(48, 48), UDim2.new(1, -56, 0, 7))
close.ZIndex = 7
local status = text({ Name = "Status", Text = "Pick a biome to travel to", FontFace = F.Bold, TextColor3 = C.Muted, Size = UDim2.new(1, -40, 0, 22), Position = UDim2.fromOffset(20, 72), MaxSize = 18, ZIndex = 7, Parent = panel })

local row = new("Frame", { Name = "Cards", Size = UDim2.new(1, -40, 1, -120), Position = UDim2.fromOffset(20, 104), BackgroundTransparency = 1, ZIndex = 6, Parent = panel }, {
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
})

local cards = {}
for i, b in ipairs(BIOMES) do
	local f = new("Frame", { Name = b.id, Size = UDim2.new(0.2, -8, 1, 0), BackgroundColor3 = C.Row, LayoutOrder = i, ZIndex = 7, Parent = row }, { corner(14), stroke(3) })
	new("Frame", { Name = "Band", Size = UDim2.new(1, 0, 0, 12), BackgroundColor3 = C.White, ZIndex = 8, Parent = f }, { corner(14), grad(b.grad) })
	local badge = new("Frame", { Name = "Badge", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromScale(0.72, 0.72), BackgroundColor3 = C.White, ZIndex = 8, Parent = f },
		{ corner(16), stroke(3), grad(b.grad), new("UIAspectRatioConstraint", { AspectRatio = 1 }), new("UISizeConstraint", { MaxSize = Vector2.new(84, 84) }) })
	text({ Name = "Emoji", Text = b.emoji, FontFace = F.Num, Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), MaxSize = 54, ZIndex = 9, Parent = badge })
	local name = text({ Name = "Title", Text = b.name, TextWrapped = true, Size = UDim2.new(1, -10, 0, 44), Position = UDim2.new(0, 5, 1, -112), MaxSize = 20, ZIndex = 8, Parent = f })
	textStroke(2).Parent = name
	local here = text({ Name = "Here", Text = "YOU ARE HERE", FontFace = F.Bold, TextColor3 = C.Gold, Size = UDim2.new(1, -10, 0, 14), Position = UDim2.new(0, 5, 1, -66), MaxSize = 12, Visible = false, ZIndex = 8, Parent = f })
	local go = button(f, "Teleport", b.grad, UDim2.new(1, -14, 0, 42), UDim2.new(0.5, 0, 1, -8), Vector2.new(0.5, 1))
	go.Name = "Teleport"
	go.ZIndex = 8
	Skin.Surface(f)
	f.BackgroundColor3 = C.Row
	cards[b.id] = { frame = f, go = go, here = here, badge = badge, name = name }
	go.MouseButton1Click:Connect(function()
		status.Text = "Teleporting to " .. b.name .. "..."
		status.TextColor3 = C.Muted
		Teleport:FireServer("go", b.id)
	end)
end

local panelHost, fitScale = Skin.Holder(dim, panel)
local function fit()
	local phone = canvas.AbsoluteSize.Y < 500
	local w, h = if phone then 720 else 640, if phone then 300 else 400
	panel.Size = UDim2.fromOffset(w, h)
	Skin.Fit(panelHost, fitScale, canvas, w, h)
	hudButton.Size = UDim2.fromOffset(if phone then 76 else 96, if phone then 76 else 96)
	hudButton.Position = UDim2.new(1, -14, 0.5, if phone then 56 else 62)
end
canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()

local function currentBiome(): string?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	for _, b in ipairs(BIOMES) do
		if root.Position.X < b.maxX then
			return b.id
		end
	end
	return nil
end
local function refreshHere()
	local here = currentBiome()
	for id, c in cards do
		c.here.Visible = id == here
	end
end

local panelOpen = false
local function openPanel()
	if workspace:GetAttribute("MM_ArenaServer") or workspace:FindFirstChild("MM_ArenaServer") then
		return
	end
	panelOpen = true
	refreshHere()
	status.Text = "Pick a biome to travel to"
	status.TextColor3 = C.Muted
	dim.Visible = true
	panelScale.Scale = 0.85
	TweenService:Create(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end
local function closePanel()
	panelOpen = false
	dim.Visible = false
end
hudButton.MouseButton1Click:Connect(function()
	if panelOpen then
		closePanel()
	else
		openPanel()
	end
end)
close.MouseButton1Click:Connect(closePanel)

Teleport.OnClientEvent:Connect(function(kind, ok, msg)
	if kind ~= "result" then
		return
	end
	status.Text = tostring(msg or "")
	status.TextColor3 = if ok then C.Gold else C.Red
	if ok then
		refreshHere()
		task.delay(0.6, closePanel)
	end
end)

-- no travel button inside an arena server
local function arenaCheck()
	local arena = workspace:GetAttribute("MM_ArenaServer") or workspace:FindFirstChild("MM_ArenaServer")
	hudButton.Visible = not arena
	if arena and panelOpen then
		closePanel()
	end
end
workspace:GetAttributeChangedSignal("MM_ArenaServer"):Connect(arenaCheck)
workspace.ChildAdded:Connect(arenaCheck)
arenaCheck()
