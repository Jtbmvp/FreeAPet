-- BiomeTeleportServer (ServerScriptService): teleports a player to a biome's arrival point.
-- Points: Workspace.Map.TeleportPoints.TP_<Biome> (invisible, anchored, no collision).
-- Remote: ReplicatedStorage.BiomeTeleportRemotes.Teleport (RemoteEvent)
--   client -> server: ("go", biomeName)   biomeName "Base" = the player's own base plot
--     (Workspace.Map.Bases.Base_<N> whose PlotIndex/BaseIndex matches the player's PlotIndex
--      attribute set by BaseService; read only, BaseService is not touched)
--   server -> client: ("result", ok: boolean, message: string, biomeName: string?)
-- Travel portal animation (StarterPlayerScripts.TravelPortalClient):
--   server -> that player: ("start", biomeName)  the trip is accepted; the client plays the portal
--     cinematic (on a hidden stage under the map) and sends ("enter") when the character dives in.
--   client -> server: ("enter")  the server then does the real move to TP_* / the base spawn.
--     If "enter" never comes, the server moves the player anyway after ENTER_TIMEOUT seconds.
--   server -> all: ("fx", "depart" | "arrive", player, cframe, biomeName)  everyone sees the portal on the spot.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local COOLDOWN = 3
local ENTER_TIMEOUT = 5 -- seconds: never leave anyone on the portal stage
local ENTER_MIN = 0.4 -- an "enter" sooner than this after "start" waits until then
local LIFT = Vector3.new(0, 3, 0)
local BIOMES = {
	Lobby = "TP_Lobby",
	Forest = "TP_Forest",
	Desert = "TP_Desert",
	Ice = "TP_Ice",
	Kingdom = "TP_Kingdom",
}
local LABEL = { Lobby = "Lobby", Forest = "Forest", Desert = "Desert", Ice = "Ice", Kingdom = "Forgotten Kingdom", Base = "your base" }

local folder = ReplicatedStorage:FindFirstChild("BiomeTeleportRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "BiomeTeleportRemotes"
	folder.Parent = ReplicatedStorage
end
local remote = folder:FindFirstChild("Teleport") :: RemoteEvent?
if not remote then
	local r = Instance.new("RemoteEvent")
	r.Name = "Teleport"
	r.Parent = folder
	remote = r
end
local Teleport = remote :: RemoteEvent

local PvpBattle
task.spawn(function()
	local mod = ServerScriptService:WaitForChild("PvpBattle", 15)
	if mod and mod:IsA("ModuleScript") then
		local ok, res = pcall(require, mod)
		if ok then
			PvpBattle = res
		end
	end
end)

local function isArenaServer(): boolean
	return workspace:GetAttribute("MM_ArenaServer") == true or workspace:FindFirstChild("MM_ArenaServer") ~= nil
end

local function inPvp(player: Player): boolean
	if PvpBattle and PvpBattle.IsBattling then
		local ok, res = pcall(PvpBattle.IsBattling, player)
		return ok and res == true
	end
	return false
end

local function point(name: string): BasePart?
	local map = workspace:FindFirstChild("Map")
	local pts = map and map:FindFirstChild("TeleportPoints")
	local p = pts and pts:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

-- The player's own base: the plot BaseService gave them (PlotIndex attribute), its Spawn marker.
local function plotIndexOf(plot: Instance): number?
	for _, name in { "PlotIndex", "BaseIndex" } do
		local v = plot:GetAttribute(name)
		if typeof(v) == "number" then
			return v
		end
	end
	return nil
end
local function baseTarget(player: Player): CFrame?
	local index = player:GetAttribute("PlotIndex")
	local map = workspace:FindFirstChild("Map")
	local bases = map and map:FindFirstChild("Bases")
	if typeof(index) ~= "number" or not bases then
		return nil
	end
	for _, plot in bases:GetChildren() do
		if plot:IsA("Model") and plotIndexOf(plot) == index then
			local owner = plot:GetAttribute("OwnerUserId")
			if owner ~= nil and owner ~= player.UserId then
				return nil -- never send anyone into another player's base
			end
			local spawn = plot:FindFirstChild("Spawn")
			if spawn and spawn:IsA("BasePart") then
				return spawn.CFrame * CFrame.new(0, 4, 0) -- same as BaseService's own spawn
			end
			local zone = plot:FindFirstChild("SafeZone")
			if zone and zone:IsA("BasePart") then
				return CFrame.new(zone.Position.X, zone.Position.Y - zone.Size.Y / 2 + 4, zone.Position.Z)
			end
			return nil
		end
	end
	return nil
end

local last: { [Player]: number } = {}
type Trip = { biome: string, target: CFrame, started: number }
local pending: { [Player]: Trip } = {}

local function reply(player: Player, ok: boolean, msg: string, biome: string?)
	Teleport:FireClient(player, "result", ok, msg, biome)
end

-- the real move: the server is the authority on where the player ends up
local function finish(player: Player, trip: Trip)
	if pending[player] ~= trip then
		return
	end
	pending[player] = nil
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and hum) or hum.Health <= 0 then
		reply(player, false, "Teleport cancelled", trip.biome)
		return
	end
	if hum.Sit then
		hum.Sit = false
	end
	char:PivotTo(trip.target)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
	Teleport:FireAllClients("fx", "arrive", player, trip.target, trip.biome)
	reply(player, true, if trip.biome == "Base" then "Welcome home!" else "Welcome to " .. LABEL[trip.biome] .. "!", trip.biome)
end

local function onEnter(player: Player)
	local trip = pending[player]
	if not trip then
		return
	end
	local early = ENTER_MIN - (os.clock() - trip.started)
	if early > 0 then
		task.wait(early)
	end
	finish(player, trip)
end

local function onGo(player: Player, biome: any)
	if type(biome) ~= "string" or (BIOMES[biome] == nil and biome ~= "Base") then
		return
	end
	if pending[player] then
		return -- already travelling: repeated clicks are ignored
	end
	local now = os.clock()
	local since = now - (last[player] or -math.huge)
	if since < COOLDOWN then
		reply(player, false, ("Wait %d s before teleporting again"):format(math.ceil(COOLDOWN - since)), biome)
		return
	end
	if isArenaServer() then
		reply(player, false, "You can't teleport in the arena", biome)
		return
	end
	if player:GetAttribute("InBattle") == true or inPvp(player) then
		reply(player, false, "Finish your battle first", biome)
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (char and hum and root) or hum.Health <= 0 then
		reply(player, false, "You need to be alive to teleport", biome)
		return
	end
	local targetCf: CFrame
	if biome == "Base" then
		local cf = baseTarget(player)
		if not cf then
			reply(player, false, "You don't have a base yet", biome)
			return
		end
		targetCf = cf
	else
		local target = point(BIOMES[biome])
		if not target then
			reply(player, false, "That biome is not ready yet", biome)
			return
		end
		targetCf = target.CFrame + LIFT
	end
	last[player] = now
	if hum.Sit then
		hum.Sit = false
	end
	local trip: Trip = { biome = biome, target = targetCf, started = now }
	pending[player] = trip
	task.spawn(pcall, player.RequestStreamAroundAsync, player, targetCf.Position, 4)
	Teleport:FireClient(player, "start", biome)
	Teleport:FireAllClients("fx", "depart", player, root.CFrame, biome)
	task.delay(ENTER_TIMEOUT, finish, player, trip)
end

Teleport.OnServerEvent:Connect(function(player: Player, action: any, biome: any)
	if action == "go" then
		onGo(player, biome)
	elseif action == "enter" then
		onEnter(player)
	end
end)

Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
	pending[p] = nil
end)
