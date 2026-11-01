--!strict
-- Trading pets between two players in the same server (OPEN #5, decided):
--   1. A asks B (tablet > Trade); B accepts from the notification.
--   2. Both add base pets to their offer. Any change clears both "Ready"
--      and "Confirm" marks.
--   3. Both press Ready, then both press Confirm: a countdown starts; any
--      change or cancel stops it.
--   4. When it ends the server checks everything again (owners, pets still
--      in the base, room in both bases, daily limit) and swaps the pets.
-- Accounts younger than minAccountAgeDays can't trade (not in Studio).
-- The client only sends intents ("TradeRequest", "TradeRespond",
-- "TradeAction") and shows "TradeUpdate".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local AnimalService = require(script.Parent.AnimalService)
local HomeService = require(script.Parent.HomeService)
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

local function settings()
	return Config.Gameplay.trade
end

local function today(): number
	return os.time() // 86400
end

local function tradesLeft(data: Types.PlayerData): number
	if data.trades.day ~= today() then
		data.trades.day = today()
		data.trades.count = 0
	end
	return settings().maxPerDay - data.trades.count
end

-- Why this player can't trade right now, or nil.
local function blocker(player: Player): string?
	local data = PlayerDataService.Get(player)
	if not data then
		return "Your save is still loading."
	end
	if not RunService:IsStudio() and player.AccountAge < settings().minAccountAgeDays then
		return `Accounts need to be {settings().minAccountAgeDays} days old to trade.`
	end
	if tradesLeft(data) <= 0 then
		return "You reached today's trade limit."
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
		growth = record.growth,
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
		return record
	end
	return nil
end

local function execute(session: Session)
	local a, b = session.players[1], session.players[2]
	-- Check everything again: anything off cancels the trade, nothing moves.
	local records: { [Player]: { AnimalRecord } } = { [a] = {}, [b] = {} }
	for _, player in session.players do
		local reason = blocker(player)
		if reason or not player.Parent then
			close(session, reason or "The other player left.")
			return
		end
		for _, id in session.offers[player] do
			local record = tradable(player, id)
			if not record then
				close(session, "A pet in the trade is no longer in its base. Trade cancelled.")
				return
			end
			table.insert(records[player], record)
		end
	end
	for _, player in session.players do
		local other = otherOf(session, player)
		local room = HomeService.FreeSlots(other) + #records[other]
		if room < #records[player] then
			close(session, `{other.DisplayName}'s base has no room for the pets. Trade cancelled.`)
			return
		end
	end
	if #records[a] == 0 and #records[b] == 0 then
		close(session, "Nothing to trade.")
		return
	end

	-- Swap: everything leaves both bases first, then moves in.
	for _, player in session.players do
		for _, record in records[player] do
			HomeService.GiveAway(player, record)
		end
	end
	for _, player in session.players do
		local other = otherOf(session, player)
		for _, record in records[player] do
			HomeService.Receive(other, record)
		end
	end
	for _, player in session.players do
		local data = PlayerDataService.Get(player) :: Types.PlayerData
		tradesLeft(data)
		data.trades.count += 1
		PlayerDataService.SaveNow(player)
	end
	close(session, "Trade complete!")
	for _, player in session.players do
		NotifyService.Send(player, {
			text = `Trade with {otherOf(session, player).DisplayName} complete!`,
			kind = "success",
			icon = "success",
		})
	end
end

local function onRequest(player: Player, targetUserId: unknown)
	if typeof(targetUserId) ~= "number" or sessions[player] then
		return
	end
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
	local requesterId = tonumber(requesterUserId)
	local requester = requesterId and Players:GetPlayerByUserId(requesterId)
	local pending = requests[player]
	if not requester or not pending or (pending[requester] or 0) < os.clock() then
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
			NotifyService.Send(player, { text = reason, kind = "info" })
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
		if typeof(id) ~= "string" then
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
		session.confirmed = {}
		session.countdownEndsAt = nil
		push(session, nil)
	elseif kind == "confirm" then
		local other = otherOf(session, player)
		if not (session.ready[player] and session.ready[other]) then
			return
		end
		session.confirmed[player] = true
		if session.confirmed[other] then
			session.countdownEndsAt = now + settings().countdownSeconds
			local version = session.version
			task.delay(settings().countdownSeconds, function()
				if not session.ended and session.version == version and session.countdownEndsAt then
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
	end)
end

return TradeService
