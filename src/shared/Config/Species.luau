--!strict
-- Species are identical on every server. Individuals vary in size, growth
-- and (later) mutations. modelName points at a model under
-- ReplicatedStorage.Assets.Animals; until the real models arrive a
-- placeholder model is used, so swapping art never touches code.

local Rarities = require(script.Parent.Rarities)

export type Species = {
	id: string,
	displayName: string,
	displayNamePT: string,
	biome: string, -- key in Config.Biomes
	rarity: Rarities.RarityId,
	modelName: string,
	spawnWeight: number, -- PLACEHOLDER: relative chance inside its biome
	-- Adult height in studs at size 1 (the player is about 5). The art is
	-- normalised to this, so models can be exported at any scale. See
	-- docs/SCALE.md for the reference table.
	heightStuds: number,
}

local Species: { [string]: Species } = {
	AcornSquirrel = {
		id = "AcornSquirrel",
		displayName = "Acorn Squirrel",
		displayNamePT = "Esquilo Bolota",
		biome = "Forest",
		rarity = "Common",
		modelName = "AcornSquirrel",
		spawnWeight = 70,
		heightStuds = 4,
	},
	HoppingMushroom = {
		id = "HoppingMushroom",
		displayName = "Hopping Mushroom",
		displayNamePT = "Cogumelo Saltitão",
		biome = "Forest",
		rarity = "Uncommon",
		modelName = "HoppingMushroom",
		spawnWeight = 25,
		heightStuds = 4.5,
	},
	BranchDeer = {
		id = "BranchDeer",
		displayName = "Branch Deer",
		displayNamePT = "Veado Ramos",
		biome = "Forest",
		rarity = "Rare",
		modelName = "BranchDeer",
		spawnWeight = 5,
		heightStuds = 8,
	},
	RunningCactus = {
		id = "RunningCactus",
		displayName = "Running Cactus",
		displayNamePT = "Cacto Corredor",
		biome = "Desert",
		rarity = "Common",
		modelName = "RunningCactus",
		spawnWeight = 70,
		heightStuds = 5.5,
	},
	BallScorpion = {
		id = "BallScorpion",
		displayName = "Ball Scorpion",
		displayNamePT = "Escorpião Bolinha",
		biome = "Desert",
		rarity = "Uncommon",
		modelName = "BallScorpion",
		spawnWeight = 25,
		heightStuds = 3,
	},
	SunCamel = {
		id = "SunCamel",
		displayName = "Sun Camel",
		displayNamePT = "Camelo Sol",
		biome = "Desert",
		rarity = "Rare",
		modelName = "SunCamel",
		spawnWeight = 5,
		heightStuds = 9,
	},
}

return Species
