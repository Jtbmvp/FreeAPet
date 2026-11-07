--!strict
local Config = require(script.Parent.Config)
local ProgressionMath = require(script.Parent.ProgressionMath)

local AnimalMath = {}

function AnimalMath.StageFor(level: number)
	return ProgressionMath.Stage(level)
end

function AnimalMath.ScaleFor(level: number, legacyScaleFloor: number?): number
	return math.max(ProgressionMath.Scale(level), legacyScaleFloor or 0)
end

function AnimalMath.IncomeFactor(level: number, legacyIncomeFloor: number?): number
	return math.max(ProgressionMath.Stage(level).incomeFactor, legacyIncomeFloor or 0)
end

function AnimalMath.ValuePerSecond(
	speciesId: string,
	size: number,
	level: number,
	legacyIncomeFloor: number?
): number
	local species = Config.Species[speciesId]
	local biome = species.biome and Config.Biomes[species.biome]
	local rarity = Config.Rarities[species.rarity]
	return (if biome then biome.baseValue else 1)
		* rarity.multiplier
		* size
		* AnimalMath.IncomeFactor(level, legacyIncomeFloor)
end

return AnimalMath
