--!nocheck
local checks = 0
local function check(v, why)
	checks += 1
	assert(v, why or `assertion {checks}`)
end
local function near(a, b, why)
	check(math.abs(a - b) < 0.00001, why or `{a} ~= {b}`)
end
local function event()
	local handlers = {}
	return {
		Connect = function(_, fn)
			local h = { fn = fn, active = true }
			table.insert(handlers, h)
			return {
				Disconnect = function()
					h.active = false
				end,
			}
		end,
		Fire = function(_, ...)
			for _, h in handlers do
				if h.active then
					h.fn(...)
				end
			end
		end,
	}
end
local vector = {}
vector.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2)
	end
end
vector.__sub = function(a, b)
	return setmetatable({ X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }, vector)
end
Vector3.new = function(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, vector)
end
local frame = {}
frame.__index = frame
function frame:Lerp(other, a)
	return CFrame.new(
		self.X + (other.X - self.X) * a,
		self.Y + (other.Y - self.Y) * a,
		self.Z + (other.Z - self.Z) * a
	)
end
CFrame = {
	new = function(x, y, z, ...)
		return setmetatable(
			{ X = x or 0, Y = y or 0, Z = z or 0, Position = Vector3.new(x or 0, y or 0, z or 0) },
			frame
		)
	end,
}
CFrame.identity = CFrame.new()
local originalTypeof = typeof
local function signals(object)
	object.signals = {}
	function object:GetAttribute(name)
		return self.attrs and self.attrs[name]
	end
	function object:GetAttributeChangedSignal(name)
		self.signals[name] = self.signals[name] or event()
		return self.signals[name]
	end
	function object:GetPropertyChangedSignal(name)
		return self:GetAttributeChangedSignal(name)
	end
	function object:SetAttribute(name, value)
		self.attrs[name] = value
		if self.signals[name] then
			self.signals[name]:Fire()
		end
	end
	return object
end
local Contract = load("ReplicatedStorage.Shared.OriginalPets.Contract")
local variant = Contract.Get("acorn_squirrel/Baby")
local rig = load("ReplicatedStorage.Shared.OriginalPets.Clips.AcornSquirrel")
local legacy = {
	fps = 1,
	joints = { { name = "legacy", parent = "RootPart" } },
	clips = {
		Idle = { duration = 1, frames = 2, loop = true, tracks = { legacy = { r = { 0, 0, 0, 1, 0, 0, 0, 1 } } } },
		Walk = { duration = 1, frames = 2, loop = true, tracks = {} },
		Attack_Test = { duration = 1, frames = 2, loop = false, tracks = {
			legacy = { r = { 0, 0, 0, 1, 0, 0, 0, 1 }, t = { 0, 0, 0, 1, 2, 3 } },
		} },
	},
}
mocks["ReplicatedStorage.Shared.PetAnimations"] = {
	Get = function()
		return legacy
	end,
}
-- Folder nodes resolve only the actual copied clip modules, lazily.
local folder = node("ReplicatedStorage.Shared.OriginalPets.Clips")
function folder:FindFirstChild(name)
	local module = node(self.path .. "." .. name)
	function module:IsA(class)
		return class == "ModuleScript"
	end
	return module
end
local actualGameGet = game.GetService
function game:GetService(name)
	if name == "ReplicatedStorage" then
		return {
			Shared = {
				PetAnimations = node("ReplicatedStorage.Shared.PetAnimations"),
				OriginalPets = {
					Contract = node("ReplicatedStorage.Shared.OriginalPets.Contract"),
					Clips = folder,
				},
			},
		}
	end
	return actualGameGet(self, name)
end
local function model(original)
	local m = signals({
		attrs = { SpeciesId = "AcornSquirrel", State = "Battling" },
		desc = {},
		DescendantAdded = event(),
		scale = 1,
	})
	function m:IsA(class)
		return class == "Model"
	end
	function m:GetDescendants()
		return self.desc
	end
	function m:GetScale()
		return self.scale
	end
	local root = {
		Position = Vector3.new(0, 0, 0),
		Size = Vector3.new(2, 3, 2),
		AssemblyLinearVelocity = Vector3.new(0, 0, 0),
	}
	function root:FindFirstChild(name)
		return if name == "CarryWeld" and self.carried then {} else nil
	end
	m.PrimaryPart = root
	if original then
		m.attrs.PetVariantKey = variant.key
		m.attrs.ArtSourceSha256 = variant.sourceSha256
		m.attrs.ImportedStudsPerMetre = 2
		local bones = {}
		for _, name in variant.bones do
			local b = signals({ Name = name, attrs = {}, Transform = CFrame.identity })
			function b:IsA(class)
				return class == "Bone"
			end
			bones[name] = b
			table.insert(m.desc, b)
		end
		for name, bone in bones do
			bone.Parent = bones[variant.boneParents[name]] or m
		end
		m.bones = bones
	else
		local motor = signals({ Name = "legacy", attrs = {}, Transform = CFrame.identity })
		function motor:IsA(class)
			return class == "Motor6D"
		end
		m.desc = { motor }
		m.bones = { legacy = motor }
	end
	return m
end
local pet = model(true)
local animals = { children = { pet }, ChildAdded = event(), ChildRemoved = event() }
function animals:GetChildren()
	return self.children
end
pet.Parent = animals
services.Workspace = {
	CurrentCamera = { CFrame = { Position = Vector3.new(0, 0, 0) } },
	WaitForChild = function(_, name)
		check(name == "Animals")
		return animals
	end,
}
services.RunService.PreSimulation = event()
local Animator = load("Client.Controllers.PetAnimator")
Animator.Start()
drainScheduled()
check(Animator.PlayOnce(pet, "Walk") == nil, "Gated original does not play")
pet:SetAttribute("OriginalPetPlaybackEnabled", true)
drainScheduled()
local duration, markers = Animator.PlayOnce(pet, "Attack_Tackle")
near(duration, rig.clips.Attack_Tackle.duration / 1.15, "Baby playback speed")
near(markers.impact, rig.clips.Attack_Tackle.markers.impact / 1.15, "markers follow phase speed")
local rate = 1.15
local function tick(dt)
	services.RunService.PreSimulation:Fire(dt)
end
local function hipsAt(clip, time)
	local track = rig.clips[clip].tracks.jnt_hips
	local n = math.min(math.floor(time * rig.fps), rig.clips[clip].frames - 1) * 3
	return track.t[n + 1] * 1.12, track.t[n + 2] * 1.12, track.t[n + 3] * 1.12
end
Animator.PlayOnce(pet, "Faint", true)
tick(10)
local x, y, z = hipsAt("Faint_Baby", rig.clips.Faint_Baby.duration)
near(pet.bones.jnt_hips.Transform.X, x)
near(pet.bones.jnt_hips.Transform.Y, y, "stage metres times imported factor exactly once")
near(pet.bones.jnt_hips.Transform.Z, z)
tick(4)
near(pet.bones.jnt_hips.Transform.Y, y, "Faint holds last pose indefinitely")
pet:SetAttribute("State", "Following")
tick(0.5)
check(math.abs(pet.bones.jnt_hips.Transform.Y - y) > 0.001, "state change releases held Faint")
Animator.PlayOnce(pet, "Attack_Tackle")
tick(0.2)
local first = pet.bones.jnt_hips.Transform.Y
Animator.PlayOnce(pet, "Attack_Tackle")
tick(0.2)
near(pet.bones.jnt_hips.Transform.Y, first, "repeated same-name attack restarts")
Animator.Freeze(pet, 1)
tick(0.3)
near(pet.bones.jnt_hips.Transform.Y, first, "hitstop preserves pose")
clock += 1.1
tick(0.3)
check(Animator.PlayOnce(pet, "MissingClip") == nil, "missing clip preserves procedural fallback")
local old = model(false)
animals.children[2] = old
old.Parent = animals
animals.ChildAdded:Fire(old)
drainScheduled()
check(Animator.PlayOnce(old, "Attack_Test") == 1, "legacy Motor6D path remains available")
tick(1)
near(old.bones.legacy.Transform.X, 1)
near(old.bones.legacy.Transform.Y, 2)
check(Animator.PlayOnce(old, "Faint") == nil, "legacy rig without Faint uses old effect")
-- Invalid provenance, partial and duplicate skeletons must not become tracked rigs.
for _, bad in { "hash", "scale", "partial", "duplicate", "species", "package" } do
	local m = model(true)
	m.attrs.OriginalPetPlaybackEnabled = true
	if bad == "hash" then
		m.attrs.ArtSourceSha256 = "wrong"
	elseif bad == "scale" then
		m.attrs.ImportedStudsPerMetre = 0 / 0
	elseif bad == "partial" then
		table.remove(m.desc)
	elseif bad == "duplicate" then
		table.insert(m.desc, m.desc[1])
	elseif bad == "species" then
		m.attrs.SpeciesId = "Spoutle"
	elseif bad == "package" then
		table.insert(m.desc, {
			IsA = function(_, class)
				return class == "PackageLink"
			end,
		})
	end
	check(Animator.PlayOnce(m, "Walk") == nil, "reject " .. bad)
end
-- Other stages select their calibrated Faint and report their own timing.
for _, stage in { "Juvenile", "Adult" } do
	local m = model(true)
	local v = Contract.Get("acorn_squirrel/" .. stage)
	m.attrs.PetVariantKey = v.key
	m.attrs.ArtSourceSha256 = v.sourceSha256
	m.attrs.OriginalPetPlaybackEnabled = true
	local len = Animator.PlayOnce(m, "Faint", true)
	near(
		len,
		rig.clips[if stage == "Adult" then "Faint" else "Faint_Juvenile"].duration
			/ (if stage == "Juvenile" then 1.07 else 1)
	)
end
pet:SetAttribute("OriginalPetPlaybackEnabled", false)
tick(0.1)
check(Animator.PlayOnce(pet, "Walk") == nil, "revoked gate stops playback")
near(pet.bones.jnt_hips.Transform.Y, 0, "revoked gate restores rest pose")
pet:SetAttribute("OriginalPetPlaybackEnabled", true)
tick(0.1)
check(Animator.PlayOnce(pet, "Attack_Tackle") ~= nil, "re-enable revalidates rig")
animals.ChildRemoved:Fire(pet)
print(`PASS {checks} Bone/Motor6D playback assertions; synthetic engine, G1-G6 still UNVERIFIED`)
