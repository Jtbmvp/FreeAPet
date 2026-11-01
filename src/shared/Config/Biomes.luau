--!strict
-- Biomes in a straight line from the base. Order = distance = value.
-- Every number marked PLACEHOLDER is tuned by testing.

export type HazardId = "LowVisibility" | "Heat"

export type Biome = {
	id: string,
	displayName: string,
	order: number, -- 1 = closest to the base
	baseValue: number, -- PLACEHOLDER: cash/sec base before multipliers
	hazard: HazardId,
}

local Biomes: { [string]: Biome } = {
	Forest = {
		id = "Forest",
		displayName = "Forest",
		order = 1,
		baseValue = 1, -- PLACEHOLDER
		hazard = "LowVisibility",
	},
	Desert = {
		id = "Desert",
		displayName = "Desert",
		order = 2,
		baseValue = 3, -- PLACEHOLDER
		hazard = "Heat",
	},
}

return Biomes
