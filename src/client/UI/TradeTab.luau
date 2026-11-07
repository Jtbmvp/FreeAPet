--!strict
-- Tablet > Trade. Without a trade: the players in the server, each with a
-- "Trade" button (sends a request; they accept from a notification). In a
-- trade: what you give and what they give, your base pets to add (tap to
-- add, tap an offered pet to take it back) and Ready / Confirm / Cancel.
-- Shows TradeService's "TradeUpdate"; every rule is checked on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local PetPortrait = require(script.Parent.PetPortrait)
local TabletData = require(script.Parent.TabletData)

local TradeTab = {}

type Api = { Open: (tabId: string) -> (), Close: (() -> ())? }

local function petCard(pet: any, parent: Instance, onTap: (() -> ())?): TextButton
	local species = Config.Species[pet.speciesId]
	local card = Instance.new("TextButton")
	card.Text = ""
	card.Size = UDim2.fromOffset(104, 128)
	card.BackgroundColor3 = UITheme.colors.outline
	card.BackgroundTransparency = 0.4
	UITheme.Corner(card)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Config.Rarities[species.rarity].color
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	local portrait = PetPortrait.New(pet.speciesId, nil, pet.stage)
	portrait.Position = UDim2.fromOffset(7, 4)
	portrait.Size = UDim2.fromOffset(90, 78)
	portrait.Parent = card
	local name = UITheme.Label(species.displayName, 15)
	name.Position = UDim2.fromOffset(4, 84)
	name.Size = UDim2.new(1, -8, 0, 20)
	UITheme.FitText(name, 15)
	name.Parent = card
	local level = UITheme.Label(`Lv {pet.level}`, 14, UITheme.colors.gold)
	level.Position = UDim2.fromOffset(4, 104)
	level.Size = UDim2.new(1, -8, 0, 18)
	level.Parent = card
	card.Parent = parent
	if onTap then
		card.Activated:Connect(onTap)
	end
	return card
end

local function row(parent: Instance, position: UDim2, size: UDim2): ScrollingFrame
	local frame = Instance.new("ScrollingFrame")
	frame.BackgroundColor3 = UITheme.colors.outline
	frame.BackgroundTransparency = 0.55
	frame.BorderSizePixel = 0
	frame.Position = position
	frame.Size = size
	frame.CanvasSize = UDim2.new()
	frame.AutomaticCanvasSize = Enum.AutomaticSize.X
	frame.ScrollingDirection = Enum.ScrollingDirection.X
	frame.ScrollBarThickness = 6
	UITheme.Corner(frame)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.Parent = frame
	frame.Parent = parent
	return frame
end

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiButton") or (child:IsA("TextLabel") and child.Name == "Empty") then
			child:Destroy()
		end
	end
end

local function emptyText(frame: Instance, text: string)
	local label = UITheme.Label(text, 16, Color3.fromRGB(190, 205, 235))
	label.Name = "Empty"
	label.Size = UDim2.fromOffset(300, 40)
	label.Parent = frame
end

function TradeTab.Mount(container: Frame, api: Api)
	local alive = true
	local connections: { RBXScriptConnection } = {}
	local function listen(signal: RBXScriptSignal, callback: any)
		local connection = signal:Connect(callback)
		table.insert(connections, connection)
	end
	local player = Players.LocalPlayer
	local state: any = nil -- last TradeUpdate
	local visible = false
	local closeRequested = false

	-- No trade: the players list.
	local lobby = Instance.new("Frame")
	lobby.BackgroundTransparency = 1
	lobby.Size = UDim2.fromScale(1, 1)
	lobby.Parent = container
	local lobbyTitle = UITheme.Label("Trade pets with a player in this server.", 20)
	lobbyTitle.TextXAlignment = Enum.TextXAlignment.Left
	lobbyTitle.Size = UDim2.new(1, 0, 0, 28)
	UITheme.FitText(lobbyTitle, 20)
	lobbyTitle.Parent = lobby
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 36)
	list.Size = UDim2.new(1, 0, 1, -36)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.Parent = lobby
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = list

	-- In a trade.
	local room = Instance.new("Frame")
	room.BackgroundTransparency = 1
	room.Size = UDim2.fromScale(1, 1)
	room.Visible = false
	room.Parent = container

	local giveTitle = UITheme.Label("You give", 18, UITheme.colors.gold)
	giveTitle.TextXAlignment = Enum.TextXAlignment.Left
	giveTitle.Size = UDim2.new(0.5, -6, 0, 24)
	giveTitle.Parent = room
	local getTitle = UITheme.Label("They give", 18, UITheme.colors.gold)
	getTitle.TextXAlignment = Enum.TextXAlignment.Left
	getTitle.Position = UDim2.new(0.5, 6, 0, 0)
	getTitle.Size = UDim2.new(0.5, -6, 0, 24)
	getTitle.Parent = room
	local giveRow = row(room, UDim2.fromOffset(0, 28), UDim2.new(0.5, -6, 0, 144))
	local getRow = row(room, UDim2.new(0.5, 6, 0, 28), UDim2.new(0.5, -6, 0, 144))

	local status = UITheme.Label("", 18)
	status.Position = UDim2.fromOffset(0, 180)
	status.Size = UDim2.new(1, 0, 0, 24)
	UITheme.FitText(status, 18)
	status.Parent = room

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Position = UDim2.fromOffset(0, 210)
	buttons.Size = UDim2.new(1, 0, 0, 56)
	buttons.Parent = room
	local buttonsLayout = Instance.new("UIListLayout")
	buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buttonsLayout.Padding = UDim.new(0, 10)
	buttonsLayout.Parent = buttons
	local readyButton, readyText = UITheme.Button("info", UDim2.fromOffset(180, 54), "Ready")
	readyButton.Parent = buttons
	local confirmButton, confirmText = UITheme.Button("disabled", UDim2.fromOffset(180, 54), "Confirm")
	confirmButton.Parent = buttons
	local cancelButton, _ = UITheme.Button("warning", UDim2.fromOffset(150, 54), "Cancel")
	cancelButton.Parent = buttons

	local function reflowButtons()
		local width = math.max(48, math.floor((container.AbsoluteSize.X - 24) / 3))
		for _, button in { readyButton, confirmButton, cancelButton } do
			button.Size = UDim2.fromOffset(width, 54)
		end
	end
	listen(container:GetPropertyChangedSignal("AbsoluteSize"), reflowButtons)
	reflowButtons()
	local baseTitle = UITheme.Label("Your base pets (tap to add)", 16, Color3.fromRGB(190, 205, 235))
	baseTitle.TextXAlignment = Enum.TextXAlignment.Left
	baseTitle.Position = UDim2.fromOffset(0, 274)
	baseTitle.Size = UDim2.new(1, 0, 0, 22)
	baseTitle.Parent = room
	local baseRow = row(room, UDim2.fromOffset(0, 298), UDim2.new(1, 0, 1, -298))

	local function action(payload: { [string]: any })
		Remotes.Get("TradeAction"):FireServer(payload)
	end
	readyButton.Activated:Connect(function()
		action({ kind = "ready" })
	end)
	confirmButton.Activated:Connect(function()
		action({ kind = "confirm" })
	end)
	cancelButton.Activated:Connect(function()
		action({ kind = "cancel" })
	end)

	local function refreshLobby()
		local level = player:GetAttribute("PlayerLevel")
		local unlocked = typeof(level) == "number"
			and level >= Config.Progression.unlocks.Trade
			and player:GetAttribute("DataLoaded") == true
		lobbyTitle.Text = if unlocked
			then "Trade pets with a player in this server."
			else `Trade unlocks at player level {Config.Progression.unlocks.Trade}.`
		for _, child in list:GetChildren() do
			if child:IsA("Frame") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end
		local count = 0
		for _, other in Players:GetPlayers() do
			if other ~= player then
				count += 1
				local entry = UITheme.Panel("blue")
				entry.Size = UDim2.new(1, -8, 0, 60)
				local name = UITheme.Label(other.DisplayName, 22)
				name.TextXAlignment = Enum.TextXAlignment.Left
				name.Position = UDim2.fromOffset(14, 0)
				name.Size = UDim2.new(1, -190, 1, 0)
				name.ZIndex = 4
				UITheme.FitText(name, 22)
				name.Parent = entry
				local button, _ = UITheme.Button(
					"action",
					UDim2.fromOffset(150, 46),
					if unlocked then "Trade" else `Player Lv {Config.Progression.unlocks.Trade}`
				)
				button.AnchorPoint = Vector2.new(1, 0.5)
				button.Position = UDim2.new(1, -8, 0.5, 0)
				button.Parent = entry
				button.Activated:Connect(function()
					if player:GetAttribute("TradeUnlocked") == true then
						Remotes.Get("TradeRequest"):FireServer(other.UserId)
					end
				end)
				entry.Parent = list
			end
		end
		if count == 0 then
			-- Empty state: big trade icon and a line under it.
			local none = Instance.new("Frame")
			none.BackgroundTransparency = 1
			none.Size = UDim2.new(1, 0, 0, 220)
			local icon = UITheme.Icon("trade", 120)
			if icon then
				icon.AnchorPoint = Vector2.new(0.5, 0)
				icon.Position = UDim2.new(0.5, 0, 0, 30)
				icon.ImageTransparency = 0.35
				icon.Parent = none
			end
			local text = UITheme.Label("Nobody else is in this server right now.", 22)
			text.Position = UDim2.fromOffset(0, 160)
			text.Size = UDim2.new(1, 0, 0, 30)
			UITheme.FitText(text, 22)
			text.Parent = none
			none.Parent = list
		end
	end

	local function refreshRoom()
		if not state or not state.active then
			return
		end
		getTitle.Text = `{state.partner} gives`
		clear(giveRow)
		clear(getRow)
		clear(baseRow)
		local offered: { [string]: boolean } = {}
		for _, pet in state.mine do
			offered[pet.id] = true
			petCard(pet, giveRow, function()
				action({ kind = "remove", id = pet.id })
			end)
		end
		for _, pet in state.theirs do
			petCard(pet, getRow, nil)
		end
		if #state.mine == 0 then
			emptyText(giveRow, "Nothing yet")
		end
		if #state.theirs == 0 then
			emptyText(getRow, "Nothing yet")
		end
		local data = TabletData.Get()
		local shown = 0
		for _, pet in (data and data.pets or {}) do
			if pet.state == "InBase" and not offered[pet.id] then
				shown += 1
				petCard(pet, baseRow, function()
					action({ kind = "add", id = pet.id })
				end)
			end
		end
		if shown == 0 then
			emptyText(baseRow, "No pets in your base to add")
		end

		readyText.Text = if state.myReady then "Ready ✓" else "Ready"
		UITheme.Recolor(readyButton, if state.myReady then UITheme.colors.success else UITheme.colors.info)
		local canConfirm = state.myReady and state.theirReady and not state.myConfirm
		confirmText.Text = if state.myConfirm then "Confirmed ✓" else "Confirm"
		UITheme.Recolor(
			confirmButton,
			if canConfirm
				then UITheme.colors.action
				elseif state.myConfirm then UITheme.colors.success
				else UITheme.colors.disabled
		)
		local partnerState = if state.theirConfirm
			then "confirmed"
			elseif state.theirReady then "is ready"
			else "is choosing"
		status.Text = if state.countdown
			then `Trading in {math.ceil(state.countdown)}...`
			else `{state.partner} {partnerState}.` .. (if state.note then `  {state.note}` else "")
	end

	local function show()
		local active = state ~= nil and state.active
		lobby.Visible = not active
		room.Visible = active
		if active then
			refreshRoom()
		else
			refreshLobby()
		end
	end

	listen(Remotes.Get("TradeUpdate").OnClientEvent, function(newState)
		local started = newState.active and not (state and state.active)
		state = newState
		if closeRequested and not newState.active then
			closeRequested = false
			if api.Close then
				api.Close()
			end
		end
		if started then
			TabletData.Invalidate()
			api.Open("Trade")
		end
		if not newState.active then
			TabletData.Invalidate()
			if newState.note then
				lobbyTitle.Text = newState.note
			end
		end
		if visible then
			show()
		end
		if newState.countdown then
			-- Tick the countdown on screen.
			task.spawn(function()
				local endsAt = os.clock() + newState.countdown
				while alive and state == newState and os.clock() < endsAt do
					status.Text = `Trading in {math.ceil(endsAt - os.clock())}...`
					task.wait(0.2)
				end
			end)
		end
	end)
	listen(Players.PlayerAdded, function()
		if visible and not (state and state.active) then
			refreshLobby()
		end
	end)
	listen(Players.PlayerRemoving, function()
		if visible and not (state and state.active) then
			task.defer(refreshLobby)
		end
	end)

	return {
		Destroy = function()
			alive = false
			visible = false
			for _, connection in connections do
				connection:Disconnect()
			end
		end,
		RequestClose = function(): boolean
			if state and state.active then
				if not closeRequested then
					closeRequested = true
					action({ kind = "cancel" })
				end
				return false
			end
			return true
		end,
		Show = function()
			visible = true
			show()
		end,
		Hide = function()
			visible = false
		end,
	}
end

return TradeTab
