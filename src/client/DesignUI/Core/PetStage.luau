-- PetStage: a pet's real model playing its real Idle clip in a ViewportFrame.
-- A viewport has no physics, so nothing here uses joints: forward kinematics from the shared
-- rig data (Shared.PetAnimations) sets the CFrame of anchored clones. Purely presentation.
-- PetStage.new(parent, { pos, size, priority, isVisible }): priority stages step every frame;
-- the rest share a small budget per frame and only step while isVisible() says so.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Core = script.Parent
local Layout = require(Core.Layout)
local Motion = require(Core.Motion)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PetAnimations = require(Shared:WaitForChild("PetAnimations"))

local PetStage = {}
PetStage.__index = PetStage

local FOV = 24
local YAW, PITCH = math.rad(205), math.rad(10)
local SWAY = math.rad(9)
local GROWTH_ZOOM = { Baby = 1.3, Juvenile = 1.14, Adult = 1 }
local FADE_SECONDS = 0.2
local BUDGET_DESKTOP, BUDGET_MOBILE = 3, 2

local stages = {}
local connection = nil
local cursor = 1

local function artFor(speciesId)
	local species = Config.Species[speciesId]
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local animals = assets and assets:FindFirstChild("Animals")
	local art = species and animals and animals:FindFirstChild(species.modelName)
	local rig = PetAnimations.Get(speciesId)
	if art and art:IsA("Model") and rig and rig.clips and rig.clips.Idle then
		return art, rig
	end
	return nil, nil
end

-- True when this species can play a real clip; otherwise the caller keeps its portrait.
function PetStage.CanAnimate(speciesId)
	return (artFor(speciesId)) ~= nil
end

-- Same sampling as PetAnimator: quaternion nlerp plus optional translation, looped.
local function sample(rig, clipName, time, joint, scale)
	local clip = rig.clips[clipName]
	local track = clip and clip.tracks[joint]
	if not track then
		return CFrame.identity
	end
	local position = time * rig.fps
	local i0 = math.floor(position)
	local alpha = position - i0
	local last = math.max(1, clip.frames - 1)
	local i1 = i0 + 1
	if clip.loop then
		i0 %= last
		i1 %= last
	else
		i0 = math.min(i0, last)
		i1 = math.min(i1, last)
	end
	local r = track.r
	local a, b = i0 * 4, i1 * 4
	local x, y, z, w = r[a + 1], r[a + 2], r[a + 3], r[a + 4]
	local bx, by, bz, bw = r[b + 1], r[b + 2], r[b + 3], r[b + 4]
	if x * bx + y * by + z * bz + w * bw < 0 then
		bx, by, bz, bw = -bx, -by, -bz, -bw
	end
	x, y, z, w = x + (bx - x) * alpha, y + (by - y) * alpha, z + (bz - z) * alpha, w + (bw - w) * alpha
	local px, py, pz = 0, 0, 0
	local t = track.t
	if t then
		local c, d = i0 * 3, i1 * 3
		px = (t[c + 1] + (t[d + 1] - t[c + 1]) * alpha) * scale
		py = (t[c + 2] + (t[d + 2] - t[c + 2]) * alpha) * scale
		pz = (t[c + 3] + (t[d + 3] - t[c + 3]) * alpha) * scale
	end
	return CFrame.new(px, py, pz, x, y, z, w)
end

local function build(self)
	if not self.speciesId then
		return
	end
	local art, rig = artFor(self.speciesId)
	if not art then
		self.built = true
		return
	end
	local clone = art:Clone()
	local pivot = clone:GetPivot()
	local rootRest = pivot * PetAnimations.ToCFrame(rig.root)
	local rest = { RootPart = rootRest }
	local chain = {}
	for _, joint in rig.joints do
		local parentRest = rest[joint.parent]
		if parentRest then
			local frame = pivot * PetAnimations.ToCFrame(joint.frame)
			rest[joint.name] = frame
			table.insert(chain, { name = joint.name, parent = joint.parent, c0 = parentRest:ToObjectSpace(frame) })
		end
	end
	local attached = {}
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
			local holder = part.Parent
			while holder and holder ~= clone and not rest[holder.Name] do
				holder = holder.Parent
			end
			local bone = if holder and holder ~= clone then holder.Name else "RootPart"
			table.insert(attached, { part = part, bone = bone, offset = rest[bone]:ToObjectSpace(part.CFrame) })
		elseif part:IsA("Script") or part:IsA("LocalScript") then
			part:Destroy()
		end
	end
	self.rig, self.rootRest, self.chain, self.attached = rig, rootRest, chain, attached
	self.world = { RootPart = rootRest }
	self.scale = clone:GetScale()
	self.clip, self.time = "Idle", math.random() * 2
	self.fromClip, self.fromTime, self.fade = nil, 0, 1
	self.nextFidget = os.clock() + math.random(5, 11)

	-- Frame the rest pose once, so the idle's small movements never make the camera breathe.
	local center, size = clone:GetBoundingBox()
	local frame = self.Frame
	local px = frame.AbsoluteSize
	local aspect = if px.Y > 0 then px.X / px.Y else (self.aspect or 1)
	local tanHalf = math.tan(math.rad(FOV) / 2)
	local wide = math.abs(math.cos(YAW)) * size.X + math.abs(math.sin(YAW)) * size.Z
	local depth = math.abs(math.sin(YAW)) * size.X + math.abs(math.cos(YAW)) * size.Z
	local fit = math.max(size.Y / 2 / tanHalf, wide / 2 / (tanHalf * aspect))
	self.focus = center.Position
	self.distance = (fit * 1.03 + depth * 0.35) * (GROWTH_ZOOM[self.growth or "Adult"] or 1)
	clone.Parent = frame
	self.model = clone
	self.built = true
	self:_aim(0)
	self:_pose(0)
	if self.OnBuilt then
		self.OnBuilt()
	end
end

function PetStage:_aim(t)
	local yaw = YAW + (if self.priority and not Motion.Reduced then math.sin(t * 0.55) * SWAY else 0)
	local offset = CFrame.Angles(0, yaw, 0) * CFrame.Angles(-PITCH, 0, 0) * Vector3.new(0, 0, self.distance)
	self.Camera.CFrame = CFrame.lookAt(self.focus + offset, self.focus)
end

function PetStage:_pose(dt)
	local rig = self.rig
	local clips = rig.clips
	self.time += dt
	local current = clips[self.clip]
	if self.clip ~= "Idle" and (not current or self.time >= current.duration) then
		self.fromClip, self.fromTime, self.fade = self.clip, self.time, 0
		self.clip, self.time = "Idle", 0
	end
	if self.fromClip then
		self.fromTime += dt
		self.fade = math.min(1, self.fade + dt / FADE_SECONDS)
		if self.fade >= 1 then
			self.fromClip = nil
		end
	end
	local world, scale = self.world, self.scale
	for _, joint in self.chain do
		local pose = sample(rig, self.clip, self.time, joint.name, scale)
		if self.fromClip then
			pose = sample(rig, self.fromClip, self.fromTime, joint.name, scale):Lerp(pose, self.fade)
		end
		world[joint.name] = world[joint.parent] * joint.c0 * pose
	end
	for _, item in self.attached do
		item.part.CFrame = world[item.bone] * item.offset
	end
end

function PetStage:_step(now)
	local dt = now - (self.lastStep or now)
	self.lastStep = now
	if Motion.Reduced then
		return
	end
	if self.priority then
		if self.clip == "Idle" and now >= self.nextFidget and self.rig.clips.Fidget then
			self:PlayOnce("Fidget")
			self.nextFidget = now + math.random(9, 16)
		end
		self:_aim(now)
	end
	self:_pose(math.min(dt, 0.5))
end

-- A one-shot clip (Fidget) over the idle, with the usual crossfade.
function PetStage:PlayOnce(clipName)
	if not self.rig or not self.rig.clips[clipName] then
		return
	end
	self.fromClip, self.fromTime, self.fade = self.clip, self.time, 0
	self.clip, self.time = clipName, 0
end

local function tick()
	local now = os.clock()
	local budget = if Layout.isMobile() then BUDGET_MOBILE else BUDGET_DESKTOP
	local builtThisFrame = false
	local count = #stages
	if count == 0 then
		return
	end
	for _, stage in stages do
		if stage.priority and stage.active and stage.speciesId then
			if not stage.built then
				build(stage)
				builtThisFrame = true
			elseif stage.model then
				stage:_step(now)
			end
		end
	end
	-- Everything else shares the budget round-robin.
	local visited = 0
	while visited < count and budget > 0 do
		cursor = (cursor % count) + 1
		visited += 1
		local stage = stages[cursor]
		if stage and not stage.priority and stage.active and stage.speciesId and (not stage.isVisible or stage.isVisible()) then
			if not stage.built then
				if not builtThisFrame then
					build(stage)
					builtThisFrame = true
				end
				budget -= 1
			elseif stage.model then
				stage:_step(now)
				budget -= 1
			end
		end
	end
end

local function syncLoop()
	local wanted = false
	for _, stage in stages do
		if stage.active then
			wanted = true
			break
		end
	end
	if wanted and not connection then
		connection = RunService.RenderStepped:Connect(function()
			local ok, err = pcall(tick)
			if not ok then
				connection:Disconnect()
				connection = nil
				warn("PetStage stopped: " .. tostring(err))
			end
		end)
	elseif not wanted and connection then
		connection:Disconnect()
		connection = nil
	end
end

function PetStage.new(parent, o)
	local vp = Instance.new("ViewportFrame")
	vp.Name = o.name or "PetStage"
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(205, 205, 212)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.LightDirection = Vector3.new(-0.45, -1, -0.7)
	vp.Position = o.pos or UDim2.new()
	vp.Size = o.size or UDim2.fromScale(1, 1)
	vp.ZIndex = o.z or 1
	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.Parent = vp
	vp.CurrentCamera = camera
	vp.Parent = parent
	local self = setmetatable({
		Frame = vp,
		Camera = camera,
		priority = o.priority == true,
		isVisible = o.isVisible,
		aspect = o.aspect,
		active = false,
		built = false,
	}, PetStage)
	table.insert(stages, self)
	return self
end

-- Swaps the pet. Returns false when the species has no animated model (keep the portrait).
function PetStage:Set(speciesId, growth)
	if self.speciesId == speciesId and self.growth == growth then
		return self.model ~= nil or PetStage.CanAnimate(speciesId)
	end
	if self.model then
		self.model:Destroy()
		self.model = nil
	end
	self.speciesId, self.growth = speciesId, growth
	self.built, self.rig, self.lastStep = false, nil, nil
	return PetStage.CanAnimate(speciesId)
end

function PetStage:SetActive(on)
	self.active = on
	self.lastStep = nil
	syncLoop()
end

function PetStage:Destroy()
	local index = table.find(stages, self)
	if index then
		table.remove(stages, index)
	end
	self.active = false
	self.Frame:Destroy()
	syncLoop()
end

return PetStage
