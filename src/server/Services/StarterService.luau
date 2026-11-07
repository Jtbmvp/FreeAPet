--!strict
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Config = require(RS.Shared.Config)
local Remotes = require(RS.Shared.Remotes)
local BattleMath = require(RS.Shared.BattleMath)
local ProgressionMath = require(RS.Shared.ProgressionMath)
local PlayerData = require(script.Parent.PlayerDataService)
local AnimalService = require(script.Parent.AnimalService)
local TeamService = require(script.Parent.TeamService)
local HomeService = require(script.Parent.HomeService)
local Guard = require(script.Parent.PlayerMutationGuard)
local StarterService = {}
local lastRead: { [Player]: number } = {}
local lastAction: { [Player]: number } = {}
local function allowed(data: any): number
	local level = ProgressionMath.PlayerState(data.playerTotalXp)
	return if level >= Config.Progression.unlocks.Starter3
		then 3
		elseif level >= Config.Progression.unlocks.Starter2 then 2
		else 1
end
local function view(player: Player): any
	local data = PlayerData.Get(player)
	if not data or not PlayerData.IsReady(player) then
		return nil
	end
	local choices = {}
	for _, id in Config.Progression.starters.species do
		if not table.find(data.starters.choices, id) then
			table.insert(choices, id)
		end
	end
	return {
		choices = choices,
		nextIndex = #data.starters.choices + 1,
		available = #data.starters.choices < allowed(data),
		pending = Guard.IsBusy(player),
	}
end
local function grant(player: Player, data: any, speciesId: string)
	local index = #data.starters.choices + 1
	-- Grant + chosen-species marker + capsule marker share a single profile.
	local id = HttpService:GenerateGUID(false)
	local saved = {
		speciesId = speciesId,
		size = 1,
		slot = 0,
		location = "Inventory",
		level = 1,
		xp = 0,
		hp = BattleMath.Stats(speciesId, 1).hp,
		origin = {
			ownerUserId = player.UserId,
			ownerName = player.DisplayName,
			capturedAt = os.time(),
			place = "Starter",
		},
	}
	local record = assert(AnimalService.Restore(id, saved, player.UserId), "Starter content missing")
	data.animals[id] = saved
	table.insert(data.starters.choices, speciesId)
	if index == 1 and not data.starters.capsulesGranted then
		data.capsules += Config.Progression.starters.capsules
		data.starters.capsulesGranted = true
	end
	-- Inventory first: full base/team cannot discard a free starter.
	HomeService.Store(player, record)
	TeamService.Equip(player, record, true, true)
end
local function choose(player: Player, expectedIndex: unknown, speciesId: unknown)
	local now = os.clock()
	if now - (lastAction[player] or -math.huge) < 0.5 then
		return
	end
	lastAction[player] = now
	local data = PlayerData.Get(player)
	if not data or not PlayerData.IsReady(player) or player:GetAttribute("InBattle") then
		return
	end
	if
		typeof(expectedIndex) ~= "number"
		or expectedIndex ~= #data.starters.choices + 1
		or expectedIndex > allowed(data)
	then
		return
	end
	if
		typeof(speciesId) ~= "string"
		or not table.find(Config.Progression.starters.species, speciesId)
		or table.find(data.starters.choices, speciesId)
	then
		return
	end
	if not Guard.Acquire(player, "starter") then
		return
	end
	grant(player, data, speciesId)
	-- At level20 the final remaining starter is automatic after the second choice.
	if #data.starters.choices == 2 and allowed(data) == 3 then
		for _, id in Config.Progression.starters.species do
			if not table.find(data.starters.choices, id) then
				grant(player, data, id)
				break
			end
		end
	end
	local count = #data.starters.choices
	Remotes.Get("StarterResult"):FireClient(player, { phase = "Pending" })
	PlayerData.SaveConfirmed(player, function(saved)
		return #saved.starters.choices >= count and saved.starters.capsulesGranted
	end, function()
		Guard.Release(player, "starter")
		Remotes.Get("StarterResult"):FireClient(player, { phase = "Committed", snapshot = view(player) })
	end)
end
function StarterService.Start()
	Remotes.Get("ChooseStarter").OnServerEvent:Connect(choose)
	Remotes.GetFunction("GetStarters").OnServerInvoke = function(player)
		local now = os.clock()
		if now - (lastRead[player] or -math.huge) < 1 then
			return nil
		end
		lastRead[player] = now
		local data = PlayerData.Get(player)
		if
			data
			and PlayerData.IsReady(player)
			and #data.starters.choices == 2
			and allowed(data) == 3
			and not Guard.IsBusy(player)
		then
			for _, id in Config.Progression.starters.species do
				if not table.find(data.starters.choices, id) then
					choose(player, 3, id)
					break
				end
			end
		end
		-- A lost save callback can be reconciled from LastSavedData.
		if data and Guard.IsBusy(player) then
			local saved = PlayerData.GetCommitted(player)
			if
				saved
				and #saved.starters.choices == #data.starters.choices
				and #saved.starters.choices > 0
			then
				Guard.Release(player, "starter")
			end
		end
		return view(player)
	end
	PlayerData.OnReleasing(function(player)
		lastRead[player], lastAction[player] = nil, nil
		Guard.Forget(player)
	end)
end
return StarterService
