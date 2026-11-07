--!strict
-- Biomes in a straight line from the base. Order = distance = value.
-- Every number marked PLACEHOLDER is tuned by testing.

export type Biome = {
	id: string,
	displayName: string,
	order: number, -- 1 = closest to the base
	baseValue: number, -- PLACEHOLDER: cash/sec base before multipliers
}

local Biomes: { [string]: Biome } = {
	Forest = {
		id = "Forest",
		displayName = "Forest",
		order = 1,
		baseValue = 1, -- PLACEHOLDER
	},
	Desert = {
		id = "Desert",
		displayName = "Desert",
		order = 2,
		baseValue = 3, -- PLACEHOLDER
	},
}

return Biomes
