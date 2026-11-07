--!nocheck
local Fx = load("Client.Battle.Fx")
local Presentation = load("Client.Battle.Fx.AttackPresentation")
local Profiles = load("Client.Battle.Fx.AttackProfiles")
local Settings = load("Client.Battle.BattleSettings")
local a = model(Vector3.new(2.7, 2.625, 3.3), Vector3.new(-1, 0, 6))
local b = model(Vector3.new(2.4, 9, 8.7), Vector3.new(3, 0, -6))
local function context(species, move)
	return {
		attacker = a,
		target = b,
		species = species,
		move = move,
		moveType = "Neutral",
		effect = "normal",
		damage = 21,
		impact = function() end,
		clip = function()
			return nil, nil
		end,
	}
end
local configBattle = load("ReplicatedStorage.Shared.Config.Battle")
local configured = 0
for species, definition in configBattle.species do
	for index = 2, 4 do
		local move = definition.moves[index]
		configured += 1
		check(Profiles.profiles[species][move.name] ~= nil, "actual Config move has a profile")
		check(
			Profiles.profiles[species][move.name].clip == Fx.ClipName(move.name),
			"clip binding matches actual Config"
		)
	end
end
near(configured, 27)
local profiles = 0
for species, moves in Profiles.profiles do
	for move in moves do
		profiles += 1
		local ctx = context(species, move)
		local count = 0
		ctx.impact = function()
			count += 1
		end
		Fx.Play(ctx)
		near(count, 1, "one authoritative presentation impact")
		near(Fx.Stats().active, 0, "pooled slots returned after cast")
		check(Fx.Stats().highWater <= 18)
	end
end
near(profiles, 27)
local ctx = context("Glimmouse", "Tackle")
local hit = 0
ctx.impact = function()
	hit += 1
end
Fx.Play(ctx)
near(hit, 1)
near(#legacy, 0, "recognised moves never dispatch legacy rendering")
near(oldImpact, 0, "Common.Hit old particles/debris suppressed")
near(oldFlash, 0, "no out-of-budget Highlight")
near(oldNumbers, 0, "uses bounded labels instead of old damage allocation")
local before = created
for _ = 1, 30 do
	Fx.Play(context("Spoutle", "Jet Splash"))
	near(Fx.Stats().active, 0)
end
advance(1)
near(render:Count(), 0, "no residual pool/damage connections")
-- Only labels allocate per cast:3 small instances, no unbounded emitter/debris allocations.
check(created - before <= 30 * 3, "Common.Hit extra allocations bounded")
local cancelled = context("Glimmouse", "Gem Whip")
local late = 0
cancelled.impact = function()
	late += 1
end
local began = clock
cancelled.cancelled = function()
	return clock - began >= 0.05
end
Fx.Play(cancelled)
near(late, 0, "cancel before marker never delivers a late impact")
near(Fx.Stats().active, 0)
local byEpoch = context("Glimmouse", "Hop Kick")
byEpoch.impact = function()
	late += 1
end
byEpoch.onBeat = function(phase)
	if phase == "anticipation" then
		Fx.CancelAll()
	end
end
Fx.Play(byEpoch)
near(late, 0, "CancelAll fences final fallback too")
attrs.V3MobileProfile = true
local emitted = Fx.Stats().emitted or 0
Fx.Play(context("Spoutle", "Fountain Geyser"))
near(Fx.Stats().capacity, 10)
check(Fx.Stats().emitted <= 44, "mobile per-cast particle budget")
local labels = screenRoot:GetDescendants()
advance(1)
Fx.CancelAll()
near(render:Count(), 0)
-- A quality change cancels the previous owner without allowing its fallback impact.
local qualityCancelled = context("Glimmouse", "Gem Whip")
local qualityHit = 0
qualityCancelled.impact = function()
	qualityHit += 1
end
onAdvance = function()
	Presentation.SetOptions({ mobile = false })
	onAdvance = nil
end
Fx.Play(qualityCancelled)
near(qualityHit, 0, "QoS cancellation fences final impact")
-- Unknown moves retain a guarded, idempotent fallback.
local unknown = context("Unknown", "Unknown")
local unknownHits = 0
unknown.impact = function()
	unknownHits += 1
end
Fx.Play(unknown)
near(unknownHits, 1)
near(oldImpact, 1)
near(oldFlash, 1)
near(oldNumbers, 1)
-- A feedback failure cannot drop the HP callback.
local savedHit = Common.Hit
Common.Hit = function()
	error("synthetic effect failure")
end
local broken = context("Unknown", "Unknown")
broken.impact = function()
	unknownHits += 1
end
Fx.Play(broken)
near(unknownHits, 2)
Common.Hit = savedHit
-- Missing clip/marker and malformed numeric duration retain fallback timing.
mocks["Client.Controllers.PetAnimator"].PlayOnce = function()
	return 0 / 0, { impact = math.huge }
end
local noClip = context("Glimmouse", "Crystal Chime")
local noClipHit = 0
noClip.impact = function()
	noClipHit += 1
end
Fx.Play(noClip)
near(noClipHit, 1)
-- No clip, no marker and invalid markers all use deterministic fallback timing.
for _, mode in { "none", "no-marker", "invalid-marker" } do
	mocks["Client.Controllers.PetAnimator"].PlayOnce = function()
		if mode == "none" then
			return nil, nil
		elseif mode == "no-marker" then
			return 1, nil
		else
			return 1, { impact = math.huge }
		end
	end
	local test = context("Glimmouse", "Crystal Chime")
	local times = {}
	local began = clock
	test.impact = function()
		table.insert(times, clock - began)
	end
	Fx.Play(test)
	near(#times, 1)
	local expected = if mode == "none"
		then Profiles.profiles.Glimmouse["Crystal Chime"].windup
			+ Profiles.profiles.Glimmouse["Crystal Chime"].travel
		else 0.5
	check(times[1] >= expected - 0.001 and times[1] <= expected + 0.11, "fallback marker clock")
end
local renderer = Presentation.Play
Presentation.Play = function()
	error("synthetic renderer failure")
end
local fails = context("Spoutle", "Jet Splash")
local failHits = 0
fails.impact = function()
	failHits += 1
end
Fx.Play(fails)
near(failHits, 1, "renderer error does not drop HP callback")
Presentation.Play = renderer
-- Destroyed target cancels the cast and returns all borrowed slots.
local doomed = context("Glimmouse", "Gem Whip")
local doomedHit = 0
doomed.impact = function()
	doomedHit += 1
end
onAdvance = function()
	b.Parent = nil
	onAdvance = nil
end
Fx.Play(doomed)
near(doomedHit, 0)
near(Fx.Stats().active, 0)
b.Parent = world
Fx.Destroy()
advance(1)
near(render:Count(), 0)
-- Real ShotRecipes against narrow, phone landscape and wide aspects, tiny/large pets.
local Shots = load("Client.Battle.ShotRecipes")
for _, aspect in { 0.75, 16 / 9, 21 / 9 } do
	for _, height in { 2.625, 3, 8, 9 } do
		local large = model(Vector3.new(5.4, height, 8.7), Vector3.new(2, 0, -6))
		local boundA, boundB = Shots.Capture(a), Shots.Capture(large)
		for _, recipe in
			{
				Shots.TwoShot(CFrame.identity, boundA, boundB, aspect, false),
				Shots.Attack(CFrame.identity, boundA, boundB, aspect, false),
			}
		do
			local eye, focus, fov = recipe(0.2)
			local view = CFrame.lookAt(eye, focus)
			for _, bounds in { boundA, boundB } do
				local cf = bounds.model:GetPivot() * bounds.localCentre
				for _, x in { -1, 1 } do
					for _, y in { -1, 1 } do
						for _, z in { -1, 1 } do
							local point =
								view:PointToObjectSpace(cf * (bounds.size * Vector3.new(x, y, z) * 0.5))
							local tan = math.tan(math.rad(fov / 2))
							check(-point.Z > 0, "all bounds in front of camera")
							check(math.abs(point.Y) <= -point.Z * tan, "vertical bounds fit")
							check(math.abs(point.X) <= -point.Z * tan * aspect, "horizontal bounds fit")
						end
					end
				end
			end
		end
	end
end
-- Feet pivots are not mistaken for body centres.
local foot = model(Vector3.new(3, 9, 8.7), Vector3.zero)
function foot:GetBoundingBox()
	return self:GetPivot() * CFrame.new(0, 4.5, 0), self.Size
end
local footBounds = Shots.Capture(foot)
near(footBounds.localCentre.Position.Y, 4.5)
local _, footFocus = Shots.Hero(CFrame.identity, footBounds, true, 16 / 9, true)(0)
check(footFocus.Y > 4.5, "hero focuses above the original feet pivot")
-- Camera replacement and abort restore exact ownership, FOV and Focus.
local original = world.CurrentCamera
local kind, subject, fov, focus =
	original.CameraType, original.CameraSubject, original.FieldOfView, original.Focus
BattleCamera.Begin(CFrame.identity, a, b)
BattleCamera.Move(BattleCamera.Gameplay(), 0.1)
advance(0.2)
check(original.CameraType == Enum.CameraType.Scriptable)
local other = makeCamera(57)
other.CameraType = "Track"
world.CurrentCamera = other
cameraChanged:Fire()
near(original.FieldOfView, fov)
check(original.CameraType == kind and original.CameraSubject == subject)
near(original.Focus.Position.Y, focus.Position.Y)
BattleCamera.Move(BattleCamera.Gameplay(), 0.1)
advance(0.2)
BattleCamera.Release(0)
near(other.FieldOfView, 57)
check(other.CameraType == "Track")
near(render:Count(), 0)
Settings.reducedMotion = true
BattleCamera.Begin(CFrame.identity, a, b)
BattleCamera.Move(BattleCamera.Gameplay(), 1)
BattleCamera.Shake("heavy")
BattleCamera.Punch(-20, 2)
advance(0.3)
local staticFov = other.FieldOfView
advance(0.4)
near(other.FieldOfView, staticFov, "reduced motion suppresses FOV punch")
-- Terrain is a first-class ray target, never queried through BasePart.Size.
world.Raycast = function()
	return { Instance = world.Terrain, Position = Vector3.new(0, 0, 0) }
end
advance(0.1)
BattleCamera.Release(0)
world.Raycast = function()
	return nil
end
near(render:Count(), 0)

-- A delayed release from a previous battle cannot restore a newer owner's camera.
local oldTicket = BattleCamera.Begin(CFrame.identity, a, b)
local newTicket = BattleCamera.Begin(CFrame.identity, a, b)
BattleCamera.Release(0, oldTicket)
check(world.CurrentCamera.CameraType == Enum.CameraType.Scriptable)
BattleCamera.Release(0, newTicket)
near(render:Count(), 0)
-- A new battle during an eased release keeps ownership after the old wait resumes.
Settings.reducedMotion = false
local oldOwner = BattleCamera.Begin(CFrame.identity, a, b)
local nextOwner = nil
onAdvance = function()
	nextOwner = BattleCamera.Begin(CFrame.identity, a, b)
	onAdvance = nil
end
BattleCamera.Release(0.5, oldOwner)
check(world.CurrentCamera.CameraType == Enum.CameraType.Scriptable, "new owner survives old release")
BattleCamera.Release(0, nextOwner)
near(render:Count(), 0)
-- Intro paths always disconnect skip input and run both cleanup functions.
mocks["ReplicatedStorage.Shared.Config"] = { Battle = { arenaRadius = 15 } }
local barsClosed, ringShown, flashes = 0, 0, 0
Common.Letterbox = function()
	return function()
		barsClosed += 1
	end
end
Common.RingReveal = function()
	return function()
		ringShown += 1
	end
end
Common.Desaturate = function()
	flashes += 1
end
Common.Reveal = function() end
Common.Countdown = function(sleep, punch, reduced)
	for _ = 1, 3 do
		punch()
		if sleep(0.1) then
			return true
		end
	end
	return false
end
Common.FightSlam = function()
	flashes += 1
end
local Intro = load("Client.Battle.BattleIntro")
Settings.reducedMotion = false
local abort = false
onAdvance = function()
	abort = true
	onAdvance = nil
end
BattleCamera.Begin(CFrame.identity, a, b)
check(not Intro.Play({
	centre = CFrame.identity,
	mine = a,
	foe = b,
	short = false,
	cancelled = function()
		return abort
	end,
}))
near(barsClosed, 1)
near(ringShown, 1)
near(services.UserInputService.InputBegan:Count(), 0)
BattleCamera.Release(0)
Settings.reducedMotion = true
local oldFlashes = flashes
BattleCamera.Begin(CFrame.identity, a, b)
check(Intro.Play({
	centre = CFrame.identity,
	mine = a,
	foe = b,
	short = false,
	cancelled = function()
		return false
	end,
}))
near(flashes, oldFlashes, "reduced motion creates no desaturation/flash")
near(services.UserInputService.InputBegan:Count(), 0)
BattleCamera.Release(0)
-- Retained capsule channels: no AnimationIds, explicit dropped scale, owned cleanup.
local originals = {}
for _, clip in capsuleFixture.clips do
	originals[clip.name] = clip
end
services.HttpService.JSONDecode = function(_, name)
	return originals[name]
end
mocks["ReplicatedStorage.Shared.Sfx"] = { Play = function() end }
local capsule = model(Vector3.new(1, 2, 1), Vector3.zero)
capsule.scale = capsuleFixture.studsPerMeter
capsule:SetAttribute("FaP_SourceAssetId", "82152145130743")
capsule:SetAttribute("FaP_SourceSHA256", "3f08246c02d7f763f128918a11b128172522762938da57f6b15f220fe2092808")
capsule:SetAttribute("FaP_OriginalLogicalJointsRestored", 5)
local data = Instance.new("Folder")
data.Name = "OriginalClipData"
data.Parent = capsule
local positions = {}
for _, joint in capsuleFixture.joints do
	positions[joint.name] = Vector3.new(table.unpack(joint.position))
end
local joints = {}
for _, joint in capsuleFixture.joints do
	local node = Instance.new("Motor6D")
	node.Name = joint.name
	node.C0 =
		CFrame.new((positions[joint.name] - (positions[joint.parent] or Vector3.zero)) * capsule:GetScale())
	node.Transform = CFrame.identity
	node.Parent = capsule
	joints[joint.name] = node
end
for _, clip in capsuleFixture.clips do
	local value = Instance.new("StringValue")
	value.Name = clip.name
	value.Value = clip.name
	value.Parent = data
end
local ClipPlayer = load("Client.Battle.CapsuleClipPlayer")
local player = ClipPlayer.Attach(capsule)
check(player ~= nil)
for _, name in { "Throw", "Close", "Open", "Shake", "Lock" } do
	check(player.Play(name))
	check(player.Duration(name) > 0)
	advance(player.Duration(name) + 0.1)
	near(render:Count(), 0)
end
check(capsule:GetAttribute("CapsuleScaleChannelsDropped") == true)
check(not player.Play("Missing"))
player.Play("Throw")
advance(0.3)
check(joints.jnt_root.Transform.Position.Y > 0, "source root translation applied relative to rest")
player.Destroy()
near(render:Count(), 0)
near(joints.jnt_root.Transform.Position.Y, 0)
local Sequence = load("Client.Battle.CapsuleSequence")
Sequence.SetTemplate(capsule)
a.PrimaryPart.LocalTransparencyModifier = 0.25
local warningCount = #warnings
Sequence.Play(Vector3.new(0, 4, 0), a, 3, false, function()
	return false
end)
near(#warnings, warningCount, "original capsule path runs without swallowed error")
near(a.PrimaryPart.LocalTransparencyModifier, 0.25, "escape restores exact original visibility")
near(render:Count(), 0, "all original clip callbacks removed")
Sequence.Play(Vector3.new(0, 4, 0), a, 3, true, function()
	return false
end)
near(#warnings, warningCount, "capture path runs without swallowed error")
near(a.PrimaryPart.LocalTransparencyModifier, 0.25, "capture does not leave an invisible owned pet")
local beforeClip = render:Count()
onAdvance = function()
	Sequence.CancelAll()
	onAdvance = nil
end
Sequence.Play(Vector3.new(0, 4, 0), a, 3, true, function()
	return false
end)
near(render:Count(), beforeClip, "capsule abort disconnects native playback")
near(a.PrimaryPart.LocalTransparencyModifier, 0.25)
local bad = model(Vector3.one, Vector3.zero)
check(not pcall(Sequence.SetTemplate, bad), "unreviewed templates refused")
-- The reviewed original is available even when the map placement streams out.
local replicated=Instance.new("Folder");local assets=Instance.new("Folder");assets.Name="Assets";assets.Parent=replicated
rawset(services.ReplicatedStorage,"FindFirstChild",function(_,name)return replicated:FindFirstChild(name)end)
services.ServerStorage=Instance.new("Folder")
local imports=Instance.new("Folder");imports.Name="MapV3Imports";imports.Parent=services.ServerStorage
capsule.Name="asset_82152145130743";capsule.Parent=imports
local package=Instance.new("PackageLink");package.Parent=capsule
local export=load("Server.Services.BattlePresentationService");export.Start()
local provided=assets:FindFirstChild("BattleCapsule");check(provided~=nil)
near(provided:GetScale(),capsule:GetScale(),"original capsule scale preserved")
check(provided:FindFirstChild("OriginalClipData")~=nil)
for _,item in provided:GetDescendants()do check(not item:IsA("PackageLink"),"detached package sanitized")end
local children=#assets:GetChildren();export.Start();near(#assets:GetChildren(),children,"no duplicate replicated template")
print(`PASS {checks} battle presentation assertions; real Luau modules, synthetic engine/persistence only`)
