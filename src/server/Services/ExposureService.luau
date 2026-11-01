--!strict
-- Exposure meter. Each biome has its own meter per player that rises while
-- the player is inside that biome (slower with the right protection) and
-- recovers while they are elsewhere. At 100 the player is expelled to their
-- base and whatever they carry goes back to its home biome.
-- No invisible walls: anyone may go anywhere, they just cannot stay long.
-- Publishes player attributes: Exposure (0..100, current biome), ExposureHazard.
-- Protection per hazard: player attribute "Protection_<HazardId>", a
-- multiplier on the rise (1 = none; set by ResearchService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BaseService = require(script.Parent.BaseService)
local CarryService = require(script.Parent.CarryService)
local NotifyService = require(script.Parent.NotifyService)

local ExposureService = {}

local TICK_SECONDS = 0.25

-- meters[player][biomeId] = 0..maxValue
local meters: { [Player]: { [string]: number } } = {}
local warned: { [Player]: { [string]: boolean } } = {}

local function protectionMultiplier(player: Player, hazardId: string): number
	local multiplier = player:GetAttribute(`Protection_{hazardId}`)
	return if typeof(multiplier) == "number" then math.clamp(multiplier, 0, 1) else 1
end

local function expel(player: Player, biomeId: string)
	local carried = #CarryService.GetCarried(player)
	CarryService.ReturnAllHome(player)
	local plot = BaseService.GetPlot(player)
	local character = player.Character
	if plot and character then
		local spawn = plot:FindFirstChild("Spawn") :: BasePart
		character:PivotTo(spawn.CFrame * CFrame.new(0, 4, 0))
	end
	meters[player][biomeId] = 0
	warned[player][biomeId] = false
	local hazard = Config.Biomes[biomeId].hazard
	local reason = if hazard == "Heat" then "The heat was too much" else "You got lost in the dark"
	local lost = if carried > 0 then " Your animal ran back to its home." else ""
	NotifyService.Send(
		player,
		{ text = `{reason}! You were sent back to your base.{lost}`, kind = "warning" }
	)
end

local function step(player: Player, dt: number)
	local playerMeters = meters[player]
	if not playerMeters then
		return
	end
	local settings = Config.Exposure
	if player:GetAttribute("InBattle") then
		return -- paused during a battle (the arena protects the player)
	end
	local zone = player:GetAttribute("Zone")
	local inBiome = typeof(zone) == "string" and Config.Biomes[zone] ~= nil

	for biomeId, biome in Config.Biomes do
		local value = playerMeters[biomeId] or 0
		if inBiome and zone == biomeId then
			local hazard = settings.hazards[biome.hazard]
			value += hazard.risePerSecond * protectionMultiplier(player, biome.hazard) * dt
		else
			value -= settings.decayPerSecondOutside * dt
		end
		value = math.clamp(value, 0, settings.maxValue)
		playerMeters[biomeId] = value

		if value >= settings.warningAt and not warned[player][biomeId] then
			warned[player][biomeId] = true
			local text = if biome.hazard == "Heat"
				then "You're overheating! Head back soon."
				else "It's getting too dark! Head back soon."
			NotifyService.Send(player, {
				text = text,
				kind = "warning",
				icon = if biome.hazard == "Heat" then "heat" else "darkness",
			})
		elseif value < settings.warningAt then
			warned[player][biomeId] = false
		end

		if value >= settings.maxValue then
			expel(player, biomeId)
		end
	end

	-- Effects fade instead of vanishing: each biome meter is published, and
	-- the bar shows the highest one (the biome you left keeps draining).
	local highest, hazardId = 0, nil
	for biomeId, value in playerMeters do
		player:SetAttribute(`Exposure_{biomeId}`, value)
		if value > highest then
			highest, hazardId = value, Config.Biomes[biomeId].hazard
		end
	end
	if inBiome and playerMeters[zone :: string] >= highest then
		hazardId = Config.Biomes[zone :: string].hazard
	end
	player:SetAttribute("Exposure", highest)
	player:SetAttribute("ExposureHazard", hazardId)
end

local function reset(player: Player)
	meters[player] = {}
	warned[player] = {}
	player:SetAttribute("Exposure", 0)
end

-- Debug and tests: set a biome meter directly.
function ExposureService.Set(player: Player, biomeId: string, value: number)
	if meters[player] then
		meters[player][biomeId] = value
	end
end

function ExposureService.Start()
	local function onPlayerAdded(player: Player)
		reset(player)
		player.CharacterAdded:Connect(function()
			reset(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		meters[player] = nil
		warned[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			local dt = task.wait(TICK_SECONDS)
			for _, player in Players:GetPlayers() do
				step(player, dt)
			end
		end
	end)
end

return ExposureService
