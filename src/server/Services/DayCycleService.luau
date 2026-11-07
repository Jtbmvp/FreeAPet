--!strict
-- Day number and rare spawns. Owned pets are never released by a reset.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local AnimalService = require(script.Parent.AnimalService)
local NotifyService = require(script.Parent.NotifyService)

local DayCycleService = {}

local dayNumber = 0
local dayEndsAt = 0
local rng = Random.new()

-- Each day one Rare spawns in a random biome and the server is told where.
local function announceRare()
	local options = {}
	for _, species in Config.Species do
		if species.rarity == "Rare" then
			table.insert(options, species)
		end
	end
	if #options == 0 then
		return
	end
	local species = options[rng:NextInteger(1, #options)]
	if AnimalService.SpawnWild(species.biome, species.id, true) then
		NotifyService.Broadcast({
			text = `A Rare {species.displayName} appeared in the {species.biome}!`,
			kind = "success",
			icon = "rare",
		})
	end
end

local function startDay()
	dayNumber += 1
	dayEndsAt = Workspace:GetServerTimeNow() + Config.Gameplay.day.lengthSeconds
	Workspace:SetAttribute("DayNumber", dayNumber)
	Workspace:SetAttribute("DayEndsAt", dayEndsAt)
	if #Players:GetPlayers() > 0 then
		announceRare()
	else
		-- Empty server (first day): announce once someone is here to hear it
		-- (NotifyService queues it until their client is ready).
		task.spawn(function()
			Players.PlayerAdded:Wait()
			announceRare()
		end)
	end
end

function DayCycleService.ForceReset()
	NotifyService.Broadcast({
		text = "A new day begins!",
		kind = "info",
		icon = "day",
	})
	startDay()
end

function DayCycleService.Start()
	startDay()
	task.spawn(function()
		while true do
			task.wait(1)
			if Workspace:GetServerTimeNow() >= dayEndsAt then
				DayCycleService.ForceReset()
			end
		end
	end)
end

return DayCycleService
