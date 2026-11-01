--!strict
-- Data for the tablet (Inventory + Index), built on request from the save
-- and the live animal records, so the client never holds anything it could
-- fake. Also lets the owner manage the battle team from the tablet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimalMath = require(ReplicatedStorage.Shared.AnimalMath)
local BattleMath = require(ReplicatedStorage.Shared.BattleMath)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local AnimalService = require(script.Parent.AnimalService)
local HomeService = require(script.Parent.HomeService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local TeamService = require(script.Parent.TeamService)

export type PetView = {
	id: string,
	speciesId: string,
	size: number,
	growth: number,
	state: string, -- "InBase" | "Following" | "Loose" | "Carried"
	cashPerSecond: number, -- what it earns in the base (0 while away or equipped)
	origin: Types.PetOrigin?,
	level: number,
	xp: number,
	xpToNext: number,
	hp: number,
	maxHp: number,
	moves: { string },
}

export type TabletView = {
	now: number, -- os.time() on the server, for ages
	pets: { PetView },
	index: { [string]: Types.IndexEntry },
}

local TabletService = {}

local REQUEST_COOLDOWN = 0.3
-- Separate cooldowns, so refreshing right after equipping still answers.
local lastRequestAt: { [string]: { [Player]: number } } = { view = {}, equip = {} }

local function tooSoon(player: Player, kind: string): boolean
	local now = os.clock()
	local last = lastRequestAt[kind]
	if now - (last[player] or 0) < REQUEST_COOLDOWN then
		return true
	end
	last[player] = now
	return false
end

local function view(player: Player): TabletView?
	local data = PlayerDataService.Get(player)
	if not data then
		return nil
	end
	local multiplier = player:GetAttribute("IncomeMultiplier")
	multiplier = if typeof(multiplier) == "number" then multiplier else 1
	local pets = {}
	for id, saved in data.animals do
		local record = AnimalService.Get(id)
		local growth = if record then record.growth else saved.growth
		local state = if record then record.state else "InBase"
		local level = if record then record.level else saved.level or 1
		local maxHp = BattleMath.Stats(saved.speciesId, level).hp
		local hp = if record then record.hp else saved.hp
		local moves = {}
		for _, move in Config.Battle.species[saved.speciesId].moves do
			table.insert(moves, move.name)
		end
		table.insert(pets, {
			id = id,
			speciesId = saved.speciesId,
			size = saved.size,
			growth = growth,
			state = state,
			cashPerSecond = if state == "InBase"
				then AnimalMath.ValuePerSecond(saved.speciesId, saved.size, growth) * multiplier
				else 0,
			origin = saved.origin,
			level = level,
			xp = if record then record.xp else saved.xp or 0,
			xpToNext = BattleMath.XpToNext(level),
			hp = math.min(hp or maxHp, maxHp),
			maxHp = maxHp,
			moves = moves,
		})
	end
	return { now = os.time(), pets = pets, index = data.index }
end

function TabletService.Start()
	Remotes.GetFunction("GetTablet").OnServerInvoke = function(player: Player)
		if tooSoon(player, "view") then
			return nil
		end
		return view(player)
	end

	Remotes.Get("SetEquipped").OnServerEvent
		:Connect(function(player: Player, animalId: unknown, equip: unknown)
			if
				typeof(animalId) ~= "string"
				or #animalId > 64
				or typeof(equip) ~= "boolean"
				or tooSoon(player, "equip")
			then
				return
			end
			local record = AnimalService.Get(animalId)
			if not record or record.ownerUserId ~= player.UserId then
				return
			end
			if equip then
				TeamService.Equip(player, record) -- checks state and team size, tells the player
			else
				TeamService.Unequip(player, record)
			end
		end)

	-- Base pets are managed from the Pets window only (no prompts on them).
	-- Picking one up needs you in your own base, like walking to it did.
	Remotes.Get("PickUpPet").OnServerEvent:Connect(function(player: Player, animalId: unknown)
		if typeof(animalId) ~= "string" or #animalId > 64 or tooSoon(player, "equip") then
			return
		end
		local record = AnimalService.Get(animalId)
		if not record or record.ownerUserId ~= player.UserId then
			return
		end
		if player:GetAttribute("InOwnBase") ~= true then
			NotifyService.Send(player, {
				text = "Go to your base to pick this pet up.",
				kind = "info",
				icon = "release",
			})
			return
		end
		HomeService.PickUp(player, record) -- checks state and the loose limit, tells the player
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt.view[player] = nil
		lastRequestAt.equip[player] = nil
	end)
end

return TabletService
