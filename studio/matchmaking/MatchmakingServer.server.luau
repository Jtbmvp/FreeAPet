-- MatchmakingServer (ServerScriptService): global 1v1 matchmaking across every public server.
--
-- Lobby servers
--   * MemoryStore sorted map "MM_Rooms_v1": one room per waiting player (2 seats max).
--   * MemoryStore sorted map "MM_Players_v1": a lock per player, so nobody sits in two rooms.
--   * MessagingService topic pushes room changes to every server; each server also polls
--     every few seconds, so a lost message never leaves anyone stuck.
--   * When a room fills, both servers show "Match Found!" and a 5 s countdown. The host's
--     server then reserves a private server (ReserveServer), writes the match record
--     ("MM_Matches_v1", keyed by the private server id) and flips the room to "teleporting";
--     each server teleports its own player with the same access code.
-- Arena server (a reserved server whose PrivateServerId has a match record)
--   * Waits for exactly the two expected players, freezes them on Spawn_Red / Spawn_Blue of
--     the existing colosseum (Workspace.MIDAS_PvPArena_Staging.Markers), counts down and
--     releases them. If one of them never arrives or leaves before the start, the match is
--     cancelled and the other goes back to a public lobby server.
-- Studio: ReserveServer/teleports do not work, so the arena flow runs in the same server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("MatchmakingShared"))
local PvpBattle = require(game:GetService("ServerScriptService"):WaitForChild("PvpBattle"))
local remotes = ReplicatedStorage:WaitForChild("MatchmakingRemotes")
local Action = remotes:WaitForChild("Action") :: RemoteEvent
local State = remotes:WaitForChild("State") :: RemoteEvent

local IS_STUDIO = RunService:IsStudio()
local NS = if IS_STUDIO then "studio_" else ""
local roomsMap = MemoryStoreService:GetSortedMap(NS .. "MM_Rooms_" .. Config.VERSION)
local playersMap = MemoryStoreService:GetSortedMap(NS .. "MM_Players_" .. Config.VERSION)
local matchesMap = MemoryStoreService:GetSortedMap(NS .. "MM_Matches_" .. Config.VERSION)
local TOPIC = NS .. Config.TOPIC
local JOB = if game.JobId ~= "" then game.JobId else ("studio-" .. HttpService:GenerateGUID(false))

-- server-to-server hook used by ArenaLinkServer's colosseum return portal in arena servers
local bindings = ServerStorage:FindFirstChild("MatchmakingBindings")
if not bindings then
	bindings = Instance.new("Folder")
	bindings.Name = "MatchmakingBindings"
	bindings.Parent = ServerStorage
end
local ReturnToLobby = bindings:FindFirstChild("ReturnToLobby") :: BindableEvent?
if not ReturnToLobby then
	local b = Instance.new("BindableEvent")
	b.Name = "ReturnToLobby"
	b.Parent = bindings
	ReturnToLobby = b
end

local function log(...)
	print("[Matchmaking]", ...)
end

-- MemoryStore / service call with retries (throttling and transient errors are common)
local function try(label: string, fn: (...any) -> ...any, ...): (boolean, ...any)
	local lastErr
	for attempt = 1, 3 do
		local result = table.pack(pcall(fn, ...))
		if result[1] then
			return table.unpack(result, 1, result.n)
		end
		lastErr = result[2]
		task.wait(0.35 * attempt)
	end
	warn("[Matchmaking] " .. label .. " failed: " .. tostring(lastErr))
	return false, lastErr
end

local function now(): number
	return os.time()
end

local function send(player: Player, payload: { [string]: any })
	if player.Parent == Players then
		State:FireClient(player, payload)
	end
end

local function publish(msg: { [string]: any })
	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(TOPIC, msg)
		end)
	end)
end

local function playerInfo(p: Player)
	return { id = p.UserId, name = p.Name, display = p.DisplayName }
end

-- userId -> JobId of the public server the player came from (filled by the arena)
local originOf: { [number]: string } = {}

-- Sends the player back to the server they came from (or any public server if that one is
-- gone or full). The game's BaseService spawns every arriving character on their own base.
local function returnToLobby(player: Player, reason: string?, origin: string?)
	if player.Parent ~= Players then
		return
	end
	origin = origin or originOf[player.UserId]
	send(player, { state = "returning", reason = reason })
	if IS_STUDIO then
		-- Studio: same server; a fresh character spawns on the player's base (BaseService)
		send(player, { state = "idle" })
		task.wait(0.5)
		if player.Parent == Players then
			player:LoadCharacter()
		end
		return
	end
	local function attempt(useOrigin: boolean): (boolean, any)
		return pcall(function()
			local options = Instance.new("TeleportOptions")
			if useOrigin and origin and origin ~= "" and not origin:find("^studio") then
				options.ServerInstanceId = origin
			end
			options:SetTeleportData({ mmReturn = Config.VERSION })
			TeleportService:TeleportAsync(game.PlaceId, { player }, options)
		end)
	end
	for n = 1, Config.TELEPORT_RETRIES do
		-- first try the original server, then any public server
		local ok, err = attempt(n == 1)
		if ok then
			return
		end
		warn("[Matchmaking] return teleport failed (" .. n .. "): " .. tostring(err))
		task.wait(2 * n)
		if player.Parent ~= Players then
			return
		end
	end
	player:Kick("Could not return to the lobby. Please rejoin.")
end

--------------------------------------------------------------------------------------------
-- ARENA SERVER
--------------------------------------------------------------------------------------------
local function freeze(character: Model, on: boolean)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.Anchored = on
	end
end

local function spawnCFrame(side: string): CFrame?
	local arena = workspace:FindFirstChild("MIDAS_PvPArena_Staging")
	local markers = arena and arena:FindFirstChild("Markers")
	local red = markers and markers:FindFirstChild("Spawn_Red") :: BasePart?
	local blue = markers and markers:FindFirstChild("Spawn_Blue") :: BasePart?
	if not (red and blue) then
		warn("[Matchmaking] Spawn_Red / Spawn_Blue markers missing in the colosseum")
		return nil
	end
	local me, other = red, blue
	if side == "blue" then
		me, other = blue, red
	end
	local pos = me.Position
	return CFrame.lookAt(pos, Vector3.new(other.Position.X, pos.Y, other.Position.Z)) + Vector3.new(0, 3.5, 0)
end

-- Battle centre in the colosseum, seen from the red side (-Z looks at the blue side), placed so
-- the two pets stand either side of Markers.Center.
local function battleCentre(): CFrame
	local arena = workspace:FindFirstChild("MIDAS_PvPArena_Staging")
	local markers = arena and arena:FindFirstChild("Markers")
	local centre = markers and markers:FindFirstChild("Center") :: BasePart?
	local red = markers and markers:FindFirstChild("Spawn_Red") :: BasePart?
	local blue = markers and markers:FindFirstChild("Spawn_Blue") :: BasePart?
	local c = if centre then centre.Position else Vector3.new(920, 0.5, 1900)
	local dir = if red and blue then (blue.Position - red.Position) * Vector3.new(1, 0, 1) else Vector3.new(-1, 0, 0)
	local layout = require(ReplicatedStorage.Shared.Config).Battle.layout
	local mid = (layout.mine + layout.foe) / 2
	return CFrame.lookAt(c, c + dir.Unit) * CFrame.new(-mid.X, 0, -mid.Z)
end

-- match = { id, players = { {id,name,display,side}, ... } }; present = players already here (Studio)
local function runArena(match, inServer: boolean)
	workspace:SetAttribute("MM_ArenaServer", true)
	workspace:SetAttribute("MM_MatchId", match.id)
	log("arena for match", match.id)

	local expected: { [number]: any } = {}
	for _, info in ipairs(match.players) do
		expected[info.id] = info
		if type(info.server) == "string" then
			originOf[info.id] = info.server
		end
	end
	local started, ended = false, false
	local connections = {}

	local function opponentOf(userId: number)
		for _, info in ipairs(match.players) do
			if info.id ~= userId then
				return info
			end
		end
		return nil
	end

	local function place(player: Player, character: Model)
		local info = expected[player.UserId]
		if not info then
			return
		end
		task.wait(0.25) -- let other spawn logic run first, then put the player on their mark
		if character.Parent == nil then
			return
		end
		local cf = spawnCFrame(info.side)
		if cf then
			character:PivotTo(cf)
		end
		freeze(character, not started)
	end

	local function hook(player: Player)
		if not expected[player.UserId] then
			if not inServer then
				player:Kick("This arena is reserved for a match.")
			end
			return
		end
		table.insert(connections, player.CharacterAdded:Connect(function(c)
			place(player, c)
		end))
		if player.Character then
			task.spawn(place, player, player.Character)
		end
		send(player, { state = "arena_wait", opponent = opponentOf(player.UserId) })
	end

	local function finish(reason: string, winnerId: number?)
		if ended then
			return
		end
		ended = true
		for _, c in ipairs(connections) do
			c:Disconnect()
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if expected[p.UserId] then
				if p.Character then
					freeze(p.Character, false)
				end
				send(p, { state = "arena_end", reason = reason, won = (winnerId == p.UserId) })
				task.delay(Config.ARENA_RETURN_DELAY, returnToLobby, p, reason)
			end
		end
		pcall(function()
			matchesMap:RemoveAsync(match.key or "")
			matchesMap:RemoveAsync("room_" .. tostring(match.id))
		end)
		if inServer then -- Studio simulation: this server is also the lobby
			workspace:SetAttribute("MM_ArenaServer", nil)
			workspace:SetAttribute("MM_MatchId", nil)
		end
	end

	if not inServer then
		table.insert(connections, Players.PlayerAdded:Connect(hook))
	end
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	local battling = false
	table.insert(connections, Players.PlayerRemoving:Connect(function(p)
		if not expected[p.UserId] or ended or battling then
			return -- during the battle PvpBattle turns a departure into a forfeit
		end
		if started then
			local other = opponentOf(p.UserId)
			finish("opponent_left", other and other.id)
		else
			finish("cancelled_left")
		end
	end))

	local function presentCount(): number
		local n = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if expected[p.UserId] and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
				n += 1
			end
		end
		return n
	end

	-- Studio test: one real player against a bot that copies their team
	local botTest = inServer and workspace:GetAttribute("MM_StudioBotBattle") == true
	local need = if botTest then 1 else 2

	-- wait for both players (and their characters)
	local deadline = os.clock() + Config.ARENA_LOAD_TIMEOUT
	while not ended and presentCount() < need and os.clock() < deadline do
		task.wait(0.5)
	end
	if ended then
		return
	end
	if presentCount() < need then
		finish("cancelled_noshow")
		return
	end

	-- both teams must be loaded (pets spawned next to their trainers)
	local here = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if expected[p.UserId] then
			table.insert(here, p)
		end
	end
	for _, p in ipairs(here) do
		if not PvpBattle.WaitForTeam(p, Config.ARENA_TEAM_TIMEOUT) then
			if ended then
				return
			end
			finish("cancelled_noteam")
			return
		end
	end

	task.wait(Config.ARENA_SETTLE)
	if ended then
		return
	end
	if presentCount() < need then
		finish("cancelled_left")
		return
	end

	for n = Config.ARENA_COUNTDOWN, 1, -1 do
		for _, p in ipairs(Players:GetPlayers()) do
			if expected[p.UserId] then
				send(p, { state = "arena_countdown", n = n, opponent = opponentOf(p.UserId) })
			end
		end
		task.wait(1)
		if ended then
			return
		end
	end
	if presentCount() < need then
		finish("cancelled_left")
		return
	end

	-- battle: the red player is side 1, the blue player side 2
	local red, blue
	for _, p in ipairs(here) do
		if expected[p.UserId].side == "red" then
			red = p
		else
			blue = p
		end
	end
	if botTest then
		red = red or blue
		blue = nil
	end
	started = true
	battling = true
	for _, p in ipairs(here) do
		if p.Character then
			freeze(p.Character, false)
		end
		send(p, { state = "arena_start", opponent = opponentOf(p.UserId), side = expected[p.UserId].side })
	end
	local ok, why = PvpBattle.Start(red, blue, battleCentre(), function(winner: Player?, _loser: Player?, reason: string)
		battling = false
		finish("battle_" .. reason, winner and winner.UserId)
	end, { bot = botTest })
	if not ok then
		battling = false
		warn("[Matchmaking] battle could not start: " .. tostring(why))
		finish("cancelled_noteam")
		return
	end
	log("battle started", match.id)
end

-- Reserved servers are only created by this matchmaking (the game has no other ReserveServer).
local isReserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
if isReserved then
	workspace:SetAttribute("MM_ArenaServer", true) -- hide the HUD button straight away
	-- the colosseum return portal (ArenaLinkServer) sends players to a public lobby server
	-- a return that fails after starting (origin server full or closed): any public server
	local returnFails: { [Player]: number } = {}
	TeleportService.TeleportInitFailed:Connect(function(p, result, message)
		returnFails[p] = (returnFails[p] or 0) + 1
		warn(("[Matchmaking] return failed for %s (%s): %s"):format(p.Name, tostring(result), tostring(message)))
		if returnFails[p] > Config.TELEPORT_RETRIES then
			p:Kick("Could not return to the lobby. Please rejoin.")
			return
		end
		task.wait(2)
		pcall(function()
			local options = Instance.new("TeleportOptions")
			options:SetTeleportData({ mmReturn = Config.VERSION })
			TeleportService:TeleportAsync(game.PlaceId, { p }, options)
		end)
	end)
	local returnEvent = ReturnToLobby :: BindableEvent
	returnEvent.Event:Connect(function(p: Player)
		if not PvpBattle.IsBattling(p) then
			returnToLobby(p)
		end
	end)
	Action.OnServerEvent:Connect(function(player, action)
		if action == "open" then
			send(player, { state = "arena_busy" })
		end
	end)
	task.spawn(function()
		-- 1) by private server id (written by the host's server right after ReserveServer)
		local ok, record = try("read match", function()
			return matchesMap:GetAsync(game.PrivateServerId)
		end)
		local key = game.PrivateServerId
		-- 2) fallback: the room id in the teleport data of the first arrival; the record itself
		--    is server-written, and runArena only admits the two players listed in it
		if not (ok and type(record) == "table") then
			local first = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
			local data = first:GetJoinData().TeleportData
			local roomId = type(data) == "table" and data.roomId
			if type(roomId) == "string" then
				key = "room_" .. roomId
				ok, record = try("read match by room", function()
					return matchesMap:GetAsync(key)
				end)
			end
		end
		if ok and type(record) == "table" then
			record.key = key
			runArena(record, false)
		else
			warn("[Matchmaking] reserved server without a match record: sending players back")
			for _, p in ipairs(Players:GetPlayers()) do
				task.spawn(returnToLobby, p, "no_match")
			end
			Players.PlayerAdded:Connect(function(p)
				returnToLobby(p, "no_match")
			end)
		end
	end)
	return -- an arena server never runs the lobby matchmaking
end

--------------------------------------------------------------------------------------------
-- LOBBY SERVER
--------------------------------------------------------------------------------------------
type Session = {
	roomId: string?,
	role: string?, -- "host" | "guest"
	uiOpen: boolean,
	teleporting: boolean,
	tpFails: number,
	lastAction: number,
	lastSent: string?,
}
local sessions: { [Player]: Session } = {}
local reserving: { [string]: boolean } = {}
local listCache: { any } = {}
local listDirty = true

local function session(p: Player): Session
	local s = sessions[p]
	if not s then
		s = { uiOpen = false, teleporting = false, tpFails = 0, lastAction = 0 }
		sessions[p] = s
	end
	return s
end

local function clearSession(p: Player)
	local s = sessions[p]
	if s then
		s.roomId = nil
		s.role = nil
		s.teleporting = false
		s.tpFails = 0
		s.lastSent = nil
	end
end

local function sendState(p: Player, payload: { [string]: any })
	-- avoid re-sending identical states every poll (keeps the client countdown smooth)
	local key = HttpService:JSONEncode(payload)
	local s = sessions[p]
	if s and s.lastSent == key then
		return
	end
	if s then
		s.lastSent = key
	end
	send(p, payload)
end

-- player locks ---------------------------------------------------------------------------
local function lockFresh(lock: any): boolean
	return type(lock) == "table" and type(lock.t) == "number" and now() - lock.t <= Config.LOCK_FRESH
end

-- Takes the player's global lock for roomId. Refuses if the player already sits in another
-- live room (any server).
local function acquireLock(p: Player, roomId: string): (boolean, string?)
	local ok, current = try("read lock", function()
		return playersMap:GetAsync(tostring(p.UserId))
	end)
	if not ok then
		return false, "Matchmaking is busy, try again."
	end
	if lockFresh(current) and current.roomId and current.roomId ~= roomId then
		local okRoom, room = try("read room", function()
			return roomsMap:GetAsync(current.roomId)
		end)
		if okRoom and type(room) == "table" and room.state ~= "cancelled"
			and (room.hostId == p.UserId or room.guestId == p.UserId) then
			return false, "You are already in a room."
		end
	end
	local observed = if type(current) == "table" then current.roomId else nil
	local okSet, result = try("write lock", function()
		return playersMap:UpdateAsync(tostring(p.UserId), function(old)
			local oldRoom = if type(old) == "table" then old.roomId else nil
			if lockFresh(old) and oldRoom ~= observed and oldRoom ~= roomId then
				return nil -- changed under us (another server): refuse
			end
			return { roomId = roomId, server = JOB, t = now() }
		end, Config.PLAYER_TTL)
	end)
	if not okSet or result == nil then
		return false, "You are already in a room."
	end
	return true
end

local function releaseLock(userId: number, roomId: string?)
	try("release lock", function()
		return playersMap:UpdateAsync(tostring(userId), function(old)
			if type(old) == "table" and roomId and old.roomId ~= roomId then
				return nil -- someone else's lock now: keep it
			end
			return { t = 0 }
		end, 1)
	end)
end

-- rooms ----------------------------------------------------------------------------------
local function roomView(room)
	return {
		id = room.id,
		state = room.state,
		host = { id = room.hostId, name = room.hostName, display = room.hostDisplay },
		guest = if room.guestId then { id = room.guestId, name = room.guestName, display = room.guestDisplay } else nil,
	}
end

local function refreshList()
	local ok, items = try("list rooms", function()
		return roomsMap:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)
	if not ok then
		return
	end
	local list = {}
	for _, item in ipairs(items) do
		local r = item.value
		if type(r) == "table" and r.state == "open" and not r.guestId then
			table.insert(list, { id = r.id, host = { id = r.hostId, name = r.hostName, display = r.hostDisplay }, age = now() - (r.created or now()) })
			if #list >= Config.MAX_ROOMS_SHOWN then
				break
			end
		end
	end
	listCache = list
	listDirty = false
end

local function pushList(p: Player)
	local s = session(p)
	if s.roomId then
		return
	end
	sendState(p, { state = "lobby", rooms = listCache, me = p.UserId })
end

local function pushListToBrowsers()
	for p, s in pairs(sessions) do
		if s.uiOpen and not s.roomId then
			pushList(p)
		end
	end
end

local function teleportToMatch(p: Player, room)
	local s = session(p)
	if s.teleporting then
		return -- never teleport the same player twice
	end
	s.teleporting = true
	sendState(p, { state = "teleporting", room = roomView(room) })
	if IS_STUDIO and not workspace:GetAttribute("MM_StudioRealTeleport") then
		return -- Studio: the arena runs in this server (see handleRoom)
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = room.accessCode
	options:SetTeleportData({ mm = Config.VERSION, roomId = room.id })
	for attempt = 1, Config.TELEPORT_RETRIES do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, { p }, options)
		end)
		if ok then
			return -- TeleportInitFailed handles asynchronous failures
		end
		warn("[Matchmaking] teleport call failed (" .. attempt .. "): " .. tostring(err))
		task.wait(1.5 * attempt)
		if p.Parent ~= Players then
			return
		end
	end
	s.teleporting = false
	releaseLock(p.UserId, s.roomId)
	clearSession(p)
	send(p, { state = "error", text = "Teleport failed. Please search again." })
end

TeleportService.TeleportInitFailed:Connect(function(p, result, message, placeId, options)
	local s = sessions[p]
	if not s or not s.teleporting then
		return
	end
	s.tpFails += 1
	warn(("[Matchmaking] teleport failed for %s (%s): %s"):format(p.Name, tostring(result), tostring(message)))
	if s.tpFails < Config.TELEPORT_RETRIES and p.Parent == Players then
		task.wait(2 * s.tpFails)
		pcall(function()
			TeleportService:TeleportAsync(placeId, { p }, options)
		end)
	else
		releaseLock(p.UserId, s.roomId)
		clearSession(p)
		send(p, { state = "error", text = "Teleport failed. Please search again." })
	end
end)

local function cancelRoom(roomId: string, reason: string)
	try("cancel room", function()
		return roomsMap:UpdateAsync(roomId, function(r)
			if type(r) ~= "table" or r.state == "teleporting" then
				return nil
			end
			r.state = "cancelled"
			r.reason = reason
			return r
		end, 30)
	end)
	publish({ t = "room", id = roomId })
	listDirty = true
end

-- host's server: verify both players, reserve the arena server, flip the room to teleporting
local function startMatch(room)
	if reserving[room.id] then
		return
	end
	reserving[room.id] = true
	task.spawn(function()
		-- the guest must still hold a fresh lock on this room
		local okLock, lock = try("read guest lock", function()
			return playersMap:GetAsync(tostring(room.guestId))
		end)
		if not okLock or not lockFresh(lock) or lock.roomId ~= room.id then
			log("guest gone before teleport, reopening", room.id)
			try("reopen room", function()
				return roomsMap:UpdateAsync(room.id, function(r)
					if type(r) ~= "table" or r.state ~= "full" then
						return nil
					end
					r.state = "open"
					r.guestId, r.guestName, r.guestDisplay, r.guestServer, r.fullAt = nil, nil, nil, nil, nil
					return r
				end, Config.ROOM_TTL)
			end)
			publish({ t = "room", id = room.id })
			reserving[room.id] = nil
			return
		end

		local code, psId
		if IS_STUDIO then
			code, psId = "STUDIO", "studio-" .. room.id
		else
			local okRes, c, id = try("reserve server", function()
				return TeleportService:ReserveServer(game.PlaceId)
			end)
			if not okRes then
				cancelRoom(room.id, "reserve_failed")
				reserving[room.id] = nil
				return
			end
			code, psId = c, id
		end

		local match = {
			id = room.id,
			players = {
				{ id = room.hostId, name = room.hostName, display = room.hostDisplay, side = "red", server = room.hostServer },
				{ id = room.guestId, name = room.guestName, display = room.guestDisplay, side = "blue", server = room.guestServer },
			},
		}
		local okMatch = try("write match", function()
			-- by private server id, plus a copy by room id (fallback lookup in the arena)
			if psId and psId ~= "" then
				matchesMap:SetAsync(psId, match, Config.MATCH_TTL)
			end
			return matchesMap:SetAsync("room_" .. room.id, match, Config.MATCH_TTL)
		end)
		if not okMatch then
			cancelRoom(room.id, "match_write_failed")
			reserving[room.id] = nil
			return
		end

		local okFlip, flipped = try("flip room", function()
			return roomsMap:UpdateAsync(room.id, function(r)
				if type(r) ~= "table" or r.state ~= "full" or r.accessCode then
					return nil -- someone left or it was already flipped: no duplicate teleport
				end
				r.state = "teleporting"
				r.accessCode = code
				r.psId = psId
				return r
			end, Config.ROOM_TTL)
		end)
		if okFlip and flipped then
			log("match ready", room.id)
			publish({ t = "room", id = room.id })
		end
		reserving[room.id] = nil
	end)
end

local studioArenas: { [string]: boolean } = {}

local function localMembers(room): { [string]: Player }
	local out = {}
	for p, s in pairs(sessions) do
		if s.roomId == room.id and p.Parent == Players then
			if room.hostId == p.UserId then
				out.host = p
			elseif room.guestId == p.UserId then
				out.guest = p
			end
		end
	end
	return out
end

local function handleRoom(roomId: string, room: any)
	-- every local player that believes they are in roomId
	local mine = {}
	for p, s in pairs(sessions) do
		if s.roomId == roomId then
			table.insert(mine, p)
		end
	end
	if #mine == 0 then
		return
	end

	if type(room) ~= "table" or room.state == "cancelled" then
		for _, p in ipairs(mine) do
			local s = session(p)
			if not s.teleporting then
				releaseLock(p.UserId, roomId)
				clearSession(p)
				send(p, { state = "cancelled", text = if s.role == "guest" then "The room was closed." else "Room closed." })
				if s.uiOpen then
					pushList(p)
				end
			end
		end
		return
	end

	-- a guest that is no longer in the room (host's server reopened it)
	for _, p in ipairs(mine) do
		local s = session(p)
		if s.role == "guest" and room.guestId ~= p.UserId and not s.teleporting then
			releaseLock(p.UserId, roomId)
			clearSession(p)
			send(p, { state = "cancelled", text = "Your opponent left. Search again." })
		end
	end

	local members = localMembers(room)
	if room.state == "open" then
		if members.host then
			sendState(members.host, { state = "waiting", room = roomView(room) })
		end
	elseif room.state == "full" then
		local remaining = math.max(0, (room.fullAt or now()) + Config.COUNTDOWN - now())
		for _, p in pairs(members) do
			sendState(p, { state = "found", room = roomView(room), remaining = remaining })
		end
		if members.host and remaining <= 0 then
			startMatch(room)
		elseif not members.host and now() > (room.fullAt or now()) + Config.COUNTDOWN + Config.FULL_STALE then
			cancelRoom(roomId, "host_gone") -- host server died
		end
	elseif room.state == "teleporting" then
		for _, p in pairs(members) do
			teleportToMatch(p, room)
		end
		-- Studio: no teleports, so the arena runs here with the local member(s); a member that
		-- sits in another test server never arrives, which exercises the no-show path
		if IS_STUDIO and (members.host or members.guest) and not studioArenas[roomId]
			and not workspace:GetAttribute("MM_StudioRealTeleport") then
			studioArenas[roomId] = true
			task.spawn(function()
				task.wait(1)
				local okM, match = try("read match", function()
					return matchesMap:GetAsync(room.psId)
				end)
				for _, p in pairs(members) do
					releaseLock(p.UserId, roomId)
					clearSession(p)
				end
				if okM and type(match) == "table" then
					match.key = room.psId
					runArena(match, true)
				end
			end)
		end
		if members.host then
			task.delay(20, function()
				pcall(function()
					roomsMap:RemoveAsync(roomId)
				end)
			end)
		end
	end
end

local function pollRoom(roomId: string)
	local ok, room = try("read room", function()
		return roomsMap:GetAsync(roomId)
	end)
	if ok then
		handleRoom(roomId, room)
	end
end

-- actions --------------------------------------------------------------------------------
local function createRoom(p: Player)
	local s = session(p)
	if s.roomId or s.teleporting then
		return
	end
	if not PvpBattle.HasTeam(p) then
		send(p, { state = "error", text = "Add a pet to your team first (Pets > Equip)." })
		return
	end
	local roomId = string.format("%012d_%d", now(), p.UserId)
	local okLock, err = acquireLock(p, roomId)
	if not okLock then
		send(p, { state = "error", text = err })
		return
	end
	local room = {
		id = roomId,
		state = "open",
		created = now(),
		hostId = p.UserId,
		hostName = p.Name,
		hostDisplay = p.DisplayName,
		hostServer = JOB,
	}
	local okSet = try("create room", function()
		return roomsMap:SetAsync(roomId, room, Config.ROOM_TTL)
	end)
	if not okSet then
		releaseLock(p.UserId, roomId)
		send(p, { state = "error", text = "Could not create the room. Try again." })
		return
	end
	if p.Parent ~= Players then
		cancelRoom(roomId, "host_left")
		return
	end
	s.roomId, s.role = roomId, "host"
	sendState(p, { state = "waiting", room = roomView(room) })
	publish({ t = "list" })
	listDirty = true
	log(p.Name, "created", roomId)
end

local function joinRoom(p: Player, roomId: any)
	local s = session(p)
	if s.roomId or s.teleporting or type(roomId) ~= "string" or #roomId > 64 then
		return
	end
	if not PvpBattle.HasTeam(p) then
		send(p, { state = "error", text = "Add a pet to your team first (Pets > Equip)." })
		return
	end
	local okLock, err = acquireLock(p, roomId)
	if not okLock then
		send(p, { state = "error", text = err })
		return
	end
	local okJoin, joined = try("join room", function()
		return roomsMap:UpdateAsync(roomId, function(r)
			if type(r) ~= "table" or r.state ~= "open" or r.guestId or r.hostId == p.UserId then
				return nil -- full, gone or own room: refuse atomically
			end
			r.guestId, r.guestName, r.guestDisplay, r.guestServer = p.UserId, p.Name, p.DisplayName, JOB
			r.state = "full"
			r.fullAt = now()
			return r
		end, Config.ROOM_TTL)
	end)
	if not okJoin or joined == nil then
		releaseLock(p.UserId, roomId)
		send(p, { state = "error", text = "That room is no longer available." })
		listDirty = true
		pushList(p)
		return
	end
	if p.Parent ~= Players then
		-- left while joining: give the seat back
		try("leave room", function()
			return roomsMap:UpdateAsync(roomId, function(r)
				if type(r) ~= "table" or r.guestId ~= p.UserId or r.state ~= "full" then
					return nil
				end
				r.state = "open"
				r.guestId, r.guestName, r.guestDisplay, r.guestServer, r.fullAt = nil, nil, nil, nil, nil
				return r
			end, Config.ROOM_TTL)
		end)
		releaseLock(p.UserId, roomId)
		return
	end
	s.roomId, s.role = roomId, "guest"
	log(p.Name, "joined", roomId)
	publish({ t = "room", id = roomId })
	publish({ t = "list" })
	handleRoom(roomId, joined)
end

local function leaveRoom(p: Player, why: string)
	local s = sessions[p]
	if not s or not s.roomId or s.teleporting then
		return
	end
	local roomId, role = s.roomId, s.role
	clearSession(p) -- first, so a poll running meanwhile does not report our own room as closed
	if role == "host" then
		cancelRoom(roomId, why)
	else
		try("leave room", function()
			return roomsMap:UpdateAsync(roomId, function(r)
				if type(r) ~= "table" or r.guestId ~= p.UserId or r.state == "teleporting" then
					return nil
				end
				r.state = "open"
				r.guestId, r.guestName, r.guestDisplay, r.guestServer, r.fullAt = nil, nil, nil, nil, nil
				return r
			end, Config.ROOM_TTL)
		end)
		publish({ t = "room", id = roomId })
		publish({ t = "list" })
	end
	releaseLock(p.UserId, roomId)
	clearSession(p)
	listDirty = true
	log(p.Name, "left", roomId, why)
end

Action.OnServerEvent:Connect(function(p: Player, action: any, arg: any)
	local s = session(p)
	local t = os.clock()
	if action ~= "open" and action ~= "close" and t - s.lastAction < Config.ACTION_COOLDOWN then
		return
	end
	s.lastAction = t
	if action == "open" then
		s.uiOpen = true
		if s.roomId then
			s.lastSent = nil
			pollRoom(s.roomId)
		else
			s.lastSent = nil
			if listDirty or #listCache == 0 then
				refreshList()
			end
			pushList(p)
		end
	elseif action == "close" then
		s.uiOpen = false
	elseif action == "search" then
		createRoom(p)
	elseif action == "join" then
		joinRoom(p, arg)
	elseif action == "leave" then
		leaveRoom(p, "left")
		s.lastSent = nil
		refreshList()
		pushList(p)
	elseif action == "refresh" then
		refreshList()
		s.lastSent = nil
		pushList(p)
	end
end)

Players.PlayerRemoving:Connect(function(p)
	local s = sessions[p]
	if s and s.roomId then
		if s.teleporting then
			releaseLock(p.UserId, s.roomId) -- on the way to the arena: free them for later
		else
			leaveRoom(p, "left_game")
		end
	end
	sessions[p] = nil
end)

-- cross-server messages ------------------------------------------------------------------
task.spawn(function()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function(message)
			local data = message.Data
			if type(data) ~= "table" then
				return
			end
			if data.t == "room" and type(data.id) == "string" then
				for _, s in pairs(sessions) do
					if s.roomId == data.id then
						pollRoom(data.id)
						break
					end
				end
				listDirty = true
			elseif data.t == "list" then
				listDirty = true
			end
		end)
	end)
	if not ok then
		warn("[Matchmaking] MessagingService subscribe failed, polling only: " .. tostring(err))
	end
end)

-- poll + heartbeat loops -----------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(Config.POLL)
		local rooms = {}
		local browsing = false
		for p, s in pairs(sessions) do
			if s.roomId then
				rooms[s.roomId] = true
			elseif s.uiOpen then
				browsing = true
			end
		end
		for roomId in pairs(rooms) do
			task.spawn(pollRoom, roomId)
		end
		if browsing then
			refreshList()
			pushListToBrowsers()
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(Config.HEARTBEAT)
		for p, s in pairs(sessions) do
			if s.roomId and not s.teleporting and p.Parent == Players then
				local roomId, role = s.roomId, s.role
				task.spawn(function()
					pcall(function()
						playersMap:UpdateAsync(tostring(p.UserId), function(old)
							if type(old) == "table" and old.roomId == roomId then
								old.t = now()
								return old
							end
							return nil
						end, Config.PLAYER_TTL)
					end)
					if role == "host" then
						pcall(function()
							roomsMap:UpdateAsync(roomId, function(r)
								if type(r) == "table" and r.hostId == p.UserId and (r.state == "open" or r.state == "full") then
									return r -- same value, fresh TTL
								end
								return nil
							end, Config.ROOM_TTL)
						end)
					end
				end)
			end
		end
	end
end)

game:BindToClose(function()
	for p, s in pairs(sessions) do
		if s.roomId and not s.teleporting then
			leaveRoom(p, "server_closed")
		end
	end
end)

log("lobby matchmaking ready (" .. (if IS_STUDIO then "Studio" else "live") .. ")")
