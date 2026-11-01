--!strict
-- Server bootstrap. Services are added here, in order, milestone by milestone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Services = script.Parent.Services
local startOrder = {
	require(Services.NotifyService),
	require(Services.MapPolishService),
	require(Services.PlayerDataService),
	require(Services.PlayerStateService),
	require(Services.BaseService),
	require(Services.ZoneService),
	require(Services.AnimalService),
	require(Services.CarryService),
	require(Services.IndexService),
	require(Services.HomeService),
	require(Services.TeamService),
	require(Services.TabletService),
	require(Services.BattleService),
	require(Services.TradeService),
	require(Services.LeaderboardService),
	require(Services.GrowthService),
	require(Services.ExposureService),
	require(Services.ResearchService),
	require(Services.DayCycleService),
}

for _, service in startOrder do
	service.Start()
end

print(`[FreeAPet] Server started. Debug = {Config.Debug.enabled}`)
