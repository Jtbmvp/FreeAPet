local assertions = 0
local function check(condition, message)
	assertions += 1
	assert(condition, message or "Assertion failed")
end
local function eq(actual, expected, message)
	check(
		actual == expected,
		(message or "Unexpected value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected)
	)
end
local function close(actual, expected, message)
	check(math.abs(actual - expected) < 0.000001, message)
end
local function count(t)
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end
local Config = load("ReplicatedStorage.Shared.Config")
local Math = load("ReplicatedStorage.Shared.ProgressionMath")
local BattleMath = load("ReplicatedStorage.Shared.BattleMath")
local AnimalMath = load("ReplicatedStorage.Shared.AnimalMath")
local Migration = load("ServerScriptService.Server.Services.ProfileMigration")
for level = 1, 29 do
	check(Math.PetXpToNext(level + 1) > Math.PetXpToNext(level), "Pet curve must rise")
	check(Math.PlayerXpToNext(level + 1) > Math.PlayerXpToNext(level), "Player curve must rise")
end
eq(Math.PetXpToNext(1), 35)
eq(Math.PetXpToNext(15), 1225)
eq(Math.PetXpToNext(29), 4375)
eq(Math.PlayerState(259), 2)
eq(Math.PlayerState(260), 3)
eq(Math.PlayerState(839), 4)
eq(Math.PlayerState(840), 5)
eq(Math.ResearchLevel("IncomeBoost", 25), 27)
eq(Math.ResearchLevel("CarryCapacity", 3), 7)
eq(Math.ResearchLevel("MoveSpeed", 10), 23)
eq(Math.ResearchLevel("OfflineIncome", 10), 25)
eq(Math.ResearchLevel("Accelerator", 10), 28)
eq(Math.Stage(4).id, "Baby")
eq(Math.Stage(5).id, "Juvenile")
eq(Math.Stage(14).id, "Juvenile")
eq(Math.Stage(15).id, "Adult")
for level = 15, 100 do
	eq(Math.Scale(level), 1, "Adult must stop growing")
end
close(Math.Scale(1), 0.75)
close(Math.Scale(5), 0.88)
eq(BattleMath.Stats("AcornSquirrel", 2).hp, 44)
eq(BattleMath.Stats("AcornSquirrel", 2).attack, 49)
close(AnimalMath.ScaleFor(1, 1), 1)
close(AnimalMath.ValuePerSecond("AcornSquirrel", 1, 1, 1), 1)

local function pet(fields)
	local saved = {
		speciesId = "AcornSquirrel",
		size = 1,
		growth = 1,
		slot = 1,
		level = 1,
		xp = 7,
		hp = 0,
		origin = { ownerUserId = 123, ownerName = "Synthetic", capturedAt = 1, place = "Forest" },
	}
	for k, v in fields or {} do
		saved[k] = v
	end
	return saved
end
local original = {
	schemaVersion = 1,
	cash = 100,
	baseSlots = 2,
	lastOnlineAt = 6400,
	animals = {
		a = pet(),
		b = pet({ away = true, slot = 2 }),
		c = pet({ equipped = true, slot = 2 }),
		d = pet({ speciesId = "UninstalledSpecies", slot = 1 }),
	},
	research = {
		IncomeBoost = { level = 1 },
		GrowthBoost = { level = 3, activeLevel = 4, finishesAt = timestamp + 50 },
		HeatProtection = { level = 2 },
	},
}
local migrated, report = Migration.Prepare(original, timestamp)
eq(count(migrated.animals), 4)
eq(original.schemaVersion, 1)
eq(original.animals.b.location, nil, "Input remains unchanged")
eq(migrated.schemaVersion, 3)
eq(migrated.animals.a.level, 1)
eq(migrated.animals.a.xp, 7)
eq(migrated.animals.a.hp, 0)
eq(migrated.animals.a.origin.ownerUserId, 123, "Origin is not the current owner")
eq(migrated.animals.a.legacyScaleFloor, 1)
eq(migrated.animals.a.location, "Base")
eq(migrated.animals.b.location, "Inventory")
eq(migrated.animals.b.slot, 0)
eq(migrated.animals.c.location, "Team")
eq(migrated.animals.d.location, "Inventory")
eq(report.unavailablePets, 1)
close(report.offlineCash, 936, "Only the old base pet earns at its legacy adult income")
close(migrated.cash, 1036)
eq(report.pendingRefunds, 2)
eq(migrated.research.GrowthBoost, nil)
eq(migrated.retiredResearch.GrowthBoost.progress.activeLevel, 4)
eq(migrated.retiredResearch.GrowthBoost.refundStatus, "PendingHistory")
local again, againReport = Migration.Prepare(migrated, timestamp)
eq(again.cash, migrated.cash, "Reentry cannot pay offline income twice")
eq(count(again.animals), 4)
eq(againReport.pendingRefunds, 2)
eq(again.animals.a.xp, 7)
eq(again.animals.a.hp, 0)
local future = { schemaVersion = 4, cash = 100, animals = { a = pet() } }
check(not pcall(Migration.Prepare, future, timestamp), "Future schemas are rejected")
eq(future.schemaVersion, 4)
eq(future.cash, 100)
local corrupt = { schemaVersion = 1, animals = { a = pet({ xp = 0 / 0 }) } }
check(not pcall(Migration.Prepare, corrupt, timestamp), "NaN is never persisted")
eq(corrupt.schemaVersion, 1)
local lots = { schemaVersion = 1, animals = {}, research = {}, baseSlots = 2, lastOnlineAt = 0 }
for i = 1, 250 do
	lots.animals[string.format("pet-%03d", i)] = pet({ slot = 1, away = i % 3 == 0, equipped = i % 4 == 0 })
end
local overflow = Migration.Prepare(lots, timestamp)
local team, base, stored = 0, 0, 0
for id, saved in overflow.animals do
	check(lots.animals[id] ~= nil)
	eq(saved.xp, 7)
	eq(saved.hp, 0)
	if saved.location == "Team" then
		team += 1
	elseif saved.location == "Base" then
		base += 1
	else
		stored += 1
	end
end
eq(count(overflow.animals), 250)
eq(team, 3)
check(base <= 2)
check(stored >= 245)
local overflowAgain = Migration.Prepare(overflow, timestamp)
for id, saved in overflow.animals do
	eq(overflowAgain.animals[id].location, saved.location)
	eq(overflowAgain.animals[id].slot, saved.slot)
end

-- Actual progression service: ownership checks, once-only rewards, claims and HP.
local datasets, records = {}, {}
local loadedHooks, saveHooks, prepareHooks = {}, {}, {}
local saves = 0
local committedDatas, commitRequests = {}, {}
local Data = {}
function Data.Get(p)
	return datasets[p]
end
function Data.IsReady(p)
	return datasets[p] ~= nil and p:GetAttribute("DataLoaded") == true
end
function Data.SaveNow()
	saves += 1
end
function Data.GetCommitted(p)
	return committedDatas[p]
end
function Data.SaveConfirmed(p, contains, callback)
	saves += 1
	table.insert(commitRequests, { player = p, contains = contains, callback = callback })
	return true
end
function Data.OnLoaded(fn)
	table.insert(loadedHooks, fn)
end
function Data.OnBeforeSave(fn)
	table.insert(saveHooks, fn)
end
function Data.OnPreparing(fn)
	table.insert(prepareHooks, fn)
end
function Data.OnReleasing() end
function Data.OnMessage() end
mocks["ServerScriptService.Server.Services.PlayerDataService"] = Data
local Animal = {}
function Animal.Get(id)
	return records[id]
end
function Animal.All()
	return records
end
function Animal.Rescale(record)
	record.rescaled = (record.rescaled or 0) + 1
end
function Animal.Store(record)
	record.model = nil
	record.carrier = nil
	record.state = "Inventory"
end
mocks["ServerScriptService.Server.Services.AnimalService"] = Animal
local Progression = load("ServerScriptService.Server.Services.ProgressionService")
Progression.Start()
local p = player(1)
Players.list = { p }
p:SetAttribute("DataLoaded", true)
local data = Migration.Prepare({ schemaVersion = 1, animals = {}, research = {} }, timestamp)
datasets[p] = data
for _, fn in loadedHooks do
	fn(p, data)
end
local function own(id, level, xp, hp, owner)
	local record = {
		id = id,
		speciesId = "AcornSquirrel",
		size = 1,
		level = level or 1,
		xp = xp or 0,
		hp = hp,
		ownerUserId = owner or p.UserId,
		state = "Following",
	}
	records[id] = record
	data.animals[id] = pet({ level = record.level, xp = record.xp })
	return record
end
local first = own("first", 1, 0, nil)
local fainted = own("fainted", 1, 34, 0)
local outsider = own("outsider", 1, 0, nil, 99)
eq(Progression.GrantPetXp(p, first, 35), 1)
eq(first.level, 2)
eq(first.hp, 40, "A full pet retains old absolute HP")
eq(first.xp, 0)
eq(Progression.GrantPetXp(p, fainted, 1), 1)
eq(fainted.hp, 0, "Fainted remains fainted")
eq(Progression.GrantPetXp(p, outsider, 1000), 0)
eq(outsider.xp, 0, "Other owners cannot gain through a claim")
local before = data.playerTotalXp
check(Progression.Outcome(p, "win", 3, { first, first, outsider }, "encounter-a"))
eq(data.playerTotalXp, before + 35)
eq(first.xp, 25, "Participant duplicates don't double XP")
eq(outsider.xp, 0)
check(not Progression.Outcome(p, "win", 3, { first }, "encounter-a"))
eq(data.playerTotalXp, before + 35)
local bench = own("bench", 1, 0, nil)
check(Progression.Outcome(p, "capture", 3, { first }, "encounter-b"))
eq(data.playerTotalXp, before + 59)
eq(bench.xp, 0, "No bench/captured-pet award")
eq(data.missions.CaptureOne.progress, 1)
eq(data.missions.WinThree.progress, 1)
check(not Progression.Outcome(p, "lost", 100, { first }, "loss"))
eq(data.playerTotalXp, before + 59)
clock += 1
check(not Progression.Claim(p, "CaptureOne", "outsider"))
check(not data.missions.CaptureOne.claimed)
clock += 1
check(not Progression.Claim(p, "CaptureOne", "absent"))
check(not data.missions.CaptureOne.claimed)
clock += 1
check(Progression.Claim(p, "CaptureOne", "first"))
eq(data.playerTotalXp, before + 159)
check(data.missions.CaptureOne.claimed)
clock += 1
check(not Progression.Claim(p, "CaptureOne", "first"))
eq(data.playerTotalXp, before + 159, "Claim is once-only")
local cap = own("cap", 29, 0, 0)
Progression.GrantPetXp(p, cap, 1000000)
eq(cap.level, 30)
eq(cap.hp, 0)
local capXp = cap.xp
Progression.GrantPetXp(p, cap, 500)
eq(cap.xp, capXp, "At cap no extra XP, legacy XP not erased")
p:SetAttribute("DataLoaded", false)
check(not Progression.Outcome(p, "win", 3, { first }, "not-ready"))
p:SetAttribute("DataLoaded", true)

-- Actual HomeService reserve paths: no full-base loose fallback, one dictionary.
local caught = 0
mocks["ServerScriptService.Server.Services.BaseService"] = {
	GetPlot = function()
		return nil
	end,
}
mocks["ServerScriptService.Server.Services.CarryService"] = {
	Take = function()
		return true
	end,
	GetCarried = function()
		return {}
	end,
}
mocks["ServerScriptService.Server.Services.IndexService"] = {
	MarkCaught = function()
		caught += 1
	end,
}
mocks["ServerScriptService.Server.Services.NotifyService"] = { Send = function() end }
mocks["ServerScriptService.Server.Services.PlayerStateService"] = { SetIncomePerSecond = function() end }
mocks["ReplicatedStorage.Shared.Format"] = { Short = tostring }
local Home = load("ServerScriptService.Server.Services.HomeService")
local newPet =
	{ id = "new", speciesId = "AcornSquirrel", size = 1, level = 4, xp = 3, hp = 0, state = "Battling" }
check(Home.ReserveAcquisition(p, newPet))
eq(data.animals.new.location, "Inventory")
eq(newPet.state, "Battling", "Commit doesn't move the arena model")
check(Home.PlaceBack(p, newPet))
eq(newPet.state, "Inventory")
eq(data.animals.new.hp, 0)
eq(newPet.ownerUserId, p.UserId)
eq(caught, 1)
check(Home.Receive(p, newPet))
eq(caught, 1, "Playback placement doesn't duplicate acquisition/index count")
Config.Progression.inventoryCapacity = 1
check(not Home.CanAcquire(p))
check(Home.CanAcquire(p, 0), "Legacy excess isn't confiscated")
Config.Progression.inventoryCapacity = 0
check(Home.CanAcquire(p))

-- Unconfirmed transported catches also reserve room before another acquisition.
Config.Progression.inventoryCapacity = 2
mocks["ServerScriptService.Server.Services.CarryService"].GetCarried = function()
	return { { ownerUserId = nil } }
end
check(not Home.CanAcquire(p), "Pending carried captures cannot oversubscribe a positive cap")
mocks["ServerScriptService.Server.Services.CarryService"].GetCarried = function()
	return {}
end
check(Home.CanAcquire(p))
Config.Progression.inventoryCapacity = 0

-- Actual PlayerDataService load pipeline with a synthetic ProfileStore adapter.
-- Verifies ordering and safe failure without real DataStore writes.
mocks["ServerScriptService.Server.Services.PlayerDataService"] = nil
local newProfiles, acquisition = {}, nil
local store = {}
function store:StartSessionAsync(_, options)
	if acquisition then
		return acquisition(options)
	end
	return table.remove(newProfiles, 1)
end
function store:MessageAsync()
	return true
end
local ProfileStore = {
	OnError = signal(),
	New = function(name, template)
		eq(name, "PlayerData_Studio")
		check(template.schemaVersion == 3)
		return store
	end,
}
mocks["ServerScriptService.Server.Vendor.ProfileStore"] = ProfileStore
local function profile(input, messages)
	local pr = {
		Data = input,
		OnSave = signal(),
		OnAfterSave = signal(),
		OnSessionEnd = signal(),
		LastSavedData = input,
		saved = 0,
		ended = 0,
		processed = 0,
	}
	function pr:AddUserId() end
	function pr:Reconcile()
		check(self.Data.schemaVersion == 3, "Migrate before reconcile")
	end
	function pr:IsActive()
		return self.ended == 0
	end
	function pr:Save()
		self.OnSave:Fire()
		self.saved += 1
	end
	function pr:EndSession()
		self.ended += 1
		self.OnSave:Fire()
	end
	function pr:MessageHandler(fn, sync)
		check(sync)
		for _, message in messages or {} do
			fn(message, function()
				self.processed += 1
			end)
		end
	end
	return pr
end
Players.list = {}
local PDS = load("ServerScriptService.Server.Services.PlayerDataService")
local order = {}
PDS.OnMessage(function(_, d, m)
	table.insert(order, "message")
	d.animals[m.animalId] = nil
end)
PDS.OnPreparing(function(_, d)
	table.insert(order, "prepare")
	d.animals.stale = nil
end)
PDS.OnLoaded(function(who, d)
	table.insert(order, "loaded")
	eq(who:GetAttribute("DataLoaded"), false)
	eq(d.animals.stolen, nil)
	eq(d.animals.stale, nil)
end)
PDS.OnBeforeSave(function(_, d)
	d.snapshotCount = (d.snapshotCount or 0) + 1
end)
PDS.Start()
local q = player(2)
local pr = profile({
	schemaVersion = 1,
	animals = { stolen = pet(), stale = pet(), kept = pet() },
	research = {},
	lastOnlineAt = 6400,
}, { { kind = "AnimalStolen", animalId = "stolen" } })
table.insert(newProfiles, pr)
Players.PlayerAdded:Fire(q)
eq(table.concat(order, ","), "message,prepare,loaded")
check(PDS.IsReady(q))
eq(pr.processed, 1)
eq(pr.saved, 1)
close(pr.Data.cash, 900, "Transferred/stolen pets never generate offline income")
local confirmations = 0
PDS.SaveConfirmed(q, function(saved)
	return saved.rewardRevision >= 1
end, function()
	confirmations += 1
end)
eq(confirmations, 0, "Save enqueue is not a durable acknowledgement")
pr.OnAfterSave:Fire({ rewardRevision = 0 })
eq(confirmations, 0)
pr.OnAfterSave:Fire({ rewardRevision = 1 })
eq(confirmations, 1)
pr.OnAfterSave:Fire({ rewardRevision = 1 })
eq(confirmations, 1, "Confirmation occurs once")
q.Parent = nil
Players.PlayerRemoving:Fire(q)
eq(pr.ended, 1)
eq(pr.Data.snapshotCount, 3, "Final snapshot runs once and isn't repeated by EndSession")
eq(PDS.Get(q), nil)
local f = player(3)
local fpr = profile({ schemaVersion = 4, animals = { a = pet() }, cash = 999 })
table.insert(newProfiles, fpr)
Players.PlayerAdded:Fire(f)
eq(fpr.Data.schemaVersion, 4)
eq(fpr.Data.cash, 999)
eq(fpr.ended, 1)
check(f.kicked ~= nil)
check(not PDS.IsReady(f))
local late = player(4)
local lateProfile = profile({ schemaVersion = 1, animals = {} })
acquisition = function(options)
	clock += 31
	for _, entry in delayed do
		if entry.seconds == 30 then
			entry.fn(table.unpack(entry.args))
		end
	end
	check(options.Cancel(), "Cancel observes global deadline")
	return lateProfile
end
Players.PlayerAdded:Fire(late)
eq(lateProfile.ended, 1)
eq(lateProfile.Data.schemaVersion, 1)
check(not PDS.IsReady(late))
check(late.kicked ~= nil)
acquisition = nil
local failed = player(5)
local bad = profile({ schemaVersion = 1, animals = { x = pet({ hp = -1 }) }, cash = 17 })
table.insert(newProfiles, bad)
Players.PlayerAdded:Fire(failed)
eq(bad.Data.schemaVersion, 1)
eq(bad.Data.cash, 17)
eq(bad.ended, 1)
check(not PDS.IsReady(failed))

-- Refund only the complete actual receipt ledger, including an active rank.
local receipts = {
	schemaVersion = 1,
	cash = 9,
	animals = {},
	research = {
		GrowthBoost = {
			level = 2,
			activeLevel = 3,
			finishesAt = timestamp + 10,
			paidByRank = { ["1"] = 11, ["2"] = 13, ["3"] = 17 },
		},
		LooseLimit = { level = 2, paidByRank = { ["1"] = 5 } },
	},
}
local refunded, refundReport = Migration.Prepare(receipts, timestamp)
eq(refunded.cash, 50)
eq(refunded.retiredResearch.GrowthBoost.refundedCash, 41)
eq(refunded.retiredResearch.GrowthBoost.refundStatus, "Refunded")
eq(refundReport.pendingRefunds, 1)
eq(refunded.retiredResearch.LooseLimit.refundStatus, "PendingHistory")
eq(Migration.Prepare(refunded, timestamp).cash, 50, "Paid refund cannot run twice")
eq(receipts.cash, 9)

-- Exercise the real RemoteEvent handlers, with UI attributes deliberately stale.
mocks["ServerScriptService.Server.Services.PlayerDataService"] = Data
local notices = {}
mocks["ServerScriptService.Server.Services.NotifyService"].Send = function(who, notice)
	table.insert(notices, { player = who, notice = notice })
end
local State = mocks["ServerScriptService.Server.Services.PlayerStateService"]
State.TrySpend = function(who, amount)
	local d = Data.Get(who)
	if not d or d.cash < amount then
		return false
	end
	d.cash -= amount
	return true
end
mocks["ReplicatedStorage.Shared.Format"].Duration = tostring
local Research = load("ServerScriptService.Server.Services.ResearchService")
local beforeHooks = #loadedHooks
Research.Start()
data.playerTotalXp, data.cash, data.research = 0, 10000, {}
p:SetAttribute("PlayerLevel", 30) -- an attribute is not server reward authority
clock += 1
RemoteAdapter.Get("StartResearch").OnServerEvent:Fire(p, "IncomeBoost")
eq(data.cash, 10000)
eq(data.research.IncomeBoost, nil, "Direct remote cannot bypass player level")
data.playerTotalXp = 260
clock += 1
RemoteAdapter.Get("StartResearch").OnServerEvent:Fire(p, "IncomeBoost")
eq(data.cash, 9950)
eq(data.research.IncomeBoost.activeLevel, 1)
eq(data.research.IncomeBoost.paidByRank["1"], 50)
local balance = data.cash
clock += 1
RemoteAdapter.Get("StartResearch").OnServerEvent:Fire(p, "IncomeBoost")
eq(data.cash, balance, "No second charge while busy")
data.research.IncomeBoost.finishesAt = timestamp - 1
data.playerTotalXp = 0 -- an old paid timer still completes below the new gate
loadedHooks[beforeHooks + 1](p, data)
eq(data.research.IncomeBoost.level, 1)
close(p:GetAttribute("IncomeMultiplier"), 1.04)
clock += 1
RemoteAdapter.Get("StartResearch").OnServerEvent:Fire(p, "IncomeBoost")
eq(data.cash, balance, "Rank 2 rechecks required player level")
clock += 1
RemoteAdapter.Get("StartResearch").OnServerEvent:Fire(p, "GrowthBoost")
eq(data.cash, balance, "Retired nodes cannot charge")

local Trade = load("ServerScriptService.Server.Services.TradeService")
Trade.Start()
local other = player(10)
other:SetAttribute("DataLoaded", true)
local otherData = Migration.Prepare({ schemaVersion = 1, animals = {}, research = {} }, timestamp)
datasets[other] = otherData
Players.list = { p, other }
Config.Gameplay.trade.enabled = true -- exercise policy beneath the production gate
data.playerTotalXp = 839
p:SetAttribute("TradeUnlocked", true)
p:SetAttribute("PlayerLevel", 30)
notices = {}
clock += 3
RemoteAdapter.Get("TradeRequest").OnServerEvent:Fire(p, other.UserId)
eq(#notices, 1)
eq(notices[1].player, p)
check(notices[1].notice.text:find("level 15") ~= nil)
data.playerTotalXp = 200000
clock += 3
RemoteAdapter.Get("TradeRequest").OnServerEvent:Fire(p, other.UserId)
check(#notices >= 3, "Eligible sender can request without trusting UI attrs")
otherData.playerTotalXp = 839
clock += 1
RemoteAdapter.Get("TradeRespond").OnServerEvent:Fire(other, tostring(p.UserId))
eq(#RemoteAdapter.Get("TradeUpdate").messages, 0, "Ineligible recipient cannot open a trade")
otherData.playerTotalXp = 200000
clock += 3
RemoteAdapter.Get("TradeRequest").OnServerEvent:Fire(p, other.UserId)
clock += 1
RemoteAdapter.Get("TradeRespond").OnServerEvent:Fire(other, tostring(p.UserId))
data.animals[first.id].origin = { capturedAt = timestamp - 86400 }
local updates = RemoteAdapter.Get("TradeUpdate").messages
check(updates[#updates].value.active, "Both valid players can open the session")
first.state = "InBase"
clock += 1
RemoteAdapter.Get("TradeAction").OnServerEvent:Fire(p, { kind = "add", id = first.id })
clock += 1
RemoteAdapter.Get("TradeAction").OnServerEvent:Fire(p, { kind = "ready" })
clock += 1
RemoteAdapter.Get("TradeAction").OnServerEvent:Fire(other, { kind = "ready" })
clock += 1
RemoteAdapter.Get("TradeAction").OnServerEvent:Fire(p, { kind = "confirm" })
clock += 1
RemoteAdapter.Get("TradeAction").OnServerEvent:Fire(other, { kind = "confirm" })
local countdown = delayed[#delayed]
eq(countdown.seconds, Config.Gameplay.trade.countdownSeconds)
otherData.playerTotalXp = 839 -- changed eligibility must cancel at final execution
clock += 3
countdown.fn(table.unpack(countdown.args))
eq(first.ownerUserId, p.UserId)
check(data.animals[first.id] ~= nil)
eq(otherData.animals[first.id], nil)
check(not updates[#updates].value.active, "Execution fence closes before any pet moves")
Config.Gameplay.trade.enabled = false

-- New rewards publish success only after a confirmed snapshot. Retrying a
-- pending mission never applies its grants a second time.
local playerLevelBeforeConfirm = p:GetAttribute("PlayerLevel")
local changes = RemoteAdapter.Get("ProgressionChanged").messages
eq(#changes, 0, "No reward success delta before durable acknowledgement")
local pendingView = RemoteAdapter.GetFunction("GetProgression").OnServerInvoke(p)
check(pendingView.pendingSave)
check(pendingView.missions.CaptureOne.pending)
check(not pendingView.missions.CaptureOne.claimed)
local committed = Migration.Prepare(data, timestamp)
committedDatas[p] = committed
for _, request in commitRequests do
	if request.contains(committed) then
		request.callback(committed)
	end
end
check(#changes > 0)
eq(
	p:GetAttribute("PlayerLevel"),
	playerLevelBeforeConfirm,
	"Confirmations do not overwrite newer live attributes"
)
clock += 1
local confirmedView = RemoteAdapter.GetFunction("GetProgression").OnServerInvoke(p)
check(not confirmedView.pendingSave)
check(not confirmedView.missions.CaptureOne.pending)
check(confirmedView.missions.CaptureOne.claimed)

-- An idle player must remain eligible for contextual interactions/healing.
services.Workspace = {}
mocks["ServerScriptService.Server.Services.TeamService"] = {}
mocks["ServerScriptService.Server.Services.ZoneService"] = {}
local Battle = load("ServerScriptService.Server.Services.BattleService")
p:SetAttribute("InBattle", nil)
check(not Battle.IsBusy(p))
p:SetAttribute("InBattle", true)
check(Battle.IsBusy(p))
p:SetAttribute("InBattle", nil)
check(not Battle.IsBattling(p))

print("PASS " .. assertions .. " progression/migration/server lifecycle assertions; synthetic adapters only")
