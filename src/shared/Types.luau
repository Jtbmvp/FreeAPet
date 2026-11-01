--!strict
-- Saved data shapes (schema version 1). Optional fields leave room for
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
	growth: number, -- 0..1, only increases while loose
	slot: number, -- base slot it lives in (loose animals keep the slot they left)
	equipped: boolean?, -- in the battle team, following its owner
	origin: PetOrigin?, -- nil for pets caught before origins were recorded
	level: number?, -- battle level (nil = 1)
	xp: number?, -- towards the next level
	hp: number?, -- current battle health (nil = full)
	mutations: { string }?, -- post-prototype
}

export type ResearchProgress = {
	level: number, -- completed level
	activeLevel: number?, -- level being researched
	finishesAt: number?, -- os.time() timestamp
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
	multipliers: { [string]: number }?, -- post-prototype paid passes
}

-- Messages sent to a player's save while they are not in this server.
export type ProfileMessage = {
	kind: "AnimalStolen",
	animalId: string,
}

return {}
