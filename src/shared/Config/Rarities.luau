--!strict
-- Prototype rarities only. Epic, Legendary and Mythic are added later by
-- appending entries here; nothing else should need to change.

export type RarityId = "Common" | "Uncommon" | "Rare"

export type Rarity = {
	id: RarityId,
	order: number,
	multiplier: number, -- PLACEHOLDER
	timeToAdultSeconds: number, -- PLACEHOLDER: loose time from baby to adult
	color: Color3, -- UI tint
}

local Rarities: { [RarityId]: Rarity } = {
	Common = {
		id = "Common",
		order = 1,
		multiplier = 1,
		timeToAdultSeconds = 3 * 60,
		color = Color3.fromRGB(200, 200, 200),
	},
	Uncommon = {
		id = "Uncommon",
		order = 2,
		multiplier = 1.5,
		timeToAdultSeconds = 6 * 60,
		color = Color3.fromRGB(90, 200, 90),
	},
	Rare = {
		id = "Rare",
		order = 3,
		multiplier = 2.5,
		timeToAdultSeconds = 13 * 60,
		color = Color3.fromRGB(70, 140, 255),
	},
}

return Rarities
