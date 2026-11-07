--!strict
-- Saved data shapes (schema version 3). Optional fields leave room for
-- mutations, cosmetics and multipliers: Profile:Reconcile() fills new
-- template fields on old saves, and schemaVersion drives real migrations.

-- Where a pet came from, kept forever (also through thefts and trades).
export type PetOrigin = {
	ownerUserId: number, -- who caught it first
	ownerName: string, -- their DisplayName at the time
	capturedAt: number, -- os.time()
	place: string, -- zone id where it was caught ("Forest", "Desert"...)
}

export type SavedAnimal = {
	speciesId: string,
	size: number, -- Config.Economy.sizeMin..sizeMax
	growth: number?, -- legacy input only; no clock-based growth
	slot: number, -- display pad, or 0 in the persistent reserve
	location: string?, -- Base | Team | Inventory after migration
	legacyScaleFloor: number?,
	legacyIncomeFloor: number?,
	unavailableReason: string?, -- preserved, never replaced/deleted if its content is unavailable
	teamOrder: number?, -- stable combat-ranked roster/follower order across rejoin
	equipped: boolean?, -- in the battle team, following its owner
	away: boolean?, -- out of the base (loose, carried, battling) at the last save: no offline income
	origin: PetOrigin?, -- nil for pets caught before origins were recorded
	level: number?, -- battle level (nil = 1)
	xp: number?, -- towards the next level
	hp: number?, -- current battle health (nil = full)
	lastTradedAt: number?, -- last durable transfer; legacy unknown is blocked from trading
	mutations: { string }?, -- post-prototype
}

export type ResearchProgress = {
	level: number, -- completed level
	activeLevel: number?, -- level being researched
	finishesAt: number?, -- os.time() timestamp
	paidByRank: { [string]: number }?, -- actual cash charged, never estimated from config
}

export type MissionProgress = { progress: number, claimed: boolean? }
export type RetiredResearch = {
	progress: ResearchProgress,
	refundStatus: string, -- PendingHistory | Refunded
	refundedCash: number?,
}

export type MissionView = {
	progress: number,
	target: number,
	claimed: boolean,
	pending: boolean,
	playerXp: number,
	petXp: number,
}

export type ProgressionView = {
	playerLevel: number,
	currentXp: number,
	xpToNext: number,
	maxLevel: number,
	researchRequired: number,
	tradeRequired: number,
	researchUnlocked: boolean,
	tradeUnlocked: boolean,
	missions: { [string]: MissionView },
	pendingSave: boolean,
	revision: number,
	committedRevision: number,
	sessionId: string?,
	sequence: number?,
	source: string?,
}

-- Index (collection): species the player has seen up close and caught.
export type IndexEntry = {
	seen: boolean?,
	caught: number?, -- times obtained (caught, stolen or traded in)
}

export type PlayerData = {
	schemaVersion: number,
	cash: number,
	baseSlots: number,
	animals: { [string]: SavedAnimal }, -- keyed by animal id
	research: { [string]: ResearchProgress },
	index: { [string]: IndexEntry }, -- by species id
	capsules: number, -- Pet Capsules owned
	trades: { day: number, count: number }, -- trades done today (day = os.time() // 86400)
	bestIncome: number, -- highest Cash/s reached, for the global leaderboard
	lastOnlineAt: number, -- os.time(), for offline income
	playerTotalXp: number,
	rewardRevision: number,
	missions: { [string]: MissionProgress },
	retiredResearch: { [string]: RetiredResearch },
	starters: { choices: { string }, capsulesGranted: boolean },
	commerce: { revision: number, receipts: { [string]: any } },
	multipliers: { [string]: number }?, -- post-prototype paid passes
}

-- Messages sent to a player's save while they are not in this server.
export type ProfileMessage = {
	kind: "AnimalStolen",
	animalId: string,
}

return {}
