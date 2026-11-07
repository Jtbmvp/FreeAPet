--!nocheck
local count = 0
local function check(v, message)
	count += 1
	assert(v, message or `check {count}`)
end
local function eq(a, b, message)
	check(a == b, (message or "mismatch") .. `: {tostring(a)} ~= {tostring(b)}`)
end
local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local r = {}
	for k, x in v do
		r[k] = copy(x)
	end
	return r
end
local Config = load("ReplicatedStorage.Shared.Config")
local Math = load("ReplicatedStorage.Shared.ProgressionMath")
local Migration = load("ServerScriptService.Server.Services.ProfileMigration")
local function xp(level)
	local n = 0
	for l = 1, level - 1 do
		n += Math.PlayerXpToNext(l)
	end
	return n
end
local function newData(level)
	return Migration.Prepare(
		{ schemaVersion = 2, playerTotalXp = xp(level), cash = 1000, animals = {} },
		timestamp
	)
end
local Policy = load("ServerScriptService.Server.Services.TradePolicy")
eq(Config.Gameplay.trade.enabled, false)
eq(Config.Gameplay.trade.maxPerDay, 5)
eq(Config.Progression.unlocks.Trade, 15)
local d = newData(14)
check(Policy.PlayerReason(d, 100, timestamp) ~= nil)
d.playerTotalXp = xp(15)
eq(Policy.PlayerReason(d, 7, timestamp), nil)
check(Policy.PlayerReason(d, 6, timestamp) ~= nil)
d.playerTotalXp = xp(20)
check(Policy.PlayerReason(d, 6, timestamp) ~= nil)
d.playerTotalXp = xp(21)
eq(Policy.PlayerReason(d, 6, timestamp), nil)
d.trades = { day = timestamp // 86400, count = 5 }
check(Policy.PlayerReason(d, 100, timestamp) ~= nil)
eq(Policy.PlayerReason(d, 100, timestamp + 86400), nil)
d.playerTotalXp = xp(24)
local old = { origin = { capturedAt = timestamp - 86400 } }
check(Policy.PetReason(d, old, "BranchDeer", timestamp) ~= nil)
d.playerTotalXp = xp(25)
eq(Policy.PetReason(d, old, "BranchDeer", timestamp), nil)
check(Policy.PetReason(d, { lastTradedAt = timestamp - 86399 }, "AcornSquirrel", timestamp) ~= nil)
eq(Policy.PetReason(d, { lastTradedAt = timestamp - 86400 }, "AcornSquirrel", timestamp), nil)
check(Policy.PetReason(d, {}, "AcornSquirrel", timestamp) ~= nil)
check(Policy.PetReason(d, old, "Glimmouse", timestamp) ~= nil)
eq(Config.Battle.wildLevels.Forest.Common[2], 2)
local AnimalMath = load("ReplicatedStorage.Shared.AnimalMath")
for _, id in Config.Progression.starters.species do
	eq(Config.Species[id].biome, nil)
	eq(Config.Species[id].spawnWeight, 0)
	eq(AnimalMath.ValuePerSecond(id, 1, 1), 0.25)
	eq(AnimalMath.ValuePerSecond(id, 1, 5), 0.6)
	eq(AnimalMath.ValuePerSecond(id, 1, 15), 1)
end
local migrated = Migration.Prepare({ schemaVersion = 1, animals = {}, cash = 7 }, timestamp)
eq(migrated.schemaVersion, 3)
eq(#migrated.starters.choices, 0)
eq(migrated.starters.capsulesGranted, false)
local again = Migration.Prepare(migrated, timestamp)
eq(again.cash, migrated.cash)
check(not pcall(Migration.Prepare, { schemaVersion = 4 }, timestamp), "future schema blocked")
local a, b = player(101), player(102)
Players.list = { a, b }
local live = { [a] = newData(25), [b] = newData(25) }
local durable = { [a] = copy(live[a]), [b] = copy(live[b]) }
local records, saveQueue, releasing, loaded, saveHooks = {}, {}, {}, {}, {}
local function sync(p)
	for id, saved in live[p].animals do
		local r = records[id]
		if r then
			saved.level = r.level
			saved.hp = r.hp
			saved.location = if r.state == "Following"
				then "Team"
				elseif r.state == "InBase" then "Base"
				else "Inventory"
		end
	end
	for _, fn in saveHooks do
		fn(p, live[p])
	end
end
local P = {
	Get = function(p)
		return live[p]
	end,
	IsReady = function(p)
		return live[p] ~= nil
	end,
	GetCommitted = function(p)
		return durable[p]
	end,
	OnLoaded = function(fn)
		table.insert(loaded, fn)
	end,
	OnBeforeSave = function(fn)
		table.insert(saveHooks, fn)
	end,
	OnReleasing = function(fn)
		table.insert(releasing, fn)
	end,
	SaveNow = function() end,
	SaveConfirmed = function(p, contains, callback)
		sync(p)
		table.insert(saveQueue, { p = p, data = copy(live[p]), contains = contains, callback = callback })
		return true
	end,
}
mocks["ServerScriptService.Server.Services.PlayerDataService"] = P
local guidN = 0
services.HttpService.GenerateGUID = function()
	guidN += 1
	return string.format("00000000-0000-0000-0000-%012d", guidN)
end
services.Workspace = {
	GetServerTimeNow = function()
		return timestamp
	end,
}
local function id()
	return services.HttpService.GenerateGUID()
end
local function add(p, species, petId)
	local r = {
		id = petId or id(),
		speciesId = species,
		size = 1,
		level = 1,
		xp = 0,
		hp = 50,
		ownerUserId = p.UserId,
		state = "InBase",
	}
	records[r.id] = r
	live[p].animals[r.id] = {
		speciesId = species,
		size = 1,
		slot = 0,
		level = 1,
		location = "Base",
		origin = {
			capturedAt = timestamp - 86400,
		},
	}
	return r
end
mocks["ServerScriptService.Server.Animals.AnimalFactory"] = {}
local realAnimals = load("ServerScriptService.Server.Services.AnimalService")
local restored = realAnimals.Restore(
	"real-starter",
	{ speciesId = "Glimmouse", size = 1, level = 1, slot = 0, hp = 60 },
	a.UserId
)
check(restored ~= nil, "Starter restores with no spawn area")
eq(restored.homeArea, nil)
eq(realAnimals.SpawnWild("Forest", "Glimmouse"), nil, "starter never spawns wild")
local A = {
	Get = function(x)
		return records[x]
	end,
	Restore = function(petId, saved, owner)
		local r = {
			id = petId,
			speciesId = saved.speciesId,
			size = saved.size,
			level = saved.level,
			xp = saved.xp,
			hp = saved.hp,
			ownerUserId = owner,
			state = "Inventory",
		}
		records[petId] = r
		return r
	end,
	EnsureModel = function(r)
		return {}
	end,
	Remove = function(r)
		records[r.id] = nil
	end,
}
mocks["ServerScriptService.Server.Services.AnimalService"] = A
mocks["ServerScriptService.Server.Services.HomeService"] = {
	Store = function(p, r)
		r.state = "Inventory"
		return true
	end,
	PlaceBack = function(p, r)
		r.state = "Inventory"
		return true
	end,
	SaveCaught = function() end,
	RefreshIncome = function() end,
	GiveAway = function(p, r)
		live[p].animals[r.id] = nil
		return true
	end,
}
mocks["ServerScriptService.Server.Services.PlayerStateService"] = {
	AddCash = function(p, n)
		live[p].cash += n
	end,
}
mocks["ServerScriptService.Server.Services.TeamPresentation"] = {
	Start = function() end,
	Release = function() end,
	Stow = function() end,
	Show = function() end,
	Clear = function() end,
	Forget = function() end,
}
mocks["ServerScriptService.Server.Services.FollowerPolicy"] = {
	Select = function(team)
		return team[1]
	end,
}
mocks["ServerScriptService.Server.Services.ProgressionService"] = { OnPetChanged = function() end }
local notices = {}
mocks["ServerScriptService.Server.Services.NotifyService"] = {
	Send = function(p, n)
		table.insert(notices, n)
	end,
}
local Guard = load("ServerScriptService.Server.Services.PlayerMutationGuard")
local Team = load("ServerScriptService.Server.Services.TeamService")
Team.Start()
local Trade = load("ServerScriptService.Server.Services.TradeService")
Trade.Start()
local ap = add(a, "AcornSquirrel"), add(b, "AcornSquirrel")
local function fireTrade(p, k)
	clock += 0.2
	RemoteAdapter.Get("TradeAction").OnServerEvent:Fire(p, k)
end
-- Public default fence; even eligible players cannot start.
RemoteAdapter.Get("TradeRequest").OnServerEvent:Fire(a, b.UserId)
eq(#RemoteAdapter.Get("TradeUpdate").messages, 0)
-- Deliberately flip UI gate to exercise the unconditional execution fence.
Config.Gameplay.trade.enabled = true
clock += 3
RemoteAdapter.Get("TradeRequest").OnServerEvent:Fire(a, b.UserId)
RemoteAdapter.Get("TradeRespond").OnServerEvent:Fire(b, tostring(a.UserId))
check(Trade.IsTrading(a))
fireTrade(a, { kind = "ready" })
fireTrade(b, { kind = "ready" })
fireTrade(a, { kind = "confirm" })
fireTrade(b, { kind = "confirm" })
local n = #delayed
local deadline =
	RemoteAdapter.Get("TradeUpdate").messages[#RemoteAdapter.Get("TradeUpdate").messages].value.countdown
fireTrade(b, { kind = "confirm" })
eq(#delayed, n, "duplicate confirm does not reschedule")
local timer = delayed[n]
clock += deadline
timer.fn(table.unpack(timer.args))
eq(#saveQueue, 0)
eq(records[ap.id].ownerUserId, a.UserId)
check(not Trade.IsTrading(a))
for _, notice in notices do
	check(notice.kind ~= "success", "no early success")
end
clock += 2
local before = #notices
for i = 1, 25 do
	RemoteAdapter.Get("TradeRespond").OnServerEvent:Fire(a, "99999")
end
eq(#notices - before, 1, "invalid response burst bounded")
for _, bad in { {}, true, 0 / 0, string.rep("9", 1000), "x" } do
	RemoteAdapter.Get("TradeRespond").OnServerEvent:Fire(a, bad)
end
Config.Gameplay.trade.enabled = false
-- Commerce actions operate on a single profile, with genuine delayed acknowledgments.
local Commerce = load("ServerScriptService.Server.Services.HudCommerceService")
Commerce.Start()
local function snap(p, pending)
	clock += 1
	return RemoteAdapter.Get("GetHudCommerce").OnServerInvoke(p, pending)
end
local function act(p, intent)
	clock += 1
	RemoteAdapter.Get("HudCommerceAction").OnServerEvent:Fire(p, intent)
end
local function last()
	local m = RemoteAdapter.Get("HudCommerceResult").messages
	return m[#m].value
end
local function commit()
	local q = table.remove(saveQueue, 1)
	check(q ~= nil, "save requested")
	durable[q.p] = copy(q.data)
	check(q.contains(durable[q.p]), "saved marker")
	q.callback()
	return q
end
check(not snap(a).capabilities.buyCapsule)
Config.Commerce.enabled = true
local buy =
	{ requestId = id(), kind = "buyCapsule", quantity = 1, priceVersion = snap(a).capsule.priceVersion }
local cash, stock = live[a].cash, live[a].capsules
act(a, buy)
eq(last().phase, "Pending")
eq(live[a].cash, cash - 50)
eq(live[a].capsules, stock + 1)
check(Guard.IsBusy(a))
act(a, buy)
eq(#saveQueue, 1)
eq(last().phase, "Pending")
eq(live[a].capsules, stock + 1)
check(not Team.Equip(a, ap), "individual equip locked")
commit()
eq(last().phase, "Committed")
check(last().committedRevision >= 1)
check(not Guard.IsBusy(a))
check(last().snapshot ~= nil)
act(a, buy)
eq(last().phase, "Committed")
eq(#saveQueue, 0)
eq(live[a].capsules, stock + 1)
-- Simulate rejoin using the durable profile and a fresh service session/cache.
for _, fn in releasing do
	fn(a)
end
live[a] = copy(durable[a])
Players.PlayerAdded:Fire(a)
act(a, buy)
eq(last().phase, "Committed")
eq(#saveQueue, 0)
eq(live[a].capsules, stock + 1)
local badPrice = { requestId = id(), kind = "buyCapsule", quantity = 1, priceVersion = "old" }
act(a, badPrice)
eq(last().phase, "Pending")
commit()
eq(last().phase, "Rejected")
eq(last().reasonCode, "PRICE_CHANGED")
local savedPrice = Config.Battle.capsule.price
Config.Battle.capsule.price = 1
act(a, badPrice)
eq(last().phase, "Rejected")
eq(live[a].capsules, stock + 1)
Config.Battle.capsule.price = savedPrice
local unknown = id()
eq(snap(a, unknown).requestResult, nil, "unknown read never authorizes repeat")
-- Save callback lost/expired; read reconciles from LastSavedData instead.
local late =
	{ requestId = id(), kind = "buyCapsule", quantity = 1, priceVersion = snap(a).capsule.priceVersion }
act(a, late)
local q = table.remove(saveQueue, 1)
durable[a] = copy(q.data)
local reconciliation = snap(a, late.requestId)
eq(reconciliation.requestResult.phase, "Committed")
check(not Guard.IsBusy(a))
check(reconciliation.requestResult.snapshot ~= nil)
-- Rank based on combat instead of income and stable ID; real batch TeamService.
local deer = add(a, "BranchDeer", "aaa"), add(a, "SunCamel", "bbb")
local extra = add(a, "RunningCactus", "ccc")
local equip = { requestId = id(), kind = "equipBest" }
act(a, equip)
eq(last().phase, "Pending")
commit()
eq(last().phase, "Committed")
local team = Team.GetTeam(a)
eq(#team, 3)
eq(team[1].id, "aaa")
eq(team[2].id, "bbb")
eq(durable[a].animals["aaa"].teamOrder, 1, "ranked leader saved")
eq(durable[a].animals["bbb"].teamOrder, 2, "ranked roster order saved")
local offerPet = deer
local quote = { requestId = id(), kind = "quoteSell", petId = offerPet.id }
local oldCash = live[a].cash
act(a, quote)
eq(last().phase, "Quoted")
eq(live[a].cash, oldCash)
check(live[a].animals[offerPet.id] ~= nil)
eq(#saveQueue, 0)
local offer = last().quote
eq(offer.totalCash, 200)
eq(offer.petLevel, 1)
eq(snap(a, quote.requestId).requestResult.phase, "Quoted", "lost quote result recovered")
-- Opening/cancelling/expiring quotes cannot mutate the collection.
timestamp += 31
act(a, { requestId = id(), kind = "sellPet", petId = offerPet.id, quoteId = offer.quoteId })
commit()
eq(last().reasonCode, "QUOTE_EXPIRED")
check(live[a].animals[offerPet.id] ~= nil)
act(a, { requestId = id(), kind = "quoteSell", petId = offerPet.id })
offer = last().quote
local sell = { requestId = id(), kind = "sellPet", petId = offerPet.id, quoteId = offer.quoteId }
act(a, sell)
eq(last().phase, "Pending")
eq(live[a].cash, oldCash + 200)
eq(live[a].animals[offerPet.id], nil)
for _, r in Team.GetTeam(a) do
	check(r.id ~= offerPet.id, "sold follower removed")
end
commit()
eq(last().phase, "Committed")
act(a, sell)
eq(live[a].cash, oldCash + 200)
eq(#saveQueue, 0)
-- Refused sale persisted as a tombstone: later eligibility cannot turn it into a sale.
local rej = { requestId = id(), kind = "sellPet", petId = extra.id, quoteId = "missing" }
act(a, rej)
commit()
eq(last().phase, "Rejected")
local snap1 = snap(a)
live[a].capsules += 1
local snap2 = snap(a)
check(snap2.revision > snap1.revision)
-- Grant starters once; first equipped, others reserve when full, no random size/biome.
local Starter = load("ServerScriptService.Server.Services.StarterService")
Starter.Start()
local function choose(p, i, species)
	clock += 1
	RemoteAdapter.Get("ChooseStarter").OnServerEvent:Fire(p, i, species)
end
choose(a, 1, "Glimmouse")
eq(#live[a].starters.choices, 1)
eq(live[a].capsules, stock + 3 + 3)
check(Guard.IsBusy(a))
choose(a, 1, "Plazadillo")
eq(#live[a].starters.choices, 1)
commit()
eq(live[a].starters.capsulesGranted, true)
local beforeCaps = live[a].capsules
choose(a, 2, "Plazadillo")
eq(#live[a].starters.choices, 3, "level25 also grants the remaining starter")
eq(live[a].capsules, beforeCaps)
commit()
choose(a, 1, "Spoutle")
eq(#live[a].starters.choices, 3)
eq(live[a].capsules, beforeCaps)
local starters = 0
for _, pet in live[a].animals do
	if Config.Species[pet.speciesId].starter then
		starters += 1
		eq(pet.size, 1)
		eq(pet.level, 1)
		eq(pet.hp, Config.Battle.species[pet.speciesId].hp)
	end
end
eq(starters, 3)
-- Locks, affordability, ownership and quote drift all refuse without value movement.
local beforeBalance, beforeStock = live[a].cash, live[a].capsules
local blocked =
	{ requestId = id(), kind = "buyCapsule", quantity = 1, priceVersion = snap(a).capsule.priceVersion }
a:SetAttribute("InBattle", true)
act(a, blocked)
commit()
eq(last().phase, "Rejected")
eq(last().reasonCode, "IN_BATTLE")
a:SetAttribute("InBattle", nil)
act(a, blocked)
eq(last().phase, "Rejected")
eq(live[a].cash, beforeBalance)
eq(live[a].capsules, beforeStock)
live[a].cash = 0
act(a, { requestId = id(), kind = "buyCapsule", quantity = 1, priceVersion = snap(a).capsule.priceVersion })
commit()
eq(last().reasonCode, "NOT_ENOUGH_CASH")
eq(live[a].capsules, beforeStock)
live[a].cash = beforeBalance
act(a, { requestId = id(), kind = "quoteSell", petId = extra.id })
local drift = last().quote
records[extra.id].level += 1
act(a, { requestId = id(), kind = "sellPet", petId = extra.id, quoteId = drift.quoteId })
commit()
eq(last().reasonCode, "QUOTE_CHANGED")
check(live[a].animals[extra.id] ~= nil)
local malformedCount = #saveQueue
for _, bad in
	{
		{ requestId = "bad", kind = "buyCapsule" },
		{ requestId = id(), kind = {} },
		{
			requestId = id(),
			kind = "codes",
		},
	}
do
	act(a, bad)
end
eq(#saveQueue, malformedCount)
-- Busy intents are fenced Pending, then durably rejected without a delayed grant.
local one =
	{ requestId = id(), kind = "buyCapsule", quantity = 1, priceVersion = snap(a).capsule.priceVersion }
local two =
	{ requestId = id(), kind = "buyCapsule", quantity = 1, priceVersion = snap(a).capsule.priceVersion }
act(a, one)
act(a, two)
eq(last().phase, "Pending")
eq(#saveQueue, 1)
commit()
snap(a, two.requestId)
eq(#saveQueue, 1)
commit()
eq(last().phase, "Rejected")
local afterOne = live[a].capsules
act(a, two)
eq(last().phase, "Rejected")
eq(live[a].capsules, afterOne)
-- First-entry, level10 and level20 gates on another account.
live[b] = newData(1)
durable[b] = copy(live[b])
choose(b, 2, "Spoutle")
eq(#live[b].starters.choices, 0)
choose(b, 1, "Spoutle")
eq(#live[b].starters.choices, 1)
commit()
eq(#Team.GetTeam(b), 1, "first starter joins an empty team")
local starterId = Team.GetTeam(b)[1].id
eq(Team.GetTeam(b)[1].speciesId, "Spoutle")
choose(b, 2, "Plazadillo")
eq(#live[b].starters.choices, 1, "level1 cannot claim second")
live[b].playerTotalXp = xp(10)
choose(b, 2, "Plazadillo")
eq(#live[b].starters.choices, 2)
commit()
eq(live[b].capsules, 3)
live[b].playerTotalXp = xp(20)
clock += 2
RemoteAdapter.Get("GetStarters").OnServerInvoke(b)
eq(#live[b].starters.choices, 3, "level20 automatically grants final starter")
commit()
local rejoined = Migration.Prepare(durable[b], timestamp)
eq(#rejoined.starters.choices, 3)
eq(rejoined.capsules, 3)
check(rejoined.animals[starterId] ~= nil)
choose(b, 1, "Glimmouse")
eq(#live[b].starters.choices, 3)
eq(live[b].capsules, 3)
-- Ledger capacity never prunes old receipts or re-admits old GUIDs.
Config.Commerce.maxReceipts = 1
act(a, { requestId = id(), kind = "buyCapsule", quantity = 1, priceVersion = "x" })
eq(last().reasonCode, "CAPACITY_REACHED")
eq(#saveQueue, 0)
act(a, buy)
eq(last().phase, "Committed")
eq(#saveQueue, 0)
print(
	`PASS {count} offline integration assertions (real services; synthetic engine/save adapters, no Studio/DataStore QA)`
)
