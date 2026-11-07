--!strict
-- Offline prototype: coefficients selected within Coder/Atlas delegated scope.
return {
	enabled = false, -- enable only after Sentinel + Studio verification
	rarityBase = { Starter = 25, Common = 25, Uncommon = 75, Rare = 200 },
	perLevel = 5,
	quoteSeconds = 30,
	keepLastPet = false, -- Nova contract did not approve a last-pet sale restriction
	-- Nova v1 uses client GUIDs, with no server admission cursor. Never prune
	-- these receipts: exhausted profiles fail closed until protocol v2 migration.
	maxReceipts = 512,
}
