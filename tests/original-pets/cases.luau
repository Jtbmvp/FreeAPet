--!nocheck
local checks = 0
local function check(value, why)
	checks += 1
	assert(value, why or "Assertion failed")
end
local function eq(a, b, why)
	check(a == b, (why or "Mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function close(a, b, why)
	check(math.abs(a - b) < 0.000001, why or "Numeric mismatch")
end
CFrame = {
	Angles = function(x, y, z)
		return { x = x, y = y, z = z }
	end,
}
local contract = load("ReplicatedStorage.Shared.OriginalPets.Contract")
local catalog = load("ReplicatedStorage.Shared.OriginalPets.Catalog")
local variants = 0
for key, v in catalog.variants do
	variants += 1
	eq(key, v.key)
	check(v.stage ~= "AllStages")
	check(#v.bones > 0)
	check(v.clips.Idle.loop)
	check(v.clips.Walk.loop)
	check(#v.clips.Idle.scaleChannels > 0, "Breathing scale channels must remain disclosed")
	eq(contract.Get(key).sourceSha256, v.sourceSha256)
	check(v.clips.Hit == nil and v.clips.Faint == nil, "No invented reactions")
	close(contract.VisualOffset(v).y, math.pi, "Single +Z to -Z visual correction")
end
eq(variants, 27)
check(not catalog.active)
eq(contract.Stage(1), "Baby")
eq(contract.Stage(4), "Baby")
eq(contract.Stage(5), "Juvenile")
eq(contract.Stage(14), "Juvenile")
eq(contract.Stage(15), "Adult")
eq(contract.Stage(16), "Adult")
eq(contract.Stage(1, 1), "Adult", "Migration does not regress an old Adult shape")
eq(contract.Stage(1, 0.90), "Juvenile")
local baby = contract.ForRuntimeSpecies("AcornSquirrel", 1)
local juvenile = contract.ForRuntimeSpecies("AcornSquirrel", 5)
local adult = contract.ForRuntimeSpecies("AcornSquirrel", 15)
eq(baby.key, "acorn_squirrel/Baby")
eq(juvenile.key, "acorn_squirrel/Juvenile")
eq(adult.key, "acorn_squirrel/Adult")
eq(contract.ForRuntimeSpecies("Glimmouse", 1).key, "glimmouse/Baby", "Starter roster mapping")
eq(contract.ForRuntimeSpecies("glimmouse", 1), nil)
eq(contract.Get("glimmouse/Baby").adultHeightStuds, 3.5)
local factor = contract.Scale(baby, 2, 1, 1)
close(factor, 1.5, "Baby visual target is 3 studs, not source-size times growth twice")
close(contract.Scale(juvenile, 3, 5, 1), 3.52 / 3)
for level = 15, 30 do
	close(contract.Scale(adult, 6, level, 1), 4 / 6, "Adult stays the same height")
end
close(contract.Scale(baby, 2, 1, 1, 1), 2, "Legacy adult floor preserved")
eq(contract.Scale(baby, 0, 1, 1), nil)
eq(contract.Scale(baby, 2, 1, 0), nil)
eq(contract.Scale(baby, 2, 1, 1, math.huge), nil)
close(contract.Scale(contract.Get("glimmouse/Baby"), 2, 1, 1), 2.625 / 2)

local function binding(v)
	local b = { variantKey = v.key, sourceSha256 = v.sourceSha256, modelAssetId = v.modelAssetId, clips = {} }
	local id = 900000
	for name in v.clips do
		id += 1
		b.clips[name] = {
			assetId = tostring(id),
			clipName = name,
			sourceSha256 = v.sourceSha256,
			verifiedAssetType = "Animation",
		}
	end
	return b
end
local b = binding(baby)
check(contract.ValidateBinding(baby, b))
b.clips.Idle.assetId = baby.modelAssetId
check(not contract.ValidateBinding(baby, b), "Uploaded model is never an AnimationId")
b = binding(baby)
b.sourceSha256 = adult.sourceSha256
check(not contract.ValidateBinding(baby, b), "Never reuse source/rest poses by speciesId only")
b = binding(baby)
b.clips.Walk = nil
check(not contract.ValidateBinding(baby, b))
b = binding(baby)
b.clips.Idle.verifiedAssetType = "Model"
check(not contract.ValidateBinding(baby, b))
b = binding(baby)
b.clips.Hit = b.clips.Idle
check(not contract.ValidateBinding(baby, b))

-- Models have the exact catalog skeleton. Any attempt to set a gameplay
-- root/CFrame is outside this adapter; the test model exposes no such API.
services.Workspace = { Name = "SyntheticWorkspace" }
local workspace = services.Workspace
local objects = {}
local function object(class, name, parent)
	local o = { class = class, Name = name, Parent = parent }
	function o:IsA(wanted)
		return self.class == wanted
	end
	return o
end
local function rig(v)
	local model = object("Model", "Original", workspace)
	model.Destroying = signal()
	model.AncestryChanged = signal()
	model.attrs = { PetVariantKey = v.key, ArtSourceSha256 = v.sourceSha256 }
	function model:GetAttribute(name)
		return self.attrs[name]
	end
	function model:IsDescendantOf(parent)
		return self.Parent == parent
	end
	model.desc = {}
	function model:GetDescendants()
		return self.desc
	end
	local skin = object("MeshPart", "SkinnedBody", model)
	local bones = {}
	for _, name in v.bones do
		bones[name] = object("Bone", name, skin)
		table.insert(model.desc, bones[name])
	end
	for name, p in v.boneParents do
		bones[name].Parent = bones[p]
	end
	local controller = object("AnimationController", "OriginalController", model)
	local animator = object("Animator", "Animator", controller)
	animator.created = {}
	animator.length = 1
	animator.externalTracks = {}
	function animator:GetPlayingAnimationTracks()
		return self.externalTracks
	end
	function animator:LoadAnimation(animation)
		if self.failAt and #self.created + 1 == self.failAt then
			error("Synthetic unavailable asset")
		end
		local track = {
			Length = self.length,
			Ended = signal(),
			IsPlaying = false,
			Speed = 1,
			plays = 0,
			stops = 0,
			destroyed = false,
			animation = animation,
		}
		function track:Play(_, _, speed)
			self.IsPlaying = true
			self.Speed = speed
			self.plays += 1
		end
		function track:Stop()
			self.IsPlaying = false
			self.stops += 1
			self.Ended:Fire()
		end
		function track:AdjustSpeed(speed)
			self.Speed = speed
		end
		function track:Destroy()
			self.destroyed = true
		end
		table.insert(self.created, track)
		return track
	end
	table.insert(model.desc, animator)
	return model, animator, bones
end
Instance = {
	new = function(class)
		eq(class, "Animation", "Adapter creates only owned Animation definitions")
		local a = { class = class, destroyed = false }
		function a:Destroy()
			self.destroyed = true
		end
		table.insert(objects, a)
		return a
	end,
}
local Player = load("StarterPlayer.StarterPlayerScripts.Client.Animation.OriginalPetPlayer")
local model, animator, bones = rig(baby)
local api, err = Player.Attach(model, binding(baby))
check(api ~= nil, err)
check(api:Ready())
local clips = {}
for _, t in animator.created do
	clips[t.animation.Name] = t
end
eq(#animator.created, 5)
eq(clips.Idle.Priority, "AnimationPriority.Idle")
eq(clips.Walk.Priority, "AnimationPriority.Movement")
check(clips.Idle.Looped and clips.Walk.Looped)
check(clips.Idle.IsPlaying)
check(api:SetMotion(true, 2))
check(clips.Walk.IsPlaying)
close(clips.Walk.Speed, 2)
check(not clips.Idle.IsPlaying)
local plays = clips.Walk.plays
api:Step()
eq(clips.Walk.plays, plays, "No load/restart per frame")
check(api:SetMotion(false))
check(clips.Idle.IsPlaying)
check(not clips.Walk.IsPlaying)
eq(api:PlayOnce("Hit"), nil, "Missing reaction falls back explicitly")
eq(api:PlayOnce("Attack_TailSmack"), 1)
check(not clips.Attack_TailSmack.Looped)
eq(clips.Attack_TailSmack.Priority, "AnimationPriority.Action")
check(api:SetMotion(true, 1.5))
check(not clips.Walk.IsPlaying, "Motion waits while action owns pose")
clips.Attack_TailSmack.IsPlaying = false
clips.Attack_TailSmack.Ended:Fire()
check(clips.Walk.IsPlaying)
close(clips.Walk.Speed, 1.5)
api:Freeze(0.5)
eq(clips.Walk.Speed, 0)
clock += 0.25
api:Step()
eq(clips.Walk.Speed, 0)
clock += 0.5
api:Step()
close(clips.Walk.Speed, 1.5)
api:SetSuspended(true)
api:Step()
eq(clips.Walk.Speed, 0)
api:SetSuspended(false)
close(clips.Walk.Speed, 1.5)
check(not api:SetMotion(true, 0 / 0))
eq(Player.Attach(model, binding(baby)), nil, "One animation owner per model")
api:Destroy()
api:Destroy()
check(not api:Ready())
for _, t in animator.created do
	check(t.destroyed)
	check(t.animation.destroyed)
end
local nextPlayer = Player.Attach(model, binding(baby))
check(nextPlayer ~= nil, "Lease released after detach")
model.Parent = nil
model.AncestryChanged:Fire()
check(not nextPlayer:Ready(), "Leaving workspace cleans up")
local wrong = rig(baby)
wrong.attrs.ArtSourceSha256 = "legacy"
eq(Player.Attach(wrong, binding(baby)), nil)
local partial = rig(baby)
table.remove(partial.desc, 1)
eq(Player.Attach(partial, binding(baby)), nil, "Partial replication is not cached as a valid rig")
local duplicate = rig(baby)
table.insert(duplicate.desc, object("Bone", "jnt_hips", duplicate))
eq(Player.Attach(duplicate, binding(baby)), nil, "Combined rigs/duplicate bones rejected")
local executable = rig(baby)
table.insert(executable.desc, object("LuaSourceContainer", "ImportedScript", executable))
eq(Player.Attach(executable, binding(baby)), nil)
local waiting, wa = rig(baby)
wa.length = 0
local wp = Player.Attach(waiting, binding(baby))
check(wp ~= nil)
check(not wp:Ready())
eq(wp:PlayOnce("Attack_TailSmack"), nil)
clock += 11
wp:Step()
check(not wp:Ready())
for _, t in wa.created do
	check(t.destroyed)
end
local failed, fa = rig(baby)
fa.failAt = 3
local before = #objects
eq(Player.Attach(failed, binding(baby)), nil)
for _, t in fa.created do
	check(t.destroyed)
end
for i = before + 1, #objects do
	check(objects[i].destroyed, "Partial load frees Animation definitions")
end
fa.failAt = nil
check(Player.Attach(failed, binding(baby)) ~= nil, "Failed load releases ownership")
local busy, ba = rig(baby)
ba.externalTracks = { object("AnimationTrack", "OtherOwner", nil) }
eq(Player.Attach(busy, binding(baby)), nil)
print(
	"PASS "
		.. checks
		.. " original-pet catalog, normalization and native-player lifecycle assertions; synthetic adapters only"
)
