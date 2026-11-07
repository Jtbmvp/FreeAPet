--!strict
-- Battle formulas (docs/BATTLES.md), shared by the server (the only one that
-- decides anything) and the client (to show stats in the tablet).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local ProgressionMath = require(script.Parent.ProgressionMath)

export type Stats = { hp: number, attack: number, defense: number, speed: number }

local BattleMath = {}

local override: boolean? = nil

-- Battles are on in the published game only with Battle.enabled; in Studio
-- they are also on while Debug is, for testing (decision 3). The debug
-- "/battles" command can override this at runtime (server only).
function BattleMath.Enabled(): boolean
	if override ~= nil then
		return override
	end
	return Config.Battle.enabled or (RunService:IsStudio() and Config.Debug.enabled)
end

function BattleMath.SetOverride(value: boolean?)
	override = value
end

function BattleMath.Stats(speciesId: string, level: number): Stats
	local base = Config.Battle.species[speciesId]
	local growth = Config.Progression.pet.statGrowth
	return {
		hp = math.floor(base.hp * (1 + growth.hp * (level - 1))),
		attack = math.floor(base.attack * (1 + growth.attack * (level - 1))),
		defense = math.floor(base.defense * (1 + growth.defense * (level - 1))),
		speed = math.floor(base.speed * (1 + growth.speed * (level - 1))),
	}
end

function BattleMath.TypeMultiplier(attackType: string, defenderType: string): number
	local row = Config.Battle.typeChart[attackType]
	return row and row[defenderType] or 1
end

-- Damage of a move; `roll` is 0..1 (random on the server).
function BattleMath.Damage(
	power: number,
	attack: number,
	defense: number,
	typeMultiplier: number,
	roll: number
): number
	local random = Config.Battle.damageRandomMin + (1 - Config.Battle.damageRandomMin) * roll
	local damage = power
		* (attack / math.max(defense, 1))
		* Config.Battle.damageScale
		* typeMultiplier
		* random
	return math.max(1, math.ceil(damage))
end

function BattleMath.CaptureChance(rarity: string, hpFraction: number): number
	local capsule = Config.Battle.capsule
	local chance = (capsule.rarityBase[rarity] or 0.2) * (1.5 - hpFraction)
	return math.clamp(chance, capsule.minChance, capsule.maxChance)
end

function BattleMath.XpToNext(level: number): number
	return ProgressionMath.PetXpToNext(level)
end

function BattleMath.XpForWin(wildLevel: number): number
	local reward = Config.Progression.rewards.win
	return reward.petBase + reward.petPerLevel * wildLevel
end

-- Level range of a wild pet of this species.
function BattleMath.WildLevelRange(speciesId: string): (number, number)
	local species = Config.Species[speciesId]
	local byBiome = species.biome and Config.Battle.wildLevels[species.biome]
	local range = byBiome and byBiome[species.rarity] or { 1, 1 }
	return range[1], range[2]
end

return BattleMath
