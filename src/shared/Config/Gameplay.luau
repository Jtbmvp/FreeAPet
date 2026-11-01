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

	-- Battle team: equipped pets follow their owner, earn nothing and can't be stolen.
	team = {
		maxEquipped = 3,
		followDistance = 6, -- studs behind the player
		teleportDistance = 70, -- too far behind: jump next to the player
	},

	-- Trading pets between players (OPEN #5, decided): a double confirmation
	-- that resets on any change, then a countdown; base pets only; the server
	-- checks everything when the trade happens.
	trade = {
		minAccountAgeDays = 3, -- older accounts only (alts); not applied in Studio
		maxPerDay = 20, -- PLACEHOLDER
		maxPetsPerSide = 6,
		countdownSeconds = 3,
		requestSeconds = 30, -- an unanswered request expires
		maxDistance = 0, -- 0 = anywhere in the server
	},

	-- Global leaderboard board in the plaza: best Cash/s ever reached.
	leaderboard = {
		position = Vector3.new(150, 0, 34), -- on the lawn beside the fountain path
		facing = Vector3.new(200, 0, 0), -- looks towards the fountain
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

	-- Owner can pull a loose animal home. Real version is a cheap Developer
	-- Product; in the prototype it is a free, clearly marked debug button.
	teleportHome = {
		debugFree = true,
		developerProductId = 0, -- set when the real product exists
	},
}

return Gameplay
