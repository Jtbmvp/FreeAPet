--!strict
-- Wild battles (docs/BATTLES.md, approved 2026-10-27). All numbers PLACEHOLDER.
-- Off in the published game until the starters' art exists; on in Studio for
-- testing while Debug is on (see BattleMath.Enabled).

export type MoveType = "Forest" | "Desert" | "Neutral"

export type Move = {
	name: string,
	type: MoveType,
	power: number,
	uses: number?, -- per battle; nil = unlimited
}

export type SpeciesBattle = {
	type: MoveType,
	hp: number, -- base stats at level 1
	attack: number,
	defense: number,
	speed: number,
	moves: { Move }, -- exactly 4
}

local TACKLE: Move = { name = "Tackle", type = "Neutral", power = 40 }

local function moves(signature: string, typeMove: string, strong: string, moveType: MoveType): { Move }
	return {
		TACKLE,
		{ name = signature, type = "Neutral", power = 55, uses = 15 },
		{ name = typeMove, type = moveType, power = 50 },
		{ name = strong, type = moveType, power = 85, uses = 5 },
	}
end

local Battle = {
	enabled = false, -- published game: waits for the starters (decision 3)

	maxLevel = 30,
	statGrowthPerLevel = 0.1, -- stat = base * (1 + 0.1 * (level - 1))
	damageScale = 0.4, -- damage = power * attack / defense * 0.4 * type * random
	damageRandomMin = 0.85,

	-- Attack type -> defender type -> multiplier (missing = 1).
	typeChart = {
		Forest = { Forest = 0.67, Desert = 1.5 },
		Desert = { Forest = 1.5, Desert = 0.67 },
	} :: { [string]: { [string]: number } },

	-- Wild levels by biome and rarity: { min, max }.
	wildLevels = {
		Forest = { Common = { 1, 4 }, Uncommon = { 3, 6 }, Rare = { 6, 10 } },
		Desert = { Common = { 5, 8 }, Uncommon = { 7, 10 }, Rare = { 10, 14 } },
	} :: { [string]: { [string]: { number } } },

	xp = {
		winBase = 10, -- + perWildLevel * wild level, to each pet that fought
		perWildLevel = 5,
		captureFactor = 0.5, -- a capture gives half
		toNextBase = 20, -- xp for the next level = toNextBase + toNextPerLevel * level
		toNextPerLevel = 15,
	},

	capsule = {
		price = 50, -- Cash
		rarityBase = { Common = 0.6, Uncommon = 0.4, Rare = 0.2 } :: { [string]: number },
		minChance = 0.05,
		maxChance = 0.95,
	},

	wildStrongMoveChance = 0.2, -- a wild pet picks its strong move this often (while it has uses)

	arenaRadius = 15, -- studs
	choiceTimeoutSeconds = 60, -- no choice in time = ran away

	-- Where things stand, in studs from the arena centre (-Z looks at the foe).
	-- Staggered sideways so the over-the-shoulder camera sees the player on
	-- the left, our pet left of centre and the foe right of centre.
	layout = {
		mine = Vector3.new(-1.5, 0, 6),
		foe = Vector3.new(3, 0, -6),
		player = Vector3.new(-2.5, 3, 11.5), -- HumanoidRootPart height
		bench = Vector3.new(-7, 0, 14), -- the rest of the team, 4 studs apart further left (off camera)
		camera = Vector3.new(1.4, 7, 18.5), -- gameplay camera for ~4-stud pets
	},

	species = {
		AcornSquirrel = {
			type = "Forest",
			hp = 40,
			attack = 45,
			defense = 35,
			speed = 60,
			moves = moves("Tail Smack", "Acorn Toss", "Nut Barrage", "Forest"),
		},
		HoppingMushroom = {
			type = "Forest",
			hp = 50,
			attack = 40,
			defense = 50,
			speed = 35,
			moves = moves("Bounce", "Spore Puff", "Cap Slam", "Forest"),
		},
		BranchDeer = {
			type = "Forest",
			hp = 60,
			attack = 60,
			defense = 50,
			speed = 55,
			moves = moves("Antler Charge", "Leaf Blade", "Forest Rush", "Forest"),
		},
		RunningCactus = {
			type = "Desert",
			hp = 45,
			attack = 45,
			defense = 45,
			speed = 50,
			moves = moves("Spin Dash", "Needle Shot", "Thorn Storm", "Desert"),
		},
		BallScorpion = {
			type = "Desert",
			hp = 45,
			attack = 60,
			defense = 55,
			speed = 40,
			moves = moves("Pinch", "Sand Sting", "Venom Tail", "Desert"),
		},
		SunCamel = {
			type = "Desert",
			hp = 70,
			attack = 55,
			defense = 55,
			speed = 40,
			moves = moves("Stomp", "Sun Beam", "Solar Flare", "Desert"),
		},
	} :: { [string]: SpeciesBattle },
}

return Battle
