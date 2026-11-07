--!strict
-- Presentation only. Live snapshots and durable confirmations have separate clocks.
local State = {}
local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
function State.Progress(level: any, xp: any, needed: any): (number, string)
	if not finite(level) or not finite(xp) or not finite(needed) then
		return 0, "Loading…"
	end
	if needed <= 0 then
		return 1, "MAX"
	end
	return math.clamp(xp / needed, 0, 1), `{math.floor(xp)} / {math.floor(needed)} EXP`
end
function State.NewConfirmations()
	return { session = nil :: string?, sequence = 0, revision = 0 }
end
function State.AcceptConfirmation(cursor: any, snapshot: any): boolean
	if
		type(snapshot) ~= "table"
		or type(snapshot.sessionId) ~= "string"
		or not finite(snapshot.sequence)
		or not finite(snapshot.committedRevision)
	then
		return false
	end
	if cursor.session ~= snapshot.sessionId then
		-- The controller resets on reconnect; never switch back to another session mid-lifetime.
		if cursor.session ~= nil then
			return false
		end
		cursor.session = snapshot.sessionId
	end
	if snapshot.sequence <= cursor.sequence then
		return false
	end
	cursor.sequence = snapshot.sequence
	if snapshot.committedRevision <= cursor.revision then
		return false
	end
	cursor.revision = snapshot.committedRevision
	return true
end
return State
