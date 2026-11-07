--!strict
-- Tracks where each player is and publishes it as player attributes:
--   Zone        "Base" | "Forest" | "Desert" | "None"
--   InSafeZone  inside any base plot (no stealing there)
--   InOwnBase   inside the player's own plot
-- Zone volumes come from Workspace.Map.Zones and plot SafeZone parts.

local Players = game:GetService("Players")

local BaseService = require(script.Parent.BaseService)

local ZoneService = {}

local UPDATE_SECONDS = 0.25
local SAFE_ZONE_CLEARANCE = 0.25

local zoneParts: { BasePart } = {}
local safeParts: { BasePart } = {}

local function isInside(part: BasePart, point: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

-- Zone id at a point ("Base", "Forest", "Desert"...) or "None".
function ZoneService.ZoneAt(position: Vector3): string
	for _, part in zoneParts do
		if isInside(part, position) then
			return part:GetAttribute("ZoneId") :: string
		end
	end
	return "None"
end

-- Inside any base plot.
function ZoneService.InAnyBase(position: Vector3): boolean
	for _, part in safeParts do
		if isInside(part, position) then
			return true
		end
	end
	return false
end

local function circleSeparation(part: BasePart, position: Vector3, radius: number): Vector3?
	local localPoint = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	local closestX = math.clamp(localPoint.X, -half.X, half.X)
	local closestZ = math.clamp(localPoint.Z, -half.Z, half.Z)
	local offset = Vector2.new(localPoint.X - closestX, localPoint.Z - closestZ)
	local distance = offset.Magnitude
	if distance >= radius + SAFE_ZONE_CLEARANCE then
		return nil
	end

	local push: Vector2
	if distance > 0.001 then
		push = offset.Unit * (radius + SAFE_ZONE_CLEARANCE - distance)
	else
		-- The centre is inside the SafeZone footprint; leave by the nearest side.
		local exits = {
			{ distance = half.X - localPoint.X, direction = Vector2.new(1, 0) },
			{ distance = half.X + localPoint.X, direction = Vector2.new(-1, 0) },
			{ distance = half.Z - localPoint.Z, direction = Vector2.new(0, 1) },
			{ distance = half.Z + localPoint.Z, direction = Vector2.new(0, -1) },
		}
		local nearest = exits[1]
		for _, exit in exits do
			if exit.distance < nearest.distance then
				nearest = exit
			end
		end
		push = nearest.direction * (nearest.distance + radius + SAFE_ZONE_CLEARANCE)
	end

	local worldPush = part.CFrame:VectorToWorldSpace(Vector3.new(push.X, 0, push.Y))
	return Vector3.new(worldPush.X, 0, worldPush.Z)
end

-- Finds a nearby centre whose full battle footprint clears every plot.
-- Returns nil when the footprint cannot be moved out within maxShift studs.
function ZoneService.FindArenaCenter(position: Vector3, radius: number, maxShift: number): Vector3?
	local origin = Vector3.new(position.X, 0, position.Z)
	local candidate = origin
	local maxIterations = #safeParts * 8 + 8
	for _ = 1, maxIterations do
		local moved = false
		for _, part in safeParts do
			local push = circleSeparation(part, candidate, radius)
			if push then
				candidate += push
				if (candidate - origin).Magnitude > maxShift then
					return nil
				end
				moved = true
				break
			end
		end
		if not moved then
			return Vector3.new(candidate.X, position.Y, candidate.Z)
		end
	end
	return nil
end

local function update(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local position = root.Position

	local zone = ZoneService.ZoneAt(position)

	local inSafe = false
	local inOwn = false
	local ownPlot = BaseService.GetPlot(player)
	for _, part in safeParts do
		if isInside(part, position) then
			inSafe = true
			inOwn = ownPlot ~= nil and part:IsDescendantOf(ownPlot)
			break
		end
	end

	if player:GetAttribute("Zone") ~= zone then
		player:SetAttribute("Zone", zone)
	end
	if player:GetAttribute("InSafeZone") ~= inSafe then
		player:SetAttribute("InSafeZone", inSafe)
	end
	if player:GetAttribute("InOwnBase") ~= inOwn then
		player:SetAttribute("InOwnBase", inOwn)
	end
end

function ZoneService.Start()
	-- Timeouts so a missing map piece warns instead of stalling every later service.
	local map = workspace:WaitForChild("Map", 10)
	local zones = map and map:WaitForChild("Zones", 5)
	local bases = map and map:WaitForChild("Bases", 5)
	if zones then
		for _, part in zones:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("ZoneId") then
				table.insert(zoneParts, part)
			end
		end
	else
		warn("[ZoneService] Workspace.Map.Zones not found: every player is in zone None")
	end
	if bases then
		for _, plot in bases:GetChildren() do
			local safe = plot:FindFirstChild("SafeZone")
			if safe and safe:IsA("BasePart") then
				table.insert(safeParts, safe)
			end
		end
	else
		warn("[ZoneService] Workspace.Map.Bases not found: no safe zones")
	end

	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				update(player)
			end
			task.wait(UPDATE_SECONDS)
		end
	end)
end

return ZoneService
