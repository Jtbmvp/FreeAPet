--!strict
-- Exposure meter per biome hazard. 0..100; at 100 the player is expelled.
-- Rates are % per second. Protection comes from research: a multiplier on
-- the rise (player attribute Protection_<HazardId>, 1 = none).

local Exposure = {
	maxValue = 100,
	warningAt = 75, -- color + sound + alert from here
	decayPerSecondOutside = 10, -- recovers when back in the base or a safe area

	hazards = {
		Heat = {
			risePerSecond = 1.5, -- PLACEHOLDER: ~67 s unprotected
		},
		LowVisibility = {
			-- OPEN #7 decided: slower rise plus fog (client only) that gets
			-- thicker as the meter rises, at its thickest from fullAt.
			risePerSecond = 0.8, -- PLACEHOLDER: ~125 s unprotected
			fog = {
				maxDensity = 0.78, -- Atmosphere.Density at full fog
				maxHaze = 2.5,
				fullAt = 75, -- meter % where the fog is thickest
				color = Color3.fromRGB(70, 90, 75),
			},
		},
	},

	-- Brief: wrong protection gives a different penalty. There is only one
	-- protection per hazard so far; revisit with protection items in M6.
	expelLosesTripResources = true, -- no trip resources exist yet (materials come later)
}

return Exposure
