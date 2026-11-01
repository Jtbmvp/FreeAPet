--!strict
-- Research tree (brief section 5): the client asks to start a node, the
-- server checks everything, takes the cash and stores a finish timestamp in
-- the save, so research keeps running while the player is offline. When a
-- timer runs out the level is written down and its effect applied.
--
-- Effects: player attributes read by other services (CarryCapacity,
-- IncomeMultiplier, GrowthMultiplier, Protection_<HazardId>), the
-- character's WalkSpeed, and values read straight from the save through
-- ResearchMath (releaseShieldSeconds, offlineIncomePercent, maxLoose,
-- researchTimeMultiplier).
-- The client sees progress through attributes: Research_<NodeId> = level,
-- ResearchActive = node id, ResearchFinishesAt = os.time() timestamp.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ResearchMath = require(ReplicatedStorage.Shared.ResearchMath)
local Types = require(ReplicatedStorage.Shared.Types)
local HomeService = require(script.Parent.HomeService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local PlayerStateService = require(script.Parent.PlayerStateService)

local ResearchService = {}

local lastRequestAt: { [Player]: number } = {}

local function applyWalkSpeed(player: Player, character: Model?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	-- In a battle the player stands still; BattleService restores the speed after.
	if humanoid and not player:GetAttribute("InBattle") then
		humanoid.WalkSpeed = player:GetAttribute("WalkSpeed") :: number
	end
end

-- Pushes every effect and the panel attributes from the save.
local function applyAll(player: Player, data: Types.PlayerData)
	local now = os.time()
	local progress = data.research
	player:SetAttribute(
		"CarryCapacity",
		ResearchMath.Value(progress, "carryCapacity", Config.Gameplay.carry.startingCapacity, now)
	)
	player:SetAttribute(
		"WalkSpeed",
		ResearchMath.Value(progress, "walkSpeed", Config.Gameplay.player.walkSpeed, now)
	)
	player:SetAttribute("IncomeMultiplier", ResearchMath.Value(progress, "incomeMultiplier", 1, now))
	player:SetAttribute("GrowthMultiplier", ResearchMath.Value(progress, "growthMultiplier", 1, now))
	for hazardId in Config.Exposure.hazards do
		player:SetAttribute(
			`Protection_{hazardId}`,
			ResearchMath.Value(progress, `protection.{hazardId}`, 1, now)
		)
	end
	applyWalkSpeed(player, player.Character)
	HomeService.RefreshIncome(player)

	for id in Config.Research do
		player:SetAttribute(`Research_{id}`, ResearchMath.LevelOf(progress, id, now))
	end
	local active, finishesAt = ResearchMath.Active(progress, now)
	player:SetAttribute("ResearchActive", active)
	player:SetAttribute("ResearchFinishesAt", finishesAt)
end

-- Writes down research whose timer ran out. Returns the finished node ids.
local function completeDue(data: Types.PlayerData): { string }
	local now = os.time()
	local finished = {}
	for id, entry in data.research do
		if entry.activeLevel and entry.finishesAt and entry.finishesAt <= now then
			entry.level = entry.activeLevel
			entry.activeLevel = nil
			entry.finishesAt = nil
			table.insert(finished, id)
		end
	end
	return finished
end

local function announce(player: Player, finished: { string }, data: Types.PlayerData)
	for _, id in finished do
		local node = Config.Research[id]
		if node then
			NotifyService.Send(player, {
				text = `Research complete: {node.displayName} Lv {data.research[id].level}!`,
				kind = "success",
				icon = "research",
			})
		end
	end
end

local function start(player: Player, nodeId: unknown)
	if typeof(nodeId) ~= "string" or #nodeId > 64 then
		return
	end
	local now = os.clock()
	if now - (lastRequestAt[player] or 0) < 0.5 then
		return
	end
	lastRequestAt[player] = now

	local node = Config.Research[nodeId]
	local data = PlayerDataService.Get(player)
	if not node or not data then
		return
	end
	local time = os.time()
	local progress = data.research
	local entry = progress[nodeId] or { level = 0 }
	local level = ResearchMath.LevelOf(progress, nodeId, time)
	local nextLevel = node.levels[level + 1]
	if not nextLevel then
		return -- already at max level
	end

	local running = 0
	for _, other in progress do
		if other.activeLevel and other.finishesAt and other.finishesAt > time then
			running += 1
		end
	end
	if running >= Config.Gameplay.research.maxActive then
		NotifyService.Send(
			player,
			{ text = "Wait for your current research to finish.", kind = "info", icon = "timer" }
		)
		return
	end
	if not ResearchMath.IsUnlocked(progress, nodeId, time) then
		NotifyService.Send(player, {
			text = "Research a node next to this one first.",
			kind = "info",
			icon = "locked",
		})
		return
	end
	if not PlayerStateService.TrySpend(player, nextLevel.cost) then
		NotifyService.Send(player, {
			text = `You need ${Format.Short(nextLevel.cost)} for this research.`,
			kind = "info",
			icon = "cash",
		})
		return
	end

	entry.level = level -- a finished-but-unwritten level counts
	entry.activeLevel = level + 1
	local duration = ResearchMath.Duration(progress, nodeId, level + 1, time)
	entry.finishesAt = time + duration
	progress[nodeId] = entry
	PlayerDataService.SaveNow(player) -- cash was spent
	applyAll(player, data)
	NotifyService.Send(player, {
		text = `Researching {node.displayName} Lv {level + 1}: ready in {Format.Duration(duration)}.`,
		kind = "info",
		icon = "research",
	})
end

function ResearchService.Start()
	Remotes.Get("StartResearch").OnServerEvent:Connect(start)

	PlayerDataService.OnLoaded(function(player: Player, data: Types.PlayerData)
		local finished = completeDue(data) -- finished while offline
		applyAll(player, data)
		announce(player, finished, data)
		player.CharacterAdded:Connect(function(character)
			applyWalkSpeed(player, character)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local data = PlayerDataService.Get(player)
				if data then
					local finished = completeDue(data)
					if #finished > 0 then
						applyAll(player, data)
						announce(player, finished, data)
					end
				end
			end
		end
	end)
end

return ResearchService
