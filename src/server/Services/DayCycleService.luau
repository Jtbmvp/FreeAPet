--!strict
-- Day cycle. At each reset every owned animal that is out of its base
-- (loose, or being carried by a thief) goes back to its owner's base.
-- Owners who left the server lose them for now; from M4 they go to the
-- saved base instead. The same happens when the server shuts down.
-- Publishes Workspace attributes DayNumber and DayEndsAt (server time).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local AnimalService = require(script.Parent.AnimalService)
local HomeService = require(script.Parent.HomeService)
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

local function returnAllHome()
	for _, record in AnimalService.All() do
		if record.ownerUserId and record.state ~= "InBase" and record.state ~= "Following" then
			if not HomeService.ReturnToBase(record) then
				local ownerOnline = Players:GetPlayerByUserId(record.ownerUserId) ~= nil
				if not ownerOnline then
					AnimalService.Remove(record) -- M4: write to the owner's saved base instead
				end
				-- Owner online but base full: it stays loose until the next reset.
			end
		end
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
	returnAllHome()
	NotifyService.Broadcast({
		text = "A new day begins! Loose animals went back home.",
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
	game:BindToClose(returnAllHome)
end

return DayCycleService
