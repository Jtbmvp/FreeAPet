--!strict
-- The tablet's data (pets + Index), asked from the server (GetTablet) and
-- kept for a moment so several tabs can share one request.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

export type PetView = {
	id: string,
	speciesId: string,
	size: number,
	growth: number,
	state: string,
	cashPerSecond: number,
	origin: Types.PetOrigin?,
	level: number,
	xp: number,
	xpToNext: number,
	hp: number,
	maxHp: number,
	moves: { string },
}

export type TabletView = {
	now: number,
	pets: { PetView },
	index: { [string]: Types.IndexEntry },
}

local TabletData = {}

local MAX_AGE = 0.5 -- seconds a fetched view is reused

local cached: TabletView? = nil
local fetchedAt = 0

-- Latest view, or nil before the save has loaded.
function TabletData.Get(): TabletView?
	if cached and os.clock() - fetchedAt < MAX_AGE then
		return cached
	end
	local ok, result = pcall(function()
		return Remotes.GetFunction("GetTablet"):InvokeServer()
	end)
	if ok and typeof(result) == "table" then
		cached = result :: any
		fetchedAt = os.clock()
	end
	return cached
end

-- Forget the cache (after an action that changes the pets).
function TabletData.Invalidate()
	fetchedAt = 0
end

return TabletData
