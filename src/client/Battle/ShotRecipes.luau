--!strict
-- Pure shot recipes: BattleCamera remains the only writer/owner of the camera.
-- Capture once per pet/phase; never recompute a 122-mesh bbox every frame.
local Shots = {}
export type Bounds = { model: Model, localCentre: CFrame, size: Vector3 }
export type Shot = (number) -> (Vector3, Vector3, number)

function Shots.Capture(model: Model): Bounds
	local cf, size = model:GetBoundingBox()
	return { model = model, localCentre = model:GetPivot():ToObjectSpace(cf), size = size * 1.15 }
end

local function boundsFrame(bounds: Bounds): CFrame
	return bounds.model:GetPivot() * bounds.localCentre
end

local function corners(bounds: Bounds): { Vector3 }
	local cf = boundsFrame(bounds)
	local points = {}
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(points, cf * (bounds.size * Vector3.new(x, y, z) * 0.5))
			end
		end
	end
	return points
end

local function fit(
	focus: Vector3,
	away: Vector3,
	groups: { Bounds },
	aspect: number,
	fov: number
): (Vector3, Vector3, number)
	away = away.Unit
	local basis = CFrame.lookAt(focus + away * 10, focus)
	local tanV = math.tan(math.rad(fov * 0.5)) * 0.78 -- reserves HUD/letterbox margin
	local tanH = tanV * math.max(aspect, 0.35)
	local distance = 4
	for _, bounds in groups do
		for _, point in corners(bounds) do
			local offset = point - focus
			local depth = offset:Dot(basis.LookVector)
			distance = math.max(
				distance,
				math.abs(offset:Dot(basis.RightVector)) / tanH - depth,
				math.abs(offset:Dot(basis.UpVector)) / tanV - depth,
				1.5 - depth
			)
		end
	end
	return focus + away * (distance + 1), focus, fov
end

function Shots.TwoShot(arena: CFrame, mine: Bounds, foe: Bounds, aspect: number, reducedMotion: boolean): Shot
	return function(elapsed)
		local a, b = boundsFrame(mine).Position, boundsFrame(foe).Position
		local focus = a:Lerp(b, 0.54)
		-- Stay on one side of the fight axis; no 180-degree camera flip.
		local drift = if reducedMotion then 0 else math.min(elapsed, 0.6) * 0.025
		local away = arena:VectorToWorldSpace(Vector3.new(0.23 + drift, 0.27, 1))
		return fit(focus, away, { mine, foe }, aspect, 52)
	end
end

function Shots.Hero(
	arena: CFrame,
	pet: Bounds,
	facingFoe: boolean,
	aspect: number,
	reducedMotion: boolean
): Shot
	return function(elapsed)
		local focus = boundsFrame(pet).Position + Vector3.yAxis * pet.size.Y * 0.05
		local front = if facingFoe then arena.LookVector else -arena.LookVector
		local push = if reducedMotion then 0 else math.min(elapsed / 0.6, 1) * 0.04
		local away = (front * 0.9 + arena.RightVector * (0.38 - push) + Vector3.yAxis * 0.1).Unit
		return fit(focus, away, { pet }, aspect, 46)
	end
end

function Shots.Attack(
	arena: CFrame,
	attacker: Bounds,
	target: Bounds,
	aspect: number,
	reducedMotion: boolean
): Shot
	return function(elapsed)
		local a, b = boundsFrame(attacker).Position, boundsFrame(target).Position
		local focus = a:Lerp(b, 0.62)
		local push = if reducedMotion then 0 else math.min(elapsed / 0.25, 1) * 0.05
		local away = arena:VectorToWorldSpace(Vector3.new(0.38 - push, 0.2, 1))
		return fit(focus, away, { attacker, target }, aspect, 48)
	end
end

function Shots.CaptureCapsule(arena: CFrame, capsule: Bounds, pet: Bounds, aspect: number): Shot
	return function(_elapsed)
		local focus = boundsFrame(capsule).Position:Lerp(boundsFrame(pet).Position, 0.25)
		return fit(focus, arena:VectorToWorldSpace(Vector3.new(0.45, 0.23, 1)), { capsule, pet }, aspect, 48)
	end
end

return Shots
