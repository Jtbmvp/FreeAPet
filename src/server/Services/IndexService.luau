--!strict
-- Index (collection): the species each player has seen up close and caught,
-- kept in the save (PlayerData.index). Seen = any pet of that species came
-- within SEEN_DISTANCE of the player. Caught = a pet of that species entered
-- their base as a new pet (caught, stolen, later traded). Read by the tablet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local AnimalService = require(script.Parent.AnimalService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local IndexService = {}

local SEEN_DISTANCE = 40 -- studs
local CHECK_SECONDS = 2

local function entryOf(data: Types.PlayerData, speciesId: string): Types.IndexEntry
	local entry = data.index[speciesId]
	if not entry then
		entry = {}
		data.index[speciesId] = entry
	end
	return entry
end

function IndexService.MarkCaught(player: Player, speciesId: string)
	local data = PlayerDataService.Get(player)
	if not data or not Config.Species[speciesId] then
		return
	end
	local entry = entryOf(data, speciesId)
	local first = (entry.caught or 0) == 0
	entry.seen = true
	entry.caught = (entry.caught or 0) + 1
	if first then
		NotifyService.Send(player, {
			text = `New in your Index: {Config.Species[speciesId].displayName}!`,
			kind = "success",
			icon = "rare",
		})
	end
end

local function markSeen(player: Player, data: Types.PlayerData, speciesId: string)
	local entry = entryOf(data, speciesId)
	if not entry.seen then
		entry.seen = true
		NotifyService.Send(player, {
			text = `New species spotted: {Config.Species[speciesId].displayName}! Check your Index.`,
			kind = "info",
			icon = "rare",
		})
	end
end

function IndexService.Start()
	-- Pets already owned count as caught (saves from before the Index).
	PlayerDataService.OnLoaded(function(_player: Player, data: Types.PlayerData)
		for _, saved in data.animals do
			if Config.Species[saved.speciesId] then
				local entry = entryOf(data, saved.speciesId)
				entry.seen = true
				entry.caught = math.max(entry.caught or 0, 1)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			local animals = AnimalService.All()
			for _, player in Players:GetPlayers() do
				local data = PlayerDataService.Get(player)
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if data and root then
					for _, record in animals do
						local entry = data.index[record.speciesId]
						local model = record.model
						if
							not (entry and entry.seen)
							and model
							and model.PrimaryPart
							and (model.PrimaryPart.Position - root.Position).Magnitude <= SEEN_DISTANCE
						then
							markSeen(player, data, record.speciesId)
						end
					end
				end
			end
		end
	end)
end

return IndexService
