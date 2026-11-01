--!strict
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

type Rig = PetAnimations.Rig

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
	motors: { [string]: Motor6D },
	clip: string,
	time: number,
	fromClip: string?,
	fromTime: number,
	fade: number, -- 0..1, weight of `clip` while fading in
	once: string?, -- one-shot clip playing instead of Idle/Walk
	frozenUntil: number, -- os.clock(): hold the pose until then (hitstop)
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
	local last = clip.frames - 1
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

local function track(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local speciesId = model:GetAttribute("SpeciesId")
	local rig = typeof(speciesId) == "string" and PetAnimations.Get(speciesId) or nil
	local root = model.PrimaryPart
	if not rig or not root then
		return
	end
	local motors = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") then
			motors[descendant.Name] = descendant
		end
	end
	if next(motors) == nil then
		return
	end
	pets[model] = {
		model = model,
		root = root,
		rig = rig,
		motors = motors,
		clip = "Idle",
		time = math.random() * 2, -- desync idles so a group does not breathe in step
		fromClip = nil,
		fromTime = 0,
		fade = 1,
		once = nil,
		frozenUntil = 0,
	}
end

local function wantedClip(pet: Pet): (string, number)
	if pet.once then
		return pet.once, 1
	end
	local root = pet.root
	if root:FindFirstChild("CarryWeld") then
		return "Idle", 1
	end
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local walk = pet.rig.clips.Walk
	if speed < MOVING_SPEED or not walk then
		return "Idle", 1
	end
	local height = math.max(root.Size.Y, 0.5)
	return "Walk", math.clamp(speed * walk.duration / (STRIDE * height), 0.5, 3)
end

local function step(pet: Pet, dt: number)
	if os.clock() < pet.frozenUntil then
		dt = 0
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
			pet.once = nil -- back to Idle/Walk (with the usual fade)
		end
	end
	if pet.fromClip then
		pet.fromTime += dt
		pet.fade = math.min(1, pet.fade + dt / FADE_SECONDS)
		if pet.fade >= 1 then
			pet.fromClip = nil
		end
	end

	local scale = pet.model:GetScale()
	for joint, motor in pet.motors do
		local pose = sample(pet.rig, pet.clip, pet.time, joint, scale)
		if pet.fromClip then
			pose = sample(pet.rig, pet.fromClip, pet.fromTime, joint, scale):Lerp(pose, pet.fade)
		end
		motor.Transform = pose
	end
end

-- Plays a one-shot clip on a pet if its rig has it. Returns the clip's
-- length and its markers ({ impact = seconds, ... }), or nil when the clip
-- doesn't exist yet (the caller then animates procedurally).
function PetAnimator.PlayOnce(model: Model, clipName: string): (number?, { [string]: number }?)
	local pet = pets[model]
	local clip = pet and pet.rig.clips[clipName]
	if not pet or not clip then
		return nil, nil
	end
	pet.once = clipName
	return clip.duration, clip.markers
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
	animals.ChildAdded:Connect(function(child)
		-- Children stream in after the model itself.
		task.defer(track, child)
	end)
	animals.ChildRemoved:Connect(function(child)
		pets[child :: Model] = nil
		skipped[child :: Model] = nil
	end)
	for _, child in animals:GetChildren() do
		track(child)
	end

	local frame = 0
	RunService.PreSimulation:Connect(function(dt)
		frame += 1
		local camera = Workspace.CurrentCamera.CFrame.Position
		for model, pet in pets do
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
