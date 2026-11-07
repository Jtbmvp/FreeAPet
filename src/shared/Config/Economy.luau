--!strict
-- Cash income, individual size and display base capacity.
-- Value per second = biome.baseValue * rarity.multiplier * sizeFactor * stage.incomeFactor

local Economy = {
	startingCash = 0,
	incomeTickSeconds = 1,

	-- Individual size rolled at spawn. sizeFactor multiplies income and model scale.
	sizeMin = 0.8,
	sizeMax = 1.4,
	-- Rolls are skewed towards small: size = min + (max - min) * random^sizeSkew
	sizeSkew = 2,

	baseStartingSlots = 6, -- PLACEHOLDER
	offlineIncomePercent = 0.25, -- PLACEHOLDER, raised by research
	offlineIncomeMaxHours = 8, -- PLACEHOLDER: offline time beyond this earns nothing
}

return Economy
