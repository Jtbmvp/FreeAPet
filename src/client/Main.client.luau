--!strict
-- Client bootstrap. The client only sends intents and shows results.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Controllers = script.Parent.Controllers

require(Controllers.CashHud).Start()
require(Controllers.PromptFilter).Start()
require(Controllers.Notifications).Start()
require(Controllers.ExposureHud).Start()
require(Controllers.ForestFog).Start()
require(Controllers.ZoneMood).Start()
task.spawn(require(Controllers.PetAnimator).Start)
task.spawn(require(Controllers.Menu).Start)
task.spawn(require(Controllers.Leaderboard).Start)
task.spawn(require(Controllers.ReleaseButton).Start)
task.spawn(require(Controllers.BattleScreen).Start)
task.spawn(require(Controllers.DayHud).Start)

if Config.Debug.enabled then
	require(Controllers.DebugHud).Start()
end

print("[FreeAPet] Client started.")
