--!strict
-- Catching, carrying, the team, research, day cycle and spawning. All PLACEHOLDER.

local Gameplay = {
	player = {
		-- Roblox default is 16. The map is ~1250 studs end to end, so 22 keeps
		-- a full crossing under a minute. Applied through StarterPlayer.
		walkSpeed = 22,
	},

	capture = {
		holdSeconds = 2,
		maxDistance = 12, -- studs, validated on the server
	},

	carry = {
		startingCapacity = 1,
	},

	-- Battle roster: only the leader is shown as a cosmetic follower.
	-- Every equipped pet earns nothing and cannot be stolen.
	team = {
		maxEquipped = 3,
		followDistance = 6, -- cosmetic companion's distance behind the player
		teleportDistance = 70, -- snap cosmetic motion after a teleport
	},

	-- Trading pets between players (OPEN #5, decided): a double confirmation
	-- that resets on any change, then a countdown; base pets only; the server
	-- checks everything when the trade happens.
	trade = {
		enabled = false, -- SEC-TRADE-01: no durable two-profile recovery yet
		minAccountAgeDays = 7,
		youngAccountMinLevel = 21, -- account <7d requires level >20, including Studio
		rareMinLevel = 25,
		petCooldownSeconds = 24 * 60 * 60,
		maxPerDay = 5,
		maxPetsPerSide = 6,
		countdownSeconds = 3,
		requestSeconds = 30, -- an unanswered request expires
		maxDistance = 0, -- 0 = anywhere in the server
	},

	-- Global leaderboard board in the plaza: best Cash/s ever reached.
	leaderboard = {
		position = Vector3.new(-176, 0, 0), -- V3 board frame
		facing = Vector3.new(-175, 0, 0), -- imported source board front +X faces the fountain
		size = 10, -- names shown
		writeSeconds = 60, -- per player, at most
		readSeconds = 120,
	},

	research = {
		maxActive = 1, -- researches running at the same time
	},

	day = {
		lengthSeconds = 10 * 60, -- OPEN #3: 10 min for testing
	},

	spawning = {
		animalsPerBiome = 8,
		respawnSeconds = 20,
		wanderRadius = 20, -- studs around the spawn point
		wanderSpeed = 4, -- slow, so catching is easy
	},
}

return Gameplay
