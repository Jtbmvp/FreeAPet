-- BiomeTeleportServer (ServerScriptService): teleports a player to a biome's arrival point.
-- Points: Workspace.Map.TeleportPoints.TP_<Biome> (invisible, anchored, no collision).
-- Remote: ReplicatedStorage.BiomeTeleportRemotes.Teleport (RemoteEvent)
--   client -> server: ("go", biomeName)
--   server -> client: ("result", ok: boolean, message: string, biomeName: string?)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local COOLDOWN = 3
local LIFT = Vector3.new(0, 3, 0)
local BIOMES = {
	Lobby = "TP_Lobby",
	Forest = "TP_Forest",
	Desert = "TP_Desert",
	Ice = "TP_Ice",
	Kingdom = "TP_Kingdom",
}
local LABEL = { Lobby = "Lobby", Forest = "Forest", Desert = "Desert", Ice = "Ice", Kingdom = "Forgotten Kingdom" }

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

local last: { [Player]: number } = {}

local function reply(player: Player, ok: boolean, msg: string, biome: string?)
	Teleport:FireClient(player, "result", ok, msg, biome)
end

Teleport.OnServerEvent:Connect(function(player: Player, action: any, biome: any)
	if action ~= "go" or type(biome) ~= "string" or BIOMES[biome] == nil then
		return
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
	local target = point(BIOMES[biome])
	if not target then
		reply(player, false, "That biome is not ready yet", biome)
		return
	end
	last[player] = now
	if hum.Sit then
		hum.Sit = false
	end
	char:PivotTo(target.CFrame + LIFT)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
	reply(player, true, "Welcome to " .. LABEL[biome] .. "!", biome)
end)

Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
end)
