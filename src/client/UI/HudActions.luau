--!strict
-- Client side of the final UI contract. Coder owns creating/validating these server endpoints.
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local State = require(script.Parent.HudActionState)
local Actions = {}
function Actions.New()
	local state = State.New()
	local alive = true
	local fetching = false
	local lastFetch = -math.huge
	local listeners: { [() -> ()]: boolean } = {}
	local resultRemote: RemoteEvent? = nil
	local connection: RBXScriptConnection? = nil
	local callback: any = nil
	local status = "Loading"
	local lastCode: string? = nil
	local client: any = {}
	local function changed()
		if alive then
			for fn in listeners do
				fn()
			end
		end
	end
	local function result(payload: any)
		if not alive then
			return
		end
		local disposition = State.Result(state, payload)
		if disposition == "ignored" then
			return
		end
		if type(payload.snapshot) == "table" then
			State.Snapshot(state, payload.snapshot)
		end
		if state.snapshot then
			status = if state.snapshot.ready then "Ready" else "Loading"
		end
		if disposition == "pending" then
			lastCode = payload.reasonCode or "SAVE_PENDING"
		end
		if disposition ~= "pending" then
			lastCode = if disposition == "rejected" then payload.reasonCode or "REJECTED" else nil
			local fn = callback
			callback = nil
			if fn then
				fn(payload)
			end
		end
		changed()
	end
	local function endpoints()
		local folder = RS:FindFirstChild("Remotes")
		local get = folder and folder:FindFirstChild("GetHudCommerce")
		local action = folder and folder:FindFirstChild("HudCommerceAction")
		local response = folder and folder:FindFirstChild("HudCommerceResult")
		if
			not get
			or not get:IsA("RemoteFunction")
			or not action
			or not action:IsA("RemoteEvent")
			or not response
			or not response:IsA("RemoteEvent")
		then
			return nil, nil
		end
		if response ~= resultRemote then
			if connection then
				connection:Disconnect()
			end
			resultRemote = response
			connection = response.OnClientEvent:Connect(result)
		end
		return get, action
	end
	function client.Subscribe(fn: () -> ())
		listeners[fn] = true
		return function()
			listeners[fn] = nil
		end
	end
	function client.Refresh(force: boolean?)
		if not alive or fetching or (not force and os.clock() - lastFetch < 3) then
			return
		end
		lastFetch = os.clock()
		local get = endpoints()
		if not get then
			status = "Unavailable"
			changed()
			return
		end
		fetching = true
		task.spawn(function()
			local ok, snapshot = pcall(function()
				return get:InvokeServer(if state.pending then state.pending.requestId else nil)
			end)
			fetching = false
			if not alive then
				return
			end
			local accepted = false
			local why: string? = nil
			if ok then
				accepted, why = State.Snapshot(state, snapshot)
			end
			if ok and (accepted or why == "stale") then
				status = if state.snapshot.ready then "Ready" else "Loading"
				if snapshot.requestResult then
					result(snapshot.requestResult)
				end
			elseif ok and snapshot == nil then
				status = "Loading"
			else
				status = "Error"
				lastCode = "INVALID_RESPONSE"
			end
			changed()
		end)
	end
	function client.Read()
		return state.snapshot, state.pending, status, lastCode
	end
	function client.Ready(kind: string): boolean
		local snapshot = state.snapshot
		return alive
			and status == "Ready"
			and snapshot ~= nil
			and snapshot.ready == true
			and snapshot.capabilities[kind] == true
			and not state.pending
	end
	function client.Request(kind: string, fields: any, fn: any): boolean
		if not client.Ready(kind) then
			return false
		end
		local _, remote = endpoints()
		if not remote then
			status = "Unavailable"
			changed()
			return false
		end
		local id = HttpService:GenerateGUID(false)
		if not State.Begin(state, id, kind, fields, os.clock()) then
			return false
		end
		callback = fn
		lastCode = nil
		local packet = table.clone(fields)
		packet.requestId = id
		packet.kind = kind
		-- Never copy a price, currency reward or computed combat rank into this intent.
		local ok = pcall(function()
			remote:FireServer(packet)
		end)
		if not ok then
			State.Timeout(state, id)
			lastCode = "TIMEOUT"
		end
		changed()
		task.delay(12, function()
			if alive and State.Timeout(state, id) then
				lastCode = "TIMEOUT"
				changed()
			end
		end)
		return true
	end
	function client.ErrorText(): string
		return State.Message(lastCode or (if status == "Loading" then "LOADING" else "UNAVAILABLE"))
	end
	function client.Destroy()
		alive = false
		callback = nil
		table.clear(listeners)
		if connection then
			connection:Disconnect()
		end
	end
	return client
end
return Actions
