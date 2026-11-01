--!strict
-- Compact server leaderboard (replaces Roblox's player list), opened and
-- closed with Tab (a small podium button on touch screens). A red stud
-- header over a see-through dark panel: columns Player | Cash/s, players
-- ranked by their leaderstats "Cash/s", gold/silver/bronze rings on the top
-- three, your row highlighted. Rows slide when the order changes. Closed at
-- start; steps aside while a menu window is open.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage.Shared.Format)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local Leaderboard = {}

local WIDTH = 270
local ROW_HEIGHT = 40
local HEADER_HEIGHT = 38
local COLUMNS_HEIGHT = 24
local RANK_COLORS = { UITheme.colors.gold, Color3.fromRGB(200, 205, 215), Color3.fromRGB(215, 135, 70) }

type Row = { frame: Frame, ring: UIStroke, value: TextLabel, order: number }

local function incomeOf(player: Player): number
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Cash/s")
	return if value and value:IsA("NumberValue") then value.Value else 0
end

function Leaderboard.Start()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	local me = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "Leaderboard"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local holder = Instance.new("Frame")
	holder.Name = "Board"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Size = UDim2.fromOffset(WIDTH, 400)
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	local camera = Workspace.CurrentCamera
	local function rescale()
		scale.Scale =
			math.clamp(math.min(camera.ViewportSize.X / 1150, camera.ViewportSize.Y / 720), 0.55, 1.1)
	end
	rescale()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Small dimensional stud header.
	local header = UITheme.Panel("red")
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.ZIndex = 2
	header.Parent = holder
	local podium = UITheme.Icon("leaderboard", 42)
	if podium then
		podium.AnchorPoint = Vector2.new(0.5, 0.5)
		podium.Position = UDim2.fromOffset(24, HEADER_HEIGHT / 2 - 2)
		podium.ZIndex = 5
		podium.Parent = header
	end
	local title = UITheme.Label("LEADERBOARD", 22)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(48, 0)
	title.Size = UDim2.new(1, -90, 1, 0)
	title.ZIndex = 5
	title.Parent = header
	local hint = UITheme.Label("Tab", 14, Color3.fromRGB(255, 220, 210))
	hint.AnchorPoint = Vector2.new(1, 0.5)
	hint.Position = UDim2.new(1, -10, 0.5, 0)
	hint.Size = UDim2.fromOffset(36, 20)
	hint.ZIndex = 5
	hint.Parent = header

	-- See-through body: column titles and the rows.
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
	body.BackgroundTransparency = 0.35
	body.Position = UDim2.fromOffset(4, HEADER_HEIGHT - 4)
	body.Size = UDim2.new(1, -8, 0, COLUMNS_HEIGHT + 8)
	body.ClipsDescendants = true
	UITheme.Corner(body, 6)
	UITheme.Outline(body, 2)
	body.Parent = holder
	local function column(text: string, alignRight: boolean)
		local label = UITheme.Label(text, 15, UITheme.colors.gold)
		label.TextXAlignment = if alignRight then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(12, 8)
		label.Size = UDim2.new(1, -24, 0, COLUMNS_HEIGHT - 4)
		label.Parent = body
	end
	column("Player", false)
	column("Cash/s", true)

	local rows: { [Player]: Row } = {}
	local function newRow(player: Player): Row
		local frame = Instance.new("Frame")
		frame.Name = player.Name
		frame.BackgroundColor3 = UITheme.colors.gold
		frame.BackgroundTransparency = if player == me then 0.75 else 1
		frame.BorderSizePixel = 0
		frame.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		frame.Position = UDim2.fromOffset(WIDTH, COLUMNS_HEIGHT + 8)
		frame.Parent = body
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Color3.new(1, 1, 1)
		line.BackgroundTransparency = 0.88
		line.Size = UDim2.new(1, -16, 0, 1)
		line.Position = UDim2.fromOffset(8, 0)
		line.Parent = frame

		local face = Instance.new("ImageLabel")
		face.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
		face.AnchorPoint = Vector2.new(0, 0.5)
		face.Position = UDim2.new(0, 10, 0.5, 0)
		face.Size = UDim2.fromOffset(30, 30)
		UITheme.Corner(face, 15)
		local ring = Instance.new("UIStroke")
		ring.Thickness = 2
		ring.Color = Color3.fromRGB(90, 90, 100)
		ring.Parent = face
		face.Parent = frame
		task.spawn(function()
			local ok, image = pcall(function()
				return Players:GetUserThumbnailAsync(
					player.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size48x48
				)
			end)
			if ok then
				face.Image = image
			end
		end)

		local name = UITheme.Label(player.DisplayName, 18)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(48, 0)
		name.Size = UDim2.new(0.58, -48, 1, 0)
		UITheme.FitText(name, 18)
		name.Parent = frame
		local cash = UITheme.Icon("cash", 22)
		if cash then
			cash.AnchorPoint = Vector2.new(1, 0.5)
			cash.Position = UDim2.new(1, -10, 0.5, 0)
			cash.Parent = frame
		end
		local value = UITheme.Label("", 18, UITheme.colors.cash)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, if cash then -36 else -10, 0, 0)
		value.Size = UDim2.new(0.42, -14, 1, 0)
		UITheme.FitText(value, 18)
		value.Parent = frame
		return { frame = frame, ring = ring, value = value, order = 0 }
	end

	local function refresh()
		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			local ia, ib = incomeOf(a), incomeOf(b)
			if ia == ib then
				return a.UserId < b.UserId
			end
			return ia > ib
		end)
		for index, player in players do
			local row = rows[player] or newRow(player)
			rows[player] = row
			row.ring.Color = RANK_COLORS[index] or Color3.fromRGB(90, 90, 100)
			row.ring.Thickness = if index <= 3 then 3 else 2
			row.value.Text = `${Format.Short(incomeOf(player))}`
			if row.order ~= index then
				row.order = index
				TweenService
					:Create(row.frame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
						Position = UDim2.fromOffset(0, COLUMNS_HEIGHT + 8 + (index - 1) * ROW_HEIGHT),
					})
					:Play()
			end
		end
		TweenService:Create(body, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
			Size = UDim2.new(1, -8, 0, COLUMNS_HEIGHT + 12 + #players * ROW_HEIGHT),
		}):Play()
	end

	-- Open/closed (Tab), and out of the way while a menu window is open.
	local open = false
	local function place()
		local away = not open or me:GetAttribute("MenuOpen") == true
		TweenService:Create(holder, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
			Position = if away then UDim2.new(1, WIDTH + 60, 0, 150) else UDim2.new(1, -12, 0, 150),
		}):Play()
	end
	local function toggle()
		open = not open
		place()
	end
	holder.Position = UDim2.new(1, WIDTH + 60, 0, 150)
	me:GetAttributeChangedSignal("MenuOpen"):Connect(place)
	ContextActionService:BindAction("ToggleLeaderboard", function(_, state)
		if state == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Tab)

	-- Touch screens have no Tab: a small podium button under the day timer.
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local button = UITheme.Button("red", UDim2.fromOffset(52, 52), "")
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -16, 0, 100)
		local icon = UITheme.Icon("leaderboard", 40)
		if icon then
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.ZIndex = 5
			icon.Parent = button
		end
		button.Activated:Connect(toggle)
		button.Parent = gui
	end

	Players.PlayerRemoving:Connect(function(player)
		local row = rows[player]
		rows[player] = nil
		if row then
			row.frame:Destroy()
		end
		refresh()
	end)
	Players.PlayerAdded:Connect(function()
		task.wait(1) -- leaderstats arrive a moment later
		refresh()
	end)

	gui.Parent = me:WaitForChild("PlayerGui")
	refresh()
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
end

return Leaderboard
