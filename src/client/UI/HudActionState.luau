--!strict
-- Pure protocol/presentation state. Never grants Cash, pets, stock or team membership.
local State = {}
local messages = {
	UNAVAILABLE = "This action is currently unavailable.",
	LOADING = "Loading your data…",
	IN_BATTLE = "Finish your battle first.",
	IN_TRADE = "Finish or cancel your trade first.",
	NOT_OWNER = "You no longer own this pet.",
	PET_NOT_FOUND = "This pet is no longer available.",
	PET_UNAVAILABLE = "This pet cannot be sold right now.",
	PROTECTED_PET = "This pet cannot be sold.",
	LAST_PET = "Keep at least one eligible pet.",
	QUOTE_EXPIRED = "This offer expired. Check the sale price again.",
	QUOTE_CHANGED = "The pet or price changed. Check the sale price again.",
	NOT_ENOUGH_CASH = "You do not have enough Cash.",
	NO_ELIGIBLE_PETS = "No eligible pets are available for your team.",
	PRICE_CHANGED = "Price changed. Review the current price before buying.",
	CAPACITY_REACHED = "You cannot hold more capsules right now.",
	RATE_LIMIT = "Please wait before trying again.",
	SAVE_PENDING = "Waiting for your progress to save…",
	SAVE_FAILED = "The action could not be confirmed. Refresh your data.",
	TIMEOUT = "Still checking this action. Please wait for the result.",
	INVALID_RESPONSE = "The result could not be confirmed. Refresh your data.",
	REJECTED = "This action could not be completed.",
	UNKNOWN_REQUEST = "Still checking this action. Waiting for the result.",
}
function State.Message(code: any): string
	return messages[code] or messages.REJECTED
end
function State.Integer(value: any): boolean
	return type(value) == "number"
		and value == value
		and math.abs(value) < math.huge
		and value >= 0
		and value % 1 == 0
end
function State.QuoteShape(quote: any, petId: string): boolean
	return type(quote) == "table"
		and quote.petId == petId
		and type(quote.quoteId) == "string"
		and #quote.quoteId > 0
		and #quote.quoteId <= 128
		and quote.currency == "Cash"
		and State.Integer(quote.petLevel)
		and quote.petLevel >= 1
		and State.Integer(quote.rarityBase)
		and State.Integer(quote.levelBonus)
		and State.Integer(quote.totalCash)
		and quote.totalCash == quote.rarityBase + quote.levelBonus
		and type(quote.expiresAt) == "number"
		and quote.expiresAt == quote.expiresAt
		and quote.expiresAt > 0
		and quote.expiresAt < math.huge
end
function State.ValidQuote(quote: any, petId: string, now: number): boolean
	return State.QuoteShape(quote, petId) and quote.expiresAt > now
end
function State.New()
	return { snapshot = nil :: any, pending = nil :: any }
end
function State.Snapshot(state: any, snapshot: any): (boolean, string?)
	if
		type(snapshot) ~= "table"
		or snapshot.schemaVersion ~= 1
		or not State.Integer(snapshot.revision)
		or type(snapshot.ready) ~= "boolean"
		or type(snapshot.capabilities) ~= "table"
	then
		return false, "invalid"
	end
	if state.snapshot and snapshot.revision < state.snapshot.revision then
		return false, "stale"
	end
	state.snapshot = snapshot
	return true, nil
end
function State.Begin(state: any, id: string, kind: string, fields: any, now: number): boolean
	if state.pending then
		return false
	end
	state.pending = { requestId = id, kind = kind, fields = fields, started = now, phase = "Pending" }
	return true
end
function State.Timeout(state: any, id: string): boolean
	if not state.pending or state.pending.requestId ~= id then
		return false
	end
	state.pending.phase = "Unknown"
	return true -- unresolved; never authorises an automatic retry
end
function State.Result(state: any, result: any): string
	local pending = state.pending
	if
		type(result) ~= "table"
		or not pending
		or result.requestId ~= pending.requestId
		or result.kind ~= pending.kind
	then
		return "ignored"
	end
	if result.phase == "Pending" then
		pending.phase = "Pending"
		return "pending"
	end
	if result.phase == "Quoted" then
		-- A delayed, expired quote is still a completed read; the UI requires a new price check.
		if pending.kind ~= "quoteSell" or not State.QuoteShape(result.quote, pending.fields.petId) then
			return "ignored"
		end
	elseif result.phase == "Committed" then
		if pending.kind == "quoteSell" or not State.Integer(result.committedRevision) then
			return "ignored"
		end
	elseif result.phase ~= "Rejected" then
		return "ignored"
	end
	state.pending = nil
	return string.lower(result.phase)
end
return State
