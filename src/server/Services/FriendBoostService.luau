--!strict
-- Prepared integration, intentionally absent from Main.startOrder until
-- Boss defines the rewarded system and policy. No rewards or save fields
-- are changed here. Friendship is resolved on the server, never claimed
-- by a client. Unknown/failed lookups return nil rather than a grant.

local Players = game:GetService("Players")

local FriendBoostMath = require(script.Parent.FriendBoostMath)

local FriendBoostService = {}

type State = { count: number?, revision: number, running: boolean }
local states: { [Player]: State } = {}
local started = false
local RETRY_SECONDS = 30

function FriendBoostService.GetCount(player: Player): number?
	local state = states[player]
	return if state then state.count else nil
end

function FriendBoostService.BonusPercent(
	player: Player,
	perFriendPercent: number,
	capPercent: number
): number?
	local count = FriendBoostService.GetCount(player)
	return if count ~= nil then FriendBoostMath.BonusPercent(count, perFriendPercent, capPercent) else nil
end

local refresh: (Player) -> ()
refresh = function(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.revision += 1
	state.count = nil
	player:SetAttribute("ServerFriendCountReady", false)
	player:SetAttribute("ServerFriendCount", nil)
	if state.running then
		return -- the worker will rerun for this newer membership revision
	end
	state.running = true
	task.spawn(function()
		while states[player] == state do
			local revision = state.revision
			local candidates = {}
			for other in states do
				if other ~= player then
					table.insert(candidates, other)
				end
			end
			local count = 0
			local complete = true
			for _, other in candidates do
				local ok, friends = pcall(player.IsFriendsWithAsync, player, other.UserId)
				if not ok then
					complete = false
				elseif friends then
					count += 1
				end
				if states[player] ~= state or state.revision ~= revision then
					break
				end
			end
			if states[player] ~= state then
				return -- left during a yielding API call
			end
			if state.revision ~= revision then
				continue -- a join/leave invalidated the snapshot
			end
			state.running = false
			if complete then
				state.count = count
				player:SetAttribute("ServerFriendCount", count)
				player:SetAttribute("ServerFriendCountReady", true)
			else
				task.delay(RETRY_SECONDS, function()
					if states[player] == state and state.revision == revision then
						refresh(player)
					end
				end)
			end
			return
		end
	end)
end

-- A future server social hook may refresh friendship changes in-place.
-- Player joins/leaves automatically invalidate every affected count.
function FriendBoostService.Refresh(player: Player)
	refresh(player)
end

local function refreshAll()
	for player in states do
		refresh(player)
	end
end

function FriendBoostService.Start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(function(player)
		states[player] = { revision = 0, running = false }
		refreshAll()
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
		refreshAll()
	end)
	for _, player in Players:GetPlayers() do
		states[player] = { revision = 0, running = false }
	end
	refreshAll()
end

return FriendBoostService
