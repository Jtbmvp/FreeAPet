--!strict
-- Global leaderboard (brief §6): a board in the plaza with the best Cash/s
-- players have ever reached, on any server. Each player's best is kept in
-- their save (bestIncome) and written to an OrderedDataStore at most once
-- a minute; the board reads the top every two minutes. Studio uses its own
-- store. The per-server ranking is the custom list on the right of the
-- screen (client Leaderboard, fed by the leaderstats PlayerStateService sets).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local PlayerDataService = require(script.Parent.PlayerDataService)
local PlayerStateService = require(script.Parent.PlayerStateService)

local LeaderboardService = {}

local storeName = if RunService:IsStudio() then "BestIncome_Studio" else "BestIncome"
local written: { [Player]: number } = {} -- last value written, x100
type BoardRow = { frame: Frame, badge: Frame, rank: TextLabel, name: TextLabel, value: TextLabel }
local rows: { BoardRow } = {}
local RANK_KINDS = { "yellow", "grey", "orange" } -- gold, silver, bronze

local function buildBoard(): Model?
	local settings = Config.Gameplay.leaderboard
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local collision = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Collision")
	if not collision then
		return nil
	end
	params.FilterDescendantsInstances = { collision, Workspace.Terrain }
	local hit = Workspace:Raycast(settings.position + Vector3.new(0, 80, 0), Vector3.new(0, -200, 0), params)
	local ground = if hit then hit.Position else settings.position

	local board = Instance.new("Model")
	board.Name = "GlobalLeaderboard"
	local facing = Vector3.new(settings.facing.X, ground.Y, settings.facing.Z)
	local base = CFrame.lookAt(ground, facing)

	local function part(
		name: string,
		size: Vector3,
		offset: CFrame,
		color: Color3,
		material: Enum.Material
	): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = base * offset
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.Parent = board
		return p
	end
	local sourceBoard = collision:FindFirstChild("board_panel", true)
	local sourcePanel = if sourceBoard and sourceBoard:IsA("BasePart") then sourceBoard else nil
	if not sourcePanel then
		part(
			"PostLeft",
			Vector3.new(1.2, 16, 1.2),
			CFrame.new(-8.5, 8, 0),
			Color3.fromRGB(240, 240, 245),
			Enum.Material.SmoothPlastic
		)
		part(
			"PostRight",
			Vector3.new(1.2, 16, 1.2),
			CFrame.new(8.5, 8, 0),
			Color3.fromRGB(240, 240, 245),
			Enum.Material.SmoothPlastic
		)
	end
	local panel = if sourcePanel
		then sourcePanel
		else part(
			"Panel",
			Vector3.new(16, 13, 0.8),
			CFrame.new(0, 9.5, 0),
			UITheme.colors.panelBottom,
			Enum.Material.SmoothPlastic
		)
	if not sourcePanel then
		part(
			"Trim",
			Vector3.new(17, 0.8, 1.2),
			CFrame.new(0, 16.3, 0),
			UITheme.colors.gold,
			Enum.Material.Neon
		)
	end

	-- Text on the side that looks at the fountain (the part's front, -Z).
	-- Same stud look as the on-screen UI; unlit so it reads at night too.
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(640, 540) -- all ten rows fit the 12.6x9 V3 source panel
	gui.LightInfluence = 0
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Name = "FreeAPetRanking"
	local existingGui = panel:FindFirstChild(gui.Name)
	if existingGui then
		existingGui:Destroy()
	end
	gui.Parent = panel
	local body = UITheme.Panel(nil)
	body.Size = UDim2.fromScale(1, 1)
	body.Parent = gui

	local header = UITheme.Panel("purple")
	header.Position = UDim2.fromOffset(10, 10)
	header.Size = UDim2.new(1, -20, 0, 66)
	header.ZIndex = 3
	header.Parent = body
	local podium = UITheme.Icon("leaderboard", 60)
	if podium then
		podium.AnchorPoint = Vector2.new(0, 0.5)
		podium.Position = UDim2.new(0, 10, 0.5, 0)
		podium.ZIndex = 6
		podium.Parent = header
	end
	local title = UITheme.Label("Top Cash/s  ·  all servers", 36)
	title.Position = UDim2.fromOffset(78, 0)
	title.Size = UDim2.new(1, -90, 1, 0)
	title.ZIndex = 6
	UITheme.FitText(title, 36)
	title.Parent = header

	local rowHeight, gap, top = 38, 4, 86
	for i = 1, settings.size do
		local frame = UITheme.Panel("dark")
		frame.Position = UDim2.fromOffset(14, top + (i - 1) * (rowHeight + gap))
		frame.Size = UDim2.new(1, -28, 0, rowHeight)
		frame.ZIndex = 3
		frame.Visible = false
		frame.Parent = body
		local badge = UITheme.Panel(RANK_KINDS[i] or "grey")
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.new(0, 6, 0.5, 0)
		badge.Size = UDim2.fromOffset(44, 30)
		badge.ZIndex = 5
		badge.Parent = frame
		local rank = UITheme.Label(tostring(i), 22)
		rank.Size = UDim2.fromScale(1, 1)
		rank.ZIndex = 7
		rank.Parent = badge
		local name = UITheme.Label("", 24)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(62, 0)
		name.Size = UDim2.new(0.62, -62, 1, 0)
		name.ZIndex = 6
		UITheme.FitText(name, 24)
		name.Parent = frame
		local value = UITheme.Label("", 24, UITheme.colors.cash)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -12, 0, 0)
		value.Size = UDim2.new(0.38, -12, 1, 0)
		value.ZIndex = 6
		UITheme.FitText(value, 24)
		value.Parent = frame
		rows[i] = { frame = frame, badge = badge, rank = rank, name = name, value = value }
	end
	if sourcePanel then
		board:Destroy() -- V3 uses the source frame; no generated duplicate geometry
		return nil
	end
	board.Parent = Workspace:FindFirstChild("Map") or Workspace
	return board
end

local function writeBest(store: OrderedDataStore, player: Player)
	local data = PlayerDataService.Get(player)
	if not data then
		return
	end
	local value = math.floor(data.bestIncome * 100)
	if value <= 0 or written[player] == value then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(tostring(player.UserId), value)
	end)
	if ok then
		written[player] = value
	else
		warn(`[Leaderboard] write failed for {player.Name}: {err}`)
	end
end

local function refreshBoard(store: OrderedDataStore)
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, Config.Gameplay.leaderboard.size)
	end)
	if not ok then
		warn(`[Leaderboard] read failed: {pages}`)
		return
	end
	local entries = (pages :: DataStorePages):GetCurrentPage()
	local ids = {}
	for _, entry in entries do
		table.insert(ids, tonumber(entry.key) :: number)
	end
	local names: { [number]: string } = {}
	if #ids > 0 then
		local infoOk, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(ids)
		end)
		if infoOk then
			for _, info in infos do
				names[info.Id] = info.DisplayName
			end
		end
	end
	for i, row in rows do
		local entry = entries[i]
		if entry then
			local id = tonumber(entry.key) :: number
			row.name.Text = names[id] or `Player {id}`
			row.value.Text = `${Format.Short(entry.value / 100)}/s`
			row.badge.Visible = true
			row.frame.Visible = true
		elseif i == 1 then
			row.name.Text = "Be the first on the board!"
			row.value.Text = ""
			row.badge.Visible = false
			row.frame.Visible = true
		else
			row.frame.Visible = false
		end
	end
end

function LeaderboardService.Start()
	local store = DataStoreService:GetOrderedDataStore(storeName)
	task.spawn(buildBoard)

	-- Track each player's best income (cheap, every few seconds).
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in Players:GetPlayers() do
				local data = PlayerDataService.Get(player)
				local state = PlayerStateService.Get(player)
				if data and state and state.incomePerSecond > data.bestIncome then
					data.bestIncome = state.incomePerSecond
				end
			end
		end
	end)
	task.spawn(function()
		task.wait(8) -- saves load first
		while true do
			for _, player in Players:GetPlayers() do
				writeBest(store, player)
			end
			task.wait(Config.Gameplay.leaderboard.writeSeconds)
		end
	end)
	task.spawn(function()
		task.wait(15) -- after the first writes
		while true do
			refreshBoard(store)
			task.wait(Config.Gameplay.leaderboard.readSeconds)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		writeBest(store, player)
		written[player] = nil
	end)
end

return LeaderboardService
