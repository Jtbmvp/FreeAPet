--!strict
-- Cash and income per player. Cash lives in the saved data
-- (PlayerDataService); income per second is computed live by HomeService.
-- The player list shows only Cash/s (the per-server ranking); the cash
-- total is shown by the client HUD from the "Cash" attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerDataService = require(script.Parent.PlayerDataService)

export type PlayerState = {
	incomePerSecond: number,
}

local PlayerStateService = {}

local states: { [Player]: PlayerState } = {}

local function publish(player: Player)
	local state = states[player]
	local data = PlayerDataService.Get(player)
	if not state then
		return
	end
	player:SetAttribute("Cash", if data then data.cash else 0)
	player:SetAttribute("IncomePerSecond", state.incomePerSecond)
	local leaderstats = player:FindFirstChild("leaderstats")
	local perSecond = leaderstats and leaderstats:FindFirstChild("Cash/s") :: NumberValue?
	if perSecond then
		perSecond.Value = math.floor(state.incomePerSecond * 10) / 10
	end
end

local function onPlayerAdded(player: Player)
	states[player] = { incomePerSecond = 0 }

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	-- A number (not text) so the player list sorts by it; Roblox formats it.
	local perSecond = Instance.new("NumberValue")
	perSecond.Name = "Cash/s"
	perSecond.Parent = leaderstats
	leaderstats.Parent = player

	publish(player)
end

function PlayerStateService.Get(player: Player): PlayerState?
	return states[player]
end

function PlayerStateService.GetCash(player: Player): number
	local data = PlayerDataService.Get(player)
	return if data then data.cash else 0
end

-- Adds (or with a negative amount, removes) cash. Ignored until the save
-- is loaded, and for NaN/infinite amounts so a bad value can never be saved.
function PlayerStateService.AddCash(player: Player, amount: number)
	local data = PlayerDataService.Get(player)
	if not data or amount ~= amount or math.abs(amount) == math.huge then
		return
	end
	data.cash = math.max(0, data.cash + amount)
	publish(player)
end

-- Takes `amount` cash only if the player has all of it. Returns whether it did.
function PlayerStateService.TrySpend(player: Player, amount: number): boolean
	local data = PlayerDataService.Get(player)
	if not data or amount ~= amount or amount < 0 or amount == math.huge or data.cash < amount then
		return false
	end
	data.cash -= amount
	publish(player)
	return true
end

function PlayerStateService.SetIncomePerSecond(player: Player, value: number)
	local state = states[player]
	if state and state.incomePerSecond ~= value then
		state.incomePerSecond = value
		publish(player)
	end
end

function PlayerStateService.Start()
	-- Every new character spawns with this speed (research and battles adjust it).
	StarterPlayer.CharacterWalkSpeed = Config.Gameplay.player.walkSpeed
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	PlayerDataService.OnLoaded(function(player)
		publish(player)
	end)
end

return PlayerStateService
