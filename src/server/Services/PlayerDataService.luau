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

local PlayerDataService = {}

local SCHEMA_VERSION = 1
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
}

local storeName = if RunService:IsStudio() then "PlayerData_Studio" else "PlayerData"
local store = ProfileStore.New(storeName, TEMPLATE)

local profiles: { [Player]: any } = {}
-- Profiles whose final snapshot was taken on leave (the world is cleaned up after it).
local snapshotTaken: { [any]: boolean } = {}
local loadedHooks: { (Player, Types.PlayerData) -> () } = {}
local saveHooks: { (Player, Types.PlayerData) -> () } = {}
local messageHooks: { (Player, Types.PlayerData, Types.ProfileMessage) -> () } = {}
local releasingHooks: { (Player) -> () } = {}
local closing = false

local function keyFor(userId: number): string
	return `player_{userId}`
end

local function migrate(data: Types.PlayerData)
	-- Future schema changes go here, one step per version.
	data.schemaVersion = SCHEMA_VERSION
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
	local startedAt = os.clock()
	local profile = store:StartSessionAsync(keyFor(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players or closing or os.clock() - startedAt > ACQUISITION_TIMEOUT
		end,
	})
	if profile == nil then
		-- Never treat a failed load as a new empty save.
		if player.Parent == Players then
			player:Kick("Your save could not be loaded. Please rejoin in a moment.")
		end
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	migrate(profile.Data)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

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
		if not snapshotTaken[profile] then
			runSaveHooks(player, profile.Data)
			profile.Data.lastOnlineAt = os.time()
		end
	end)

	for _, hook in loadedHooks do
		task.spawn(hook, player, profile.Data)
	end

	-- Messages (e.g. thefts while away) arrive now and while playing.
	profile:MessageHandler(function(message, processed)
		for _, hook in messageHooks do
			hook(player, profile.Data, message :: Types.ProfileMessage)
		end
		processed()
	end)
	player:SetAttribute("DataLoaded", true)
end

local function releasePlayer(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	if profile and not snapshotTaken[profile] then
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

-- Saves right away (after an important change). Save hooks run first.
function PlayerDataService.SaveNow(player: Player)
	local profile = profiles[player]
	if profile then
		profile:Save()
	end
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
