-- InteriorDoorsServer (ServerScriptService): doors between the map and the hidden interiors
-- under the islands (Workspace.Map.Interiors).
-- A door is any BasePart with the attribute InteriorDoor ("IglooIn", "IglooOut", "CastleIn", "CabinIn", "PyramidIn",
-- "CastleOut", ...), a ProximityPrompt child and an ObjectValue "Target" pointing at an
-- invisible arrival Part (its CFrame gives position and facing).
--   *In  doors: set Player attribute InInterior = <room's InteriorName> ("Igloo", "Castle").
--   *Out doors: clear InInterior.
-- InInterior is also cleared when the character respawns or leaves the room by other means
-- (Travel button, BiomeTeleportServer), so the NPC / mood code can trust it.
--
-- Entry/exit animation (2026-11-21): the server stays the authority (validates + teleports) but
-- first tells the client to play the transition (InteriorTransitionClient):
-- Remote: ReplicatedStorage.InteriorDoorsRemotes.Transition (RemoteEvent, server -> client only)
--   ("start", info)  info = { enter: boolean, title: string?, room: string?, door: Vector3,
--                             lead: number }   lead = seconds until the server teleports
--   ("arrived", cf: CFrame)  the character was moved; cf = where it now stands
--   ("cancel")       validation failed after "start" (died, battle...): fade back in
-- The client never fires it, and gives up on its own after 4 s.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local COOLDOWN = 1.5
local LEAD_IN = 0.85 -- seconds between "start" and the teleport when entering (screen is black by then)
local LEAD_OUT = 0.55 -- same when leaving (shorter animation)
local TITLES = { Igloo = "Igloo", Castle = "Forgotten Castle", Cabin = "Wood Cabin", Pyramid = "Pyramid Temple" } -- room attribute InteriorTitle wins

local remoteFolder = ReplicatedStorage:FindFirstChild("InteriorDoorsRemotes")
if not remoteFolder then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = "InteriorDoorsRemotes"
	remoteFolder.Parent = ReplicatedStorage
end
local existing = remoteFolder:FindFirstChild("Transition") :: RemoteEvent?
if not existing then
	local r = Instance.new("RemoteEvent")
	r.Name = "Transition"
	r.Parent = remoteFolder
	existing = r
end
local TransitionRemote = existing :: RemoteEvent
local LIFT = Vector3.new(0, 3, 0)
local DISTANCE_SLACK = 6 -- server-side margin on top of the prompt's MaxActivationDistance
local ROOM_RADIUS = 90 -- farther than this from the room's pivot = no longer inside

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

local function inPvp(player: Player): boolean
	if PvpBattle and PvpBattle.IsBattling then
		local ok, res = pcall(PvpBattle.IsBattling, player)
		return ok and res == true
	end
	return false
end

local function isArenaServer(): boolean
	return workspace:GetAttribute("MM_ArenaServer") == true or workspace:FindFirstChild("MM_ArenaServer") ~= nil
end

local function interiorsRoot(): Instance?
	local map = workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("Interiors")
end

-- The room model (attribute InteriorName) that holds an instance, if any.
local function roomOf(inst: Instance): Model?
	local node = inst.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("InteriorName") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

local last: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
local wired: { [ProximityPrompt]: boolean } = {}

-- Can this player use a door right now? Returns the character parts when yes.
local function usable(player: Player): (Model?, Humanoid?, BasePart?)
	if isArenaServer() or player:GetAttribute("InBattle") == true or inPvp(player) then
		return nil, nil, nil
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and hum and root) or hum.Health <= 0 then
		return nil, nil, nil
	end
	return char, hum, root
end

local function teleport(player: Player, door: BasePart, prompt: ProximityPrompt)
	local kind = door:GetAttribute("InteriorDoor")
	if type(kind) ~= "string" or busy[player] then
		return
	end
	local now = os.clock()
	if now - (last[player] or -math.huge) < COOLDOWN then
		return
	end
	local char, hum, root = usable(player)
	if not (char and hum and root) then
		return
	end
	if (root.Position - door.Position).Magnitude > prompt.MaxActivationDistance + DISTANCE_SLACK then
		return
	end
	local targetValue = door:FindFirstChild("Target")
	local target = targetValue and targetValue:IsA("ObjectValue") and targetValue.Value
	if not (target and target:IsA("BasePart")) then
		warn("[InteriorDoors] door has no Target:", door:GetFullName())
		return
	end
	busy[player] = true
	last[player] = now
	local cf = target.CFrame + LIFT
	local room = roomOf(target)
	local roomName = room and room:GetAttribute("InteriorName")
	local title = nil
	if room then
		local custom = room:GetAttribute("InteriorTitle")
		title = if type(custom) == "string" then custom else (TITLES[roomName] or roomName)
	end
	local lead = if room then LEAD_IN else LEAD_OUT
	TransitionRemote:FireClient(player, "start", {
		enter = room ~= nil,
		title = title,
		room = roomName,
		door = door.Position,
		lead = lead,
	})
	-- StreamingEnabled: stream the destination in while the client fades out.
	local streamed = false
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(cf.Position, 5)
		end)
		streamed = true
	end)
	task.wait(lead)
	local waitStart = os.clock()
	while not streamed and os.clock() - waitStart < 1.5 do
		task.wait()
	end
	local nowChar = usable(player)
	if player.Parent == nil or nowChar ~= char then
		busy[player] = nil
		if player.Parent then
			TransitionRemote:FireClient(player, "cancel")
		end
		return
	end
	if hum.Sit then
		hum.Sit = false
	end
	char:PivotTo(cf)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
	player:SetAttribute("InInterior", roomName)
	last[player] = os.clock()
	busy[player] = nil
	TransitionRemote:FireClient(player, "arrived", cf)
end


local function wire(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or wired[prompt] then
		return
	end
	local door = prompt.Parent
	if not (door and door:IsA("BasePart") and door:GetAttribute("InteriorDoor") ~= nil) then
		return
	end
	wired[prompt] = true
	CollectionService:AddTag(prompt, "InteriorDoorPrompt")
	prompt.Triggered:Connect(function(player: Player)
		teleport(player, door, prompt)
	end)
	prompt.Destroying:Connect(function()
		wired[prompt] = nil
	end)
end

local function watch(root: Instance)
	for _, d in root:GetDescendants() do
		wire(d)
	end
	root.DescendantAdded:Connect(function(d)
		task.defer(wire, d)
	end)
end

task.spawn(function()
	local map = workspace:WaitForChild("Map", 60)
	local root = map and map:WaitForChild("Interiors", 60)
	if root then
		watch(root)
	else
		warn("[InteriorDoors] Workspace.Map.Interiors not found")
	end
end)

-- Keep InInterior honest: clear it on respawn or once the player is away from the room.
local function roomByName(name: string): Model?
	local root = interiorsRoot()
	if not root then
		return nil
	end
	for _, m in root:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("InteriorName") == name then
			return m
		end
	end
	return nil
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		player:SetAttribute("InInterior", nil)
	end)
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function()
		player:SetAttribute("InInterior", nil)
	end)
end

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local name = player:GetAttribute("InInterior")
			if type(name) == "string" then
				local room = roomByName(name)
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not room or not root or (root.Position - room:GetPivot().Position).Magnitude > ROOM_RADIUS then
					player:SetAttribute("InInterior", nil)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	last[p] = nil
	busy[p] = nil
end)
