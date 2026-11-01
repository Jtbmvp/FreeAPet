--!strict
-- Research tree, drawn as a hexagon grid. Paid with cash and time; timers
-- use os.time() timestamps so they keep counting while the player is
-- offline. One research runs at a time (Config.Gameplay.research.maxActive).
--
-- Unlocking: root nodes are open from the start; any other node opens once
-- a neighbouring hexagon has at least level 1. `hex` is the axial position
-- (q, r) of a pointy-top hexagon; neighbours are the six around it.
--
-- Levels come from a curve: cost and time grow by a factor per level, the
-- value is a function of the level. All numbers PLACEHOLDER.

export type ResearchLevel = {
	cost: number,
	durationSeconds: number,
	value: number, -- meaning depends on the node (see effect)
}

export type Category = "Economy" | "Defense" | "Utility"

export type ResearchNode = {
	id: string,
	displayName: string,
	icon: string, -- key in Config.UI.icons
	category: Category, -- colour of the hexagon
	hex: { number }, -- { q, r }
	root: boolean?, -- open from the start
	-- What the server reads (ResearchMath.Value): incomeMultiplier,
	-- offlineIncomePercent, growthMultiplier, carryCapacity, walkSpeed,
	-- maxLoose, researchTimeMultiplier, protection.<HazardId> (multiplier on
	-- the meter's rise), releaseShieldSeconds.
	effect: string,
	levels: { ResearchLevel },
}

type Curve = {
	maxLevel: number,
	cost: number, -- level 1
	costGrowth: number,
	seconds: number, -- level 1
	secondsGrowth: number,
	value: (level: number) -> number,
}

-- Rounds to 2 significant digits so prices read cleanly ($1.2K, not $1,187).
local function nice(value: number): number
	if value < 100 then
		return math.max(1, math.round(value / 5) * 5)
	end
	local magnitude = 10 ^ (math.floor(math.log10(value)) - 1)
	return math.round(value / magnitude) * magnitude
end

local function curve(spec: Curve): { ResearchLevel }
	local levels = {}
	for level = 1, spec.maxLevel do
		table.insert(levels, {
			cost = nice(spec.cost * spec.costGrowth ^ (level - 1)),
			durationSeconds = nice(spec.seconds * spec.secondsGrowth ^ (level - 1)),
			value = spec.value(level),
		})
	end
	return levels
end

local Research: { [string]: ResearchNode } = {
	-- Economy (green)
	IncomeBoost = {
		id = "IncomeBoost",
		displayName = "Bigger Income",
		icon = "cash",
		category = "Economy",
		hex = { 0, 0 },
		root = true,
		effect = "incomeMultiplier",
		levels = curve({
			maxLevel = 25,
			cost = 50,
			costGrowth = 1.22,
			seconds = 15,
			secondsGrowth = 1.15,
			value = function(level)
				return 1 + 0.04 * level
			end,
		}),
	},
	OfflineIncome = {
		id = "OfflineIncome",
		displayName = "Offline Income",
		icon = "offline",
		category = "Economy",
		hex = { -1, 0 },
		effect = "offlineIncomePercent", -- base is Config.Economy.offlineIncomePercent (25%)
		levels = curve({
			maxLevel = 10,
			cost = 300,
			costGrowth = 1.35,
			seconds = 60,
			secondsGrowth = 1.25,
			value = function(level)
				return 0.25 + 0.025 * level
			end,
		}),
	},
	GrowthBoost = {
		id = "GrowthBoost",
		displayName = "Fast Growth",
		icon = "upgrade",
		category = "Economy",
		hex = { -1, 1 },
		effect = "growthMultiplier",
		levels = curve({
			maxLevel = 20,
			cost = 120,
			costGrowth = 1.25,
			seconds = 30,
			secondsGrowth = 1.18,
			value = function(level)
				return 1 + 0.05 * level
			end,
		}),
	},

	-- Utility (purple)
	CarryCapacity = {
		id = "CarryCapacity",
		displayName = "Carry Capacity",
		icon = "carry",
		category = "Utility",
		hex = { 1, 0 },
		root = true,
		effect = "carryCapacity",
		levels = curve({
			maxLevel = 3,
			cost = 200,
			costGrowth = 4,
			seconds = 60,
			secondsGrowth = 3,
			value = function(level)
				return 1 + level
			end,
		}),
	},
	MoveSpeed = {
		id = "MoveSpeed",
		displayName = "Movement Speed",
		icon = "speed",
		category = "Utility",
		hex = { 1, -1 },
		effect = "walkSpeed", -- base is Config.Gameplay.player.walkSpeed (22)
		levels = curve({
			maxLevel = 10,
			cost = 100,
			costGrowth = 1.3,
			seconds = 20,
			secondsGrowth = 1.25,
			value = function(level)
				return 22 + 0.4 * level
			end,
		}),
	},
	LooseLimit = {
		id = "LooseLimit",
		displayName = "More Loose Pets",
		icon = "release",
		category = "Utility",
		hex = { 2, -1 },
		effect = "maxLoose", -- base is Config.Economy.maxLooseAnimals (2)
		levels = curve({
			maxLevel = 3,
			cost = 600,
			costGrowth = 4,
			seconds = 120,
			secondsGrowth = 3,
			value = function(level)
				return 2 + level
			end,
		}),
	},
	Accelerator = {
		id = "Accelerator",
		displayName = "Accelerator",
		icon = "timer",
		category = "Utility",
		hex = { 0, 1 },
		effect = "researchTimeMultiplier",
		levels = curve({
			maxLevel = 10,
			cost = 400,
			costGrowth = 1.35,
			seconds = 60,
			secondsGrowth = 1.25,
			value = function(level)
				return 1 - 0.03 * level
			end,
		}),
	},

	-- Defense (blue)
	HeatProtection = {
		id = "HeatProtection",
		displayName = "Heat Protection",
		icon = "heat",
		category = "Defense",
		hex = { 2, 0 },
		effect = "protection.Heat",
		levels = curve({
			maxLevel = 15,
			cost = 80,
			costGrowth = 1.28,
			seconds = 20,
			secondsGrowth = 1.2,
			value = function(level)
				return 1 - 0.05 * level
			end,
		}),
	},
	VisibilityProtection = {
		id = "VisibilityProtection",
		displayName = "Lantern",
		icon = "darkness",
		category = "Defense",
		hex = { 1, 1 },
		effect = "protection.LowVisibility",
		levels = curve({
			maxLevel = 15,
			cost = 80,
			costGrowth = 1.28,
			seconds = 20,
			secondsGrowth = 1.2,
			value = function(level)
				return 1 - 0.05 * level
			end,
		}),
	},
	-- Brief's "base protection", redefined for concept v2 (the base is always
	-- safe): a freshly released pet cannot be stolen for a while.
	ReleaseShield = {
		id = "ReleaseShield",
		displayName = "Release Shield",
		icon = "shield",
		category = "Defense",
		hex = { 2, 1 },
		effect = "releaseShieldSeconds",
		levels = curve({
			maxLevel = 10,
			cost = 300,
			costGrowth = 1.35,
			seconds = 60,
			secondsGrowth = 1.25,
			value = function(level)
				return 60 * level
			end,
		}),
	},
}

return Research
