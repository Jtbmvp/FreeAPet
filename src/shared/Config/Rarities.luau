--!strict
-- Prototype rarities only. Epic, Legendary and Mythic are added later by
-- appending entries here; nothing else should need to change.

export type RarityId = "Starter" | "Common" | "Uncommon" | "Rare"

export type Rarity = {
	id: RarityId,
	order: number,
	multiplier: number, -- PLACEHOLDER
	color: Color3, -- UI tint
}

local Rarities: { [RarityId]: Rarity } = {
	Starter = { id = "Starter", order = 0, multiplier = 1, color = Color3.fromRGB(255, 227, 107) },
	Common = {
		id = "Common",
		order = 1,
		multiplier = 1,
		color = Color3.fromRGB(200, 200, 200),
	},
	Uncommon = {
		id = "Uncommon",
		order = 2,
		multiplier = 1.5,
		color = Color3.fromRGB(90, 200, 90),
	},
	Rare = {
		id = "Rare",
		order = 3,
		multiplier = 2.5,
		color = Color3.fromRGB(70, 140, 255),
	},
}

return Rarities
