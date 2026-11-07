--!strict
-- Pure eligibility; execution stays unavailable until a durable coordinator exists.
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Shared.Config)
local ProgressionMath = require(RS.Shared.ProgressionMath)
local Policy = {}
function Policy.PlayerReason(data: any, accountAge: number, now: number): string?
	local level = ProgressionMath.PlayerState(data.playerTotalXp)
	if level < Config.Progression.unlocks.Trade then
		return `Player level {Config.Progression.unlocks.Trade} is required to trade.`
	end
	if
		accountAge < Config.Gameplay.trade.minAccountAgeDays
		and level < Config.Gameplay.trade.youngAccountMinLevel
	then
		return "Accounts under 7 days old need player level above 20 to trade."
	end
	if data.trades.day == now // 86400 and data.trades.count >= Config.Gameplay.trade.maxPerDay then
		return "You reached today's trade limit."
	end
	return nil
end
function Policy.PetReason(data: any, saved: any, speciesId: string, now: number): string?
	local species = Config.Species[speciesId]
	if not species or not saved then
		return "This pet is unavailable."
	end
	if species.starter then
		return "Starter pets cannot be traded."
	end
	if
		species.rarity == "Rare"
		and ProgressionMath.PlayerState(data.playerTotalXp) < Config.Gameplay.trade.rareMinLevel
	then
		return `Player level {Config.Gameplay.trade.rareMinLevel} is required to trade rare pets.`
	end
	-- New ownership time must be recorded on every future durable transfer.
	-- Unknown legacy history is deliberately ineligible, never guessed as old enough.
	local acquired = saved.lastTradedAt or (saved.origin and saved.origin.capturedAt)
	if
		type(acquired) ~= "number"
		or acquired ~= acquired
		or math.abs(acquired) == math.huge
		or now - acquired < Config.Gameplay.trade.petCooldownSeconds
	then
		return "Pets need a verified 24-hour ownership period before trading."
	end
	return nil
end
return Policy
