-- BiomeTeleportClient (StarterGui.BiomeTeleportGui): "Travel" HUD button + travel panel.
-- The Travel button takes the place of the HUD's green "Base" button (top centre): at runtime
-- it hides PlayerGui...HUD.Base and puts a copy of it, labelled "Travel", in the same spot.
-- The HUD scripts are not edited. Going to your own base moved into the panel ("My Base" card).
-- Every decision is made by ServerScriptService.BiomeTeleportServer; this only asks and shows the answer.
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
	{ id = "Base", name = "My Base", emoji = "🏠", image = "74579908738802", grad = G.Green, zone = nil },
	{ id = "Lobby", name = "Lobby", emoji = "⛲", image = "77141567044546", grad = G.Gold, zone = "Base" },
	{ id = "Forest", name = "Forest", emoji = "🌲", image = "118986846511929", grad = G.Forest, zone = "Forest" },
	{ id = "Desert", name = "Desert", emoji = "🏜️", image = "130846288095244", grad = G.Desert, zone = "Desert" },
	{ id = "Ice", name = "Ice", emoji = "❄️", image = "126009387604003", grad = G.Heal, zone = "Ice" },
	{ id = "Kingdom", name = "Forgotten Kingdom", emoji = "🏰", image = "96027797689391", grad = G.Purple, zone = "Kingdom" },
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
-- Fallback HUD button (only used if the HUD's Base button never shows up): top centre.
--------------------------------------------------------------------------------------------
local hudButton = new("TextButton", {
	Name = "BiomeTeleportButton", Text = "", AutoButtonColor = false, BackgroundColor3 = C.White,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(240, 62),
	Visible = false, Parent = canvas,
}, { corner(10), stroke(3), grad(G.Green) })
pressable(hudButton)
Skin.Plate(hudButton)
local hudLabel = text({ Name = "Label", Text = "Travel", Size = UDim2.new(1, -16, 1, -12), Position = UDim2.fromOffset(8, 6), MaxSize = 36, ZIndex = 3, Parent = hudButton })
textStroke(3).Parent = hudLabel

--------------------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------------------
local dim = new("TextButton", {
	Name = "Dim", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5,
	Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 5, Parent = canvas,
})
local panel = new("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(860, 560),
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
local status = text({ Name = "Status", Text = "Pick where to travel", FontFace = F.Bold, TextColor3 = C.Muted, Size = UDim2.new(1, -40, 0, 22), Position = UDim2.fromOffset(20, 72), MaxSize = 18, ZIndex = 7, Parent = panel })

-- 3 x 2 grid of picture cards (one photo of each island, taken in Studio: build/travel-ui in the main repo)
local grid = new("Frame", { Name = "Cards", Size = UDim2.new(1, -40, 1, -122), Position = UDim2.fromOffset(20, 104), BackgroundTransparency = 1, ZIndex = 6, Parent = panel }, {
	new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -10, 0.5, -7), CellPadding = UDim2.fromOffset(14, 14), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center }),
})

local function goTo(b)
	if player:GetAttribute("TravelPortalActive") then
		return -- a trip is already playing (TravelPortalClient)
	end
	status.Text = "Teleporting to " .. b.name .. "..."
	status.TextColor3 = C.Muted
	Teleport:FireServer("go", b.id)
end

local IMG_ZOOM = 1.1 -- hover zoom of the photo
local cards = {}
for i, b in ipairs(BIOMES) do
	-- holder: carries the biome-coloured border; the CanvasGroup inside clips the photo to round corners
	local f = new("Frame", { Name = b.id, BackgroundColor3 = b.grad[2], LayoutOrder = i, ZIndex = 7, Parent = grid }, { corner(16) })
	local border = new("UIStroke", { Thickness = 4, Color = b.grad[1], ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f })
	local group = new("CanvasGroup", { Name = "Clip", Size = UDim2.fromScale(1, 1), BackgroundColor3 = b.grad[2], ZIndex = 7, Parent = f }, { corner(16) })
	local photo = new("ImageLabel", {
		Name = "Photo", Image = "rbxassetid://" .. b.image, ScaleType = Enum.ScaleType.Crop, BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = group,
	})
	-- dark fade at the bottom so the name and button read on any picture
	new("Frame", { Name = "Shade", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.62),
		BackgroundColor3 = Color3.fromRGB(8, 14, 26), BorderSizePixel = 0, ZIndex = 8, Parent = group }, {
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.55, 0.35), NumberSequenceKeypoint.new(1, 0.1) }) }),
	})
	-- biome colour strip across the top
	new("Frame", { Name = "Band", Size = UDim2.new(1, 0, 0, 7), BackgroundColor3 = C.White, BorderSizePixel = 0, ZIndex = 9, Parent = group }, { grad(b.grad) })
	local glow = new("Frame", { Name = "Glow", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.White, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 9, Parent = group })

	-- the whole picture is clickable too
	local hit = new("TextButton", { Name = "Hit", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = f })

	local name = text({ Name = "Title", Text = string.upper(b.name), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1), Size = UDim2.new(1, -20, 0.24, 0), Position = UDim2.new(0, 10, 1, -54), MaxSize = 28, ZIndex = 11, Parent = f })
	textStroke(3).Parent = name
	local here = new("Frame", { Name = "HereTag", Position = UDim2.fromOffset(8, 14), Size = UDim2.fromOffset(112, 22), BackgroundColor3 = C.Gold, Visible = false, ZIndex = 11, Parent = f },
		{ corner(11), stroke(2) })
	local hereText = text({ Name = "Here", Text = "YOU ARE HERE", FontFace = F.Bold, TextColor3 = C.Outline, Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), MaxSize = 12, ZIndex = 12, Parent = here })
	local go = button(f, if b.id == "Base" then "Go home" else "Travel", b.grad, UDim2.new(1, -16, 0, 40), UDim2.new(0.5, 0, 1, -8), Vector2.new(0.5, 1))
	go.Name = "Teleport"
	go.ZIndex = 11
	for _, d in go:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = math.max(d.ZIndex, 12)
		end
	end
	cards[b.id] = { frame = f, go = go, here = here, hereText = hereText, name = name }

	local hovered = false
	local function hover(on: boolean)
		if hovered == on then
			return
		end
		hovered = on
		local ti = TweenInfo.new(0.18, Enum.EasingStyle.Quad)
		local z = if on then IMG_ZOOM else 1
		TweenService:Create(photo, ti, { Size = UDim2.fromScale(z, z) }):Play()
		TweenService:Create(glow, ti, { BackgroundTransparency = if on then 0.88 else 1 }):Play()
		TweenService:Create(border, ti, { Thickness = if on then 6 else 4, Color = if on then C.White else b.grad[1] }):Play()
	end
	hit.MouseEnter:Connect(function()
		hover(true)
	end)
	hit.MouseLeave:Connect(function()
		hover(false)
	end)
	go.MouseEnter:Connect(function()
		hover(true)
	end)
	hit.MouseButton1Click:Connect(function()
		goTo(b)
	end)
	go.MouseButton1Click:Connect(function()
		goTo(b)
	end)
end

local panelHost, fitScale = Skin.Holder(dim, panel)
local function fit()
	local phone = canvas.AbsoluteSize.Y < 500
	local w, h = if phone then 900 else 860, if phone then 430 else 560
	panel.Size = UDim2.fromOffset(w, h)
	Skin.Fit(panelHost, fitScale, canvas, w, h)
end
canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()

-- Biomes are separate islands now: use the Zone attribute set by ZoneService (Map.Zones).
local function currentBiome(): string?
	local zone = player:GetAttribute("Zone")
	for _, b in ipairs(BIOMES) do
		if b.zone ~= nil and zone == b.zone then
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
player:GetAttributeChangedSignal("Zone"):Connect(refreshHere)

local panelOpen = false
local function openPanel()
	if workspace:GetAttribute("MM_ArenaServer") or workspace:FindFirstChild("MM_ArenaServer") then
		return
	end
	panelOpen = true
	refreshHere()
	status.Text = "Pick where to travel"
	status.TextColor3 = C.Muted
	dim.Visible = true
	panelScale.Scale = 0.85
	TweenService:Create(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end
local function closePanel()
	panelOpen = false
	dim.Visible = false
end
local function togglePanel()
	if panelOpen then
		closePanel()
	else
		openPanel()
	end
end
hudButton.MouseButton1Click:Connect(togglePanel)
close.MouseButton1Click:Connect(closePanel)

Teleport.OnClientEvent:Connect(function(kind, ok, msg)
	if kind == "start" then
		closePanel() -- the portal animation takes over (StarterPlayerScripts.TravelPortalClient)
		return
	end
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

--------------------------------------------------------------------------------------------
-- Travel button in the HUD: replaces the HUD's "Base" button (same place, size and look)
--------------------------------------------------------------------------------------------
local isArena = false
local hudBase: Frame? = nil -- the HUD's own Base plate (kept hidden)
local travel: Frame? = nil -- our copy of it, labelled "Travel"
local baseConn: RBXScriptConnection? = nil

local function findHudBase(): Frame?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	for _, d in pg:GetDescendants() do
		if d.Name == "Base" and d:IsA("Frame") and d.Parent and d.Parent.Name == "HUD" and not d:IsDescendantOf(gui) then
			return d
		end
	end
	-- fallback: any HUD plate whose label says "Base"
	for _, d in pg:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "Base" and not d:IsDescendantOf(gui) then
			local plate = d:FindFirstAncestor("Base")
			if plate and plate:IsA("Frame") then
				return plate
			end
		end
	end
	return nil
end

local function hideBase(b: Frame)
	if b.Visible then
		b.Visible = false
	end
end

local function shineLoop(t: Frame)
	local shine = t:FindFirstChild("Shine", true) :: Frame?
	if not shine then
		return
	end
	task.spawn(function()
		while t.Parent do
			shine.Position = UDim2.new(0, -80, 0.5, 0)
			TweenService:Create(shine, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Position = UDim2.new(0, 400, 0.5, 0) }):Play()
			task.wait(4.5)
		end
	end)
end

local function makeTravel(b: Frame): Frame
	local t = b:Clone() :: Frame
	t.Name = "TravelButton"
	t:SetAttribute("BiomeTeleport", true)
	t.Visible = not isArena
	for _, d in t:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "Base" then
			d.Text = "Travel"
		end
	end
	local hit = t:FindFirstChild("Hit") :: TextButton?
	local body = t:FindFirstChild("Body")
	local scale = body and body:FindFirstChildOfClass("UIScale")
	if hit then
		hit.Activated:Connect(togglePanel)
		if scale then
			hit.MouseButton1Down:Connect(function()
				TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.96 }):Play()
			end)
			hit.MouseButton1Up:Connect(function()
				TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
			end)
			hit.MouseLeave:Connect(function()
				TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
			end)
		end
	end
	t.Parent = b.Parent
	shineLoop(t)
	return t
end

-- the HUD moves its buttons (edge pins on wide screens): follow the Base button's spot
local function follow(b: Frame, t: Frame)
	if t.Position ~= b.Position then
		t.Position = b.Position
	end
	if t.Size ~= b.Size then
		t.Size = b.Size
	end
	if t.AnchorPoint ~= b.AnchorPoint then
		t.AnchorPoint = b.AnchorPoint
	end
	if t.ZIndex ~= b.ZIndex then
		t.ZIndex = b.ZIndex
	end
end

local function attach(): boolean
	if hudBase and hudBase.Parent and travel and travel.Parent == hudBase.Parent then
		hideBase(hudBase)
		follow(hudBase, travel)
		travel.Visible = not isArena
		return true
	end
	local b = findHudBase()
	if not b then
		return false
	end
	if baseConn then
		baseConn:Disconnect()
	end
	if travel then
		travel:Destroy()
	end
	hudBase = b
	travel = makeTravel(b)
	hideBase(b)
	baseConn = b.Changed:Connect(function(prop)
		if prop == "Visible" then
			hideBase(b) -- the HUD showed it again: hide it again
		elseif travel and (prop == "Position" or prop == "Size" or prop == "AnchorPoint") then
			follow(b, travel)
		end
	end)
	follow(b, travel)
	hudButton.Visible = false
	return true
end

-- keep it attached: the HUD can be rebuilt (respawn, UI reload)
task.spawn(function()
	local started = os.clock()
	while gui.Parent do
		local ok = attach()
		if not ok and os.clock() - started > 20 then
			hudButton.Visible = not isArena -- no HUD Base button: show the fallback at the top centre
		end
		task.wait(if ok then 1 else 0.5)
	end
end)

-- no travel button inside an arena server
local function arenaCheck()
	local arena = workspace:GetAttribute("MM_ArenaServer") or workspace:FindFirstChild("MM_ArenaServer")
	isArena = arena ~= nil and arena ~= false
	if travel then
		travel.Visible = not isArena
	end
	if isArena then
		hudButton.Visible = false
	end
	if isArena and panelOpen then
		closePanel()
	end
end
workspace:GetAttributeChangedSignal("MM_ArenaServer"):Connect(arenaCheck)
workspace.ChildAdded:Connect(arenaCheck)
arenaCheck()
