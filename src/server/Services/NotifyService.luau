--!strict
-- Sends short on-screen messages (toasts) to one player or everyone.
-- Messages sent before a client is listening (right after joining: offline
-- earnings, thefts while away, the first rare spawn) are queued until the
-- client fires ClientReady.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local NotifyService = {}

local MAX_QUEUED = 10

local notify = Remotes.Get("Notify")
local ready: { [Player]: boolean } = {}
local queued: { [Player]: { Remotes.Notification } } = {}

function NotifyService.Send(player: Player, notification: Remotes.Notification)
	if player.Parent ~= Players then
		return
	end
	if ready[player] then
		notify:FireClient(player, notification)
		return
	end
	local queue = queued[player] or {}
	if #queue < MAX_QUEUED then
		table.insert(queue, notification)
	end
	queued[player] = queue
end

function NotifyService.SendUserId(userId: number?, notification: Remotes.Notification)
	local player = userId and Players:GetPlayerByUserId(userId)
	if player then
		NotifyService.Send(player, notification)
	end
end

function NotifyService.Broadcast(notification: Remotes.Notification)
	for _, player in Players:GetPlayers() do
		NotifyService.Send(player, notification)
	end
end

function NotifyService.Start()
	Remotes.Get("ClientReady").OnServerEvent:Connect(function(player)
		if ready[player] then
			return
		end
		ready[player] = true
		for _, notification in queued[player] or {} do
			notify:FireClient(player, notification)
		end
		queued[player] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
		queued[player] = nil
	end)
end

return NotifyService
