--!strict
-- Native port of FreeAPet HUD (offline).html. UI only; existing services own mutations.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local GS = game:GetService("GuiService")
local CAS = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local Shared = RS.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Format = require(Shared.Format)
local UI = script.Parent.Parent.UI
local P = require(UI.HudPrimitives)
local Layout = require(UI.HudLayout)
local State = require(UI.HudState)
local Actions = require(UI.HudActions)
local Hud = {}
local running = false
local modules = {
	Pets = require(UI.UserPets),
	Index = require(UI.UserIndex),
	Research = require(UI.UserResearch),
	Trade = require(UI.TradeTab),
	Leaderboard = require(UI.UserLeaderboard),
	Shop = require(UI.UserShop),
	Settings = require(UI.SettingsTab),
}
function Hud.Start()
	if running then
		return
	end
	running = true
	local player = Players.LocalPlayer
	local pg = player:WaitForChild("PlayerGui")
	local alive = true
	local connections: { RBXScriptConnection } = {}
	local function listen(signal: RBXScriptSignal, fn: any)
		local c = signal:Connect(fn)
		table.insert(connections, c)
		return c
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "UserHud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
	gui.DisplayOrder = 5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local safe = P.Frame(gui, "SafeArea", nil, 1)
	safe.Size = UDim2.fromScale(1, 1)
	local hud = P.Frame(safe, "Exploration", nil, 1)
	hud.Size = UDim2.fromScale(1, 1)
	local progress = P.Frame(hud, "PlayerProgress", nil, 0.3)
	P.Round(progress)
	P.Stroke(progress)
	local level = P.Text(progress, "Level", "LEVEL —", 18)
	level.Position = UDim2.fromOffset(10, 3)
	level.Size = UDim2.new(1, -20, 0, 24)
	local xpTrack, xpFill = P.Bar(progress, "EXP")
	xpTrack.Position = UDim2.new(0, 10, 1, -16)
	xpTrack.Size = UDim2.new(1, -20, 0, 10)
	local xpText = P.Text(progress, "EXPText", "Loading…", 14)
	xpText.Position = UDim2.fromOffset(10, 28)
	xpText.Size = UDim2.new(1, -20, 0, 20)
	local base = P.Button(hud, "Base", "Base", P.colors.Trade)
	local settings = P.Button(hud, "Settings", "", P.colors.Settings, "settings")
	local nav = {}
	local navLabels = {}
	local locks = {}
	for i, name in { "Pets", "Index", "Research", "Trade", "Shop" } do
		local b, l = P.Button(hud, name, name, P.colors[name], string.lower(name))
		nav[i] = b
		navLabels[name] = l
		if name == "Research" or name == "Trade" then
			local cover = P.Frame(b, "Locked", Color3.fromRGB(14, 16, 20), 0.1)
			cover.Size = UDim2.fromScale(1, 1)
			P.Round(cover)
			local icon = P.Image(cover, "lock")
			icon.Size = UDim2.fromScale(0.6, 0.65)
			icon.Position = UDim2.fromScale(0.2, 0)
			local text = P.Text(cover, "Required", "", 16)
			text.Position = UDim2.fromScale(0, 0.62)
			text.Size = UDim2.fromScale(1, 0.38)
			locks[name] = { frame = cover, text = text }
		end
	end
	local cash = P.Frame(hud, "CashDay", nil, 1)
	local money = P.Text(cash, "Cash", "$—", 56)
	money.TextColor3 = Color3.fromRGB(106, 228, 84)
	money.Position = UDim2.fromOffset(48, 0)
	money.Size = UDim2.new(1, -48, 0.53, 0)
	money.TextXAlignment = Enum.TextXAlignment.Left
	local cashIcon = P.Image(cash, "cash")
	cashIcon.Size = UDim2.fromOffset(44, 52)
	local income = P.Text(cash, "Income", "—/s", 24)
	income.Position = UDim2.new(0, 48, 0.5, 0)
	income.Size = UDim2.new(1, -48, 0.23, 0)
	income.TextXAlignment = Enum.TextXAlignment.Left
	local day = P.Text(cash, "Day", "DAY ENDS IN —", 24)
	day.Position = UDim2.fromScale(0, 0.76)
	day.Size = UDim2.fromScale(1, 0.24)
	day.TextColor3 = P.colors.gold
	day.TextXAlignment = Enum.TextXAlignment.Left
	local boosts = P.Frame(hud, "Boosts", nil, 1)
	for i, key in { "friends", "plus", "news" } do
		local icon = P.Image(boosts, key)
		icon.Position = UDim2.fromScale((i - 1) / 3, 0)
		icon.Size = UDim2.fromScale(1 / 3, 0.72)
	end
	local friendText = P.Text(boosts, "FriendPercent", "—", 16)
	friendText.Position = UDim2.fromScale(0, 0.72)
	friendText.Size = UDim2.fromScale(1 / 3, 0.28)
	local plusText = P.Text(boosts, "PlusPercent", "—", 16)
	plusText.Position = UDim2.fromScale(1 / 3, 0.72)
	plusText.Size = UDim2.fromScale(1 / 3, 0.28)
	local quickBoard = P.Button(hud, "Players", "Players", P.colors.Settings)
	local board = P.Frame(hud, "Leaderboard", nil, 0.2)
	P.Round(board)
	P.Stroke(board)
	local boardToggle = P.Button(board, "Toggle", "Leaderboard", P.colors.Settings)
	boardToggle.Size = UDim2.new(1, 0, 0, 48)
	local boardList = Instance.new("ScrollingFrame")
	boardList.Name = "Players"
	boardList.BackgroundTransparency = 1
	boardList.BorderSizePixel = 0
	boardList.Position = UDim2.fromOffset(8, 56)
	boardList.Size = UDim2.new(1, -16, 1, -64)
	boardList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	boardList.CanvasSize = UDim2.new()
	boardList.ScrollBarThickness = 6
	boardList.Parent = board
	local boardLayout = Instance.new("UIListLayout")
	boardLayout.Padding = UDim.new(0, 6)
	boardLayout.Parent = boardList
	local boardRows: { [Player]: TextLabel } = {}
	local expanded = false
	local window = P.Frame(safe, "Window", nil, 0.08)
	P.Round(window)
	P.Stroke(window, 5)
	window.Visible = false
	window.SelectionGroup = true
	for _, direction in { "Up", "Down", "Left", "Right" } do
		(window :: any)[`SelectionBehavior{direction}`] = Enum.SelectionBehavior.Stop
	end
	local header = P.Frame(window, "Header", P.colors.Pets)
	header.Size = UDim2.new(1, 0, 0, 64)
	P.Round(header)
	P.Studs(header)
	local title = P.Text(header, "Title", "Pets", 32)
	title.Position = UDim2.fromOffset(68, 0)
	title.Size = UDim2.new(1, -144, 1, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local headerIcon = P.Image(header, "pets")
	headerIcon.Position = UDim2.fromOffset(6, 0)
	headerIcon.Size = UDim2.fromOffset(56, 60)
	local close = P.Button(header, "Close", "X", P.colors.Shop)
	close.Position = UDim2.new(1, -56, 0, 8)
	close.Size = UDim2.fromOffset(48, 48)
	close.SelectionOrder = 1000
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ContentScroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(16, 76)
	scroll.Size = UDim2.new(1, -32, 1, -92)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.Parent = window
	local bodies = {}
	local handles = {}
	local panelRefreshing: { [string]: boolean } = {}
	local current: string? = nil
	local origin: GuiObject? = nil
	local compact = false
	local metrics: any = nil
	local activeSnapshot: any = nil
	local message = P.Text(safe, "Message", "", 18)
	message.Visible = false
	message.TextWrapped = true
	message.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	message.BackgroundTransparency = 0.1
	message.Position = UDim2.new(0.25, 0, 0, 8)
	message.Size = UDim2.new(0.5, 0, 0, 56)
	message.ZIndex = 30
	local messageVersion = 0
	local function announce(text: string)
		messageVersion += 1
		local id = messageVersion
		message.Text = text
		message.Visible = true
		task.delay(4, function()
			if alive and messageVersion == id then
				message.Visible = false
			end
		end)
	end
	local function focus(group: GuiObject)
		if UIS.PreferredInput == Enum.PreferredInput.Gamepad then
			GS:Select(group)
		end
	end
	local function bodySize()
		if not current then
			return
		end
		local body = bodies[current]
		local minHeight = if handles[current].ContentHeight
			then handles[current].ContentHeight()
			elseif current == "Pets" then 360
			elseif current == "Index" then 300
			elseif current == "Trade" then 520
			elseif current == "Settings" then 480
			elseif current == "Research" then 560
			else 0
		body.Size = UDim2.new(1, -8, 0, math.max(minHeight, scroll.AbsoluteSize.Y))
	end
	local function closeWindow(force: boolean?)
		if not current then
			return
		end
		local h = handles[current]
		if not force and h.RequestClose and not h.RequestClose() then
			return
		end
		if force and h.RequestClose then
			h.RequestClose()
		end
		h.Hide()
		bodies[current].Visible = false
		current = nil
		window.Visible = false
		player:SetAttribute("MenuOpen", false)
		hud.Visible = player:GetAttribute("InBattle") ~= true
		if UIS.PreferredInput == Enum.PreferredInput.Gamepad then
			if origin and origin.Parent and origin.Visible then
				GS.SelectedObject = origin
			else
				GS.SelectedObject = nil
			end
		end
	end
	local function open(name: string, opener: GuiObject?)
		if not handles[name] or player:GetAttribute("InBattle") == true or GS.MenuIsOpen then
			return
		end
		if current == name then
			handles[name].Show()
			return
		end
		if current then
			closeWindow()
			if current then
				return
			end
		end
		local required = if name == "Research"
			then Config.Progression.unlocks.Research
			elseif name == "Trade" then Config.Progression.unlocks.Trade
			else nil
		local pl = player:GetAttribute("PlayerLevel")
		if required and (typeof(pl) ~= "number" or pl < required) then
			announce(
				if typeof(pl) == "number"
					then `{name} unlocks at player level {required}.`
					else "Loading your progress…"
			)
			return
		end
		current = name
		origin = opener
		title.Text = name
		header.BackgroundColor3 = P.colors[name]
		headerIcon.Image = require(Shared.Config.HudImages)[if name == "Leaderboard"
			then "trophy"
			else string.lower(name)] or ""
		window.Visible = true
		bodies[name].Visible = true
		hud.Visible = false
		player:SetAttribute("MenuOpen", true)
		scroll.CanvasPosition = Vector2.zero
		bodySize()
		handles[name].Show()
		task.defer(function()
			if alive and current == name then
				focus(window)
			end
		end)
	end
	local actions = Actions.New()
	local api = {
		Actions = actions,
		Open = function(name: string)
			open(name, nil)
		end,
		Close = function()
			closeWindow()
		end,
		Notify = announce,
		Resize = function()
			scroll.CanvasPosition = Vector2.zero
			bodySize()
		end,
		PinContent = function(pinned: boolean)
			scroll.ScrollingEnabled = not pinned
			scroll.CanvasPosition = Vector2.zero
		end,
	}
	for name, module in modules do
		local body = P.Frame(scroll, name, nil, 1)
		body.Visible = false
		body.Size = UDim2.new(1, -8, 1, 0)
		bodies[name] = body
		handles[name] = module.Mount(body, api)
	end
	local function refreshPanel()
		local key = current
		if not key or not handles[key].Refresh or panelRefreshing[key] then
			return
		end
		panelRefreshing[key] = true
		task.spawn(function()
			local ok, err = pcall(handles[key].Refresh)
			panelRefreshing[key] = nil
			if not ok then
				warn(`[UserHud] {key} refresh failed: {tostring(err)}`)
			end
		end)
	end
	listen(close.Activated, function()
		closeWindow()
	end)
	for i, name in { "Pets", "Index", "Research", "Trade", "Shop" } do
		listen(nav[i].Activated, function()
			open(name, nav[i])
		end)
	end
	listen(quickBoard.Activated, function()
		open("Leaderboard", quickBoard)
	end)
	listen(settings.Activated, function()
		open("Settings", settings)
	end)
	listen(base.Activated, function()
		announce("Base travel is not available from this button yet.")
	end)
	listen(boardToggle.Activated, function()
		expanded = not expanded
		boardList.Visible = expanded
	end)
	local contextObject: GuiObject? = nil
	local function avoidContext()
		if not metrics then
			return
		end
		local obstacle = if contextObject
				and contextObject.Parent
				and contextObject.Visible
			then {
				x = contextObject.AbsolutePosition.X - safe.AbsolutePosition.X,
				y = contextObject.AbsolutePosition.Y - safe.AbsolutePosition.Y,
				w = contextObject.AbsoluteSize.X,
				h = contextObject.AbsoluteSize.Y,
			}
			else nil
		progress.Visible = not obstacle or not Layout.Overlaps(metrics.progress, obstacle)
		base.Visible = not obstacle or not Layout.Overlaps(metrics.base, obstacle)
		settings.Visible = not obstacle or not Layout.Overlaps(metrics.settings, obstacle)
		board.Visible = not compact and (not obstacle or not Layout.Overlaps(metrics.board, obstacle))
		cash.Visible = not obstacle or not Layout.Overlaps(metrics.cash, obstacle)
		boosts.Visible = not obstacle or not Layout.Overlaps(metrics.boosts, obstacle)
		for i, b in nav do
			b.Visible = not obstacle or not Layout.Overlaps(metrics.nav[i], obstacle)
		end
		quickBoard.Visible = compact and (not obstacle or not Layout.Overlaps(metrics.showPets, obstacle))
		local selected = GS.SelectedObject
		if not GS.MenuIsOpen and selected and selected:IsDescendantOf(hud) and not selected.Visible then
			local action = contextObject and contextObject:FindFirstChild("Interact")
			GS.SelectedObject = if action and action:IsA("GuiButton") then action else nil
		end
	end
	local function observeContext(candidate: Instance)
		if candidate.Name ~= "ContextActions" then
			return
		end
		local found = candidate:FindFirstChild("Action", true)
		if not found or not found:IsA("GuiObject") then
			return
		end
		contextObject = found
		listen(found:GetPropertyChangedSignal("Visible"), avoidContext)
		listen(found:GetPropertyChangedSignal("AbsolutePosition"), avoidContext)
		listen(found:GetPropertyChangedSignal("AbsoluteSize"), avoidContext)
		avoidContext()
	end
	local function place()
		local size = safe.AbsoluteSize
		local touch = UIS.PreferredInput == Enum.PreferredInput.Touch
		local jump = pg:FindFirstChild("TouchGui")
		local jumpButton = jump and jump:FindFirstChild("JumpButton", true)
		local top = if jumpButton
				and jumpButton:IsA("GuiObject")
				and jumpButton.Visible
			then jumpButton.AbsolutePosition.Y - safe.AbsolutePosition.Y
			else nil
		metrics = Layout.Compute(size.X, size.Y, touch, top)
		compact = metrics.compact
		P.Place(progress, metrics.progress)
		P.Place(base, metrics.base)
		P.Place(settings, metrics.settings)
		for i, b in nav do
			P.Place(b, metrics.nav[i])
			navLabels[({ "Pets", "Index", "Research", "Trade", "Shop" })[i]].TextSize = if compact
				then 14
				else math.max(16, math.floor(24 * metrics.scale))
		end
		P.Place(quickBoard, metrics.showPets)
		quickBoard.Visible = compact
		P.Place(cash, metrics.cash)
		P.Place(boosts, metrics.boosts)
		P.Place(window, metrics.window)
		P.Place(board, metrics.board)
		xpText.Visible = true
		xpText.TextSize = if compact then 12 else 14
		xpText.Position = UDim2.fromOffset(10, if compact then 20 else 28)
		xpText.Size = UDim2.new(1, -20, 0, if compact then 14 else 20)
		xpTrack.Position = UDim2.new(0, 10, 1, if compact then -8 else -16)
		xpTrack.Size = UDim2.new(1, -20, 0, if compact then 6 else 10)
		level.TextSize = if compact then 14 else 18
		money.TextSize = if compact then 26 else math.floor(72 * metrics.scale)
		income.TextSize = if compact then 14 else math.floor(28 * metrics.scale)
		day.TextSize = if compact then 14 else math.floor(26 * metrics.scale)
		-- Board collapses to a header on short viewports; never forces a full list over touch HUD.
		board.Visible = not compact
		boardList.Visible = expanded
		bodySize()
		avoidContext()
	end
	listen(safe:GetPropertyChangedSignal("AbsoluteSize"), place)
	listen(scroll:GetPropertyChangedSignal("AbsoluteSize"), bodySize)
	listen(UIS:GetPropertyChangedSignal("PreferredInput"), function()
		place()
		if current then
			focus(window)
		end
	end)
	local function live()
		local pl = player:GetAttribute("PlayerLevel")
		local xp = player:GetAttribute("PlayerXp")
		local needed = player:GetAttribute("PlayerXpToNext")
		local ratio, text = State.Progress(pl, xp, needed)
		xpFill.Size = UDim2.fromScale(ratio, 1)
		xpText.Text = text
		level.Text = if typeof(pl) == "number" then `LEVEL {pl}` else "LEVEL —"
		for name, info in locks do
			local required = Config.Progression.unlocks[name]
			info.frame.Visible = typeof(pl) ~= "number" or pl < required
			info.text.Text = if typeof(pl) == "number" then `Lv {required}` else "…"
		end
		local amount = player:GetAttribute("Cash")
		local rate = player:GetAttribute("IncomePerSecond")
		money.Text = if typeof(amount) == "number" then `$ {Format.Short(amount)}` else "$ —"
		income.Text = if typeof(rate) == "number" then `+${Format.Short(rate)}/s` else "—/s"
		-- No hardcoded +5/+25: show only a bonus explicitly supplied by the server.
		local f = player:GetAttribute("FriendBoostPercent")
		local plus = player:GetAttribute("PlusBoostPercent")
		friendText.Text = if typeof(f) == "number" then `+{f}%` else "—"
		plusText.Text = if typeof(plus) == "number" then `+{plus}%` else "—"
	end
	for _, attr in
		{
			"PlayerLevel",
			"PlayerXp",
			"PlayerXpToNext",
			"Cash",
			"IncomePerSecond",
			"FriendBoostPercent",
			"PlusBoostPercent",
		}
	do
		listen(player:GetAttributeChangedSignal(attr), live)
	end
	listen(pg.ChildAdded, observeContext)
	for _, child in pg:GetChildren() do
		observeContext(child)
	end
	local confirmations = State.NewConfirmations()
	listen(Remotes.Get("ProgressionChanged").OnClientEvent, function(snapshot)
		if State.AcceptConfirmation(confirmations, snapshot) then
			announce("Progress saved")
			refreshPanel()
		end
	end)
	local fetching = false
	local function fetch()
		if fetching then
			return
		end
		fetching = true
		local ok, snapshot = pcall(function()
			return Remotes.GetFunction("GetProgression"):InvokeServer()
		end)
		fetching = false
		if not alive then
			return
		end
		if ok and typeof(snapshot) == "table" then
			activeSnapshot = snapshot
			-- Bootstrap uses snapshot only if replicated attributes have not arrived yet.
			if player:GetAttribute("PlayerLevel") == nil then
				local ratio, text =
					State.Progress(snapshot.playerLevel, snapshot.currentXp, snapshot.xpToNext)
				level.Text = `LEVEL {snapshot.playerLevel}`
				xpText.Text = text
				xpFill.Size = UDim2.fromScale(ratio, 1)
			end
		end
	end
	listen(player:GetAttributeChangedSignal("InBattle"), function()
		if player:GetAttribute("InBattle") == true then
			closeWindow(true)
			hud.Visible = false
		else
			hud.Visible = current == nil
		end
	end)
	listen(GS.MenuClosed, function()
		if current then
			focus(window)
		end
	end)
	CAS:BindActionAtPriority("UserHudBack", function(_, state)
		if state ~= Enum.UserInputState.Begin or not current or GS.MenuIsOpen then
			return Enum.ContextActionResult.Pass
		end
		if handles[current].Back and handles[current].Back() then
			return Enum.ContextActionResult.Sink
		end
		closeWindow()
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.ButtonB)
	CAS:BindAction("UserHudPets", function(_, state)
		if state ~= Enum.UserInputState.Begin or UIS:GetFocusedTextBox() or GS.MenuIsOpen then
			return Enum.ContextActionResult.Pass
		end
		open("Pets", nav[1])
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.T)
	CAS:BindAction("UserHudLeaderboard", function(_, state)
		if state ~= Enum.UserInputState.Begin or UIS:GetFocusedTextBox() or GS.MenuIsOpen then
			return Enum.ContextActionResult.Pass
		end
		open("Leaderboard", quickBoard)
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Tab)
	local function boardRefresh()
		local entries = Players:GetPlayers()
		table.sort(entries, function(a, b)
			return (a:GetAttribute("IncomePerSecond") or 0) > (b:GetAttribute("IncomePerSecond") or 0)
		end)
		for i, p in entries do
			local row = boardRows[p]
			if not row then
				row = P.Text(boardList, "Player", "", 16)
				row.Size = UDim2.new(1, -8, 0, 46)
				boardRows[p] = row
			end
			row.LayoutOrder = i
			local l = p:GetAttribute("PlayerLevel")
			local r = p:GetAttribute("IncomePerSecond")
			row.Text =
				`{p.DisplayName}  ·  Lv {if typeof(l) == "number" then tostring(l) else "—"}  ·  ${if typeof(
						r
					) == "number"
					then Format.Short(r)
					else "—"}/s`
		end
		for p, row in boardRows do
			if not p.Parent then
				row:Destroy()
				boardRows[p] = nil
			end
		end
	end
	listen(gui.Destroying, function()
		if current and handles[current].RequestClose then
			handles[current].RequestClose()
		end
		alive = false
		running = false
		actions.Destroy()
		player:SetAttribute("MenuOpen", false)
		CAS:UnbindAction("UserHudBack")
		CAS:UnbindAction("UserHudPets")
		CAS:UnbindAction("UserHudLeaderboard")
		for _, handle in handles do
			if handle.Destroy then
				handle.Destroy()
			else
				handle.Hide()
			end
		end
		for _, c in connections do
			c:Disconnect()
		end
	end)
	gui.Parent = pg
	place()
	live()
	hud.Visible = player:GetAttribute("InBattle") ~= true
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	task.spawn(function()
		local tick = 0
		while alive do
			-- One broker across Pets/Shop; a timeout never starts a second financial action.
			if current == "Pets" or current == "Shop" or select(2, actions.Read()) then
				actions.Refresh()
			end
			local ending = Workspace:GetAttribute("DayEndsAt")
			if typeof(ending) == "number" then
				local left = math.max(0, math.floor(ending - Workspace:GetServerTimeNow()))
				day.Text = string.format("DAY ENDS IN %02d:%02d", left // 60, left % 60)
				day.TextColor3 = if left <= 30 then Color3.fromRGB(255, 100, 100) else P.colors.gold
			end
			boardRefresh()
			tick += 1
			if tick == 1 or activeSnapshot == nil then
				task.spawn(fetch)
			end
			refreshPanel()
			task.wait(1)
		end
	end)
end
return Hud
