--!strict
-- Coder handoff candidate: client-only, bounded pool, no gameplay object writes.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EffectPool = {}
EffectPool.__index = EffectPool

type Slot = {
	part: Part,
	a: Attachment,
	b: Attachment,
	beam: Beam,
	emitter: ParticleEmitter,
	light: PointLight,
	surface: SurfaceGui,
	image: ImageLabel,
	owner: any?,
	started: number,
	expires: number,
	update: ((any, number) -> ())?,
}

local function makeSlot(parent: Folder): Slot
	local part = Instance.new("Part")
	part.Name = "PooledEffect"
	part.Anchored = true
	part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.1
	part.Material = Enum.Material.Neon
	local a, b = Instance.new("Attachment"), Instance.new("Attachment")
	a.Parent, b.Parent = part, part
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a, b
	beam.Enabled = false
	beam.FaceCamera = true
	beam.LightEmission = 0.8
	beam.Segments = 12
	beam.Parent = part
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled, emitter.Rate = false, 0
	emitter.Parent = part
	local light = Instance.new("PointLight")
	light.Enabled, light.Shadows = false, false
	light.Parent = part
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.CanvasSize = Vector2.new(256, 256)
	surface.AlwaysOnTop = false
	surface.LightInfluence = 0
	surface.MaxDistance = 140
	surface.Enabled = false
	surface.Parent = part
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Parent = surface
	part.Parent = parent -- fully configured before becoming visible
	return {
		part = part,
		a = a,
		b = b,
		beam = beam,
		emitter = emitter,
		light = light,
		surface = surface,
		image = image,
		owner = nil,
		started = 0,
		expires = 0,
		update = nil,
	}
end

function EffectPool.new(mobile: boolean)
	assert(RunService:IsClient(), "EffectPool is presentation on the client only")
	local root = Instance.new("Folder")
	root.Name = "BattlePresentationPool"
	root.Parent = Workspace
	local self: any = setmetatable({
		root = root,
		mobile = mobile,
		slots = {},
		connection = nil,
		active = 0,
		highWater = 0,
		misses = 0,
		emitted = 0,
		destroyed = false,
	}, EffectPool)
	for _ = 1, if mobile then 10 else 18 do
		table.insert(self.slots, makeSlot(root))
	end
	return self
end

function EffectPool._release(self: any, slot: Slot)
	if not slot.owner then
		return
	end
	slot.owner, slot.update = nil, nil
	slot.part.Transparency = 1
	slot.part.Shape = Enum.PartType.Block
	slot.part.Size = Vector3.one * 0.1
	slot.a.Position, slot.b.Position = Vector3.zero, Vector3.zero
	slot.beam.Enabled = false
	slot.beam.CurveSize0, slot.beam.CurveSize1 = 0, 0
	slot.emitter.Enabled = false
	slot.emitter:Clear()
	slot.light.Enabled = false
	slot.surface.Enabled = false
	self.active -= 1
end

function EffectPool._borrow(self: any, owner: any, seconds: number, update: ((any, number) -> ())?): Slot?
	if self.destroyed or not owner.active then
		return nil
	end
	for _, slot in self.slots do
		if not slot.owner then
			slot.owner, slot.started, slot.expires = owner, os.clock(), os.clock() + math.max(seconds, 0.01)
			slot.update = update
			self.active += 1
			self.highWater = math.max(self.active, self.highWater)
			if not self.connection then
				self.connection = RunService.PreRender:Connect(function()
					local now = os.clock()
					for _, current in self.slots do
						if current.owner then
							if not current.owner.active or now >= current.expires then
								self:_release(current)
							elseif current.update then
								local ok, problem = pcall(
									current.update,
									current,
									(now - current.started) / (current.expires - current.started)
								)
								if not ok then
									warn("[BattlePresentation] " .. tostring(problem))
									self:_release(current)
								end
							end
						end
					end
					if self.active == 0 and self.connection then
						self.connection:Disconnect()
						self.connection = nil
					end
				end)
			end
			return slot
		end
	end
	self.misses += 1 -- cosmetic degradation never delays impact/damage presentation
	return nil
end

function EffectPool.Burst(
	self: any,
	owner: any,
	position: Vector3,
	texture: string,
	color: Color3,
	count: number,
	radius: number,
	light: boolean?
)
	count = math.min(math.floor(count), owner.remaining)
	if count <= 0 then
		return
	end
	local slot = self:_borrow(owner, 0.7, function(s, alpha)
		s.light.Brightness = 0.65 * (1 - alpha) ^ 2
	end)
	if not slot then
		return
	end
	owner.remaining -= count
	self.emitted += count
	slot.part.CFrame = CFrame.new(position)
	local emitter = slot.emitter
	emitter.Texture = texture
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission, emitter.LightInfluence = 0.65, 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(130, 130)
	emitter.Speed = NumberRange.new(radius, radius * 2.2)
	emitter.Acceleration = Vector3.new(0, -3, 0)
	emitter.Drag = 3
	emitter.Lifetime = NumberRange.new(0.35, 0.65)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.32),
		NumberSequenceKeypoint.new(0.2, 0.48),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.65, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rotation = NumberRange.new(-180, 180)
	emitter.RotSpeed = NumberRange.new(-60, 60)
	emitter.Rate = 0
	-- Enabled stays false: every particle is an explicitly budgeted burst.
	emitter:Emit(count)
	slot.light.Color, slot.light.Range = color, math.min(radius * 2, 10)
	slot.light.Brightness = 0.65
	slot.light.Enabled = light == true and not self.mobile
end

function EffectPool.Line(
	self: any,
	owner: any,
	from: Vector3,
	to: Vector3,
	color: Color3,
	width: number,
	duration: number,
	curve: number?
)
	local slot = self:_borrow(owner, duration, function(s, alpha)
		local envelope = math.sin(alpha * math.pi)
		s.beam.Width0, s.beam.Width1 = width * envelope, width * envelope * 0.65
	end)
	if not slot then
		return
	end
	slot.part.CFrame = CFrame.identity
	slot.a.WorldCFrame = CFrame.new(from)
	slot.b.WorldCFrame = CFrame.new(to)
	slot.beam.Color = ColorSequence.new(color)
	slot.beam.Width0, slot.beam.Width1 = 0, 0
	slot.beam.CurveSize0, slot.beam.CurveSize1 = curve or 0, -(curve or 0)
	slot.beam.Transparency = NumberSequence.new(0.18, 0.8)
	slot.beam.Enabled = true
end

function EffectPool.Projectile(
	self: any,
	owner: any,
	from: Vector3,
	to: Vector3,
	color: Color3,
	duration: number,
	arc: number,
	delay: number,
	diameter: number
)
	local function set(s: Slot, alpha: number)
		local elapsed = alpha * (duration + delay)
		if elapsed < delay then
			return
		end
		local t = math.clamp((elapsed - delay) / duration, 0, 1)
		local position = from:Lerp(to, t) + Vector3.new(0, 4 * arc * t * (1 - t), 0)
		s.part.CFrame = CFrame.new(position) * CFrame.Angles(t * 9, t * 12, 0)
		s.part.Transparency = 0.18
	end
	local slot = self:_borrow(owner, duration + delay, set)
	if not slot then
		return
	end
	slot.part.Size = Vector3.one * diameter
	slot.part.Shape = Enum.PartType.Ball
	slot.part.Color = color
	set(slot, 0)
end

function EffectPool.Ring(
	self: any,
	owner: any,
	position: Vector3,
	color: Color3,
	image: string,
	radius: number,
	duration: number,
	normal: Vector3?
)
	local n = normal or Vector3.yAxis
	local reference = if math.abs(n:Dot(Vector3.zAxis)) < 0.9 then Vector3.zAxis else Vector3.xAxis
	local right = reference:Cross(n).Unit
	local slot = self:_borrow(owner, duration, function(s, alpha)
		local diameter = radius * 2 * (0.25 + 0.75 * alpha)
		s.part.Size = Vector3.new(diameter, 0.05, diameter)
		s.image.ImageTransparency = 0.35 + 0.65 * alpha
	end)
	if not slot then
		return
	end
	slot.part.CFrame = CFrame.fromMatrix(position + n * 0.08, right, n)
	slot.part.Size = Vector3.new(radius * 0.5, 0.05, radius * 0.5)
	slot.image.Image, slot.image.ImageColor3 = image, color
	slot.image.ImageTransparency = 0.35
	slot.surface.Enabled = true
end

function EffectPool.Cancel(self: any, owner: any)
	owner.active = false
	for _, slot in self.slots do
		if slot.owner == owner then
			self:_release(slot)
		end
	end
end

function EffectPool.Stats(self: any)
	return {
		active = self.active,
		capacity = #self.slots,
		highWater = self.highWater,
		misses = self.misses,
		emitted = self.emitted,
	}
end

function EffectPool.Destroy(self: any)
	if self.destroyed then
		return
	end
	self.destroyed = true
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	for _, slot in self.slots do
		if slot.owner then
			slot.owner.active = false
		end
		self:_release(slot)
	end
	self.root:Destroy()
end

return EffectPool
