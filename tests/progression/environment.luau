--!nocheck
-- Engine adapters for deterministic unit tests; no real account/profile data.
local factories, cache, mocks = {}, {}, {}
local clock, timestamp = 10, 10000
local nativeOs = os
local os = setmetatable({
	clock = function()
		return clock
	end,
	time = function()
		return timestamp
	end,
}, { __index = nativeOs })
local warnings = {}
local function warn(message)
	table.insert(warnings, message)
end
local function signal()
	local event = { handlers = {} }
	function event:Connect(fn)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end }
	end
	function event:Fire(...)
		for _, fn in self.handlers do
			fn(...)
		end
	end
	return event
end
local delayed, scheduled = {}, {}
local task = {}
function task.delay(seconds, fn, ...)
	table.insert(delayed, { seconds = seconds, fn = fn, args = { ... } })
end
function task.spawn(fn, ...)
	table.insert(scheduled, { fn = fn, args = { ... } })
end
function task.defer(fn, ...)
	table.insert(scheduled, { fn = fn, args = { ... } })
end
function task.wait()
	error("Unexpected wait in a deterministic unit test")
end
local function drainScheduled()
	while #scheduled > 0 do
		local entry = table.remove(scheduled, 1)
		entry.fn(table.unpack(entry.args))
	end
end
local function node(path)
	return setmetatable({ path = path }, {
		__index = function(_, key)
			if key == "Parent" then
				return node(path:match("^(.*)%.[^.]+$"))
			end
			if key == "Name" then
				return path:match("[^.]+$")
			end
			return node(path .. "." .. key)
		end,
	})
end
local function load(target)
	local path = if type(target) == "string" then target else target.path
	if mocks[path] then
		return mocks[path]
	end
	if cache[path] then
		return cache[path]
	end
	assert(factories[path], "Missing factory " .. path)
	cache[path] = factories[path](load, node(path))
	return cache[path]
end
local Color3 = {
	new = function(...)
		return { ... }
	end,
	fromRGB = function(...)
		return { ... }
	end,
}
local Vector2 = {
	new = function(x, y)
		return { X = x, Y = y, Magnitude = math.sqrt(x * x + y * y) }
	end,
}
local Random = {
	new = function()
		return {}
	end,
}
local Vector3 = {
	new = function(x, y, z)
		return { X = x, Y = y, Z = z }
	end,
}
local Enum = setmetatable({}, {
	__index = function(_, category)
		return setmetatable({}, {
			__index = function(_, item)
				return category .. "." .. item
			end,
		})
	end,
})
local Players = { list = {}, PlayerAdded = signal(), PlayerRemoving = signal() }
function Players:GetPlayers()
	return self.list
end
function Players:GetPlayerByUserId(id)
	for _, p in self.list do
		if p.UserId == id then
			return p
		end
	end
	return nil
end
local function player(id)
	local p = {
		UserId = id,
		Name = "SyntheticPlayer",
		DisplayName = "Synthetic Player",
		AccountAge = 100,
		Parent = Players,
		attrs = {},
		CharacterAdded = signal(),
		signals = {},
	}
	function p:SetAttribute(key, value)
		self.attrs[key] = value
		if self.signals[key] then
			self.signals[key]:Fire()
		end
	end
	function p:GetAttribute(key)
		return self.attrs[key]
	end
	function p:GetAttributeChangedSignal(key)
		self.signals[key] = self.signals[key] or signal()
		return self.signals[key]
	end
	function p:Kick(reason)
		self.kicked = reason
	end
	return p
end
local binds = {}
local services = {
	Players = Players,
	ReplicatedStorage = node("ReplicatedStorage"),
	RunService = {
		IsStudio = function()
			return true
		end,
	},
	HttpService = {
		GenerateGUID = function()
			return "synthetic-session"
		end,
	},
}
local game = {}
function game:GetService(name)
	assert(services[name], "Missing engine adapter " .. name)
	return services[name]
end
function game:BindToClose(fn)
	table.insert(binds, fn)
end
local function remote()
	local r = { OnServerEvent = signal(), messages = {} }
	function r:FireClient(p, value)
		table.insert(self.messages, { player = p, value = value })
	end
	return r
end
local remotes = {}
local RemoteAdapter = {}
function RemoteAdapter.Get(name)
	remotes[name] = remotes[name] or remote()
	return remotes[name]
end
RemoteAdapter.GetFunction = RemoteAdapter.Get
mocks["ReplicatedStorage.Shared.Remotes"] = RemoteAdapter
-- INSERT_FACTORIES
