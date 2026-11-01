--!strict
-- Universal battle effects (docs/VFX-CATALOGUE.md, the U entries). Client
-- only, visuals only; every effect removes what it made. World pieces go in
-- Workspace.BattleFx, screen pieces in the "BattleFx" ScreenGui.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local UITheme = require(ReplicatedStorage.Shared.UITheme)
local BattleCamera = require(script.Parent.Parent.BattleCamera)
local PetAnimator = require(script.Parent.Parent.Parent.Controllers.PetAnimator)

local Common = {}

Common.TYPE_COLORS = {
	Forest = { Color3.fromRGB(110, 220, 90), Color3.fromRGB(40, 150, 60) },
	Desert = { Color3.fromRGB(255, 180, 80), Color3.fromRGB(220, 110, 30) },
	Neutral = { Color3.fromRGB(170, 185, 215), Color3.fromRGB(105, 120, 160) },
} :: { [string]: { Color3 } }

export type CardInfo = { name: string, level: number, rarity: string?, moveType: string? }

-- What every attack effect gets (see Fx.Play).
export type Ctx = {
	attacker: Model?,
	target: Model?,
	species: string, -- the attacker's SpeciesId
	move: string,
	moveType: string, -- "Neutral" | "Forest" | "Desert"
	effect: string?, -- "super" | "weak" | nil
	damage: number,
	impact: () -> (), -- call once, at the hit: hit effects + HP bar
	clip: (name: string) -> (number?, { [string]: number }?), -- plays the attacker's clip: length, markers
}

local DUST = "rbxasset://textures/particles/smoke_main.dds"
local SPARKS = "rbxasset://textures/particles/sparkles_main.dds"
local HITSTOP = { super = 0.1, normal = 0.06 }

local folder: Folder? = nil
local overlay: ScreenGui? = nil

local function world(): Folder
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "BattleFx"
	made.Parent = Workspace
	folder = made
	return made
end

local function screen(): ScreenGui
	if overlay and overlay.Parent then
		return overlay
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "BattleFx"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	overlay = gui
	return gui
end

local function screenScale(): number
	local viewport = Workspace.CurrentCamera.ViewportSize
	return math.clamp(math.min(viewport.X / 1150, viewport.Y / 720), 0.5, 1.3)
end

-- A full-screen holder; `centred` content scales with the screen around
-- the middle (edge content adds its own UIScale, see banner).
local function scaled(name: string, centred: boolean?): Frame
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	if centred then
		local scale = Instance.new("UIScale")
		scale.Scale = screenScale()
		scale.Parent = holder
	end
	holder.Parent = screen()
	return holder
end

local function invisiblePart(cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.CFrame = cframe
	part.Parent = world()
	return part
end

function Common.TypeColor(moveType: string?): Color3
	return (Common.TYPE_COLORS[moveType or "Neutral"] or Common.TYPE_COLORS.Neutral)[1]
end

-- Dust thrown outward along the ground from `position`.
function Common.Dust(position: Vector3, count: number, speed: number, color: Color3?)
	local holder = invisiblePart(CFrame.new(position + Vector3.new(0, 0.3, 0)))
	local per = math.max(1, math.floor(count / 8))
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		local attachment = Instance.new("Attachment")
		attachment.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(math.cos(angle), 0.15, math.sin(angle)))
		attachment.Parent = holder
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = DUST
		emitter.Color = ColorSequence.new(color or Color3.fromRGB(225, 215, 195))
		emitter.EmissionDirection = Enum.NormalId.Front
		emitter.SpreadAngle = Vector2.new(20, 10)
		emitter.Speed = NumberRange.new(speed * 0.6, speed)
		emitter.Drag = 4
		emitter.Lifetime = NumberRange.new(0.4, 0.7)
		emitter.Size =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 2.6) })
		emitter.Transparency =
			NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		emitter.Rate = 0
		emitter.Parent = attachment
		emitter:Emit(per)
	end
	Debris:AddItem(holder, 1)
end

-- U14: a flat ring racing out over the ground, with dust.
function Common.Shockwave(position: Vector3, radius: number, color: Color3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.15
	ring.Size = Vector3.new(0.15, 1, 1)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = world()
	TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
		Size = Vector3.new(0.15, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.45)
	Common.Dust(position, 20, radius * 1.4)
end

-- U01: black bars top and bottom; returns the function that removes them.
function Common.Letterbox(): () -> ()
	local bars: { Frame } = {}
	for index, anchor in { 0, 1 } do
		local hidden = UDim2.fromScale(0, if anchor == 0 then -0.09 else 1.09)
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.AnchorPoint = Vector2.new(0, anchor)
		bar.Size = UDim2.fromScale(1, 0.09)
		bar.Position = hidden
		bar.Parent = screen()
		TweenService:Create(bar, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
			Position = UDim2.fromScale(0, anchor),
		}):Play()
		bars[index] = bar
	end
	local closed = false
	return function()
		if closed then
			return
		end
		closed = true
		for index, bar in bars do
			TweenService:Create(bar, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
				Position = UDim2.fromScale(0, if index == 1 then -0.09 else 1.09),
			}):Play()
			Debris:AddItem(bar, 0.35)
		end
	end
end

-- The world loses its colour for a moment and comes back.
function Common.Desaturate(amount: number, seconds: number)
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "BattleFxDesaturate"
	effect.Saturation = -amount
	effect.Parent = Lighting
	TweenService:Create(effect, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Saturation = 0 }):Play()
	Debris:AddItem(effect, seconds + 0.1)
end

-- A white flash over the whole screen.
function Common.Flash(seconds: number)
	local flash = Instance.new("Frame")
	flash.BorderSizePixel = 0
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.Size = UDim2.fromScale(1, 1)
	flash.Parent = screen()
	TweenService:Create(flash, TweenInfo.new(seconds), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(flash, seconds + 0.05)
end

-- The arena ring draws itself round the circle (only for this player).
-- Returns the function that shows every segment at once (skip).
function Common.RingReveal(arena: Instance?, seconds: number): () -> ()
	local segments: { BasePart } = {}
	if arena then
		for _, part in arena:GetChildren() do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1
				table.insert(segments, part)
			end
		end
	end
	local done = false
	local function finish()
		done = true
		for _, part in segments do
			part.LocalTransparencyModifier = 0
		end
	end
	task.spawn(function()
		for _, part in segments do
			if done then
				return
			end
			part.LocalTransparencyModifier = 0
			task.wait(seconds / math.max(#segments, 1))
		end
	end)
	return finish
end

-- Lifts a (server-anchored) pet and drops it back with a bounce, locally.
local function hop(model: Model, height: number)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local start = root.CFrame
	local up =
		TweenService:Create(root, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = start + Vector3.new(0, height, 0),
		})
	up:Play()
	up.Completed:Once(function()
		TweenService:Create(root, TweenInfo.new(0.3, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
			CFrame = start,
		}):Play()
	end)
end

-- Slanted stud name banner sliding in from one side, then out.
local function banner(info: CardInfo, side: string)
	local left = side == "left"
	local holder = scaled("Banner")
	local panel = UITheme.Panel(if left then "blue" else "red")
	panel.AnchorPoint = Vector2.new(if left then 0 else 1, 1)
	local shown = UDim2.new(if left then 0 else 1, if left then 60 else -60, 0.85, 0)
	panel.Position = shown + UDim2.fromOffset(if left then -560 else 560, 0)
	panel.Size = UDim2.fromOffset(440, 108)
	panel.Rotation = if left then -3 else 3
	local size = Instance.new("UIScale")
	size.Scale = screenScale()
	size.Parent = panel
	panel.Parent = holder
	local rarity = Config.Rarities[info.rarity or "Common"]
	local stripe = Instance.new("Frame")
	stripe.BorderSizePixel = 0
	stripe.BackgroundColor3 = if rarity then rarity.color else Color3.new(1, 1, 1)
	stripe.Position = UDim2.fromOffset(10, 10)
	stripe.Size = UDim2.new(0, 12, 1, -20)
	stripe.ZIndex = 5
	UITheme.Corner(stripe, 4)
	stripe.Parent = panel
	local name = UITheme.Label(info.name, 40)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Position = UDim2.fromOffset(34, 8)
	name.Size = UDim2.new(1, -46, 0, 52)
	name.ZIndex = 5
	UITheme.FitText(name, 40)
	name.Parent = panel
	local sub = UITheme.Label(`Lv {info.level}  ·  {info.rarity or "Common"}`, 24, UITheme.colors.gold)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Position = UDim2.fromOffset(34, 60)
	sub.Size = UDim2.new(1, -46, 0, 34)
	sub.ZIndex = 5
	sub.Parent = panel
	TweenService:Create(panel, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = shown,
	}):Play()
	task.delay(0.95, function()
		TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = shown + UDim2.fromOffset(if left then -560 else 560, 0),
		}):Play()
		Debris:AddItem(holder, 0.25)
	end)
end

-- U02: a pet's hero moment: a light ring at its feet, a white outline, dust,
-- a hop and its name banner.
function Common.Reveal(model: Model?, info: CardInfo, side: string)
	banner(info, side)
	if not model or not model.Parent then
		return
	end
	local size = model:GetExtentsSize()
	local feet = model:GetPivot().Position - Vector3.new(0, size.Y / 2, 0)
	Common.Shockwave(feet, math.max(size.X, size.Z) * 1.4 + 2, Common.TypeColor(info.moveType))
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = world()
	TweenService:Create(highlight, TweenInfo.new(0.8), { OutlineTransparency = 1 }):Play()
	Debris:AddItem(highlight, 0.85)
	hop(model, math.clamp(size.Y * 0.25, 0.6, 1.6))
end

-- Text bigger than Roblox's 100 px limit: a label inside an enlarged frame.
local function bigText(parent: Instance, text: string, color: Color3?, enlarge: number): (TextLabel, UIScale)
	local wrap = Instance.new("Frame")
	wrap.BackgroundTransparency = 1
	wrap.AnchorPoint = Vector2.new(0.5, 0.5)
	wrap.Position = UDim2.fromScale(0.5, 0.45)
	wrap.Size = UDim2.fromOffset(480, 120)
	local size = Instance.new("UIScale")
	size.Scale = enlarge
	size.Parent = wrap
	local label = UITheme.Label(text, 100, color)
	label.Size = UDim2.fromScale(1, 1)
	local pop = Instance.new("UIScale")
	pop.Parent = label
	label.Parent = wrap
	wrap.Parent = parent
	return label, pop
end

-- Radial white lines flashing behind the countdown digits.
local function speedLines(parent: Instance)
	for i = 1, 14 do
		local angle = i / 14 * math.pi * 2
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Color3.new(1, 1, 1)
		line.BackgroundTransparency = 0.2
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.new(0.5, math.cos(angle) * 230, 0.5, math.sin(angle) * 230)
		line.Size = UDim2.fromOffset(5, 110)
		line.Rotation = math.deg(angle) + 90
		line.Parent = parent
		TweenService:Create(line, TweenInfo.new(0.3), {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, math.cos(angle) * 300, 0.5, math.sin(angle) * 300),
		}):Play()
		Debris:AddItem(line, 0.32)
	end
end

-- U03: 3, 2, 1. `sleep` waits and returns true if the player skipped;
-- `onDigit` runs on each number (camera punch). Returns true if skipped.
function Common.Countdown(sleep: (number) -> boolean, onDigit: (number) -> ()): boolean
	local holder = scaled("Countdown", true)
	local colors =
		{ [3] = UITheme.colors.speed, [2] = UITheme.colors.gold, [1] = Color3.fromRGB(255, 90, 80) }
	for number = 3, 1, -1 do
		speedLines(holder)
		local digit, pop = bigText(holder, tostring(number), colors[number], 1.7)
		pop.Scale = 1.7
		local stroke = digit:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = 6
		end
		TweenService
			:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
		onDigit(number)
		local skipped = sleep(0.38)
		TweenService:Create(digit, TweenInfo.new(0.12), { TextTransparency = 1 }):Play()
		TweenService:Create(pop, TweenInfo.new(0.12), { Scale = 0.7 }):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.12), { Transparency = 1 }):Play()
		end
		Debris:AddItem(digit.Parent :: Instance, 0.15)
		if skipped or sleep(0.12) then
			Debris:AddItem(holder, 0.2)
			return true
		end
	end
	Debris:AddItem(holder, 0.2)
	return false
end

-- U04: "FIGHT!" slams in with a white flash and a shockwave over the arena.
function Common.FightSlam(centre: Vector3, radius: number)
	local holder = scaled("Fight", true)
	local text, pop = bigText(holder, "FIGHT!", nil, 1.6)
	text.Rotation = -6
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 70, 50))
	gradient.Parent = text
	local stroke = text:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 7
	end
	pop.Scale = 3
	TweenService
		:Create(pop, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 })
		:Play()
	task.delay(0.14, function()
		Common.Flash(0.15)
		Common.Shockwave(centre, radius, Color3.fromRGB(255, 200, 90))
	end)
	task.delay(0.55, function()
		TweenService:Create(pop, TweenInfo.new(0.2), { Scale = 1.25 }):Play()
		TweenService:Create(text, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 1 }):Play()
		end
		Debris:AddItem(holder, 0.25)
	end)
end

-- Tweens a part's CFrame and waits for it.
local function moveTo(
	part: BasePart,
	seconds: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
	goal: CFrame
)
	local tween = TweenService:Create(part, TweenInfo.new(seconds, style, direction), { CFrame = goal })
	tween:Play()
	tween.Completed:Wait()
end
Common.MoveTo = moveTo

-- A trail behind a pet while it dashes; returns the function that removes it.
function Common.Trail(model: Model?, color: Color3): () -> ()
	local root = model and model.PrimaryPart
	if not root or not model then
		return function() end
	end
	local half = model:GetExtentsSize().Y * 0.3
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, half, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -half, 0)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = top, bottom
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 0.7
	trail.Lifetime = 0.18
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.Parent = root
	return function()
		task.delay(0.2, function()
			trail:Destroy()
			top:Destroy()
			bottom:Destroy()
		end)
	end
end

-- The flat direction and distance from one pet to the other.
function Common.Between(from: Model?, to: Model?): (Vector3, number)
	if not from or not to then
		return Vector3.new(0, 0, -1), 0
	end
	local a, b = from:GetPivot().Position, to:GetPivot().Position
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1), flat.Magnitude
end

-- U05: lean back, dash at the target with a trail, hit, hop back.
-- `spin` turns the pet round while it dashes (Tail Smack, Spin Dash).
function Common.DefaultAttack(ctx: Ctx, spin: number?)
	local root = ctx.attacker and ctx.attacker.PrimaryPart
	if not root or not ctx.target then
		ctx.impact()
		return
	end
	local start = root.CFrame
	local direction, distance = Common.Between(ctx.attacker, ctx.target)
	moveTo(
		root,
		0.28,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.Out,
		start - direction - Vector3.new(0, 0.3, 0)
	)
	local removeTrail = Common.Trail(ctx.attacker, Color3.new(1, 1, 1))
	moveTo(
		root,
		0.15,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In,
		(start + direction * distance * 0.6) * CFrame.Angles(0, math.rad(spin or 0), 0)
	)
	ctx.impact()
	removeTrail()
	moveTo(root, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, start)
end

-- Plays the attacker's clip `name` and calls impact at its "impact" marker
-- (or half way). Returns false if the clip doesn't exist yet.
function Common.PlayClip(ctx: Ctx, name: string): boolean
	local length, markers = ctx.clip(name)
	if not length then
		return false
	end
	local hitAt = markers and markers.impact or length * 0.5
	task.wait(hitAt)
	ctx.impact()
	task.wait(math.max(length - hitAt, 0))
	return true
end

-- The point on the target's surface that faces the attacker.
local function hitPoint(ctx: Ctx): Vector3?
	local target = ctx.target
	if not target or not target.Parent then
		return nil
	end
	local cframe, size = target:GetBoundingBox()
	local direction = -Common.Between(ctx.attacker, target)
	return cframe.Position + direction * math.min(size.X, size.Z) * 0.45
end

local function emit(position: Vector3, color: Color3, count: number, speed: number)
	local holder = invisiblePart(CFrame.new(position))
	local attachment = Instance.new("Attachment")
	attachment.Parent = holder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKS
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.05, 1)
	emitter.Lifetime = NumberRange.new(0.3, 0.55)
	emitter.Speed = NumberRange.new(speed * 0.5, speed)
	emitter.Drag = 3
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)
	Debris:AddItem(holder, 0.8)
end
Common.Emit = emit

-- U06: sparks in the move's colour, a star flash and stud debris. Weak hits
-- are small and grey; super hits are bigger with a ring.
function Common.Impact(ctx: Ctx)
	local point = hitPoint(ctx)
	if not point then
		return
	end
	local colors = Common.TYPE_COLORS[ctx.moveType] or Common.TYPE_COLORS.Neutral
	local weak, super = ctx.effect == "weak", ctx.effect == "super"
	emit(
		point,
		if weak then Color3.fromRGB(190, 190, 190) else colors[1],
		if super then 30 elseif weak then 8 else 16,
		20
	)
	-- Star flash, a stud towards the camera so the body doesn't cut it.
	local towardsCamera = (Workspace.CurrentCamera.CFrame.Position - point).Unit
	local holder = invisiblePart(CFrame.new(point + towardsCamera))
	local flash = Instance.new("BillboardGui")
	flash.Size = UDim2.fromScale(if super then 7 else 4.5, if super then 7 else 4.5)
	flash.LightInfluence = 0
	flash.Parent = holder
	local star = Instance.new("ImageLabel")
	star.BackgroundTransparency = 1
	star.Image = SPARKS
	star.Size = UDim2.fromScale(1, 1)
	star.ImageColor3 = if weak then Color3.fromRGB(220, 220, 220) else Color3.new(1, 1, 0.85)
	star.Parent = flash
	TweenService:Create(star, TweenInfo.new(0.14), { ImageTransparency = 1, Rotation = 40 }):Play()
	Debris:AddItem(holder, 0.2)
	-- Stud debris that falls and bounces.
	if not weak then
		for _ = 1, if super then 8 else 4 do
			local cube = Instance.new("Part")
			cube.Size = Vector3.one * 0.45
			cube.Color = colors[2]
			cube.Material = Enum.Material.SmoothPlastic
			cube.CanQuery = false
			cube.CanTouch = false
			cube.CFrame = CFrame.new(point)
			cube.Parent = world()
			cube.AssemblyLinearVelocity =
				Vector3.new(math.random(-10, 10), math.random(10, 18), math.random(-10, 10))
			Debris:AddItem(cube, 0.9)
		end
	end
	if super then
		local feet = point - Vector3.new(0, (ctx.target :: Model):GetExtentsSize().Y / 2, 0)
		Common.Shockwave(feet, 7, colors[1])
	end
end

-- U07: the target flashes white.
function Common.HitFlash(model: Model?)
	if not model or not model.Parent then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = world()
	TweenService:Create(highlight, TweenInfo.new(0.12), { FillTransparency = 1 }):Play()
	Debris:AddItem(highlight, 0.15)
end

-- U08: "-23" pops above the target and floats up.
function Common.DamageNumber(model: Model?, amount: number, effect: string?)
	local root = model and model.PrimaryPart
	if not root or not model then
		return
	end
	local super, weak = effect == "super", effect == "weak"
	local gui = Instance.new("BillboardGui")
	local size = if super then 4 elseif weak then 2.2 else 3
	gui.Size = UDim2.fromScale(size * 1.6, size)
	gui.LightInfluence = 0
	local start = Vector3.new(math.random(-10, 10) / 10, model:GetExtentsSize().Y / 2 + 1, 0)
	gui.StudsOffsetWorldSpace = start
	gui.Adornee = root
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") -- with an Adornee: always drawn
	local text = UITheme.Label(
		`-{Format.Short(amount)}{if super then "!" else ""}`,
		100,
		if super
			then UITheme.colors.gold
			elseif weak then Color3.fromRGB(200, 200, 200)
			else Color3.new(1, 1, 1)
	)
	text.Size = UDim2.fromScale(1, 1)
	text.TextScaled = true
	text.Parent = gui
	local pop = Instance.new("UIScale")
	pop.Scale = 0.5
	pop.Parent = text
	TweenService
		:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	TweenService:Create(gui, TweenInfo.new(0.9, Enum.EasingStyle.Quad), {
		StudsOffsetWorldSpace = start + Vector3.new(0, 2, 0),
	}):Play()
	task.delay(0.5, function()
		TweenService:Create(text, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		local stroke = text:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(gui, 0.95)
end

-- Everything a hit shows, once per attack (Fx.Play calls this from impact).
function Common.Hit(ctx: Ctx)
	Common.Impact(ctx)
	Common.HitFlash(ctx.target)
	Common.DamageNumber(ctx.target, ctx.damage, ctx.effect)
	local stop = HITSTOP[ctx.effect or "normal"]
	if stop then
		PetAnimator.Freeze(ctx.attacker, stop)
		PetAnimator.Freeze(ctx.target, stop)
	end
	if ctx.effect ~= "weak" then
		BattleCamera.Shake(if ctx.effect == "super" then "medium" else "light")
	end
end

export type ProjectileOptions = {
	from: Vector3,
	to: Model?,
	arc: number, -- studs above the straight line at the middle
	time: number,
	part: BasePart, -- what flies (parented and removed here)
	trail: Color3?,
	spin: boolean?,
}

-- U12: something flies from `from` to the target on an arc; yields until it lands.
function Common.Projectile(options: ProjectileOptions)
	local part = options.part
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(options.from)
	part.Parent = world()
	if options.trail then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, part.Size.Y * 0.4, 0)
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -part.Size.Y * 0.4, 0)
		a1.Parent = part
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Color = ColorSequence.new(options.trail)
		trail.LightEmission = 0.8
		trail.Lifetime = 0.2
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.FaceCamera = true
		trail.Parent = part
	end
	local target = if options.to and options.to.Parent then options.to:GetPivot().Position else options.from
	local middle = (options.from + target) / 2 + Vector3.new(0, options.arc, 0)
	local started = os.clock()
	while true do
		local alpha = math.min((os.clock() - started) / options.time, 1)
		local position = options.from:Lerp(middle, alpha):Lerp(middle:Lerp(target, alpha), alpha)
		part.CFrame = CFrame.new(position)
			* (if options.spin then CFrame.Angles(alpha * 14, alpha * 9, 0) else CFrame.identity)
		if alpha >= 1 then
			break
		end
		RunService.PreRender:Wait()
	end
	part.Transparency = 1
	Debris:AddItem(part, 0.25)
end

-- U13: a crescent swipe across the target, tilted by `angle` degrees.
function Common.Slash(target: Model?, angle: number, color: Color3)
	if not target or not target.Parent then
		return
	end
	local cframe, size = target:GetBoundingBox()
	local camera = Workspace.CurrentCamera.CFrame
	local reach = math.max(size.X, size.Y, size.Z) * 0.6 + 1
	local tilt = math.rad(angle)
	local across = camera.RightVector * math.cos(tilt) + camera.UpVector * math.sin(tilt)
	local view = (cframe.Position - camera.Position).Unit
	local bulge = view:Cross(across).Unit
	local holder = invisiblePart(CFrame.new(cframe.Position))
	local function beam(width: number, beamColor: Color3)
		local a0 = Instance.new("Attachment")
		a0.WorldCFrame = CFrame.fromMatrix(cframe.Position - across * reach, bulge, view)
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.WorldCFrame = CFrame.fromMatrix(cframe.Position + across * reach, bulge, view)
		a1.Parent = holder
		local made = Instance.new("Beam")
		made.Attachment0, made.Attachment1 = a0, a1
		made.CurveSize0, made.CurveSize1 = reach * 0.9, -reach * 0.9
		made.Color = ColorSequence.new(beamColor)
		made.LightEmission = 1
		made.FaceCamera = true
		made.Segments = 24
		made.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		made.Width0, made.Width1 = 0, 0
		made.Parent = holder
		return made, width
	end
	local beams = { { beam(1.4, color) }, { beam(0.5, Color3.new(1, 1, 1)) } }
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < 0.25 do
			local k = math.sin((os.clock() - started) / 0.25 * math.pi)
			for _, entry in beams do
				entry[1].Width0, entry[1].Width1 = entry[2] * k, entry[2] * k
			end
			RunService.PreRender:Wait()
		end
		holder:Destroy()
	end)
end

-- U15: sparks drawn into a pet and a growing glow before a big move (yields).
function Common.Charge(model: Model?, color: Color3, seconds: number)
	if not model or not model.Parent then
		task.wait(seconds)
		return
	end
	local cframe, size = model:GetBoundingBox()
	local shell = invisiblePart(cframe)
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.one * (math.max(size.X, size.Y, size.Z) * 1.8)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKS
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	emitter.Speed = NumberRange.new(6, 10)
	emitter.Lifetime = NumberRange.new(0.35, 0.45)
	emitter.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.2) })
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Rate = 60
	emitter.Parent = shell
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Brightness = 3
	glow.Range = 0
	glow.Parent = shell
	TweenService:Create(glow, TweenInfo.new(seconds), { Range = 14 }):Play()
	BattleCamera.Punch(-6, seconds)
	task.wait(seconds)
	shell:Destroy()
end

-- Moves a pet's root along a hop to `goal`, `height` studs at the top (yields).
function Common.Hop(root: BasePart, goal: CFrame, height: number, seconds: number)
	local start = root.CFrame
	local started = os.clock()
	while true do
		local alpha = math.min((os.clock() - started) / seconds, 1)
		local position = start.Position:Lerp(goal.Position, alpha)
			+ Vector3.new(0, 4 * height * alpha * (1 - alpha), 0)
		root.CFrame = start:Lerp(goal, alpha).Rotation + position
		if alpha >= 1 then
			break
		end
		RunService.PreRender:Wait()
	end
end

-- A straight energy beam from `from` to the target, with a white core;
-- calls `onPeak` half way (yields for `seconds`).
function Common.Ray(
	from: Vector3,
	target: Model?,
	color: Color3,
	width: number,
	seconds: number,
	onPeak: () -> ()
)
	local to = if target and target.Parent then target:GetPivot().Position else from
	local a = invisiblePart(CFrame.new(from))
	local b = invisiblePart(CFrame.new(to))
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Parent, a1.Parent = a, b
	local beams = {}
	for _, entry in { { width, color }, { width * 0.35, Color3.new(1, 1, 1) } } do
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Color = ColorSequence.new(entry[2])
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Width0, beam.Width1 = 0, 0
		beam.Parent = a
		table.insert(beams, { beam, entry[1] })
	end
	local started, peaked = os.clock(), false
	while os.clock() - started < seconds do
		local t = (os.clock() - started) / seconds
		local k = math.sin(t * math.pi)
		for _, entry in beams do
			entry[1].Width0, entry[1].Width1 = entry[2] * k, entry[2] * k
		end
		if t >= 0.5 and not peaked then
			peaked = true
			onPeak()
		end
		RunService.PreRender:Wait()
	end
	if not peaked then
		onPeak()
	end
	a:Destroy()
	b:Destroy()
end

-- The spot right in front of the target, facing it (for melee hits).
function Common.InFront(ctx: Ctx, gap: number): CFrame
	local root = (ctx.attacker :: Model).PrimaryPart :: BasePart
	local direction, distance = Common.Between(ctx.attacker, ctx.target)
	local spot = root.Position + direction * math.max(distance - gap, 0)
	return root.CFrame.Rotation + spot
end

return Common
