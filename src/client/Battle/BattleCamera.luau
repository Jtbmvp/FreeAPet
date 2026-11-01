--!strict
-- Battle camera (client only). Scripted shots around the arena: a wide
-- establishing view, a hero shot of each pet from the front, and the
-- over-the-shoulder gameplay view behind the player (spots in
-- Config.Battle.layout). A shot is a function of time, so it follows its
-- pets every frame; Move blends from wherever the camera is into a new shot.
-- Shots are pulled in when a tree or rock blocks them (rays against
-- Map.Collision: the visible map is merged per material and can't tell one
-- tree from another). Shake and FOV punches are added on top.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local BattleSettings = require(script.Parent.BattleSettings)

export type Shot = (elapsed: number) -> (Vector3, Vector3, number) -- eye, focus, field of view

local BattleCamera = {}

local LAYOUT = Config.Battle.layout
local SHAKES = {
	light = { time = 0.15, amount = 0.15, roll = 0 },
	medium = { time = 0.25, amount = 0.35, roll = 0.5 },
	heavy = { time = 0.4, amount = 0.7, roll = 2 },
}

local camera = Workspace.CurrentCamera
local connection: RBXScriptConnection? = nil
local session = 0 -- bumped by Begin so an old Release can't end a new battle
local savedFov = 70

local centre = CFrame.identity
local mine: Model? = nil
local foe: Model? = nil

local shot: Shot? = nil
local shotStart = 0
local blendTime = 0.001
local easing = Enum.EasingStyle.Sine
local fromCFrame = CFrame.identity
local fromFov = 70

local shakeUntil, shakeTime, shakeAmount, shakeRoll = 0, 1, 0, 0
local punchUntil, punchTime, punchFov = 0, 1, 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function heightOf(model: Model?): number
	return if model and model.Parent then model:GetExtentsSize().Y else 4
end

-- A pet's feet and the way it faces.
local function standOf(model: Model?): (Vector3, Vector3)
	if model and model.Parent then
		local pivot = model:GetPivot()
		return pivot.Position - Vector3.new(0, model:GetExtentsSize().Y / 2, 0), pivot.LookVector
	end
	return centre.Position, centre.LookVector
end

-- Pulls the eye in front of the first tall collision part between it and
-- the focus. Grass and low bushes (under 3 studs) don't count.
local function unblock(eye: Vector3, focus: Vector3): Vector3
	local offset = eye - focus
	local length = offset.Magnitude
	if length < 0.5 then
		return eye
	end
	local direction = offset / length
	local from, travelled = focus, 0
	for _ = 1, 4 do
		local hit = Workspace:Raycast(from, direction * (length - travelled), rayParams)
		if not hit then
			return eye
		end
		local part = hit.Instance :: BasePart
		travelled += (hit.Position - from).Magnitude
		if part.Size.Y >= 3 then
			return focus + direction * math.max(travelled - 1.2, 2)
		end
		from = hit.Position + direction * 0.1
		travelled += 0.1
	end
	return eye
end

local function step()
	local current = shot
	if not current then
		return
	end
	local now = os.clock()
	local elapsed = now - shotStart
	local eye, focus, fov = current(elapsed)
	eye = unblock(eye, focus)
	local alpha =
		TweenService:GetValue(math.clamp(elapsed / blendTime, 0, 1), easing, Enum.EasingDirection.InOut)
	local cframe = fromCFrame:Lerp(CFrame.lookAt(eye, focus), alpha)
	local fieldOfView = fromFov + (fov - fromFov) * alpha
	if now < shakeUntil and BattleSettings.cameraShake then
		local k = ((shakeUntil - now) / shakeTime) ^ 2
		local n = now * 28
		cframe *= CFrame.new(math.noise(n, 1.3) * shakeAmount * k, math.noise(n, 7.1) * shakeAmount * k, 0) * CFrame.Angles(
			0,
			0,
			math.rad(math.noise(n, 3.7) * shakeRoll * k)
		)
	end
	if now < punchUntil then
		fieldOfView += punchFov * math.sin((punchUntil - now) / punchTime * math.pi)
	end
	camera.CFrame = cframe
	camera.FieldOfView = fieldOfView
end

-- Takes the camera for a battle. `arenaCentre` looks from our side at the foe.
function BattleCamera.Begin(arenaCentre: CFrame, minePet: Model?, foePet: Model?)
	session += 1
	centre, mine, foe = arenaCentre, minePet, foePet
	local map = Workspace:FindFirstChild("Map")
	local collision = map and map:FindFirstChild("Collision")
	rayParams.FilterDescendantsInstances = if collision then { collision } else {}
	if not connection then
		savedFov = camera.FieldOfView
		connection = RunService.PreRender:Connect(step)
	end
	camera.CameraType = Enum.CameraType.Scriptable
	fromCFrame, fromFov = camera.CFrame, camera.FieldOfView
end

function BattleCamera.SetPets(minePet: Model?, foePet: Model?)
	mine, foe = minePet, foePet
end

-- Blends from the current view into `newShot` over `seconds`.
function BattleCamera.Move(newShot: Shot, seconds: number, style: Enum.EasingStyle?)
	fromCFrame, fromFov = camera.CFrame, camera.FieldOfView
	shot = newShot
	shotStart = os.clock()
	blendTime = math.max(seconds, 0.001)
	easing = style or Enum.EasingStyle.Sine
end

function BattleCamera.Shake(tier: string)
	local settings = SHAKES[tier] or SHAKES.light
	shakeTime, shakeAmount, shakeRoll = settings.time, settings.amount, settings.roll
	shakeUntil = os.clock() + settings.time
end

-- A quick field-of-view dip and back (negative = zoom in).
function BattleCamera.Punch(fovDelta: number, seconds: number)
	punchFov, punchTime = fovDelta, seconds
	punchUntil = os.clock() + seconds
end

-- High side view of the whole arena, slowly orbiting.
function BattleCamera.Wide(): Shot
	return function(t)
		local orbit = centre * CFrame.Angles(0, math.rad(62 + 5 * t), 0)
		return (orbit * CFrame.new(0, 10, 26)).Position, centre.Position + Vector3.new(0, 2, 0), 60
	end
end

-- From the front of a pet, low and a little to one side (`side` 1 = its
-- right, -1 = its left), pushing in slowly.
function BattleCamera.Hero(model: Model?, side: number): Shot
	return function(t)
		local feet, look = standOf(model)
		local h = heightOf(model)
		local right = look:Cross(Vector3.yAxis)
		local distance = (1.4 * h + 4) * (1.15 - 0.15 * math.min(t / 1.3, 1))
		local eye = feet + look * distance + right * (side * 0.3 * distance) + Vector3.new(0, 0.4 * h, 0)
		return eye, feet + Vector3.new(0, 0.6 * h, 0), 45
	end
end

-- Over the player's right shoulder at our pet and the foe. Bigger pets push
-- the camera up and back so both fit.
function BattleCamera.Gameplay(): Shot
	return function()
		local big = math.max(heightOf(mine), heightOf(foe) * 0.8, 4) - 4
		local eye = centre * CFrame.new(LAYOUT.camera + Vector3.new(0.1 * big, 0.85 * big, 0.9 * big))
		local focus = centre * CFrame.new(0, 0.35 * heightOf(foe) + 1, -2.5)
		return eye.Position, focus.Position, 48
	end
end

-- Starts above and behind the gameplay view and closes in on it (countdown).
function BattleCamera.Approach(seconds: number): Shot
	local final = BattleCamera.Gameplay()
	return function(t)
		local eye, focus, fov = final(t)
		local k = 1 - math.min(t / seconds, 1)
		local back = (eye - focus).Unit
		return eye + back * 7 * k + Vector3.new(0, 3 * k, 0), focus, fov + 8 * k
	end
end

-- Gives the camera back to the player, easing to behind their character.
function BattleCamera.Release(seconds: number)
	local mySession = session
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and seconds > 0 and connection then
		local behind = root.CFrame * CFrame.new(0, 4, 11)
		BattleCamera.Move(function()
			return behind.Position, root.Position + Vector3.new(0, 2, 0), savedFov
		end, seconds)
		task.wait(seconds)
		if session ~= mySession then
			return -- a new battle took the camera meanwhile
		end
	end
	if connection then
		connection:Disconnect()
		connection = nil
	end
	shot = nil
	camera.FieldOfView = savedFov
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

return BattleCamera
