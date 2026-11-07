--!strict
-- Server bootstrap. Services are added here, in order, milestone by milestone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Services = script.Parent.Services
local startOrder = {
	require(Services.NotifyService),
	require(Services.MapPolishService),
	require(Services.BattlePresentationService),
	require(Services.PlayerStateService),
	require(Services.BaseService),
	require(Services.ZoneService),
	require(Services.AnimalService),
	require(Services.CarryService),
	require(Services.IndexService),
	require(Services.HomeService),
	require(Services.TeamService),
	require(Services.TabletService),
	require(Services.StarterService),
	require(Services.HudCommerceService),
	require(Services.BattleService),
	require(Services.WorldInteractionService),
	require(Services.TradeService),
	require(Services.LeaderboardService),
	require(Services.ResearchService),
	require(Services.DayCycleService),
	require(Services.ProgressionService),
	require(Services.DebugService), -- Studio + Debug.enabled only
	require(Services.PlayerDataService), -- registers loads after all restore/save hooks
}

for _, service in startOrder do
	service.Start()
end

print(`[FreeAPet] Server started. Debug = {Config.Debug.enabled}`)
