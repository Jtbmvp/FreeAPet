-- MatchmakingClient (StarterGui.MatchmakingGui): HUD button + matchmaking waiting room.
-- Only shows what the server says (MatchmakingRemotes.State); every decision is made by
-- ServerScriptService.MatchmakingServer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = script.Parent :: ScreenGui
local remotes = ReplicatedStorage:WaitForChild("MatchmakingRemotes")
local Action = remotes:WaitForChild("Action") :: RemoteEvent
local State = remotes:WaitForChild("State") :: RemoteEvent

-- style (same palette and fonts as the game's DesignUI Theme)
local C = {
	Outline = Color3.fromHex("0D1119"),
	Panel = Color3.fromHex("1A1D23"),
	Row = Color3.fromHex("26272B"),
	White = Color3.new(1, 1, 1),
	Muted = Color3.fromHex("CFCFD3"),
	Gold = Color3.fromHex("FFD23C"),
	Red = Color3.fromHex("F0625C"),
	Blue = Color3.fromHex("5AA8F0"),
}
local G = {
	Battle = { Color3.fromHex("FF8A3C"), Color3.fromHex("E0561C") },
	Green = { Color3.fromHex("7FE46C"), Color3.fromHex("4FC441") },
	Red = { Color3.fromHex("F0625C"), Color3.fromHex("CF3934") },
	Blue = { Color3.fromHex("5AA8F0"), Color3.fromHex("3382D6") },
	Grey = { Color3.fromHex("8C8D91"), Color3.fromHex("6C6D71") },
	Header = { Color3.fromHex("6E6F73"), Color3.fromHex("535457") },
}
local F = {
	Title = Font.fromName("Montserrat", Enum.FontWeight.Heavy),
	Bold = Font.fromName("Montserrat", Enum.FontWeight.Bold),
	Body = Font.fromName("Montserrat", Enum.FontWeight.SemiBold),
	Num = Font.fromName("FredokaOne"),
}

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
	text({ Name = "Label", Text = label, Size = UDim2.new(1, -16, 1, -12), Position = UDim2.fromOffset(8, 6), MaxSize = 26, Parent = b, ZIndex = 2 })
	textStroke(2).Parent = b.Label
	pressable(b)
	return b
end

local function headshot(userId: number): string
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId)
end

-- root scale: everything is drawn for a 1280x720 screen
local rootScale = new("UIScale", { Parent = gui })
local function rescale()
	local cam = workspace.CurrentCamera
	if cam then
		rootScale.Scale = math.clamp(cam.ViewportSize.Y / 720, 0.55, 1.4)
	end
end
rescale()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(rescale)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
end

--------------------------------------------------------------------------------------------
-- HUD button (right side, clear of the leaderboard and the bottom-right icons)
--------------------------------------------------------------------------------------------
local hudButton = new("TextButton", {
	Name = "MatchmakingButton", Text = "", AutoButtonColor = false, BackgroundColor3 = C.White,
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(96, 96),
	Parent = gui,
}, { corner(14), stroke(3), grad(G.Battle) })
pressable(hudButton)
text({ Text = "⚔️", Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 6), MaxSize = 46, Parent = hudButton })
local hudLabel = text({ Text = "1v1", Size = UDim2.new(1, -8, 0, 28), Position = UDim2.new(0, 4, 1, -34), MaxSize = 26, Parent = hudButton })
textStroke(2.5).Parent = hudLabel
local hudDot = new("Frame", {
	Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -14, 0, -6), BackgroundColor3 = C.Gold, Visible = false, Parent = hudButton,
}, { corner(10), stroke(2) })

--------------------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------------------
local dim = new("TextButton", {
	Name = "Dim", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5,
	Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 5, Parent = gui,
})
local panel = new("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(600, 430),
	BackgroundColor3 = C.Panel, ZIndex = 6, Parent = dim,
}, { corner(18), stroke(4) })
local panelScale = new("UIScale", { Parent = panel })
local header = new("Frame", { Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = C.White, ZIndex = 6, Parent = panel }, { corner(18), grad(G.Battle) })
new("Frame", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -18), BackgroundColor3 = G.Battle[2], BorderSizePixel = 0, ZIndex = 6, Parent = header })
local title = text({ Text = "⚔️  MATCHMAKING 1v1", Size = UDim2.new(1, -100, 0, 38), Position = UDim2.fromOffset(20, 12), MaxSize = 32, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = header })
textStroke(3).Parent = title
local close = button(header, "X", G.Red, UDim2.fromOffset(44, 44), UDim2.new(1, -54, 0, 9))
close.ZIndex = 7
close.Label.ZIndex = 8

local status = text({ Text = "", FontFace = F.Bold, TextColor3 = C.Muted, Size = UDim2.new(1, -40, 0, 22), Position = UDim2.fromOffset(20, 72), MaxSize = 18, ZIndex = 7, Parent = panel })

-- lobby view
local lobbyView = new("Frame", { Size = UDim2.new(1, -40, 1, -110), Position = UDim2.fromOffset(20, 100), BackgroundTransparency = 1, ZIndex = 6, Parent = panel })
local findBtn = button(lobbyView, "FIND MATCH", G.Green, UDim2.new(1, 0, 0, 58), UDim2.fromOffset(0, 0))
findBtn.ZIndex = 7
findBtn.Label.ZIndex = 8
text({ Text = "PLAYERS WAITING", FontFace = F.Title, TextColor3 = C.Gold, Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.fromOffset(2, 70), MaxSize = 18, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = lobbyView })
local refreshBtn = button(lobbyView, "REFRESH", G.Grey, UDim2.fromOffset(96, 28), UDim2.new(1, 0, 0, 66), Vector2.new(1, 0))
refreshBtn.ZIndex = 7
refreshBtn.Label.ZIndex = 8
local list = new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -104), Position = UDim2.fromOffset(0, 102), BackgroundColor3 = C.Outline, BackgroundTransparency = 0.3,
	ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 7, Parent = lobbyView,
}, { corner(10), new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }), new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 12) }) })
local emptyText = text({ Text = "Nobody is waiting yet.\nPress FIND MATCH to open a room for others to join.", FontFace = F.Body, TextColor3 = C.Muted, Size = UDim2.new(1, -20, 0, 60), Position = UDim2.fromOffset(10, 140), MaxSize = 18, ZIndex = 8, Visible = false, Parent = lobbyView })

-- room view (waiting / found / teleporting)
local roomView = new("Frame", { Size = UDim2.new(1, -40, 1, -110), Position = UDim2.fromOffset(20, 100), BackgroundTransparency = 1, Visible = false, ZIndex = 6, Parent = panel })
local function card(pos: UDim2, pair)
	local f = new("Frame", { Size = UDim2.fromOffset(210, 210), Position = pos, BackgroundColor3 = C.Row, ZIndex = 7, Parent = roomView }, { corner(14), stroke(3) })
	local band = new("Frame", { Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = C.White, ZIndex = 8, Parent = f }, { corner(14), grad(pair) })
	local img = new("ImageLabel", { Size = UDim2.fromOffset(120, 120), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20), BackgroundColor3 = C.Outline, ZIndex = 8, Parent = f }, { corner(60), stroke(3, pair[1]) })
	local name = text({ Text = "", Size = UDim2.new(1, -16, 0, 28), Position = UDim2.new(0, 8, 0, 146), MaxSize = 24, ZIndex = 8, Parent = f })
	textStroke(2).Parent = name
	local handle = text({ Text = "", FontFace = F.Body, TextColor3 = C.Muted, Size = UDim2.new(1, -16, 0, 20), Position = UDim2.new(0, 8, 0, 176), MaxSize = 16, ZIndex = 8, Parent = f })
	local q = text({ Text = "?", FontFace = F.Num, TextColor3 = C.Muted, Size = UDim2.fromOffset(120, 120), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20), MaxSize = 80, ZIndex = 9, Parent = f })
	return { frame = f, img = img, name = name, handle = handle, q = q, band = band }
end
local leftCard = card(UDim2.fromOffset(0, 0), G.Red)
local rightCard = card(UDim2.new(1, -210, 0, 0), G.Blue)
local vs = text({ Text = "VS", FontFace = F.Num, TextColor3 = C.Gold, Size = UDim2.fromOffset(110, 70), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), MaxSize = 60, ZIndex = 8, Parent = roomView })
textStroke(3).Parent = vs
local bigText = text({ Text = "", Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 222), MaxSize = 32, ZIndex = 8, TextColor3 = C.Gold, Parent = roomView })
textStroke(3).Parent = bigText
local leaveBtn = button(roomView, "LEAVE ROOM", G.Red, UDim2.fromOffset(220, 46), UDim2.new(0.5, 0, 1, -50), Vector2.new(0.5, 0))
leaveBtn.ZIndex = 7
leaveBtn.Label.ZIndex = 8

local function fillCard(c, info)
	if info then
		c.img.Image = headshot(info.id)
		c.img.Visible = true
		c.q.Visible = false
		c.name.Text = info.display or info.name
		c.handle.Text = "@" .. tostring(info.name)
	else
		c.img.Image = ""
		c.q.Visible = true
		c.name.Text = "Waiting..."
		c.handle.Text = "any server"
	end
end

--------------------------------------------------------------------------------------------
-- Banner (status when the panel is closed) and big centre text (arena countdown)
--------------------------------------------------------------------------------------------
local banner = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), Size = UDim2.fromOffset(440, 60),
	BackgroundColor3 = C.Panel, Visible = false, ZIndex = 4, Parent = gui,
}, { corner(14), stroke(3) })
local bannerText = text({ Text = "", Size = UDim2.new(1, -30, 0, 28), Position = UDim2.fromOffset(15, 6), MaxSize = 24, ZIndex = 5, Parent = banner })
textStroke(2).Parent = bannerText
local bannerSub = text({ Text = "", FontFace = F.Body, TextColor3 = C.Muted, Size = UDim2.new(1, -30, 0, 18), Position = UDim2.fromOffset(15, 36), MaxSize = 15, ZIndex = 5, Parent = banner })
local center = text({ Text = "", FontFace = F.Num, TextColor3 = C.Gold, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(600, 150), MaxSize = 130, Visible = false, ZIndex = 10, Parent = gui })
textStroke(5).Parent = center
local centerScale = new("UIScale", { Parent = center })

local bannerToken = 0
local function showBanner(t: string, sub: string?, seconds: number?)
	bannerToken += 1
	local my = bannerToken
	bannerText.Text = t
	bannerSub.Text = sub or ""
	banner.Visible = true
	if seconds then
		task.delay(seconds, function()
			if my == bannerToken then
				banner.Visible = false
			end
		end)
	end
end
local function hideBanner()
	bannerToken += 1
	banner.Visible = false
end
local function pop(t: string, col: Color3?, hold: number?)
	center.Text = t
	center.TextColor3 = col or C.Gold
	center.Visible = true
	centerScale.Scale = 1.6
	TweenService:Create(centerScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local my = t
	task.delay(hold or 0.9, function()
		if center.Text == my then
			center.Visible = false
		end
	end)
end

--------------------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------------------
local panelOpen = false
local current = "idle"
local countdownRoom: string? = nil
local countdownEnd = 0
local waitStart = 0

local function openPanel()
	if workspace:GetAttribute("MM_ArenaServer") then
		return
	end
	panelOpen = true
	dim.Visible = true
	panelScale.Scale = 0.85
	TweenService:Create(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Action:FireServer("open")
end
local function closePanel()
	panelOpen = false
	dim.Visible = false
	Action:FireServer("close")
end
hudButton.MouseButton1Click:Connect(function()
	if panelOpen then
		closePanel()
	else
		openPanel()
	end
end)
close.MouseButton1Click:Connect(closePanel)
findBtn.MouseButton1Click:Connect(function()
	status.Text = "Opening your room..."
	Action:FireServer("search")
end)
refreshBtn.MouseButton1Click:Connect(function()
	Action:FireServer("refresh")
end)
leaveBtn.MouseButton1Click:Connect(function()
	Action:FireServer("leave")
end)

local function renderList(rooms)
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local shown = 0
	for i, r in ipairs(rooms or {}) do
		if r.host.id ~= player.UserId then
			shown += 1
			local row = new("Frame", { Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = C.Row, LayoutOrder = i, ZIndex = 8, Parent = list }, { corner(10), stroke(2) })
			new("ImageLabel", { Image = headshot(r.host.id), Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 7), BackgroundColor3 = C.Outline, ZIndex = 9, Parent = row }, { corner(24), stroke(2, C.Red) })
			text({ Text = r.host.display or r.host.name, Size = UDim2.new(1, -200, 0, 24), Position = UDim2.fromOffset(66, 8), MaxSize = 20, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = row })
			local age = r.age or 0
			text({ Text = ("@%s  ·  waiting %d:%02d"):format(r.host.name, age // 60, age % 60), FontFace = F.Body, TextColor3 = C.Muted, Size = UDim2.new(1, -200, 0, 18), Position = UDim2.fromOffset(66, 34), MaxSize = 14, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = row })
			local join = button(row, "JOIN", G.Green, UDim2.fromOffset(110, 44), UDim2.new(1, -8, 0.5, 0), Vector2.new(1, 0.5))
			join.ZIndex = 9
			join.Label.ZIndex = 10
			local id = r.id
			join.MouseButton1Click:Connect(function()
				status.Text = "Joining " .. (r.host.display or r.host.name) .. "..."
				Action:FireServer("join", id)
			end)
		end
	end
	emptyText.Visible = shown == 0
	return shown
end

local function setView(which: string)
	lobbyView.Visible = which == "lobby"
	roomView.Visible = which == "room"
end

State.OnClientEvent:Connect(function(data)
	local s = data.state
	current = s
	hudDot.Visible = (s == "waiting" or s == "found" or s == "teleporting")
	if s == "lobby" then
		setView("lobby")
		local n = renderList(data.rooms)
		status.Text = if n > 0 then (n .. " player" .. (if n == 1 then "" else "s") .. " looking for a match, from any server") else "Looking for players on every server..."
		countdownRoom = nil
		hideBanner()
	elseif s == "waiting" then
		setView("room")
		local room = data.room
		fillCard(leftCard, room.host)
		fillCard(rightCard, nil)
		leaveBtn.Visible = true
		if countdownRoom ~= room.id .. ":wait" then
			countdownRoom = room.id .. ":wait"
			waitStart = os.clock()
		end
		status.Text = "Your room is open. Players on any server can join."
		showBanner("Searching for an opponent...", "Open the 1v1 menu to leave the room")
	elseif s == "found" then
		setView("room")
		local room = data.room
		fillCard(leftCard, room.host)
		fillCard(rightCard, room.guest)
		leaveBtn.Visible = true
		if countdownRoom ~= room.id .. ":found" then
			countdownRoom = room.id .. ":found"
			countdownEnd = os.clock() + (data.remaining or 5)
			if not panelOpen then
				openPanel()
			end
		end
		status.Text = "Both players are ready."
	elseif s == "teleporting" then
		setView("room")
		fillCard(leftCard, data.room.host)
		fillCard(rightCard, data.room.guest)
		leaveBtn.Visible = false
		countdownRoom = nil
		bigText.Text = "TELEPORTING TO THE COLOSSEUM..."
		status.Text = "Hold on, sending both players to a private arena."
		showBanner("Teleporting to the Colosseum...", "Private arena server")
	elseif s == "cancelled" or s == "error" then
		countdownRoom = nil
		showBanner(data.text or "Something went wrong.", "You can search again", 4)
		status.Text = data.text or ""
		if panelOpen then
			setView("lobby")
			Action:FireServer("refresh")
		end
	elseif s == "idle" then
		countdownRoom = nil
		hideBanner()
	elseif s == "arena_busy" then
		showBanner("You're in a match", nil, 3)
	elseif s == "arena_wait" then
		if panelOpen then
			closePanel()
		end
		local opp = data.opponent
		showBanner("Waiting for " .. (opp and (opp.display or opp.name) or "your opponent") .. "...", "The match starts as soon as both players load")
	elseif s == "arena_countdown" then
		hideBanner()
		pop(tostring(data.n))
	elseif s == "arena_start" then
		pop("FIGHT!", C.Red, 1.4)
		hideBanner() -- the game's battle screen takes over from here
	elseif s == "arena_end" then
		local msg
		if data.reason == "battle_knockout" then
			msg = if data.won then "Victory! You won the battle!" else "Defeat... your team fainted."
		elseif data.reason == "battle_forfeit" then
			msg = if data.won then "Victory! Your opponent forfeited." else "You forfeited the battle."
		elseif data.reason == "opponent_left" then
			msg = if data.won then "Victory! Your opponent left." else "You left the match."
		elseif data.reason == "cancelled_noteam" then
			msg = "A player has no pets in the team. Match cancelled."
		elseif data.reason == "cancelled_noshow" then
			msg = "Your opponent didn't arrive. Match cancelled."
		else
			msg = "Your opponent left before the start. Match cancelled."
		end
		showBanner(msg, "Returning to the lobby...")
	elseif s == "returning" then
		showBanner("Returning to the lobby...", nil)
	end
end)

-- local animation: countdown + waiting timer
task.spawn(function()
	while true do
		if current == "found" and countdownRoom then
			local left = math.max(0, math.ceil(countdownEnd - os.clock()))
			bigText.Text = "MATCH FOUND!  " .. left
			bannerText.Text = "Match found!  " .. left
			bannerSub.Text = "Teleporting to the Colosseum"
			banner.Visible = not panelOpen
			vs.TextColor3 = C.Red
		elseif current == "waiting" then
			local s = math.floor(os.clock() - waitStart)
			local dots = string.rep(".", (s % 3) + 1)
			bigText.Text = ("WAITING FOR AN OPPONENT%s  %d:%02d"):format(dots, s // 60, s % 60)
			banner.Visible = not panelOpen
			if not panelOpen then
				bannerText.Text = ("Searching for an opponent%s  %d:%02d"):format(dots, s // 60, s % 60)
			end
			vs.TextColor3 = C.Gold
		end
		task.wait(0.25)
	end
end)

-- no matchmaking button inside an arena server
local function arenaCheck()
	hudButton.Visible = not workspace:GetAttribute("MM_ArenaServer")
	if not hudButton.Visible and panelOpen then
		closePanel()
	end
end
workspace:GetAttributeChangedSignal("MM_ArenaServer"):Connect(arenaCheck)
arenaCheck()

-- PvP: the game's battle screen (BattleObstacles) hides, for the player in the battle, every
-- pet that was not fighting when the battle began, including the opponent's reserve pets, and
-- does not update that list on a switch. When the opponent sends out a new pet, keep the pet
-- they are fighting visible. (Wild battles never switch the foe, so they are not affected.)
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local pvpFoe: Model? = nil
Remotes.Get("Battle").OnClientEvent:Connect(function(view)
	if type(view) ~= "table" or view.kind ~= "pvp" then
		return
	end
	-- after the last update (result) let the battle screen fade and restore things itself
	pvpFoe = if view.result then nil else (view.wild and view.wild.model)
end)
local function reveal(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			if d.LocalTransparencyModifier ~= 0 then
				d.LocalTransparencyModifier = 0
			end
		end
	end
end
task.spawn(function()
	while true do
		task.wait(0.2)
		local foe = pvpFoe
		if foe and foe.Parent and player:GetAttribute("InBattle") == true then
			reveal(foe)
		elseif foe and player:GetAttribute("InBattle") ~= true then
			pvpFoe = nil
		end
	end
end)

-- re-sync after a respawn or reconnect
Action:FireServer("close")
