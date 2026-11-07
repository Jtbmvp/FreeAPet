--!strict
-- All EXP, mission progress and claims originate from confirmed server events.
-- No reward quantities, levels or completion flags are accepted from clients.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage.Shared.Config)
local BattleMath = require(ReplicatedStorage.Shared.BattleMath)
local ProgressionMath = require(ReplicatedStorage.Shared.ProgressionMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local AnimalService = require(script.Parent.AnimalService)
local PlayerDataService = require(script.Parent.PlayerDataService)

type AnimalRecord = AnimalService.AnimalRecord
local ProgressionService = {}
local sequences: { [Player]: number } = {}
local sessionIds: { [Player]: string } = {}
local outcomes: { [Player]: { [string]: boolean } } = {}
local lastRequest: { [Player]: { [string]: number } } = {}
local petChanged: { (Player, AnimalRecord) -> () } = {}

local function view(data: Types.PlayerData, committed: Types.PlayerData?): Types.ProgressionView
	local level, xp, needed = ProgressionMath.PlayerState(data.playerTotalXp)
	local missions: { [string]: Types.MissionView } = {}
	for id, config in Config.Progression.missions do
		local saved = data.missions[id]
		local durable = committed and committed.missions and committed.missions[id]
		missions[id] = {
			progress = if saved then saved.progress else 0,
			target = config.target,
			claimed = durable ~= nil and durable.claimed == true,
			pending = saved ~= nil and saved.claimed == true and not (durable and durable.claimed == true),
			playerXp = config.playerXp,
			petXp = config.petXp,
		}
	end
	return {
		playerLevel = level,
		currentXp = xp,
		xpToNext = needed,
		maxLevel = Config.Progression.player.maxLevel,
		researchRequired = Config.Progression.unlocks.Research,
		tradeRequired = Config.Progression.unlocks.Trade,
		researchUnlocked = level >= Config.Progression.unlocks.Research,
		tradeUnlocked = level >= Config.Progression.unlocks.Trade,
		missions = missions,
		pendingSave = data.rewardRevision > (if committed then committed.rewardRevision or 0 else 0),
		revision = data.rewardRevision,
		committedRevision = if committed then committed.rewardRevision or 0 else 0,
	}
end

local function publish(player: Player, data: Types.PlayerData, source: string?)
	local snapshot = view(data, PlayerDataService.GetCommitted(player))
	if not source then
		-- A late confirmation must never roll the live attributes back to an older
		-- snapshot while a newer reward is still pending.
		player:SetAttribute("PlayerLevel", snapshot.playerLevel)
		player:SetAttribute("PlayerXp", snapshot.currentXp)
		player:SetAttribute("PlayerXpToNext", snapshot.xpToNext)
		player:SetAttribute("ResearchUnlocked", snapshot.researchUnlocked)
		player:SetAttribute("TradeUnlocked", snapshot.tradeUnlocked)
	end
	if source then
		sequences[player] = (sequences[player] or 0) + 1
		snapshot.sessionId = sessionIds[player]
		snapshot.sequence = sequences[player]
		snapshot.source = source
		Remotes.Get("ProgressionChanged"):FireClient(player, snapshot)
	end
end

local function commitReward(player: Player, data: Types.PlayerData, source: string)
	data.rewardRevision += 1
	local revision = data.rewardRevision
	publish(player, data) -- current authoritative state, no success animation yet
	PlayerDataService.SaveConfirmed(player, function(saved)
		return (saved.rewardRevision or 0) >= revision
	end, function(saved)
		publish(player, saved, source) -- success delta follows persistence
	end)
end

function ProgressionService.OnPetChanged(hook: (Player, AnimalRecord) -> ())
	table.insert(petChanged, hook)
end

function ProgressionService.RefreshPet(player: Player, record: AnimalRecord)
	-- Resize after battle presentation, never while fighters are positioned.
	if not player:GetAttribute("InBattle") then
		AnimalService.Rescale(record)
		for _, hook in petChanged do
			hook(player, record)
		end
	end
end

function ProgressionService.GrantPetXp(player: Player, record: AnimalRecord, amount: number): number
	local data = PlayerDataService.Get(player)
	local saved = data and data.animals[record.id]
	if
		not saved
		or record.ownerUserId ~= player.UserId
		or amount < 0
		or amount ~= amount
		or amount == math.huge
	then
		return 0
	end
	local previous = record.level
	if previous >= Config.Progression.pet.maxLevel then
		return 0
	end
	-- Materialise nil=full at the OLD maximum: a level never heals, even at 0 HP.
	local currentHp = record.hp or BattleMath.Stats(record.speciesId, previous).hp
	record.xp += amount
	while
		record.level < Config.Progression.pet.maxLevel
		and record.xp >= ProgressionMath.PetXpToNext(record.level)
	do
		record.xp -= ProgressionMath.PetXpToNext(record.level)
		record.level += 1
	end
	record.hp = math.min(currentHp, BattleMath.Stats(record.speciesId, record.level).hp)
	saved.level, saved.xp, saved.hp = record.level, record.xp, record.hp
	ProgressionService.RefreshPet(player, record)
	return record.level - previous
end

local function grantPlayer(data: Types.PlayerData, amount: number)
	data.playerTotalXp =
		math.max(data.playerTotalXp, math.min(data.playerTotalXp + amount, ProgressionMath.PlayerCapXp()))
end

-- A unique outcome token is generated/owned by the caller, never from a Remote.
-- The encounter is already resolved; a captured pet has already entered the save.
function ProgressionService.Outcome(
	player: Player,
	kind: string,
	targetLevel: number,
	participants: { AnimalRecord },
	token: string
): boolean
	local data = PlayerDataService.Get(player)
	if not data or not PlayerDataService.IsReady(player) or (kind ~= "win" and kind ~= "capture") then
		return false
	end
	local seen = outcomes[player] or {}
	if seen[token] then
		return false
	end
	seen[token], outcomes[player] = true, seen
	local win = Config.Progression.rewards.win
	local reward = Config.Progression.rewards.capture
	local petXp = win.petBase + win.petPerLevel * targetLevel
	local playerXp = win.playerBase + win.playerPerLevel * targetLevel
	if kind == "capture" then
		playerXp = reward.playerBase + reward.playerPerLevel * targetLevel
		petXp = math.floor(petXp * reward.petWinFactor)
	end
	grantPlayer(data, playerXp)
	local awarded: { [string]: boolean } = {}
	for _, record in participants do
		if not awarded[record.id] then
			awarded[record.id] = true
			ProgressionService.GrantPetXp(player, record, petXp)
		end
	end
	for id, mission in Config.Progression.missions do
		if mission.event == kind then
			local progress = data.missions[id] or { progress = 0 }
			if not progress.claimed then
				progress.progress = math.min(mission.target, progress.progress + 1)
			end
			data.missions[id] = progress
		end
	end
	commitReward(player, data, kind)
	return true
end

local function allowed(player: Player, kind: string): boolean
	local times = lastRequest[player] or {}
	local now = os.clock()
	if now - (times[kind] or -math.huge) < 0.3 then
		return false
	end
	times[kind], lastRequest[player] = now, times
	return PlayerDataService.IsReady(player)
end

function ProgressionService.Claim(player: Player, missionId: unknown, petId: unknown): boolean
	if
		type(missionId) ~= "string"
		or #missionId > 64
		or type(petId) ~= "string"
		or #petId > 64
		or not allowed(player, "claim")
		or player:GetAttribute("InBattle")
	then
		return false
	end
	local config = Config.Progression.missions[missionId]
	local data = PlayerDataService.Get(player)
	local saved = data and data.missions[missionId]
	local record = AnimalService.Get(petId)
	if
		not data
		or not config
		or not saved
		or saved.claimed
		or saved.progress < config.target
		or not record
		or record.ownerUserId ~= player.UserId
		or not data.animals[petId]
	then
		return false
	end
	-- No yields between the marker and both rewards; one profile snapshot.
	saved.claimed = true
	grantPlayer(data, config.playerXp)
	ProgressionService.GrantPetXp(player, record, config.petXp)
	commitReward(player, data, `mission:{missionId}`)
	return true
end

function ProgressionService.Start()
	PlayerDataService.OnLoaded(function(player, data)
		sessionIds[player] = HttpService:GenerateGUID(false)
		sequences[player], outcomes[player] = 0, {}
		publish(player, data) -- loading/migration never animates a new reward
	end)
	Remotes.GetFunction("GetProgression").OnServerInvoke = function(player)
		if not allowed(player, "view") then
			return nil
		end
		local data = PlayerDataService.Get(player)
		if not data then
			return nil
		end
		local snapshot = view(data, PlayerDataService.GetCommitted(player))
		snapshot.sessionId, snapshot.sequence = sessionIds[player], sequences[player]
		return snapshot
	end
	Remotes.Get("ClaimMission").OnServerEvent:Connect(ProgressionService.Claim)
	Players.PlayerRemoving:Connect(function(player)
		sequences[player], outcomes[player], lastRequest[player], sessionIds[player] = nil, nil, nil, nil
	end)
end

return ProgressionService
