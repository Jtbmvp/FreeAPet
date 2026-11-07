--!strict
local Config = require(script.Parent.Config)

local ProgressionMath = {}

function ProgressionMath.PlayerXpToNext(level: number): number
	local curve = Config.Progression.player
	return curve.base + curve.linear * (level - 1) + curve.quadratic * (level - 1) ^ 2
end

function ProgressionMath.PetXpToNext(level: number): number
	local curve = Config.Progression.pet
	return curve.base + curve.linear * level + curve.quadratic * (level - 1) ^ 2
end

function ProgressionMath.PlayerState(totalXp: number): (number, number, number)
	local level, xp = 1, totalXp
	while level < Config.Progression.player.maxLevel do
		local required = ProgressionMath.PlayerXpToNext(level)
		if xp < required then
			return level, xp, required
		end
		xp -= required
		level += 1
	end
	return level, xp, 0
end

function ProgressionMath.PlayerCapXp(): number
	local total = 0
	for level = 1, Config.Progression.player.maxLevel - 1 do
		total += ProgressionMath.PlayerXpToNext(level)
	end
	return total
end

function ProgressionMath.ResearchLevel(nodeId: string, rank: number): number
	local gate = Config.Progression.researchRanks[nodeId]
	return if gate then gate.first + gate.step * (rank - 1) else math.huge
end

function ProgressionMath.Stage(level: number)
	local current = Config.Progression.pet.stages[1]
	for _, stage in Config.Progression.pet.stages do
		if level >= stage.level then
			current = stage
		end
	end
	return current
end

-- Adult clamps appearance; combat levels continue afterwards.
function ProgressionMath.Scale(level: number): number
	local stages = Config.Progression.pet.stages
	for i = #stages, 2, -1 do
		local from, to = stages[i - 1], stages[i]
		if level >= from.level then
			local alpha = math.clamp((level - from.level) / (to.level - from.level), 0, 1)
			return from.scale + (to.scale - from.scale) * alpha
		end
	end
	return stages[1].scale
end

return ProgressionMath
