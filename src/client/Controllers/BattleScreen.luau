--!strict
-- Battle screen: shows what BattleService sends ("Battle" remote) and sends
-- the player's choices ("BattleAction"). A battle opens with the cinematic
-- intro (Battle/BattleIntro) and is filmed by Battle/BattleCamera; each
-- event is shown in the message box and animated on this client only
-- (attacks through Battle/Fx, faint, capsule). The rest of the HUD hides meanwhile.
-- Decides nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local Battle = script.Parent.Parent.Battle
local BattleCamera = require(Battle.BattleCamera)
local BattleIntro = require(Battle.BattleIntro)
local BattleObstacles = require(Battle.BattleObstacles)
local BattleSettings = require(Battle.BattleSettings)
local Common = require(Battle.Fx.Common)
local Fx = require(Battle.Fx)

local PetAnimator = require(script.Parent.PetAnimator)

local CapsuleSequence = require(Battle.CapsuleSequence)

local BattleScreen = {}

local TYPE_COLORS = Common.TYPE_COLORS
-- HUD that steps aside for the battle (their own visibility logic is kept).
local HUD_GUIS = { "CashHud", "Leaderboard", "DayHud", "DebugHud" }
local EVENT_SECONDS = 0.95
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

type Card = {
	frame: Frame,
	name: TextLabel,
	level: TextLabel,
	fill: Frame,
	hpText: TextLabel,
	onHp: ((number, number, boolean?) -> ())?,
}

local function newCard(parent: Instance, anchor: Vector2, position: UDim2): Card
	local frame = UITheme.Panel()
	frame.AnchorPoint = anchor
	frame.Position = position
	frame.Size = UDim2.fromOffset(330, 92)
	frame.Parent = parent
	local name = UITheme.Label("", 24)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Position = UDim2.fromOffset(14, 8)
	name.Size = UDim2.new(1, -96, 0, 30)
	UITheme.FitText(name, 24)
	name.ZIndex = 3
	name.Parent = frame
	-- Level in its own gold chip (Figma kit), not squeezed into the name.
	local chip = UITheme.Panel("yellow")
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, -12, 0, 10)
	chip.Size = UDim2.fromOffset(66, 26)
	chip.ZIndex = 3
	chip.Parent = frame
	local level = UITheme.Label("", 18)
	level.Size = UDim2.fromScale(1, 1)
	level.ZIndex = 5
	level.Parent = chip
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(14, 46)
	bar.Size = UDim2.new(1, -28, 0, 18)
	bar.BackgroundColor3 = UITheme.colors.outline
	UITheme.Corner(bar, 9)
	bar.ZIndex = 3
	bar.Parent = frame
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = UITheme.colors.cash
	UITheme.Corner(fill, 9)
	fill.ZIndex = 4
	fill.Parent = bar
	local hpText = UITheme.Label("", 16)
	hpText.TextXAlignment = Enum.TextXAlignment.Right
	hpText.Position = UDim2.fromOffset(14, 66)
	hpText.Size = UDim2.new(1, -28, 0, 20)
	hpText.ZIndex = 3
	hpText.Parent = frame
	return { frame = frame, name = name, level = level, fill = fill, hpText = hpText }
end

local function setHp(card: Card, hp: number, maxHp: number, instant: boolean?)
	if card.onHp then
		card.onHp(hp, maxHp, instant)
	end
	local fraction = math.clamp(hp / math.max(maxHp, 1), 0, 1)
	local color = if fraction > 0.5
		then UITheme.colors.cash
		elseif fraction > 0.2 then UITheme.colors.gold
		else Color3.fromRGB(255, 90, 80)
	local goal = { Size = UDim2.fromScale(fraction, 1), BackgroundColor3 = color }
	if instant then
		card.fill.Size = goal.Size
		card.fill.BackgroundColor3 = color
	else
		TweenService:Create(card.fill, TweenInfo.new(0.45, Enum.EasingStyle.Quad), goal):Play()
	end
	card.hpText.Text = `{math.max(0, math.ceil(hp))}/{maxHp} HP`
end

-- A one-off particle burst at a model (client only).
local function burst(model: Model?, texture: string, color: Color3, count: number)
	local root = model and model.PrimaryPart
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.6
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.35, 0.6)
	emitter.Speed = NumberRange.new(10, 18)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)
	task.delay(1, function()
		attachment:Destroy()
	end)
end

local function faint(model: Model?)
	local root = model and model.PrimaryPart
	if not root then
		return
	end
	-- Faint owns its fall and final pose; only legacy rigs use the procedural tip.
	local length = PetAnimator.PlayOnce(model :: Model, "Faint", true)
	if not length then
		TweenService:Create(root, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
			CFrame = root.CFrame * CFrame.Angles(0, 0, math.rad(80)) - Vector3.new(0, 0.6, 0),
		}):Play()
	end
	burst(model, SMOKE, Color3.fromRGB(200, 200, 200), 16)
end

function BattleScreen.Start()
	local player = Players.LocalPlayer
	local design: any = nil
	if Config.UI.userHudEnabled and Config.UI.designHudEnabled then
		design = require(script.Parent.Parent.UI.DesignBattle).new()
	end
	local epoch, destroyed = 0, false
	local cameraTicket: number? = nil
	local queue: { any } = {}
	local function invalidate()
		epoch += 1
		Fx.CancelAll()
		CapsuleSequence.CancelAll()
	end
	local camera = Workspace.CurrentCamera

	local gui = Instance.new("ScreenGui")
	gui.Name = "Battle"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Enabled = false
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local viewport = camera.ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X, viewport.Y) / 720, 0.6, 1.3)
	end
	rescale()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local wildCard = newCard(gui, Vector2.new(0, 0), UDim2.fromOffset(20, 70))
	local mineCard = newCard(gui, Vector2.new(0, 1), UDim2.new(0, 20, 1, -150))
	if design then
		wildCard.onHp = function(hp, maxHp, instant)
			design:SetHp("wild", hp, maxHp, instant)
		end
		mineCard.onHp = function(hp, maxHp, instant)
			design:SetHp("mine", hp, maxHp, instant)
		end
	end
	mineCard.frame.Size += UDim2.fromOffset(0, 12)
	local xpBar = Instance.new("Frame")
	xpBar.BackgroundColor3 = UITheme.colors.outline
	xpBar.Position = UDim2.fromOffset(14, 90)
	xpBar.Size = UDim2.new(1, -28, 0, 7)
	xpBar.ZIndex = 3
	UITheme.Corner(xpBar, 4)
	xpBar.Parent = mineCard.frame
	local xpFill = Instance.new("Frame")
	xpFill.BackgroundColor3 = UITheme.colors.speed
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.ZIndex = 4
	UITheme.Corner(xpFill, 4)
	xpFill.Parent = xpBar
	-- Team dots: one per team pet, grey once it fainted.
	local dots: { Frame } = {}
	for i = 1, 3 do
		local dot = Instance.new("Frame")
		dot.Position = UDim2.fromOffset(14 + (i - 1) * 20, 68)
		dot.Size = UDim2.fromOffset(14, 14)
		dot.ZIndex = 4
		dot.Visible = false
		UITheme.Corner(dot, 7)
		UITheme.Outline(dot, 2)
		dot.Parent = mineCard.frame
		dots[i] = dot
	end

	local message = Instance.new("Frame")
	message.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
	message.BackgroundTransparency = 0.15
	UITheme.Corner(message, 28)
	UITheme.Outline(message)
	message.AnchorPoint = Vector2.new(0.5, 0)
	message.Position = UDim2.new(0.5, 0, 0, 12)
	message.Size = UDim2.fromOffset(520, 56)
	message.Parent = gui
	local messageText = UITheme.Label("", 22)
	messageText.Size = UDim2.new(1, -20, 1, 0)
	messageText.Position = UDim2.fromOffset(10, 0)
	messageText.ZIndex = 3
	UITheme.FitText(messageText, 22)
	messageText.Parent = message
	if design then
		messageText:GetPropertyChangedSignal("Text"):Connect(function()
			design.HUD:SetPrompt(messageText.Text)
		end)
	end

	-- Actions: 4 moves (2x2) and Capsule / Switch / Run.
	local actions = Instance.new("Frame")
	actions.BackgroundTransparency = 1
	actions.AnchorPoint = Vector2.new(1, 1)
	actions.Position = UDim2.new(1, -20, 1, -20)
	actions.Size = UDim2.fromOffset(470, 250)
	actions.Parent = gui
	-- Main actions (2x2): Attack opens the four moves, Bag throws a Pet
	-- Capsule, Switch picks a team pet, Run leaves.
	local mainFrame = Instance.new("Frame")
	mainFrame.BackgroundTransparency = 1
	mainFrame.Position = UDim2.fromOffset(0, 62)
	mainFrame.Size = UDim2.new(1, 0, 0, 188)
	mainFrame.Parent = actions
	local movesFrame = Instance.new("Frame")
	movesFrame.BackgroundTransparency = 1
	movesFrame.Size = UDim2.fromScale(1, 1)
	movesFrame.Visible = false
	movesFrame.Parent = actions
	local function bigButton(
		kind: string,
		iconKey: string,
		text: string,
		slot: number
	): (TextButton, TextLabel)
		local button, label = UITheme.Button(kind, UDim2.fromOffset(228, 86), text)
		button.Position = UDim2.fromOffset(((slot - 1) % 2) * 242, math.floor((slot - 1) / 2) * 100)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(76, 0)
		label.Size = UDim2.new(1, -82, 1, 0)
		UITheme.FitText(label, 30)
		local icon = UITheme.Icon(iconKey, 62)
		if icon then
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 10, 0.5, 0)
			icon.ZIndex = 4
			icon.Parent = button
		end
		button.Parent = mainFrame
		return button, label
	end
	local attackButton = bigButton("red", "sword", "Attack", 1)
	local capsuleButton, capsuleLabel = bigButton("blue", "bag", "Bag", 2)
	local switchButton = bigButton("green", "trade", "Switch", 3)
	local runButton = bigButton("purple", "speed", "Run", 4)

	local moveButtons: { { button: TextButton, label: TextLabel } } = {}
	for i = 1, 4 do
		local button, label = UITheme.Button("info", UDim2.fromOffset(228, 70))
		button.Position = UDim2.fromOffset(((i - 1) % 2) * 242, math.floor((i - 1) / 2) * 80)
		button.Parent = movesFrame
		label.TextWrapped = true
		moveButtons[i] = { button = button, label = label }
	end
	local backButton = UITheme.Button("grey", UDim2.fromOffset(470, 60), "Back")
	backButton.Position = UDim2.fromOffset(0, 172)
	backButton.Parent = movesFrame
	local function showMoves(show: boolean)
		movesFrame.Visible = show
		mainFrame.Visible = not show
	end
	backButton.Activated:Connect(function()
		showMoves(false)
	end)

	-- Switch list (team pets), shown over the move buttons.
	local switchPanel = UITheme.Panel()
	switchPanel.AnchorPoint = Vector2.new(1, 1)
	switchPanel.Position = UDim2.new(1, -20, 1, -100)
	switchPanel.Size = UDim2.fromOffset(470, 170)
	switchPanel.Visible = false
	switchPanel.Parent = gui
	local switchList = Instance.new("Frame")
	switchList.BackgroundTransparency = 1
	switchList.Position = UDim2.fromOffset(10, 10)
	switchList.Size = UDim2.new(1, -20, 1, -20)
	switchList.ZIndex = 3
	switchList.Parent = switchPanel
	local switchLayout = Instance.new("UIListLayout")
	switchLayout.Padding = UDim.new(0, 6)
	switchLayout.Parent = switchList

	local view: any = nil -- the last state from the server
	local busy = false -- playing events: no input
	local inBattle = false

	local function setActionsEnabled(enabled: boolean)
		if design then
			design:Actions(enabled)
		end
		actions.Visible = enabled
		showMoves(false)
		if not enabled then
			switchPanel.Visible = false
		end
	end

	local function refreshButtons()
		if design and view then
			design:Refresh(view)
		end
		if not view then
			return
		end
		for i, entry in moveButtons do
			local move = view.mine.moves[i]
			local colors = TYPE_COLORS[move.type] or TYPE_COLORS.Neutral
			local usable = move.usesLeft == nil or move.usesLeft > 0
			UITheme.Recolor(entry.button, if usable then colors else UITheme.colors.disabled)
			local uses = if move.maxUses then `  {move.usesLeft}/{move.maxUses}` else ""
			entry.label.Text = `{move.name}\n{move.type} · {move.power}{uses}`
		end
		-- Capsules only against wild pets; a defending owner can only pick moves.
		local attacker = view.role ~= "defender"
		local canBag = attacker and view.kind == "wild"
		UITheme.Recolor(capsuleButton, if canBag then UITheme.colors.blue else UITheme.colors.disabled)
		UITheme.Recolor(switchButton, if attacker then UITheme.colors.green else UITheme.colors.disabled)
		UITheme.Recolor(runButton, if attacker then UITheme.colors.purple else UITheme.colors.disabled)
		capsuleLabel.Text = if view.capsules > 0
			then `Bag  x{view.capsules}`
			else `Bag  ${Format.Short(view.capsulePrice)}`
	end

	local function showCards()
		local wildSpecies = Config.Species[view.wild.speciesId]
		local mineSpecies = Config.Species[view.mine.speciesId]
		wildCard.name.Text = view.foeName or ("Wild " .. wildSpecies.displayName)
		wildCard.level.Text = `Lv {view.wild.level}`
		mineCard.name.Text = mineSpecies.displayName
		mineCard.level.Text = `Lv {view.mine.level}`
		for i, dot in dots do
			local fighter = view.team and view.team[i]
			dot.Visible = fighter ~= nil
			if fighter then
				dot.BackgroundColor3 = if fighter.hp > 0
					then UITheme.colors.cash
					else Color3.fromRGB(90, 90, 100)
			end
		end
		local xpShare = (view.mine.xp or 0) / math.max(view.mine.xpToNext or 1, 1)
		TweenService
			:Create(xpFill, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(xpShare, 0, 1), 1) })
			:Play()
	end

	local hidden: { [ScreenGui]: boolean } = {}
	local function showHud(show: boolean)
		if show then
			for hud, wasEnabled in hidden do
				hud.Enabled = wasEnabled
			end
			table.clear(hidden)
			return
		end
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		for _, name in HUD_GUIS do
			local hud = playerGui and playerGui:FindFirstChild(name)
			if hud and hud:IsA("ScreenGui") and hidden[hud] == nil then
				hidden[hud] = hud.Enabled
				hud.Enabled = false
			end
		end
	end

	-- The battle UI slides in from the edges once the intro is over.
	local panels = {
		{ frame = wildCard.frame, from = UDim2.fromOffset(-420, 0) },
		{ frame = mineCard.frame, from = UDim2.fromOffset(-420, 0) },
		{ frame = message, from = UDim2.fromOffset(0, -140) },
		{ frame = actions, from = UDim2.fromOffset(560, 0) },
	}
	local homes: { [GuiObject]: UDim2 } = {}
	for _, panel in panels do
		homes[panel.frame] = panel.frame.Position
	end
	local function slidePanels(show: boolean)
		if design then
			if show then
				design:Show()
			else
				design:Hide()
			end
		end
		for index, panel in panels do
			local home = homes[panel.frame]
			if show then
				panel.frame.Position = home + panel.from
				task.delay(0.06 * index, function()
					if destroyed or not inBattle then
						return
					end
					TweenService:Create(
						panel.frame,
						TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{ Position = home }
					):Play()
				end)
			else
				panel.frame.Position = home + panel.from
			end
		end
	end

	local function leave(immediate: boolean?)
		invalidate()
		table.clear(queue)
		inBattle = false
		gui.Enabled = false
		if design then
			design:Hide()
		end
		UserInputService.ModalEnabled = false
		showHud(true)
		BattleObstacles.Restore()
		local ticket = cameraTicket
		if ticket then
			if immediate then
				BattleCamera.Release(0, ticket)
				if cameraTicket == ticket then
					cameraTicket = nil
				end
			else
				task.spawn(function()
					BattleCamera.Release(0.6, ticket)
					if cameraTicket == ticket then
						cameraTicket = nil
					end
				end)
			end
		end
	end

	local function send(action: { [string]: any })
		if busy or not inBattle then
			return
		end
		setActionsEnabled(false)
		Remotes.Get("BattleAction"):FireServer(action)
	end

	if design then
		design.HUD.Attack:Connect(function(index)
			local move = view and view.mine.moves[index]
			if move and (move.usesLeft == nil or move.usesLeft > 0) then
				send({ kind = "move", index = index })
			end
		end)
		design.HUD.Throw:Connect(function()
			if view and view.role ~= "defender" and view.kind == "wild" then
				send({ kind = "capsule" })
			end
		end)
		design.HUD.Run:Connect(function()
			if view and view.role ~= "defender" then
				send({ kind = "run" })
			end
		end)
		design.HUD.Switch:Connect(function(index)
			local pet = view and view.team[index]
			if view and view.role ~= "defender" and pet and pet.id ~= view.mine.id and pet.hp > 0 then
				send({ kind = "switch", petId = pet.id })
			end
		end)
	end
	for i, entry in moveButtons do
		entry.button.Activated:Connect(function()
			local move = view and view.mine.moves[i]
			if move and (move.usesLeft == nil or move.usesLeft > 0) then
				send({ kind = "move", index = i })
			end
		end)
	end
	attackButton.Activated:Connect(function()
		if not busy then
			showMoves(true)
		end
	end)
	capsuleButton.Activated:Connect(function()
		if view and view.role ~= "defender" and view.kind == "wild" then
			send({ kind = "capsule" })
		end
	end)
	runButton.Activated:Connect(function()
		if view and view.role ~= "defender" then
			send({ kind = "run" })
		end
	end)
	switchButton.Activated:Connect(function()
		if busy or not view or view.role == "defender" then
			return
		end
		for _, child in switchList:GetChildren() do
			if child ~= switchLayout then
				child:Destroy()
			end
		end
		local count = 0
		for _, pet in view.team do
			if pet.id ~= view.mine.id and pet.hp > 0 then
				count += 1
				local name = Config.Species[pet.speciesId].displayName
				local button, _ = UITheme.Button(
					"info",
					UDim2.new(1, 0, 0, 44),
					`{name}  Lv {pet.level}  ({pet.hp}/{pet.maxHp})`
				)
				button.ZIndex = 4
				button.Parent = switchList
				button.Activated:Connect(function()
					switchPanel.Visible = false
					send({ kind = "switch", petId = pet.id })
				end)
			end
		end
		if count == 0 then
			local none = UITheme.Label("No other healthy pet in your team.", 18)
			none.Size = UDim2.new(1, 0, 0, 40)
			none.ZIndex = 4
			none.Parent = switchList
		end
		switchPanel.Visible = not switchPanel.Visible
	end)

	-- Plays the events of one update, then shows the new state.
	local function play(newView: any)
		local token = epoch
		local function cancelled(): boolean
			return destroyed or not inBattle or token ~= epoch
		end
		busy = true
		local previous = view
		local hp = {
			mine = if previous then previous.mine.hp else newView.mine.hp,
			wild = if previous then previous.wild.hp else newView.wild.hp,
		}
		local maxHp = {
			mine = if previous then previous.mine.maxHp else newView.mine.maxHp,
			wild = newView.wild.maxHp,
		}
		local models = {
			mine = if previous then previous.mine.model else newView.mine.model,
			wild = newView.wild.model,
		}
		for _, event in newView.events do
			if cancelled() then
				return
			end
			local pause = if previous then EVENT_SECONDS else 0.5
			messageText.Text = event.text
			if event.effect == "capture" or event.effect == "escape" then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				CapsuleSequence.Play(
					if root then root.Position + Vector3.new(0, 2, 0) else newView.centre.Position,
					models.wild,
					event.damage or 1,
					event.effect == "capture",
					cancelled
				)
			elseif event.damage and event.actor and event.target then
				-- The attack's own animation and effects (Battle/Fx); the HP
				-- bar drops at its hit frame.
				local attacker = models[event.actor]
				local targetSide = event.target
				hp[targetSide] -= event.damage
				Fx.Play({
					attacker = attacker,
					target = models[targetSide],
					species = attacker and attacker:GetAttribute("SpeciesId") or "",
					move = event.move or "",
					moveType = event.moveType or "Neutral",
					effect = event.effect,
					damage = event.damage,
					cancelled = cancelled,
					onBeat = BattleCamera.OnBeat,
					impact = function()
						setHp(
							if targetSide == "mine" then mineCard else wildCard,
							hp[targetSide],
							maxHp[targetSide]
						)
					end,
					clip = function()
						return nil, nil
					end,
				})
				pause = 0.35
			elseif event.effect == "faint" and event.target then
				faint(models[event.target])
			elseif event.effect == "levelup" then
				Sfx.Play("levelUp")
				models.mine, models.wild = newView.mine.model, newView.wild.model
				BattleCamera.SetPets(models.mine, models.wild)
				if models.mine then
					PetAnimator.PlayOnce(models.mine, "Happy")
				end
			elseif event.effect == "switch" then
				view = newView
				models.mine = newView.mine.model
				BattleCamera.SetPets(newView.mine.model, newView.wild.model)
				hp.mine, maxHp.mine = newView.mine.hp, newView.mine.maxHp
				showCards()
				setHp(mineCard, hp.mine, maxHp.mine, true)
			end
			-- The intro already named both pets: its lines go by quicker;
			-- an attack already took its time.
			task.wait(pause)
			if cancelled() then
				return
			end
		end
		if cancelled() then
			return
		end
		view = newView
		showCards()
		setHp(wildCard, newView.wild.hp, newView.wild.maxHp)
		setHp(mineCard, newView.mine.hp, newView.mine.maxHp)
		refreshButtons()
		busy = false
		if newView.result then
			local texts = if newView.role == "defender"
				then {
					won = "You defended your pet!",
					lost = "Your pet was beaten...",
					ran = "The battle is over.",
				}
				else {
					won = "You won!",
					captured = "Caught! It's yours now.",
					lost = "Your team fainted...",
					ran = "You left the battle.",
				}
			messageText.Text = texts[newView.result] or ""
			if newView.result == "won" or newView.result == "captured" then
				Sfx.Play("won")
				if models.mine then
					PetAnimator.PlayOnce(models.mine, "Happy")
				end
			end
			if design then
				design:Result(newView, messageText.Text)
			end
			task.wait(1.6)
			if not cancelled() then
				leave()
			end
		else
			local petName = Config.Species[newView.mine.speciesId].displayName
			messageText.Text = if newView.role == "defender"
				then `Defend! Pick {petName}'s next move.`
				else `What will {petName} do?`
			setActionsEnabled(true)
		end
	end

	local function cardOf(fighter: any, name: string): Common.CardInfo
		local battleSpecies = Config.Battle.species[fighter.speciesId]
		local species = Config.Species[fighter.speciesId]
		return {
			name = name,
			level = fighter.level,
			rarity = species and species.rarity,
			moveType = battleSpecies and battleSpecies.type,
		}
	end

	-- First view of a battle: take the camera, play the intro, show the UI.
	local function begin(newView: any): boolean
		invalidate()
		local token = epoch
		local function cancelled(): boolean
			return destroyed or not inBattle or token ~= epoch
		end
		inBattle = true
		if design then
			design:Begin(newView)
		end
		view = nil
		gui.Enabled = true
		slidePanels(false)
		showHud(false)
		-- Phones: hide the thumbstick and jump button, they would sit under the moves.
		UserInputService.ModalEnabled = true
		setActionsEnabled(false)
		view = newView
		showCards()
		setHp(wildCard, newView.wild.hp, newView.wild.maxHp, true)
		setHp(mineCard, newView.mine.hp, newView.mine.maxHp, true)
		view = nil -- let play() treat this as the first update
		messageText.Text = ""

		local arena: Instance? = newView.arena
		if not arena then
			-- The arena may not have replicated with the first message: find it.
			local battles = Workspace:FindFirstChild("Battles")
			local closest = math.huge
			for _, candidate in (battles and battles:GetChildren() or {}) do
				if candidate:IsA("Model") then
					local distance = (candidate:GetPivot().Position - newView.centre.Position).Magnitude
					if distance < closest then
						arena, closest = candidate, distance
					end
				end
			end
		end
		local mineName = Config.Species[newView.mine.speciesId].displayName
		cameraTicket = BattleCamera.Begin(newView.centre, newView.mine.model, newView.wild.model)
		-- Clear the view: other pets, players and small props in the ring or
		-- in front of the camera hide for this player until the battle ends.
		local keepList: { Instance? } = { newView.mine.model, newView.wild.model, newView.foeTrainer }
		for _, fighter in newView.team or {} do
			table.insert(keepList, fighter.model)
		end
		local eye, focus = BattleCamera.Gameplay()(0)
		local targets = { focus }
		for _, model in { newView.mine.model, newView.wild.model } do
			if model and model.Parent then
				table.insert(targets, model:GetPivot().Position)
			end
		end
		BattleObstacles.Hide(newView.centre.Position, keepList, eye, targets)
		BattleIntro.Play({
			centre = newView.centre,
			arena = arena,
			mine = newView.mine.model,
			foe = newView.wild.model,
			mineCard = cardOf(newView.mine, mineName),
			foeCard = cardOf(
				newView.wild,
				newView.foeName or Config.Species[newView.wild.speciesId].displayName
			),
			short = BattleSettings.shortIntro or BattleSettings.reducedMotion or newView.role == "defender",
			cancelled = cancelled,
		})
		if cancelled() then
			return false
		end
		slidePanels(true)
		return true
	end

	-- Death/respawn/remote errors may abort while a renderer is yielding.
	local connections: { RBXScriptConnection } = {}
	local death: RBXScriptConnection? = nil
	local function watchCharacter(character: Model)
		if death then
			death:Disconnect()
			death = nil
		end
		local humanoid = character:WaitForChild("Humanoid", 5)
		if destroyed or character ~= player.Character or not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		death = humanoid.Died:Connect(function()
			leave(true)
		end)
	end
	table.insert(connections, player.CharacterAdded:Connect(watchCharacter))
	table.insert(
		connections,
		player.CharacterRemoving:Connect(function()
			leave(true)
		end)
	)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	table.insert(
		connections,
		player:GetAttributeChangedSignal("BattleReducedMotion"):Connect(function()
			BattleSettings.reducedMotion = player:GetAttribute("BattleReducedMotion") == true
		end)
	)
	BattleSettings.reducedMotion = player:GetAttribute("BattleReducedMotion") == true
	table.insert(
		connections,
		player:GetAttributeChangedSignal("InBattle"):Connect(function()
			if player:GetAttribute("InBattle") ~= true then
				local token = epoch
				task.delay(3, function()
					if
						not destroyed
						and token == epoch
						and inBattle
						and player:GetAttribute("InBattle") ~= true
					then
						leave(true)
					end
				end)
			end
		end)
	)
	local working = false
	table.insert(
		connections,
		Remotes.Get("Battle").OnClientEvent:Connect(function(newView)
			if destroyed then
				return
			end
			if not inBattle and #queue == 0 and not working and newView.result then
				return
			end
			if inBattle then
				for _, event in newView.events or {} do
					if event.effect == "switch" then
						invalidate()
						break
					end
				end
			end
			table.insert(queue, newView)
			if working then
				return
			end
			working = true
			task.spawn(function()
				while #queue > 0 and not destroyed do
					local nextView = table.remove(queue, 1)
					local ok, problem = xpcall(function()
						if not inBattle and not begin(nextView) then
							return
						end
						if inBattle then
							play(nextView)
						end
					end, debug.traceback)
					if not ok then
						warn("[BattleScreen] " .. tostring(problem))
						leave(true)
					end
				end
				working = false
			end)
		end)
	)
	gui.Destroying:Connect(function()
		destroyed = true
		leave(true)
		Fx.Destroy()
		if design then
			design:Destroy()
		end
		if death then
			death:Disconnect()
		end
		for _, connection in connections do
			connection:Disconnect()
		end
	end)

	if design then
		-- Retain the fallback widgets and their existing control flow, outside the visible design.
		local legacy = Instance.new("Frame")
		legacy.Name = "LegacyVisuals"
		legacy.Visible = false
		legacy.Size = UDim2.fromScale(1, 1)
		for _, child in gui:GetChildren() do
			if child:IsA("GuiObject") then
				child.Parent = legacy
			end
		end
		legacy.Parent = gui
	end
	gui.Parent = player:WaitForChild("PlayerGui")
end

return BattleScreen
