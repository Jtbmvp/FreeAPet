--!strict
-- Initial progression values approved 2026-11-03. All rewards are server-owned.
return {
	player = { maxLevel = 30, base = 100, linear = 50, quadratic = 10 },
	pet = {
		maxLevel = 30,
		base = 20,
		linear = 15,
		quadratic = 5,
		statGrowth = { hp = 0.10, attack = 0.10, defense = 0.10, speed = 0.10 },
		stages = {
			{ id = "Baby", level = 1, scale = 0.75, incomeFactor = 0.25 },
			{ id = "Juvenile", level = 5, scale = 0.88, incomeFactor = 0.60 },
			{ id = "Adult", level = 15, scale = 1, incomeFactor = 1 },
		},
	},
	unlocks = { Research = 3, Trade = 15, Starter2 = 10, Starter3 = 20 },
	starters = { species = { "Glimmouse", "Plazadillo", "Spoutle" }, capsules = 3 },
	researchRanks = {
		IncomeBoost = { first = 3, step = 1 },
		CarryCapacity = { first = 3, step = 2 },
		MoveSpeed = { first = 5, step = 2 },
		OfflineIncome = { first = 7, step = 2 },
		Accelerator = { first = 10, step = 2 },
	},
	rewards = {
		win = { playerBase = 20, playerPerLevel = 5, petBase = 10, petPerLevel = 5 },
		capture = { playerBase = 15, playerPerLevel = 3, petWinFactor = 0.5 },
	},
	-- Reserve capacity, separate from display pads. Zero means unlimited.
	inventoryCapacity = 0,
	missions = {
		CaptureOne = { event = "capture", target = 1, playerXp = 100, petXp = 50 },
		WinThree = { event = "win", target = 3, playerXp = 100, petXp = 50 },
	},
}
