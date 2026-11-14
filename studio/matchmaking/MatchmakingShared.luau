-- MatchmakingShared (ReplicatedStorage): constants shared by MatchmakingServer and the GUI.
-- Global 1v1 matchmaking: MemoryStore rooms + MessagingService + reserved arena servers.
-- Source: studio/matchmaking/ in the repo (branch dc/astra-matchmaking).
return {
	VERSION = "v1",
	TOPIC = "FreeAPet_MM_v1", -- MessagingService topic

	ROOM_TTL = 60, -- seconds a room lives in MemoryStore without a heartbeat
	PLAYER_TTL = 30, -- seconds a player lock lives without a heartbeat
	MATCH_TTL = 900, -- seconds the match record (read by the arena server) lives
	HEARTBEAT = 4, -- seconds between heartbeats (room TTL + player locks)
	POLL = 2, -- seconds between room polls on each server
	LOCK_FRESH = 12, -- a player lock older than this is treated as dead

	COUNTDOWN = 5, -- "Match Found!" countdown before the teleport
	FULL_STALE = 25, -- a full room older than fullAt + COUNTDOWN + this is cancelled
	TELEPORT_RETRIES = 3,

	ARENA_LOAD_TIMEOUT = 45, -- seconds the arena waits for both players
	ARENA_SETTLE = 3, -- seconds after both loaded before the countdown
	ARENA_COUNTDOWN = 3,
	ARENA_RETURN_DELAY = 6, -- seconds before sending a player back to the lobby

	MAX_ROOMS_SHOWN = 30,
	ACTION_COOLDOWN = 0.5,
}
