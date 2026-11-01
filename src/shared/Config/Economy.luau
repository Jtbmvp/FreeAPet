--!strict
-- Income, growth and base numbers. All PLACEHOLDER until tested.
-- Value per second = biome.baseValue * rarity.multiplier * sizeFactor * stage.incomeFactor

export type GrowthStage = {
	id: "Baby" | "Juvenile" | "Adult",
	minProgress: number, -- 0..1 growth progress where this stage starts
	incomeFactor: number,
	scale: number, -- visual scale of the model
}

local Economy = {
	startingCash = 0,
	incomeTickSeconds = 1,

	-- Growth happens only while loose. Progress 0..1, capped at adult.
	growthStages = {
		{ id = "Baby", minProgress = 0, incomeFactor = 0.25, scale = 0.75 },
		{ id = "Juvenile", minProgress = 0.4, incomeFactor = 0.6, scale = 0.88 },
		{ id = "Adult", minProgress = 1, incomeFactor = 1, scale = 1 },
	} :: { GrowthStage },

	-- Loose pets grow at full speed in their home biome and slower anywhere
	-- else (concept v2: released by hand wherever the owner wants).
	growthBiomeFactor = {
		home = 1,
		other = 0.4, -- PLACEHOLDER
	},

	-- Individual size rolled at spawn. sizeFactor multiplies income and model scale.
	sizeMin = 0.8,
	sizeMax = 1.4,
	-- Rolls are skewed towards small: size = min + (max - min) * random^sizeSkew
	sizeSkew = 2,

	maxLooseAnimals = 2, -- PLACEHOLDER (OPEN #3)
	baseStartingSlots = 6, -- PLACEHOLDER
	offlineIncomePercent = 0.25, -- PLACEHOLDER, raised by research
	offlineIncomeMaxHours = 8, -- PLACEHOLDER: offline time beyond this earns nothing
}

return Economy
