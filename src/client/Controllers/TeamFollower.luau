--!strict
-- One cosmetic companion per owner. No NPC movement or follower physics:
-- the server publishes the leader's art, while retaining the full roster
-- and original battle models. A single loop owns motion and cleanup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local TeamFollower = {}

local FAR = 160
local GROUND_INTERVAL = 0.1
local RESPONSE = 18

type Entry = {
	source: Model,
	visual: Model?,
	ownerRoot: BasePart?,
	lastOwnerPosition: Vector3?,
	groundY: number?,
	groundAt: number,
}

local entries: { [Model]: Entry } = {}

local function clear(entry: Entry)
	if entry.visual then
		entry.visual:Destroy()
		entry.visual = nil
	end
	entry.ownerRoot = nil
	entry.lastOwnerPosition = nil
	entry.groundY = nil
	entry.groundAt = 0
end

local function makeVisual(source: Model): Model?
	local count = source:GetAttribute("FollowerDescendants")
	if not source.PrimaryPart or typeof(count) ~= "number" or #source:GetDescendants() < count then
		return nil -- the template is still replicating; retry next frame
	end
	local visual = source:Clone()
	visual.Name = `Follower_{source.Name}`
	visual:SetAttribute("CosmeticFollower", true)
	visual:SetAttribute("FollowerSpeed", 0)
	return visual
end

function TeamFollower.Start()
	local templates = ReplicatedStorage:WaitForChild("TeamFollowers", 15)
	local animals = Workspace:WaitForChild("Animals", 15)
	if not templates or not animals then
		warn("[TeamFollower] Missing TeamFollowers or Animals; followers unavailable")
		return
	end
	local function added(source: Instance)
		if source:IsA("Model") then
			entries[source] = { source = source, groundAt = 0 }
		end
	end
	templates.ChildAdded:Connect(added)
	templates.ChildRemoved:Connect(function(source)
		local entry = entries[source :: Model]
		if entry then
			clear(entry)
			entries[source :: Model] = nil
		end
	end)
	for _, source in templates:GetChildren() do
		added(source)
	end
	Players.PlayerRemoving:Connect(function(player)
		for _, entry in entries do
			if entry.source:GetAttribute("OwnerUserId") == player.UserId then
				clear(entry)
			end
		end
	end)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local nextGroundAt = 0
	RunService.PreSimulation:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local now = os.clock()
		if now >= nextGroundAt then
			local exclude: { Instance } = { animals }
			for _, player in Players:GetPlayers() do
				if player.Character then
					table.insert(exclude, player.Character)
				end
			end
			-- Same optional art/collision split used by BattleService. No
			-- required V3 map names are introduced by the follower.
			local map = Workspace:FindFirstChild("Map")
			local art = map and map:FindFirstChild("Art")
			if art then
				table.insert(exclude, art)
			end
			params.FilterDescendantsInstances = exclude
			nextGroundAt = now + GROUND_INTERVAL
		end
		for _, entry in entries do
			local ownerId = entry.source:GetAttribute("OwnerUserId")
			local owner = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
			local character = owner and owner.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if
				not owner
				or not root
				or not root:IsDescendantOf(Workspace)
				or not humanoid
				or humanoid.Health <= 0
				or owner:GetAttribute("InBattle") == true
				or (root.Position - camera.CFrame.Position).Magnitude > FAR
			then
				clear(entry)
				continue
			end
			local visual = entry.visual or makeVisual(entry.source)
			local petRoot = visual and visual.PrimaryPart
			if not visual or not petRoot then
				continue
			end
			local fresh = entry.visual == nil
			entry.visual = visual
			local settings = Config.Gameplay.team
			local radius = math.max(petRoot.Size.X, petRoot.Size.Z) / 2
			local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if forward.Magnitude < 0.001 then
				forward = Vector3.new(0, 0, -1)
			end
			local frame = CFrame.lookAt(root.Position, root.Position + forward)
			local target = (frame * CFrame.new(
				math.min(radius * 0.5, 2),
				0,
				settings.followDistance + radius * 0.5
			)).Position
			local last = entry.lastOwnerPosition
			local snap = fresh
				or entry.ownerRoot ~= root
				or (last ~= nil and (root.Position - last).Magnitude > settings.teleportDistance)
				or (petRoot.Position - target).Magnitude > settings.teleportDistance
			if snap or now >= entry.groundAt then
				local hit = Workspace:Raycast(target + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), params)
				entry.groundY = if hit
					then hit.Position.Y
					else root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
				entry.groundAt = now + GROUND_INTERVAL
			end
			local position = Vector3.new(target.X, (entry.groundY :: number) + petRoot.Size.Y / 2, target.Z)
			local goal = CFrame.new(position) * frame.Rotation
			visual:PivotTo(if snap then goal else visual:GetPivot():Lerp(goal, 1 - math.exp(-RESPONSE * dt)))
			-- Anchored cosmetics have no physics velocity. Animate from the
			-- owner, not from smoothing/turning/teleport correction.
			local velocity = root.AssemblyLinearVelocity
			visual:SetAttribute(
				"FollowerSpeed",
				if snap then 0 else Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			)
			entry.ownerRoot = root
			entry.lastOwnerPosition = root.Position
			if not visual.Parent then
				visual.Parent = animals -- PetAnimator and Show pets own their normal visual passes
			end
		end
	end)
end

return TeamFollower
