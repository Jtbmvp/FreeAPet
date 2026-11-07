--!strict
-- Pure, transactional preparation. Never mutates the input profile and never
-- accesses a DataStore. Pending ownership messages must be applied first.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimalMath = require(ReplicatedStorage.Shared.AnimalMath)
local Config = require(ReplicatedStorage.Shared.Config)
local ResearchMath = require(ReplicatedStorage.Shared.ResearchMath)
local Types = require(ReplicatedStorage.Shared.Types)

local ProfileMigration = { VERSION = 3 }
local RETIRED = { "GrowthBoost", "LooseLimit", "ReleaseShield", "HeatProtection", "VisibilityProtection" }

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function copy(value: any, seen: { [any]: boolean }?): any
	if type(value) ~= "table" then
		assert(
			type(value) == "nil" or type(value) == "boolean" or type(value) == "string" or finite(value),
			"Unsupported save value"
		)
		if type(value) == "string" then
			assert(utf8.len(value), "Invalid save text")
		end
		return value
	end
	local visited = seen or {}
	assert(not visited[value], "Cyclic save table")
	visited[value] = true
	local result = {}
	for key, item in value do
		assert(type(key) == "string" or (finite(key) and key >= 1 and key % 1 == 0), "Invalid save key")
		result[key] = copy(item, visited)
	end
	visited[value] = nil
	return result
end

-- Frozen dd5ae10 compatibility only. Never used to advance growth or refund cash.
function ProfileMigration.LegacyAppearance(growth: number): (number, number)
	local g = math.clamp(growth, 0, 1)
	if g >= 1 then
		return 1, 1
	elseif g >= 0.4 then
		return 0.88 + 0.12 * (g - 0.4) / 0.6, 0.6
	end
	return 0.75 + 0.13 * g / 0.4, 0.25
end

local function offlineIncome(data: any, version: number, now: number): number
	local away = now - (data.lastOnlineAt or 0)
	if (data.lastOnlineAt or 0) <= 0 or away <= 60 then
		return 0
	end
	local perSecond = 0
	for _, saved in data.animals do
		local inBase = if version < 2 then not saved.equipped and not saved.away else saved.location == "Base"
		if inBase and Config.Species[saved.speciesId] then
			if version < 2 then
				local _, factor = ProfileMigration.LegacyAppearance(saved.growth or 0)
				local species = Config.Species[saved.speciesId]
				perSecond += (if species.biome then Config.Biomes[species.biome].baseValue else 1) * Config.Rarities[species.rarity].multiplier * saved.size * factor
			else
				perSecond += AnimalMath.ValuePerSecond(
					saved.speciesId,
					saved.size,
					saved.level or 1,
					saved.legacyIncomeFloor
				)
			end
		end
	end
	local research = data.research or {}
	local percent =
		ResearchMath.Value(research, "offlineIncomePercent", Config.Economy.offlineIncomePercent, now)
	local multiplier = ResearchMath.Value(research, "incomeMultiplier", 1, now)
	return perSecond * multiplier * percent * math.min(away, Config.Economy.offlineIncomeMaxHours * 3600)
end

local function actualResearchPayment(entry: any): number?
	local paid = entry.paidByRank
	if type(paid) ~= "table" or not finite(entry.level) or entry.level < 0 or entry.level % 1 ~= 0 then
		return nil
	end
	local ranks = entry.activeLevel or entry.level
	if not finite(ranks) or ranks % 1 ~= 0 or ranks < entry.level or ranks > entry.level + 1 then
		return nil
	end
	local total = 0
	for rank = 1, ranks do
		local amount = paid[tostring(rank)]
		if not finite(amount) or amount < 0 then
			return nil
		end
		total += amount
	end
	return total
end

function ProfileMigration.Prepare(
	input: any,
	now: number
): (Types.PlayerData, {
	offlineCash: number,
	pendingRefunds: number,
	unavailablePets: number,
})
	local version = input.schemaVersion or 1
	assert(
		finite(version) and version % 1 == 0 and version >= 1 and version <= ProfileMigration.VERSION,
		"Unsupported profile schema"
	)
	local data = copy(input)
	data.cash = data.cash or Config.Economy.startingCash
	data.baseSlots = data.baseSlots or Config.Economy.baseStartingSlots
	data.animals, data.research = data.animals or {}, data.research or {}
	data.index, data.trades = data.index or {}, data.trades or { day = 0, count = 0 }
	data.capsules, data.bestIncome = data.capsules or 0, data.bestIncome or 0
	data.playerTotalXp, data.missions = data.playerTotalXp or 0, data.missions or {}
	data.rewardRevision = data.rewardRevision or 0
	data.retiredResearch = data.retiredResearch or {}
	data.starters = data.starters or { choices = {}, capsulesGranted = false }
	data.commerce = data.commerce or { revision = 0, receipts = {} }
	assert(type(data.starters.choices) == "table" and #data.starters.choices <= 3, "Invalid starter grants")
	assert(
		data.starters.capsulesGranted == (#data.starters.choices > 0),
		"Inconsistent starter capsule marker"
	)
	local selected = {}
	for _, speciesId in data.starters.choices do
		assert(
			table.find(Config.Progression.starters.species, speciesId) and not selected[speciesId],
			"Invalid starter choice"
		)
		selected[speciesId] = true
	end
	assert(type(data.starters.capsulesGranted) == "boolean", "Invalid starter capsule grant")
	assert(
		finite(data.commerce.revision)
			and data.commerce.revision >= 0
			and data.commerce.revision % 1 == 0
			and type(data.commerce.receipts) == "table",
		"Invalid commerce ledger"
	)
	assert(
		finite(data.cash) and data.cash >= 0 and finite(data.playerTotalXp) and data.playerTotalXp >= 0,
		"Invalid balance or XP"
	)
	assert(
		finite(data.rewardRevision) and data.rewardRevision >= 0 and data.rewardRevision % 1 == 0,
		"Invalid reward revision"
	)
	assert(
		finite(data.baseSlots) and data.baseSlots >= 0 and data.baseSlots % 1 == 0,
		"Invalid display capacity"
	)
	assert(finite(data.capsules) and data.capsules >= 0 and data.capsules % 1 == 0, "Invalid capsule stock")
	local receipts = 0
	for id, receipt in data.commerce.receipts do
		receipts += 1
		assert(
			type(id) == "string" and #id == 36 and type(receipt) == "table" and receipt.requestId == id,
			"Invalid commerce receipt"
		)
		assert(
			receipt.kind == "equipBest"
				or receipt.kind == "buyCapsule"
				or receipt.kind == "sellPet"
				or receipt.kind == "quoteSell",
			"Invalid receipt kind"
		)
		assert(receipt.phase == "Committed" or receipt.phase == "Rejected", "Invalid receipt phase")
		assert(
			finite(receipt.revision)
				and receipt.revision > 0
				and receipt.revision % 1 == 0
				and receipt.revision <= data.commerce.revision,
			"Invalid receipt revision"
		)
	end
	assert(receipts <= Config.Commerce.maxReceipts, "Commerce ledger capacity exceeded")
	local ids = {}
	for id, saved in data.animals do
		assert(type(id) == "string" and type(saved) == "table", "Invalid pet entry")
		assert(
			type(saved.speciesId) == "string" and finite(saved.size) and saved.size > 0,
			"Invalid pet identity or size"
		)
		assert(
			saved.level == nil or (finite(saved.level) and saved.level >= 1 and saved.level % 1 == 0),
			"Invalid pet level"
		)
		assert(
			saved.teamOrder == nil
				or (
					finite(saved.teamOrder)
					and saved.teamOrder >= 1
					and saved.teamOrder <= Config.Gameplay.team.maxEquipped
					and saved.teamOrder % 1 == 0
				),
			"Invalid team order"
		)
		assert(saved.xp == nil or (finite(saved.xp) and saved.xp >= 0), "Invalid pet XP")
		assert(saved.hp == nil or (finite(saved.hp) and saved.hp >= 0), "Invalid pet HP")
		assert(saved.growth == nil or finite(saved.growth), "Invalid legacy growth")
		table.insert(ids, id)
	end
	table.sort(ids)
	local earned = offlineIncome(data, version, now)
	local occupied, teamCount, unavailable = {}, 0, 0
	for _, id in ids do
		local saved = data.animals[id]
		if version < 2 then
			local scale, income = ProfileMigration.LegacyAppearance(saved.growth or 0)
			saved.legacyScaleFloor, saved.legacyIncomeFloor = scale, income
			saved.location = if saved.equipped then "Team" elseif saved.away then "Inventory" else "Base"
		end
		-- Missing content is quarantined in the same collection, never substituted.
		if not Config.Species[saved.speciesId] or not Config.Battle.species[saved.speciesId] then
			saved.unavailableReason = "Species content unavailable"
			saved.location = "Inventory"
			unavailable += 1
		else
			saved.unavailableReason = nil
		end
		if saved.location == "Team" and teamCount < Config.Gameplay.team.maxEquipped then
			teamCount += 1
			saved.equipped = true
		elseif saved.location ~= "Base" then
			saved.location, saved.equipped = "Inventory", nil
		end
		if saved.location ~= "Team" then
			saved.equipped = nil
		end
		local slot = saved.slot
		local valid = finite(slot)
			and slot % 1 == 0
			and slot > 0
			and slot <= data.baseSlots
			and not occupied[slot]
		if saved.location ~= "Inventory" and valid then
			occupied[slot] = id
		else
			saved.slot = 0
		end
		saved.away = nil
	end
	-- Resolve colliding/missing pads deterministically, without changing any ID.
	for _, id in ids do
		local saved = data.animals[id]
		if saved.location == "Base" and saved.slot == 0 then
			for slot = 1, data.baseSlots do
				if not occupied[slot] then
					saved.slot, occupied[slot] = slot, id
					break
				end
			end
			if saved.slot == 0 then
				saved.location = "Inventory"
			end
		end
	end
	local pending = 0
	for _, id in RETIRED do
		local entry = data.research[id]
		if entry then
			if not data.retiredResearch[id] then
				local paid = actualResearchPayment(entry)
				data.retiredResearch[id] = {
					progress = entry,
					refundStatus = if paid ~= nil then "Refunded" else "PendingHistory",
					refundedCash = paid,
				}
				-- Schema 1 normally has no receipts. Missing history never becomes a
				-- guessed credit; a complete actual ledger is refunded exactly once.
				if paid ~= nil then
					data.cash += paid
				end
			end
			data.research[id] = nil
		end
		local retired = data.retiredResearch[id]
		if retired and retired.refundStatus == "PendingHistory" then
			pending += 1
		end
	end
	assert(finite(earned) and earned >= 0 and finite(data.cash + earned), "Invalid offline income")
	data.cash += earned
	data.lastOnlineAt = now -- offline credit and watermark persist together
	data.schemaVersion = ProfileMigration.VERSION -- commit version last
	return data :: Types.PlayerData,
		{ offlineCash = earned, pendingRefunds = pending, unavailablePets = unavailable }
end

return ProfileMigration
