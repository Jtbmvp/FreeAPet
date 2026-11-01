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
	local map = workspace:WaitForChild("Map")
	for _, part in map:WaitForChild("Zones"):GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute("ZoneId") then
			table.insert(zoneParts, part)
		end
	end
	for _, plot in map:WaitForChild("Bases"):GetChildren() do
		local safe = plot:FindFirstChild("SafeZone")
		if safe and safe:IsA("BasePart") then
			table.insert(safeParts, safe)
		end
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
