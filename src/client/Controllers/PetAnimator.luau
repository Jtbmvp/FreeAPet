--!strict
-- Plays legacy Motor6Ds and gated original Bone.Transform clips on this client.
-- Original assets require provenance, measured ImportedStudsPerMetre and explicit
-- OriginalPetPlaybackEnabled after pilot inspection. No asset insertion/activation here.
-- Plays the pets' clips on this client by driving the Motor6Ds that
-- AnimalFactory builds (data in Shared.PetAnimations). Purely visual: the
-- server never animates and nothing is replicated. A pet walks while it
-- moves (cycle speed follows its speed and size) and idles otherwise;
-- carried pets idle. Pets far from the camera keep their last pose.
-- Battles play one-shot clips (PlayOnce, e.g. "Attack_AcornToss") and
-- freeze a pet for a few frames on a hit (Freeze).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PetAnimations = require(ReplicatedStorage.Shared.PetAnimations)

local Contract = require(ReplicatedStorage.Shared.OriginalPets.Contract)
local Clips = ReplicatedStorage.Shared.OriginalPets.Clips

type Rig = {
	fps: number,
	joints: { { name: string, parent: string } },
	clips: { [string]: PetAnimations.Clip },
	stageScale: { [string]: number }?,
}
local originalRigs: { [string]: Rig } = {}
local function originalRig(speciesId: string): Rig?
	if originalRigs[speciesId] then
		return originalRigs[speciesId]
	end
	local module = Clips:FindFirstChild(speciesId)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local rig = (require :: any)(module) :: Rig
	originalRigs[speciesId] = rig
	return rig
end

local PetAnimator = {}

local FAR = 160 -- studs from the camera: beyond this, no updates
local MID = 70 -- beyond this, update every other frame
local FADE_SECONDS = 0.2
local MOVING_SPEED = 0.8 -- studs/s
local STRIDE = 1.4 -- studs walked per Walk cycle, per stud of pet height

type Pet = {
	model: Model,
	root: BasePart,
	rig: Rig,
	motors: { [string]: Motor6D | Bone },
	stage: string?,
	studsPerMetre: number,
	holdLast: boolean,
	poseState: any,
	idleSeconds: number,
	nextFidget: number,
	clip: string,
	time: number,
	fromClip: string?,
	fromTime: number,
	fade: number, -- 0..1, weight of `clip` while fading in
	once: string?, -- one-shot clip playing instead of Idle/Walk
	frozenUntil: number, -- os.clock(): hold the pose until then (hitstop)
	suspended: boolean,
}

local pets: { [Model]: Pet } = {}
local skipped: { [Model]: number } = {} -- time owed to pets updated at half rate

-- Transform of one joint in a clip at a time (seconds); identity when the
-- clip does not move that joint.
local function sample(rig: Rig, clipName: string, time: number, joint: string, scale: number): CFrame
	local clip = rig.clips[clipName]
	local track = clip and clip.tracks[joint]
	if not clip or not track then
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
	-- CFrame.new normalises the quaternion.
	return CFrame.new(px, py, pz, x, y, z, w)
end

local function track(model: Instance): boolean
	if not model:IsA("Model") then
		return false
	end
	local speciesId = model:GetAttribute("SpeciesId")
	local root = model.PrimaryPart
	if typeof(speciesId) ~= "string" or not root then
		return false
	end
	local key = model:GetAttribute("PetVariantKey")
	local stage: string? = nil
	local importedScale = 1
	local rig: Rig? = nil
	local variant = if typeof(key) == "string" then Contract.Get(key) else nil
	if key ~= nil then
		if
			not variant
			or variant.runtimeSpeciesId ~= speciesId
			or model:GetAttribute("ArtSourceSha256") ~= variant.sourceSha256
			or model:GetAttribute("OriginalPetPlaybackEnabled") ~= true
		then
			return false
		end
		local factor = model:GetAttribute("ImportedStudsPerMetre")
		if typeof(factor) ~= "number" or factor ~= factor or factor <= 0 or factor == math.huge then
			return false
		end
		importedScale, stage = factor, variant.stage
		rig = originalRig(speciesId)
	else
		rig = PetAnimations.Get(speciesId) :: any
	end
	if not rig then
		return false
	end
	local motors: { [string]: Motor6D | Bone } = {}
	local boneCount = 0
	for _, descendant in model:GetDescendants() do
		if stage and (descendant:IsA("LuaSourceContainer") or descendant:IsA("PackageLink")) then
			return false
		end
		if stage and descendant:IsA("Animator") and #descendant:GetPlayingAnimationTracks() > 0 then
			return false
		end
		if (stage and descendant:IsA("Bone")) or (not stage and descendant:IsA("Motor6D")) then
			if motors[descendant.Name] then
				return false
			end
			motors[descendant.Name] = descendant :: any
			boneCount += 1
		end
	end
	if next(motors) == nil then
		return false
	end
	if variant then
		if boneCount ~= #variant.bones then
			return false
		end
		for name, expectedParent in variant.boneParents do
			local bone = motors[name]
			local parent: Instance? = bone and bone.Parent
			while parent and parent ~= model and not parent:IsA("Bone") do
				parent = parent.Parent
			end
			if not parent or not parent:IsA("Bone") or parent.Name ~= expectedParent then
				return false
			end
		end
	end
	for _, joint in rig.joints do
		if not motors[joint.name] then
			return false
		end -- retry partial replication
	end
	pets[model] = {
		model = model,
		root = root,
		rig = rig,
		motors = motors,
		stage = stage,
		studsPerMetre = importedScale,
		holdLast = false,
		poseState = nil,
		idleSeconds = 0,
		nextFidget = math.random(10, 14),
		clip = "Idle",
		time = math.random() * 2,
		fromClip = nil,
		fromTime = 0,
		fade = 1,
		once = nil,
		frozenUntil = 0,
		suspended = false,
	}
	return true
end

local function clipFor(pet: Pet, name: string): string
	local staged = if pet.stage then `{name}_{pet.stage}` else name
	return if pet.rig.clips[staged] then staged else name
end
local function stageRate(pet: Pet, name: string): number
	if name == "Walk" then
		return 1
	end
	return if pet.stage == "Baby" then 1.15 elseif pet.stage == "Juvenile" then 1.07 else 1
end
local function motionClip(pet: Pet): (string, number)
	local root = pet.root
	if root:FindFirstChild("CarryWeld") then
		return if pet.rig.clips.Carried then "Carried" else "Idle", 1
	end
	if pet.model:GetAttribute("State") == "Battling" and pet.rig.clips.BattleIdle then
		return "BattleIdle", 1
	end
	-- Sleep is opt-in presentation only; proximity policy remains outside this player.
	if pet.model:GetAttribute("PetSleeping") == true and pet.rig.clips.Sleep then
		return clipFor(pet, "Sleep"), 1
	end
	local velocity = root.AssemblyLinearVelocity
	local followerSpeed = pet.model:GetAttribute("FollowerSpeed")
	local speed = if typeof(followerSpeed) == "number"
		then followerSpeed
		else Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local walk = pet.rig.clips.Walk
	if speed < MOVING_SPEED or not walk then
		return "Idle", 1
	end
	local height = math.max(root.Size.Y, 0.5)
	return "Walk", math.clamp(speed * walk.duration / (STRIDE * height), 0.5, 3)
end
local function wantedClip(pet: Pet): (string, number)
	local motion, rate = motionClip(pet)
	if pet.holdLast and pet.model:GetAttribute("State") ~= pet.poseState then
		pet.once = nil
		pet.holdLast = false
	end
	if pet.once == "Fidget" and motion ~= "Idle" then
		pet.once = nil
	end
	if pet.once then
		return pet.once, stageRate(pet, pet.once)
	end
	return motion, rate * stageRate(pet, motion)
end

local function step(pet: Pet, dt: number)
	if os.clock() < pet.frozenUntil then
		dt = 0
	end
	local motion = motionClip(pet)
	if
		motion == "Idle"
		and not pet.once
		and pet.rig.clips.Fidget
		and Workspace.CurrentCamera
		and (pet.root.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude < MID
	then
		pet.idleSeconds += dt
		if pet.idleSeconds >= pet.nextFidget then
			pet.once = "Fidget"
			pet.idleSeconds, pet.nextFidget = 0, math.random(16, 26)
		end
	elseif motion ~= "Idle" then
		pet.idleSeconds = 0
	end
	local clip, rate = wantedClip(pet)
	if clip ~= pet.clip then
		pet.fromClip, pet.fromTime = pet.clip, pet.time
		pet.clip, pet.time, pet.fade = clip, 0, 0
	end
	pet.time += dt * rate
	if pet.once and pet.clip == pet.once then
		local once = pet.rig.clips[pet.once]
		if not once or pet.time >= once.duration then
			if pet.holdLast and once then
				pet.time = once.duration
			else
				pet.once = nil -- back to motion (with the usual fade)
			end
		end
	end
	if pet.fromClip then
		pet.fromTime += dt
		pet.fade = math.min(1, pet.fade + dt / FADE_SECONDS)
		if pet.fade >= 1 then
			pet.fromClip = nil
		end
	end

	local stageScale = pet.rig.stageScale
	local scale = pet.model:GetScale()
		* pet.studsPerMetre
		* (if pet.stage and stageScale then stageScale[pet.stage] or 1 else 1)
	for joint, motor in pet.motors do
		local pose = sample(pet.rig, pet.clip, pet.time, joint, scale)
		if pet.fromClip then
			pose = sample(pet.rig, pet.fromClip, pet.fromTime, joint, scale):Lerp(pose, pet.fade)
		end
		-- Only use a measured rotation basis if pilot G2 found differing axes.
		local basis = if motor:IsA("Bone") then motor:GetAttribute("BonePoseBasis") else nil
		if typeof(basis) == "CFrame" then
			pose = basis.Rotation:Inverse() * pose * basis.Rotation
		end
		motor.Transform = pose
	end
end

-- Plays a one-shot clip on a pet if its rig has it. Returns the clip's
-- length and its markers ({ impact = seconds, ... }), or nil when the clip
-- doesn't exist yet (the caller then animates procedurally).
function PetAnimator.PlayOnce(
	model: Model,
	clipName: string,
	holdLast: boolean?
): (number?, { [string]: number }?)
	if not pets[model] then
		track(model)
	end
	local pet = pets[model]
	if not pet or (pet.stage and model:GetAttribute("OriginalPetPlaybackEnabled") ~= true) then
		return nil, nil
	end
	local selected = clipFor(pet, clipName)
	local clip = pet.rig.clips[selected]
	if not clip then
		return nil, nil
	end
	pet.once = selected
	pet.holdLast = holdLast == true or clipName == "Faint"
	pet.poseState = model:GetAttribute("State")
	-- Restart repeated same-name attacks rather than inheriting their old elapsed time.
	pet.fromClip, pet.fromTime = pet.clip, pet.time
	pet.clip, pet.time, pet.fade = selected, 0, 0
	local rate = stageRate(pet, selected)
	local markers: { [string]: number }? = nil
	if clip.markers then
		markers = {}
		for name, seconds in clip.markers do
			(markers :: { [string]: number })[name] = seconds / rate
		end
	end
	return clip.duration / rate, markers
end

-- Holds a pet's current pose for `seconds` (hitstop).
function PetAnimator.Freeze(model: Model?, seconds: number)
	local pet = model and pets[model]
	if pet then
		pet.frozenUntil = os.clock() + seconds
	end
end

function PetAnimator.Start()
	local animals = Workspace:WaitForChild("Animals")
	local pending: { [Instance]: { RBXScriptConnection } } = {}
	local function stopWatching(child: Instance)
		for _, connection in pending[child] or {} do
			connection:Disconnect()
		end
		pending[child] = nil
	end
	local function watch(child: Instance)
		if not child:IsA("Model") then
			return
		end
		local queued = false
		local function retry()
			if queued then
				return
			end
			queued = true
			task.defer(function()
				queued = false
				if child.Parent == animals and track(child) then
					stopWatching(child)
				end
			end)
		end
		pending[child] = {
			child.DescendantAdded:Connect(retry),
			child:GetPropertyChangedSignal("PrimaryPart"):Connect(retry),
			child:GetAttributeChangedSignal("SpeciesId"):Connect(retry),
			child:GetAttributeChangedSignal("PetVariantKey"):Connect(retry),
			child:GetAttributeChangedSignal("ArtSourceSha256"):Connect(retry),
			child:GetAttributeChangedSignal("ImportedStudsPerMetre"):Connect(retry),
			child:GetAttributeChangedSignal("OriginalPetPlaybackEnabled"):Connect(retry),
		}
		retry() -- wait for late root, species and joints without polling tasks
	end
	animals.ChildAdded:Connect(watch)
	animals.ChildRemoved:Connect(function(child)
		stopWatching(child)
		pets[child :: Model] = nil
		skipped[child :: Model] = nil
	end)
	for _, child in animals:GetChildren() do
		watch(child)
	end

	local frame = 0
	RunService.PreSimulation:Connect(function(dt)
		frame += 1
		local currentCamera = Workspace.CurrentCamera
		if not currentCamera then
			return
		end
		local camera = currentCamera.CFrame.Position
		for model, pet in pets do
			if pet.stage and model:GetAttribute("OriginalPetPlaybackEnabled") ~= true then
				if not pet.suspended then
					for _, joint in pet.motors do
						joint.Transform = CFrame.identity
					end
					pet.once, pet.fromClip, pet.holdLast = nil, nil, false
					pet.clip, pet.time = "Idle", 0
				end
				pet.suspended = true
				skipped[model] = nil
				continue
			end
			if pet.suspended then
				pets[model] = nil
				track(model) -- revalidate calibration/provenance after a paused pilot
				continue
			end
			local distance = (pet.root.Position - camera).Magnitude
			if distance < FAR then
				if distance < MID or frame % 2 == 0 then
					step(pet, dt + (skipped[model] or 0))
					skipped[model] = nil
				else
					skipped[model] = (skipped[model] or 0) + dt
				end
			end
		end
	end)
end

return PetAnimator
