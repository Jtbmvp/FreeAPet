--!strict
-- Sole camera writer. Recipes frame actual bounds, cache per phase and keep the
-- fight axis; lifecycle restores every camera we temporarily take over.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Settings = require(script.Parent.BattleSettings)
local Shots = require(script.Parent.ShotRecipes)
export type Shot = Shots.Shot
local Camera = {}
type Saved = { kind: Enum.CameraType, subject: Instance?, fov: number, focus: CFrame, cframe: CFrame }
local saved: { [Camera]: Saved } = {}
local camera: Camera? = nil
local render: RBXScriptConnection? = nil
local replacement: RBXScriptConnection? = nil
local session = 0
local centre = CFrame.identity
local mine: Model? = nil
local foe: Model? = nil
local bounds: { [Model]: Shots.Bounds } = {}
local shot: Shot? = nil
local shotStart, blendTime = 0, 0.001
local easing = Enum.EasingStyle.Sine
local fromCFrame, fromFov = CFrame.identity, 70
local shakeUntil, shakeTime, shakeAmount = 0, 1, 0
local punchUntil, punchTime, punchFov = 0, 1, 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.RespectCanCollide = true
local function capture(model: Model?): Shots.Bounds?
	if not model or not model.Parent then
		return nil
	end
	if not bounds[model] then
		bounds[model] = Shots.Capture(model)
	end
	return bounds[model]
end
local function restore(target: Camera, state: Saved)
	pcall(function()
		target.CameraType = state.kind
		local subject = state.subject
		if subject and not subject.Parent then
			local character = Players.LocalPlayer.Character
			subject = character and character:FindFirstChildOfClass("Humanoid")
		end
		target.CameraSubject = subject
		target.FieldOfView = state.fov
		target.Focus, target.CFrame = state.focus, state.cframe
	end)
end
local function take(target: Camera?)
	if camera and saved[camera] then
		restore(camera, saved[camera])
	end
	camera = target
	if not target then
		return
	end
	if not saved[target] then
		saved[target] = {
			kind = target.CameraType,
			subject = target.CameraSubject,
			fov = target.FieldOfView,
			focus = target.Focus,
			cframe = target.CFrame,
		}
	end
	fromCFrame, fromFov = target.CFrame, target.FieldOfView
	target.CameraType = Enum.CameraType.Scriptable
end
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
		travelled += (hit.Position - from).Magnitude
		if
			hit.Instance == Workspace.Terrain or (hit.Instance:IsA("BasePart") and hit.Instance.Size.Y >= 3)
		then
			return focus + direction * math.max(travelled - 1.2, 2)
		end
		from = hit.Position + direction * 0.1
		travelled += 0.1
	end
	return eye
end
local function step()
	if (mine and not mine.Parent) or (foe and not foe.Parent) then
		Camera.Release(0)
		return
	end
	if not camera or not shot then
		return
	end
	local now = os.clock()
	local elapsed = now - shotStart
	local eye, focus, fov = shot(elapsed)
	eye = unblock(eye, focus)
	local alpha =
		TweenService:GetValue(math.clamp(elapsed / blendTime, 0, 1), easing, Enum.EasingDirection.InOut)
	local pose = fromCFrame:Lerp(CFrame.lookAt(eye, focus), alpha)
	local field = fromFov + (fov - fromFov) * alpha
	if not Settings.reducedMotion then
		if now < shakeUntil and Settings.cameraShake then
			local weight = ((shakeUntil - now) / shakeTime) ^ 2
			pose *= CFrame.new(
				math.noise(now * 28, 1.3) * shakeAmount * weight,
				math.noise(now * 28, 7.1) * shakeAmount * weight,
				0
			)
		end
		if now < punchUntil then
			field += punchFov * math.sin((punchUntil - now) / punchTime * math.pi)
		end
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame, camera.Focus, camera.FieldOfView = pose, CFrame.new(focus), field
end
function Camera.Begin(arena: CFrame, minePet: Model?, foePet: Model?)
	session += 1
	centre = arena
	mine, foe = minePet, foePet
	table.clear(bounds)
	shot = nil
	local map = Workspace:FindFirstChild("Map")
	local collision = map and map:FindFirstChild("Collision")
	rayParams.FilterDescendantsInstances = if collision
		then { collision, Workspace.Terrain }
		else { Workspace.Terrain }
	if not render then
		take(Workspace.CurrentCamera)
		render = RunService.PreRender:Connect(step)
		replacement = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			take(Workspace.CurrentCamera)
		end)
	end
	return session
end
function Camera.Forget(model: Model)
	bounds[model] = nil
end
function Camera.SetPets(a: Model?, b: Model?)
	mine, foe = a, b
	table.clear(bounds)
	if render then
		Camera.Move(Camera.Gameplay(), 0.25)
	end
end
function Camera.Move(nextShot: Shot, seconds: number, style: Enum.EasingStyle?)
	if not render or not camera then
		return
	end
	fromCFrame, fromFov = camera.CFrame, camera.FieldOfView
	shot = nextShot
	shotStart = os.clock()
	blendTime = if Settings.reducedMotion then 0.001 else math.max(seconds, 0.001)
	easing = style or Enum.EasingStyle.Sine
end
local function aspectShot(factory: (number) -> Shot): Shot
	local aspect, recipe = -1, nil :: Shot?
	return function(elapsed)
		local view = if camera then camera.ViewportSize else Vector2.new(16, 9)
		local current = view.X / math.max(view.Y, 1)
		if not recipe or current ~= aspect then
			aspect = current
			recipe = factory(aspect)
		end
		return (recipe :: Shot)(elapsed)
	end
end
local function fallback(): Shot
	return function()
		return (centre * CFrame.new(0, 8, 22)).Position, centre.Position + Vector3.yAxis * 2, 52
	end
end
function Camera.Gameplay(): Shot
	local a, b = capture(mine), capture(foe)
	if not a or not b then
		return fallback()
	end
	return aspectShot(function(aspect)
		return Shots.TwoShot(centre, a, b, aspect, true)
	end)
end
function Camera.Wide(): Shot
	local a, b = capture(mine), capture(foe)
	if not a or not b then
		return fallback()
	end
	return aspectShot(function(aspect)
		return Shots.TwoShot(centre, a, b, aspect, Settings.reducedMotion)
	end)
end
function Camera.Hero(model: Model?, _side: number): Shot
	local pet = capture(model)
	if not pet then
		return fallback()
	end
	return aspectShot(function(aspect)
		return Shots.Hero(centre, pet, model == mine, aspect, Settings.reducedMotion)
	end)
end
function Camera.Approach(_seconds: number): Shot
	return Camera.Gameplay() -- fitted view, no uncontrolled orbit across the fight axis
end
function Camera.Attack(attacker: Model?, target: Model?): Shot
	local a, b = capture(attacker), capture(target)
	if not a or not b then
		return Camera.Gameplay()
	end
	return aspectShot(function(aspect)
		return Shots.Attack(centre, a, b, aspect, Settings.reducedMotion)
	end)
end
function Camera.CaptureCapsule(capsule: Model?, target: Model?): Shot
	local a, b = capture(capsule), capture(target)
	if not a or not b then
		return Camera.Gameplay()
	end
	return aspectShot(function(aspect)
		return Shots.CaptureCapsule(centre, a, b, aspect)
	end)
end
function Camera.OnBeat(phase: string, context: any, _recipe: any)
	if not render or Settings.reducedMotion or (context.cancelled and context.cancelled()) then
		return
	end
	if phase == "anticipation" then
		Camera.Move(Camera.Attack(context.attacker, context.target), 0.2)
	elseif phase == "recovery" then
		Camera.Move(Camera.Gameplay(), 0.25)
	end
end
function Camera.Shake(tier: string)
	if not render or Settings.reducedMotion or not Settings.cameraShake then
		return
	end
	local strength = if tier == "heavy" then 0.45 elseif tier == "medium" then 0.25 else 0.12
	shakeTime, shakeAmount = 0.2, strength
	shakeUntil = os.clock() + shakeTime
end
function Camera.Punch(delta: number, seconds: number)
	if not render or Settings.reducedMotion or not Settings.cameraShake then
		return
	end
	punchFov, punchTime = delta, math.max(seconds, 0.001)
	punchUntil = os.clock() + seconds
end
function Camera.Release(seconds: number, expectedSession: number?)
	if expectedSession and expectedSession ~= session then
		return
	end
	local mySession = session
	local root = Players.LocalPlayer.Character
		and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and seconds > 0 and render and not Settings.reducedMotion then
		local behind = root.CFrame * CFrame.new(0, 4, 11)
		Camera.Move(function()
			return behind.Position,
				root.Position + Vector3.yAxis * 2,
				if camera and saved[camera] then saved[camera].fov else 70
		end, seconds)
		task.wait(seconds)
	end
	if mySession ~= session then
		return
	end
	if render then
		render:Disconnect()
		render = nil
	end
	if replacement then
		replacement:Disconnect()
		replacement = nil
	end
	for target, state in saved do
		restore(target, state)
	end
	table.clear(saved)
	table.clear(bounds)
	shot = nil
	camera = nil
	shakeUntil, punchUntil = 0, 0
end
return Camera
