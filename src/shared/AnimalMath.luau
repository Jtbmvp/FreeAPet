--!strict
-- Formulas about an individual animal, shared by server and client UI.

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Config.Economy)

local AnimalMath = {}

function AnimalMath.StageFor(growth: number): Economy.GrowthStage
	local current = Config.Economy.growthStages[1]
	for _, stage in Config.Economy.growthStages do
		if growth >= stage.minProgress then
			current = stage
		end
	end
	return current
end

-- Visual scale for a growth value, interpolated between the stage scales
-- so a loose animal visibly grows a little every second.
function AnimalMath.ScaleFor(growth: number): number
	local stages = Config.Economy.growthStages
	for index = #stages, 2, -1 do
		local from, to = stages[index - 1], stages[index]
		if growth >= from.minProgress then
			local alpha = math.clamp((growth - from.minProgress) / (to.minProgress - from.minProgress), 0, 1)
			return from.scale + (to.scale - from.scale) * alpha
		end
	end
	return stages[1].scale
end

-- Value per second = biome base value × rarity multiplier × size × stage income factor
function AnimalMath.ValuePerSecond(speciesId: string, size: number, growth: number): number
	local species = Config.Species[speciesId]
	local biome = Config.Biomes[species.biome]
	local rarity = Config.Rarities[species.rarity]
	return biome.baseValue * rarity.multiplier * size * AnimalMath.StageFor(growth).incomeFactor
end

return AnimalMath
