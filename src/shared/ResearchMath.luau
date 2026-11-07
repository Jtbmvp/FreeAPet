--!strict
-- Reading the research tree from saved progress. Shared so the server
-- (effects, offline income) and the client (research panel) agree.
-- A research whose timer has run out counts as done, even before the server
-- has written it down (e.g. it finished while the player was offline).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type Progress = { [string]: Types.ResearchProgress }

local ResearchMath = {}

-- Axial offsets of the six neighbours of a pointy-top hexagon.
local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, -1 }, { -1, 1 } }

-- Completed level of a node (0 = not researched).
function ResearchMath.LevelOf(progress: Progress, nodeId: string, now: number): number
	local entry = progress[nodeId]
	if not entry then
		return 0
	end
	if entry.activeLevel and entry.finishesAt and entry.finishesAt <= now then
		return entry.activeLevel
	end
	return entry.level
end

-- Value of an effect from the researched levels, or `default` when no node
-- with that effect has been researched.
function ResearchMath.Value(progress: Progress, effect: string, default: number, now: number): number
	for id, node in Config.Research do
		if node.effect == effect then
			local level = ResearchMath.LevelOf(progress, id, now)
			if level > 0 and node.levels[level] then
				return node.levels[level].value
			end
		end
	end
	return default
end

-- The node being researched, if any (not yet finished).
function ResearchMath.Active(progress: Progress, now: number): (string?, number?)
	for id, entry in progress do
		if Config.Research[id] and entry.activeLevel and entry.finishesAt and entry.finishesAt > now then
			return id, entry.finishesAt
		end
	end
	return nil, nil
end

-- Node ids next to a node on the hexagon grid.
function ResearchMath.Neighbours(nodeId: string): { string }
	local hex = Config.Research[nodeId].hex
	local result = {}
	for id, other in Config.Research do
		for _, offset in NEIGHBOURS do
			if other.hex[1] == hex[1] + offset[1] and other.hex[2] == hex[2] + offset[2] then
				table.insert(result, id)
			end
		end
	end
	return result
end

-- Root nodes are always open; others once a neighbour has a level (a node
-- that already has levels, e.g. from an older tree layout, stays open).
function ResearchMath.IsUnlocked(progress: Progress, nodeId: string, now: number): boolean
	if Config.Research[nodeId].root or ResearchMath.LevelOf(progress, nodeId, now) > 0 then
		return true
	end
	for _, id in ResearchMath.Neighbours(nodeId) do
		if ResearchMath.LevelOf(progress, id, now) > 0 then
			return true
		end
	end
	return false
end

-- Research time of a level after the Accelerator.
function ResearchMath.Duration(progress: Progress, nodeId: string, level: number, now: number): number
	local base = Config.Research[nodeId].levels[level].durationSeconds
	return math.ceil(base * ResearchMath.Value(progress, "researchTimeMultiplier", 1, now))
end

local function percent(value: number): string
	return `{math.round(value * 100)}%`
end

-- What a node gives at a level (0 = the starting value), for the panel.
function ResearchMath.Describe(nodeId: string, level: number): string
	local node = Config.Research[nodeId]
	local effect = node.effect
	local value = if level > 0 then node.levels[level].value else nil
	if effect == "incomeMultiplier" then
		return `+{percent((value or 1) - 1)} base income`
	elseif effect == "offlineIncomePercent" then
		return `{percent(value or Config.Economy.offlineIncomePercent)} income offline`
	elseif effect == "carryCapacity" then
		local n = value or Config.Gameplay.carry.startingCapacity
		return if n == 1 then "Carry 1 pet" else `Carry {n} pets`
	elseif effect == "walkSpeed" then
		local speed = string.format("%.1f", value or Config.Gameplay.player.walkSpeed):gsub("%.0$", "")
		return `Speed {speed}`
	elseif effect == "researchTimeMultiplier" then
		return `-{percent(1 - (value or 1))} research time`
	end
	return ""
end

return ResearchMath
