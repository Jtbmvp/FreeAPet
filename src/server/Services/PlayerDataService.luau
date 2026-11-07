--!strict
-- Player saves through ProfileStore (session locking, autosave, saving on
-- leave and shutdown). Other services never touch the DataStore: they read
-- and write the live data table and register hooks:
--   OnLoaded(player, data)      after the profile is ready
--   OnBeforeSave(player, data)  right before every save (incl. the last one)
--   OnMessage(player, data, message) for messages sent while away
--   OnReleasing(player)          when the player leaves, after the final
--                                snapshot hooks ran (safe to clean up the world)
-- Studio uses a separate store so tests never touch live data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local ProfileStore = require(script.Parent.Parent.Vendor.ProfileStore)
local ProfileMigration = require(script.Parent.ProfileMigration)

local PlayerDataService = {}

local SCHEMA_VERSION = ProfileMigration.VERSION
local ACQUISITION_TIMEOUT = 30

local TEMPLATE: Types.PlayerData = {
	schemaVersion = SCHEMA_VERSION,
	cash = Config.Economy.startingCash,
	baseSlots = Config.Economy.baseStartingSlots,
	animals = {},
	research = {},
	index = {},
	capsules = 0,
	trades = { day = 0, count = 0 },
	bestIncome = 0,
	lastOnlineAt = 0,
	playerTotalXp = 0,
	rewardRevision = 0,
	missions = {},
	retiredResearch = {},
	starters = { choices = {}, capsulesGranted = false },
	commerce = { revision = 0, receipts = {} },
}

local storeName = if RunService:IsStudio() then "PlayerData_Studio" else "PlayerData"
local store = ProfileStore.New(storeName, TEMPLATE)

local profiles: { [Player]: any } = {}
-- Profiles whose final snapshot was taken on leave (the world is cleaned up after it).
local snapshotTaken: { [any]: boolean } = {}
local loadedHooks: { (Player, Types.PlayerData) -> () } = {}
local preparingHooks: { (Player, Types.PlayerData) -> () } = {}
local saveHooks: { (Player, Types.PlayerData) -> () } = {}
local messageHooks: { (Player, Types.PlayerData, Types.ProfileMessage) -> () } = {}
local releasingHooks: { (Player) -> () } = {}
local closing = false

local function keyFor(userId: number): string
	return `player_{userId}`
end

local function runSaveHooks(player: Player, data: Types.PlayerData)
	for _, hook in saveHooks do
		local ok, err = pcall(hook, player, data)
		if not ok then
			warn(`[PlayerData] save hook failed for {player.Name}: {err}`)
		end
	end
end

local function loadPlayer(player: Player)
	player:SetAttribute("DataLoaded", false)
	player:SetAttribute("ProfileLoadPhase", "Acquiring")
	local startedAt = os.clock()
	local abandoned = false
	-- Cancel cannot interrupt an in-flight DataStore request. Bound the UI wait,
	-- then end any session that arrives late; never steal a lock or load defaults.
	task.delay(ACQUISITION_TIMEOUT, function()
		if player:GetAttribute("ProfileLoadPhase") == "Acquiring" then
			abandoned = true
			if player.Parent == Players then
				player:Kick("Your save is taking too long to load. Please rejoin.")
			end
		end
	end)
	local profile = store:StartSessionAsync(keyFor(player.UserId), {
		Cancel = function()
			return abandoned
				or player.Parent ~= Players
				or closing
				or os.clock() - startedAt > ACQUISITION_TIMEOUT
		end,
	})
	if profile == nil then
		player:SetAttribute("ProfileLoadPhase", "Failed")
		-- Never treat a failed load as a new empty save.
		if player.Parent == Players then
			player:Kick("Your save could not be loaded. Please rejoin in a moment.")
		end
		return
	end

	if abandoned or closing or player.Parent ~= Players then
		profile:EndSession()
		return
	end

	-- Reject future versions before Reconcile can hide the original version.
	local original = profile.Data
	local version = original.schemaVersion or 1
	if type(version) ~= "number" or version > SCHEMA_VERSION then
		profile:EndSession() -- data is unchanged; never downgrade it
		player:Kick("This server cannot open your save version. Please rejoin a newer server.")
		return
	end
	profile:AddUserId(player.UserId)
	player:SetAttribute("ProfileLoadPhase", "Preparing")
	profiles[player] = profile
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your save was opened somewhere else. Please rejoin.")
		end
	end)
	profile.OnSave:Connect(function()
		-- After a leave the world is already cleaned up: keep the final snapshot.
		-- (On shutdown the session can end before PlayerRemoving, so the
		-- profile may already be gone from `profiles`; the hooks still run.)
		if not snapshotTaken[profile] and player:GetAttribute("DataLoaded") == true then
			runSaveHooks(player, profile.Data)
			profile.Data.lastOnlineAt = os.time()
		end
	end)

	local ok, preparationError = pcall(function()
		-- Process pending transfers before normalising, restoring or paying income.
		profile:MessageHandler(function(message, processed)
			for _, hook in messageHooks do
				hook(player, profile.Data, message :: Types.ProfileMessage)
			end
			processed() -- a failed hook remains retryable instead of acknowledging loss
		end, true)
		-- Keep successfully handled ownership removals even if preparation fails.
		for _, hook in preparingHooks do
			hook(player, profile.Data)
		end
		original = profile.Data
		local prepared, report = ProfileMigration.Prepare(original, os.time())
		profile.Data = prepared
		profile:Reconcile()
		player:SetAttribute("PendingResearchRefunds", report.pendingRefunds)
		player:SetAttribute("UnavailablePets", report.unavailablePets)
		player:SetAttribute("OfflineCashAwarded", report.offlineCash)
		for _, hook in loadedHooks do
			hook(player, profile.Data) -- ordered; Ready is published only after all hooks
		end
	end)
	if not ok then
		profile.Data = original
		profiles[player] = nil
		player:SetAttribute("ProfileLoadPhase", "Failed")
		warn(`[PlayerData] profile preparation failed: {preparationError}`)
		for _, hook in releasingHooks do
			pcall(hook, player)
		end
		profile:EndSession()
		if player.Parent == Players then
			player:Kick("Your save could not be prepared safely. Please rejoin.")
		end
		return
	end
	player:SetAttribute("ProfileLoadPhase", "Ready")
	player:SetAttribute("DataLoaded", true)
	profile:Save() -- migration, offline credit and watermark are one profile snapshot
end

local function releasePlayer(player: Player)
	local profile = profiles[player]
	local ready = player:GetAttribute("DataLoaded") == true
	player:SetAttribute("DataLoaded", false)
	profiles[player] = nil
	if profile and ready and not snapshotTaken[profile] then
		runSaveHooks(player, profile.Data)
		profile.Data.lastOnlineAt = os.time()
		snapshotTaken[profile] = true
	end
	for _, hook in releasingHooks do
		local ok, err = pcall(hook, player)
		if not ok then
			warn(`[PlayerData] releasing hook failed for {player.Name}: {err}`)
		end
	end
	if profile then
		profile:EndSession()
		task.delay(60, function()
			snapshotTaken[profile] = nil
		end)
	end
end

function PlayerDataService.Get(player: Player): Types.PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function PlayerDataService.IsReady(player: Player): boolean
	return profiles[player] ~= nil and player:GetAttribute("DataLoaded") == true
end

-- Read only. Used to distinguish pending rewards from a confirmed snapshot.
function PlayerDataService.GetCommitted(player: Player): Types.PlayerData?
	local profile = profiles[player]
	return if profile then profile.LastSavedData else nil
end

-- Subscribe BEFORE requesting the save. A successful enqueue is not a durable
-- acknowledgement. An unknown/late outcome is reconciled from the saved marker;
-- it never authorises a second grant. Lifecycle/timeout cleanup bounds listeners.
function PlayerDataService.SaveConfirmed(
	player: Player,
	contains: (Types.PlayerData) -> boolean,
	onCommitted: (Types.PlayerData) -> ()
): boolean
	local profile = profiles[player]
	if not profile or not PlayerDataService.IsReady(player) then
		return false
	end
	local savedConnection: any = nil
	local endedConnection: any = nil
	local done = false
	local function disconnect()
		if done then
			return
		end
		done = true
		if savedConnection then
			savedConnection:Disconnect()
		end
		if endedConnection then
			endedConnection:Disconnect()
		end
	end
	savedConnection = profile.OnAfterSave:Connect(function(saved: Types.PlayerData)
		if not done and contains(saved) then
			disconnect()
			if profiles[player] == profile and PlayerDataService.IsReady(player) then
				onCommitted(saved)
			end
		end
	end)
	endedConnection = profile.OnSessionEnd:Connect(disconnect)
	task.delay(60, disconnect) -- timeout is unresolved, not proof of failure
	profile:Save()
	return true
end

-- Saves right away (after an important change). Save hooks run first.
function PlayerDataService.SaveNow(player: Player)
	local profile = profiles[player]
	if profile and PlayerDataService.IsReady(player) then
		profile:Save()
	end
end

-- Ownership reconciliation runs before offline income or location migration.
function PlayerDataService.OnPreparing(hook: (Player, Types.PlayerData) -> ())
	table.insert(preparingHooks, hook)
end

function PlayerDataService.OnLoaded(hook: (Player, Types.PlayerData) -> ())
	table.insert(loadedHooks, hook)
end

function PlayerDataService.OnBeforeSave(hook: (Player, Types.PlayerData) -> ())
	table.insert(saveHooks, hook)
end

function PlayerDataService.OnReleasing(hook: (Player) -> ())
	table.insert(releasingHooks, hook)
end

function PlayerDataService.OnMessage(hook: (Player, Types.PlayerData, Types.ProfileMessage) -> ())
	table.insert(messageHooks, hook)
end

-- Delivers a message to a player's save, even if they are offline or in
-- another server. Yields; call from a spawned thread.
function PlayerDataService.SendMessage(userId: number, message: Types.ProfileMessage): boolean
	return store:MessageAsync(keyFor(userId), message)
end

function PlayerDataService.Start()
	ProfileStore.OnError:Connect(function(message, name, key)
		warn(`[PlayerData] ProfileStore error ({name}/{key}): {message}`)
	end)
	game:BindToClose(function()
		closing = true
	end)
	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(releasePlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
end

return PlayerDataService
