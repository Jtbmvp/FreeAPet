-- Protocol risks: duplicate/late results, expired offers and timeout reconciliation.
local State = require("../../src/client/UI/HudActionState")
local count = 0
local function check(value, message)
	assert(value, message)
	count += 1
end
local function snapshot(revision)
	return { schemaVersion = 1, revision = revision, ready = true, capabilities = { sellPet = true } }
end
local function quote()
	return {
		petId = "pet-A",
		petLevel = 4,
		quoteId = "quote-1",
		currency = "Cash",
		rarityBase = 100,
		levelBonus = 30,
		totalCash = 130,
		expiresAt = 2000,
	}
end
local function result(id, kind, phase)
	return { requestId = id, kind = kind, phase = phase, committedRevision = 8 }
end
for _, value in { 0, 1, 5000 } do
	check(State.Integer(value), "Cash/count accepts nonnegative integer")
end
for _, value in { -1, 0.5, math.huge, -math.huge, 0 / 0, "100", false } do
	check(not State.Integer(value), "invalid Cash/count")
end
local s = State.New()
check(not State.Snapshot(s, {}), "incomplete snapshot")
check(State.Snapshot(s, snapshot(7)), "initial authoritative revision")
check(
	not State.Snapshot(s, snapshot(6)) and s.snapshot.revision == 7,
	"stale read cannot roll back current state"
)
local badSnapshot = snapshot(8)
badSnapshot.schemaVersion = 2
check(not State.Snapshot(s, badSnapshot), "unsupported protocol cannot enable controls")
check(State.Begin(s, "buy-1", "buyCapsule", { quantity = 1 }, 10), "start explicit buy intent")
check(not State.Begin(s, "sell-2", "sellPet", {}, 11), "no overlapping new intent")
check(
	State.Result(s, result("other", "buyCapsule", "Committed")) == "ignored" and s.pending ~= nil,
	"unrelated receipt cannot finish purchase"
)
check(
	State.Result(s, result("buy-1", "sellPet", "Committed")) == "ignored" and s.pending ~= nil,
	"wrong action receipt"
)
check(State.Timeout(s, "buy-1") and s.pending.phase == "Unknown", "timeout preserves unresolved request")
check(
	not State.Begin(s, "buy-2", "buyCapsule", { quantity = 1 }, 25),
	"timeout never permits duplicate purchase"
)
check(
	State.Result(s, result("buy-1", "buyCapsule", "Pending")) == "pending" and s.pending ~= nil,
	"pending save is not success"
)
local malformed = result("buy-1", "buyCapsule", "Committed")
malformed.committedRevision = 0 / 0
check(State.Result(s, malformed) == "ignored" and s.pending ~= nil, "durable revision required")
check(
	State.Result(s, result("buy-1", "buyCapsule", "Committed")) == "committed" and s.pending == nil,
	"late commit reconciles original request"
)
check(
	State.Result(s, result("buy-1", "buyCapsule", "Committed")) == "ignored",
	"duplicate commit is presented once"
)
check(not State.Timeout(s, "buy-1"), "old timeout cannot revive completed action")
check(State.Begin(s, "best-1", "equipBest", {}, 30), "new action after durable result")
check(not State.Timeout(s, "buy-1") and s.pending.requestId == "best-1", "old timer cannot lock newer intent")
check(
	State.Result(s, result("best-1", "equipBest", "Rejected")) == "rejected" and s.pending == nil,
	"definitive refusal clears intent"
)
check(State.ValidQuote(quote(), "pet-A", 1000), "fresh server offer")
check(not State.ValidQuote(quote(), "pet-B", 1000), "offer bound to pet ID")
check(not State.ValidQuote(quote(), "pet-A", 2000), "expiry boundary requires a fresh explicit confirmation")
for _, change in
	{
		{ field = "totalCash", value = 999 },
		{ field = "currency", value = "Robux" },
		{ field = "rarityBase", value = -1 },
		{ field = "levelBonus", value = 0 / 0 },
		{ field = "petLevel", value = 0 },
		{ field = "quoteId", value = "" },
		{ field = "expiresAt", value = math.huge },
		{ field = "totalCash", value = "130" },
	}
do
	local q = quote()
	q[change.field] = change.value
	check(not State.ValidQuote(q, "pet-A", 1000), `malformed offer {change.field}`)
end
check(State.Begin(s, "quote-req", "quoteSell", { petId = "pet-A" }, 40), "price check is a separate read")
local r = result("quote-req", "quoteSell", "Committed")
check(State.Result(s, r) == "ignored", "quote cannot claim a financial commit")
r.phase = "Quoted"
r.quote = quote()
r.quote.expiresAt = 900
check(
	State.Result(s, r) == "quoted" and s.pending == nil,
	"delayed expired quote finishes read without locking all actions"
)
check(not State.ValidQuote(r.quote, "pet-A", 1000), "delayed expired quote cannot sell")
check(
	State.Begin(s, "sell-1", "sellPet", { petId = "pet-A", quoteId = "quote-new" }, 50),
	"explicit sale intent"
)
check(
	State.Result(s, result("quote-req", "quoteSell", "Quoted")) == "ignored",
	"old price reply cannot finish sale"
)
check(State.Timeout(s, "sell-1"), "sale timeout retained")
check(
	State.Result(s, result("sell-1", "sellPet", "Committed")) == "committed",
	"late durable sale completes once"
)
check(State.Message("NOT_ENOUGH_CASH") == "You do not have enough Cash.", "actionable insufficient Cash copy")
check(
	State.Message("untrusted raw backend error") == State.Message("REJECTED"),
	"no raw backend error rendered"
)
print(`PASS {count} HUD action protocol assertions; no Roblox runtime claimed`)
