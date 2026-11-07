--!strict
-- Trade offer/confirmation state machine; actual transfers are disabled.
-- Requests and responses are validated/rate-limited; repeated Confirm is
-- idempotent. Even with Gameplay.trade.enabled flipped, execute cannot move
-- value or announce success until a durable two-profile coordinator exists.
-- See build/coder-offline-2026-11-04/HANDOFF.md for the remaining recovery gate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TradePolicy = require(script.Parent.TradePolicy)
local AnimalService = require(script.Parent.AnimalService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)

type AnimalRecord = AnimalService.AnimalRecord

type Session = {
	players: { Player }, -- exactly two
	offers: { [Player]: { string } }, -- animal ids
	ready: { [Player]: boolean },
	confirmed: { [Player]: boolean },
	countdownEndsAt: number?, -- os.clock()
	version: number, -- bumps on every change (cancels a running countdown)
	ended: boolean,
}

local TradeService = {}

local sessions: { [Player]: Session } = {}
local requests: { [Player]: { [Player]: number } } = {} -- target -> requester -> expires (os.clock)
local lastActionAt: { [Player]: number } = {}
local lastRespondAt: { [Player]: number } = {}
local lastRequestAt: { [Player]: number } = {}
local REQUEST_COOLDOWN = 2 -- seconds between requests from one player, to anyone

local function settings()
	return Config.Gameplay.trade
end

-- Why this player can't trade right now, or nil.
local function blocker(player: Player): string?
	local data = PlayerDataService.Get(player)
	if not data or not PlayerDataService.IsReady(player) then
		return "Your save is still loading."
	end
	if not settings().enabled then
		return "Trading is unavailable while save safety is being verified."
	end
	local reason = TradePolicy.PlayerReason(data, player.AccountAge, os.time())
	if reason then
		return reason
	end
	if player:GetAttribute("InBattle") then
		return "Finish your battle first."
	end
	return nil
end

local function otherOf(session: Session, player: Player): Player
	return if session.players[1] == player then session.players[2] else session.players[1]
end

local function petView(id: string)
	local record = AnimalService.Get(id)
	if not record then
		return nil
	end
	return {
		id = id,
		speciesId = record.speciesId,
		level = record.level,
		size = record.size,
	}
end

local function push(session: Session, note: string?)
	for _, player in session.players do
		local other = otherOf(session, player)
		local mine, theirs = {}, {}
		for _, id in session.offers[player] do
			table.insert(mine, petView(id))
		end
		for _, id in session.offers[other] do
			table.insert(theirs, petView(id))
		end
		Remotes.Get("TradeUpdate"):FireClient(player, {
			active = not session.ended,
			partner = other.DisplayName,
			mine = mine,
			theirs = theirs,
			myReady = session.ready[player] == true,
			theirReady = session.ready[other] == true,
			myConfirm = session.confirmed[player] == true,
			theirConfirm = session.confirmed[other] == true,
			countdown = if session.countdownEndsAt
				then math.max(0, session.countdownEndsAt - os.clock())
				else nil,
			note = note,
		})
	end
end

local function close(session: Session, note: string)
	if session.ended then
		return
	end
	session.ended = true
	for _, player in session.players do
		sessions[player] = nil
	end
	push(session, note)
end

local function changed(session: Session)
	session.version += 1
	session.ready = {}
	session.confirmed = {}
	session.countdownEndsAt = nil
end

-- A pet that may go into an offer: owned by the player and in their base.
local function tradable(player: Player, id: string): AnimalRecord?
	local record = AnimalService.Get(id)
	if record and record.ownerUserId == player.UserId and record.state == "InBase" then
		local data = PlayerDataService.Get(player)
		local reason = data and TradePolicy.PetReason(data, data.animals[id], record.speciesId, os.time())
		if not data or reason then
			NotifyService.Send(player, { text = reason or "Your save is still loading.", kind = "info" })
			return nil
		end
		return record
	end
	return nil
end

local function execute(session: Session)
	-- SEC-TRADE-01/02: there is NO safe two-profile commit implementation.
	-- This unconditional fence cannot be bypassed by flipping a feature flag.
	-- No ownership mutation, save enqueue or success notification is permitted.
	close(session, "Trading is unavailable until durable transfer recovery is verified.")
end

function TradeService.IsTrading(player: Player): boolean
	return sessions[player] ~= nil
end

local function onRequest(player: Player, targetUserId: unknown)
	if
		typeof(targetUserId) ~= "number"
		or targetUserId ~= targetUserId
		or targetUserId <= 0
		or targetUserId == math.huge
		or targetUserId % 1 ~= 0
		or sessions[player]
	then
		return
	end
	local now = os.clock()
	if now - (lastRequestAt[player] or -math.huge) < REQUEST_COOLDOWN then
		return
	end
	lastRequestAt[player] = now
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return
	end
	local reason = blocker(player)
	if reason then
		NotifyService.Send(player, { text = reason, kind = "info" })
		return
	end
	if sessions[target] then
		NotifyService.Send(player, { text = `{target.DisplayName} is already trading.`, kind = "info" })
		return
	end
	requests[target] = requests[target] or {}
	if (requests[target][player] or 0) > os.clock() then
		return -- already asked
	end
	requests[target][player] = os.clock() + settings().requestSeconds
	NotifyService.Send(target, {
		text = `{player.DisplayName} wants to trade with you.`,
		kind = "info",
		icon = "info",
		action = { label = "Accept", animalId = tostring(player.UserId), kind = "trade" },
	})
	NotifyService.Send(player, { text = `Trade request sent to {target.DisplayName}.`, kind = "info" })
end

local function onRespond(player: Player, requesterUserId: unknown)
	local now = os.clock()
	if now - (lastRespondAt[player] or -math.huge) < 1 then
		return
	end
	lastRespondAt[player] = now
	if
		typeof(requesterUserId) ~= "string"
		or #requesterUserId > 20
		or not string.match(requesterUserId, "^%d+$")
	then
		return
	end
	local requesterId = tonumber(requesterUserId)
	if not requesterId or requesterId <= 0 or requesterId == math.huge or requesterId % 1 ~= 0 then
		return
	end
	local requester = requesterId and Players:GetPlayerByUserId(requesterId)
	local pending = requests[player]
	if not requester or not pending or (pending[requester] or -math.huge) <= now then
		NotifyService.Send(player, { text = "That trade request expired.", kind = "info" })
		return
	end
	pending[requester] = nil
	if sessions[player] or sessions[requester] then
		NotifyService.Send(player, { text = "One of you is already trading.", kind = "info" })
		return
	end
	for _, who in { player, requester } do
		local reason = blocker(who)
		if reason then
			-- The reason is about `who`: they get it; the other side only learns
			-- that the trade can't start.
			NotifyService.Send(who, { text = reason, kind = "info" })
			if who ~= player then
				NotifyService.Send(
					player,
					{ text = `{who.DisplayName} can't trade right now.`, kind = "info" }
				)
			end
			return
		end
	end
	local session: Session = {
		players = { requester, player },
		offers = { [requester] = {}, [player] = {} },
		ready = {},
		confirmed = {},
		countdownEndsAt = nil,
		version = 0,
		ended = false,
	}
	sessions[player] = session
	sessions[requester] = session
	push(session, "Add pets from your base. Both press Ready, then Confirm.")
end

local function onAction(player: Player, action: unknown)
	local session = sessions[player]
	if not session or session.ended or typeof(action) ~= "table" then
		return
	end
	local now = os.clock()
	if now - (lastActionAt[player] or 0) < 0.15 then
		return
	end
	lastActionAt[player] = now
	local kind = (action :: any).kind
	local offer = session.offers[player]

	if kind == "add" or kind == "remove" then
		local id = (action :: any).id
		if typeof(id) ~= "string" or #id == 0 or #id > 128 then
			return
		end
		local index = table.find(offer, id)
		if kind == "add" then
			if index or #offer >= settings().maxPetsPerSide or not tradable(player, id) then
				return
			end
			table.insert(offer, id)
		elseif index then
			table.remove(offer, index)
		else
			return
		end
		changed(session)
		push(session, nil)
	elseif kind == "ready" then
		session.ready[player] = not session.ready[player]
		session.version += 1 -- cancels a running countdown
		session.confirmed = {}
		session.countdownEndsAt = nil
		push(session, nil)
	elseif kind == "confirm" then
		local other = otherOf(session, player)
		if not (session.ready[player] and session.ready[other]) then
			return
		end
		if session.confirmed[player] then
			return
		end -- repeated Confirm preserves the shown deadline
		session.confirmed[player] = true
		if session.confirmed[other] then
			session.countdownEndsAt = now + settings().countdownSeconds
			local version = session.version
			task.delay(settings().countdownSeconds, function()
				if
					not session.ended
					and session.version == version
					and session.countdownEndsAt
					and os.clock() >= session.countdownEndsAt
				then
					execute(session)
				end
			end)
		end
		push(session, nil)
	elseif kind == "cancel" then
		close(session, `{player.DisplayName} cancelled the trade.`)
	end
end

function TradeService.Start()
	Remotes.Get("TradeRequest").OnServerEvent:Connect(onRequest)
	Remotes.Get("TradeRespond").OnServerEvent:Connect(onRespond)
	Remotes.Get("TradeAction").OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			close(session, `{player.DisplayName} left the server.`)
		end
		requests[player] = nil
		lastActionAt[player] = nil
		lastRequestAt[player] = nil
		lastRespondAt[player] = nil
		for _, pending in requests do
			pending[player] = nil
		end
	end)
end

return TradeService
