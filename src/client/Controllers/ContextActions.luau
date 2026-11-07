--!strict
-- GUI-only world actions. No ProximityPrompt instances, hidden wrappers,
-- E shortcut or gamepad world binding. Activated sends an intent; only the
-- server can pick up a pet, start a battle or heal. Legacy direct capture
-- retains its server-timed window, with an explicit Cancel action.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local ContextActions = {}
local BACK_ACTION = "ContextActionsBack"

-- A HUD may present the current action with its own button: this controller keeps every rule.
local presenter: ((view: any?) -> ())? = nil
local bridge: { press: (() -> ())?, activate: (() -> ())?, next: (() -> ())? } = {}
local presented = ""
local function present(view: any?)
	if not presenter then
		return
	end
	local key = if view
		then `{view.kind}|{view.name}|{view.label}|{view.enabled}|{view.nextVisible}|{view.nextText}`
		else ""
	if key ~= presented then
		presented = key
		presenter(view)
	end
end
function ContextActions.SetPresenter(fn: (view: any?) -> ())
	presenter = fn
	presented = "?"
end
function ContextActions.Press()
	if bridge.press then
		bridge.press()
	end
end
function ContextActions.Activate()
	if bridge.activate then
		bridge.activate()
	end
end
function ContextActions.Next()
	if bridge.next then
		bridge.next()
	end
end

type Target = {
	id: string,
	kind: string,
	name: string,
	label: string,
	color: string,
	model: Model?,
	state: string?,
	owner: number?,
	duration: number,
	distance: number,
	disabled: string?,
}
type Pending = { requestId: number, target: Target, character: Model?, beganAt: number }

local function targetKey(target: Target?): string
	return if target then `{target.kind}:{target.id}:{target.state}:{target.owner}` else ""
end

function ContextActions.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local animals = Workspace:WaitForChild("Animals", 15)
	if not animals then
		warn("[ContextActions] Animals unavailable")
		return
	end
	local request = Remotes.Get("WorldAction")
	local gui = Instance.new("ScreenGui")
	gui.Name = "ContextActions"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 4
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local safe = Instance.new("Frame")
	safe.Name = "SafeArea"
	safe.BackgroundTransparency = 1
	safe.Size = UDim2.fromScale(1, 1)
	safe.Parent = gui
	local holder = Instance.new("Frame")
	holder.Name = "Action"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Visible = false
	holder.SelectionGroup = true
	for _, direction in { "Up", "Down", "Left", "Right" } do
		(holder :: any)[`SelectionBehavior{direction}`] = Enum.SelectionBehavior.Stop
	end
	holder.Parent = safe
	local object = UITheme.Label("", 18)
	object.Name = "Target"
	object.Size = UDim2.new(1, 0, 0, 24)
	object.TextTruncate = Enum.TextTruncate.AtEnd
	object.Parent = holder
	local button, label = UITheme.Button("green", UDim2.new(1, 0, 0, 58), "")
	button.Name = "Interact"
	button.Position = UDim2.fromOffset(0, 28)
	button.Parent = holder
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "ConfirmHint"
	glyph.BackgroundTransparency = 1
	glyph.Position = UDim2.new(0, 8, 0.5, -12)
	glyph.Size = UDim2.fromOffset(24, 24)
	glyph.ZIndex = 4
	glyph.Parent = button
	for _, control in { button } do
		local ring = Instance.new("Frame")
		ring.Name = "FocusRing"
		ring.BackgroundTransparency = 1
		ring.Position = UDim2.fromOffset(-4, -4)
		ring.Size = UDim2.new(1, 8, 1, 8)
		ring.Visible = false
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Color = UITheme.colors.gold
		stroke.Parent = ring
		ring.Parent = control
		control.SelectionGained:Connect(function()
			ring.Visible = true
		end)
		control.SelectionLost:Connect(function()
			ring.Visible = false
		end)
	end
	local nextButton, nextLabel = UITheme.Button("blue", UDim2.new(1, 0, 0, 44), "Next target")
	nextButton.Name = "NextOrCancel"
	nextButton.Position = UDim2.fromOffset(0, 92)
	nextButton.Parent = holder
	local notice = UITheme.Label("", 18)
	notice.Name = "Result"
	notice.AnchorPoint = Vector2.new(0.5, 0)
	notice.Position = UDim2.fromScale(0.5, 0.66)
	notice.Size = UDim2.new(0.55, 0, 0, 48)
	notice.TextWrapped = true
	notice.Parent = safe
	gui.Parent = playerGui

	local targets: { Target } = {}
	local current: Target? = nil
	local pending: Pending? = nil
	local nextId = 0
	local pressedKey: string? = nil
	local focused = true
	local noticeUntil = 0
	local lastColor = ""
	local function announce(text: string)
		notice.Text = text
		noticeUntil = os.clock() + 2.5
	end
	local function blocked(): boolean
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return not focused
			or not humanoid
			or humanoid.Health <= 0
			or player:GetAttribute("MenuOpen") == true
			or player:GetAttribute("InBattle") == true
			or GuiService.MenuIsOpen
			or UserInputService:GetFocusedTextBox() ~= nil
		-- HUD selection is not a modal: keeping this action visible lets
		-- normal gamepad navigation reach it from another HUD control.
	end
	local function cancel()
		local active = pending
		pending = nil
		if active and active.target.duration > 0 then
			request:FireServer(active.requestId, "cancel")
		end
	end
	local function hide()
		cancel()
		current = nil
		holder.Visible = false
		present(nil)
		pressedKey = "cancelled"
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(holder) then
			GuiService.SelectedObject = nil
		end
	end

	local function discover(): { Target }
		local result: { Target } = {}
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return result
		end
		local battlesEnabled = Workspace:GetAttribute("BattlesEnabled") == true
		for _, model in animals:GetChildren() do
			if not model:IsA("Model") or model:GetAttribute("CosmeticFollower") then
				continue
			end
			local state = model:GetAttribute("State")
			local id = model:GetAttribute("AnimalId")
			local speciesId = model:GetAttribute("SpeciesId")
			local species = if typeof(speciesId) == "string" then Config.Species[speciesId] else nil
			local petRoot = model.PrimaryPart
			if
				(state ~= "Wild" or model:GetAttribute("OwnerUserId") ~= nil)
				or typeof(id) ~= "string"
				or not species
				or not petRoot
			then
				continue
			end
			local radius = math.max(petRoot.Size.X, petRoot.Size.Z) / 2
			local distance = (petRoot.Position - root.Position).Magnitude - radius
			if distance > Config.Gameplay.capture.maxDistance - 2 then
				continue
			end
			local ownerId = model:GetAttribute("OwnerUserId")
			local owner = if typeof(ownerId) == "number" then ownerId else nil
			table.insert(result, {
				id = id,
				kind = "pet",
				model = model,
				state = state,
				owner = owner,
				name = species.displayName,
				label = if battlesEnabled then "Battle" else "Catch",
				color = if battlesEnabled then "orange" else "green",
				duration = if battlesEnabled then 0 else Config.Gameplay.capture.holdSeconds,
				distance = distance,
			})
		end
		local battles = Workspace:FindFirstChild("Battles")
		local point = battles and battles:FindFirstChild("HealPoint")
		if point and point:IsA("BasePart") then
			local distance = (root.Position - point.Position).Magnitude
			local radius = point:GetAttribute("InteractionRadius")
			if typeof(radius) == "number" and distance <= radius then
				table.insert(result, {
					id = "fountain",
					kind = "heal",
					name = "Spawn Fountain",
					label = "Heal pets",
					color = "blue",
					duration = 0,
					distance = distance,
				})
			end
		end
		table.sort(result, function(a, b)
			return if a.distance == b.distance then a.id < b.id else a.distance < b.distance
		end)
		return result
	end

	-- Snapshot the target when a pointer press begins; a target disappearing
	-- during a gesture must not activate its replacement. Activated handles
	-- mouse/touch cancellation and normal gamepad focus/confirm.
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			pressedKey = targetKey(current)
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonA and GuiService.SelectedObject == button then
			pressedKey = targetKey(current) -- capture only; no gameplay binding
		end
	end)
	bridge.press = function()
		pressedKey = targetKey(current)
	end
	local function activate()
		local target = current
		if
			blocked()
			or pending
			or not target
			or target.disabled
			or (pressedKey ~= nil and pressedKey ~= targetKey(target))
		then
			return
		end
		nextId = nextId % 2147483647 + 1
		pending = { requestId = nextId, target = target, character = player.Character, beganAt = os.clock() }
		request:FireServer(nextId, target.kind, if target.kind == "pet" then target.id else nil)
	end
	button.Activated:Connect(activate)
	bridge.activate = activate
	local function nextTarget()
		if pending then
			cancel()
			announce("Capture cancelled.")
			return
		end
		if blocked() or #targets < 2 then
			return
		end
		local index = 0
		for i, target in targets do
			if targetKey(target) == targetKey(current) then
				index = i
				break
			end
		end
		current = targets[index % #targets + 1]
		pressedKey = nil
	end
	nextButton.Activated:Connect(nextTarget)
	bridge.next = nextTarget
	Remotes.Get("WorldActionResult").OnClientEvent
		:Connect(function(id: number, accepted: boolean, message: string)
			local active = pending
			if not active or active.requestId ~= id then
				return -- stale reply cannot complete a different target/request
			end
			pending = nil
			announce(message)
			if accepted and active.target.kind == "heal" then
				Sfx.Play("heal")
			end
		end)
	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(holder) then
			ContextActionService:BindActionAtPriority(BACK_ACTION, function(_, state)
				if state == Enum.UserInputState.Begin then
					cancel()
					GuiService.SelectedObject = nil
				end
				return Enum.ContextActionResult.Sink
			end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
		else
			ContextActionService:UnbindAction(BACK_ACTION)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		focused = false
		hide()
	end)
	UserInputService.WindowFocused:Connect(function()
		focused = true
	end)
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(hide)
	UserInputService.GamepadDisconnected:Connect(hide)
	player.CharacterRemoving:Connect(hide)
	UserInputService.TextBoxFocused:Connect(hide)
	GuiService.MenuOpened:Connect(hide)
	for _, name in { "MenuOpen", "InBattle" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if blocked() then
				hide()
			end
		end)
	end

	local nextScan = 0
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		notice.Visible = now < noticeUntil and not blocked()
		if blocked() then
			hide()
			return
		end
		if now >= nextScan then
			targets = discover()
			local retained: Target? = nil
			for _, target in targets do
				if targetKey(target) == targetKey(current) then
					retained = target
					break
				end
			end
			current = retained or targets[1]
			nextScan = now + 0.1
		end
		local active = pending
		if
			active
			and (player.Character ~= active.character or now - active.beganAt > active.target.duration + 5)
		then
			cancel()
			announce("Request expired. Try again when ready.")
			active = nil
		end
		if active and active.target.duration > 0 then
			local model = active.target.model
			local petRoot = model and model.PrimaryPart
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local lost = not model or not model:IsDescendantOf(Workspace) or not petRoot or not root
			if not lost and petRoot and root then
				local radius = math.max(petRoot.Size.X, petRoot.Size.Z) / 2
				lost = (root.Position - petRoot.Position).Magnitude - radius
					> Config.Gameplay.capture.maxDistance
			end
			-- State/ownership is rechecked by the server. Waiting for its reply
			-- avoids discarding success if Carried replicates before the result.
			if lost then
				cancel()
				announce("Capture cancelled: the target is no longer available.")
				active = nil
			end
		end
		local target = if active then active.target else current
		holder.Visible = target ~= nil and presenter == nil
		if not target then
			hide()
			return
		end
		button.Interactable = active == nil and target.disabled == nil
		object.Text = target.name
		label.Text = if active
			then "Waiting for server..."
			elseif target.disabled then target.disabled
			elseif target.duration > 0 then `{target.label} ({target.duration}s)`
			else target.label
		local color = if active or target.disabled then "grey" else target.color
		if color ~= lastColor then
			UITheme.Recolor(button, (UITheme.colors :: any)[color])
			lastColor = color
		end
		nextButton.Visible = if active then active.target.duration > 0 else #targets > 1
		nextLabel.Text = if active then "Cancel capture" else "Next target"
		present({
			kind = target.kind,
			name = target.name,
			label = label.Text,
			enabled = button.Interactable,
			nextVisible = nextButton.Visible,
			nextText = nextLabel.Text,
		})
		if not nextButton.Visible and GuiService.SelectedObject == nextButton then
			GuiService.SelectedObject = if button.Interactable then button else nil
		end
		local gamepad = UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
		glyph.Visible = gamepad
		if gamepad then
			glyph.Image = UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonA)
		end
		label.Position = UDim2.fromOffset(if gamepad then 34 else 0, 0)
		label.Size = UDim2.new(1, if gamepad then -40 else 0, 1, 0)
		local carrying = player:GetAttribute("CarryingOwn")
		local bottom = if typeof(carrying) == "number" and carrying > 0 then 112 else 24
		if UserInputService.PreferredInput == Enum.PreferredInput.Touch then
			local touchGui = playerGui:FindFirstChild("TouchGui")
			local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
			if jump and jump:IsA("GuiObject") and jump.Visible then
				bottom = math.max(
					bottom,
					safe.AbsolutePosition.Y + safe.AbsoluteSize.Y - jump.AbsolutePosition.Y + 12
				)
			end
		end
		holder.Size = UDim2.fromOffset(
			math.min(320, safe.AbsoluteSize.X * 0.42),
			if nextButton.Visible then 136 else 86
		)
		holder.Position = UDim2.new(0.5, 0, 1, -bottom)
	end)
end

return ContextActions
