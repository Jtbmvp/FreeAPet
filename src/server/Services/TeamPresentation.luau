--!strict
-- Owns presentation only. Real team models are held off-world during
-- exploration; one sanitized template lets each client render the leader.
-- Battles get the original models back, with their physics restored.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local AnimalService = require(script.Parent.AnimalService)
type AnimalRecord = AnimalService.AnimalRecord

local TeamPresentation = {}

type SavedPhysics = { anchored: boolean, evaluate: boolean? }
local stored: { [Model]: SavedPhysics } = {}
local templates: { [Player]: Model } = {}
local reserves: Folder
local followers: Folder

function TeamPresentation.Clear(player: Player)
	local template = templates[player]
	if template then
		templates[player] = nil
		template:Destroy()
	end
end

function TeamPresentation.Stow(record: AnimalRecord)
	local model = record.model
	local root = model and model.PrimaryPart
	if not model or not root or stored[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	stored[model] = {
		anchored = root.Anchored,
		evaluate = if humanoid then humanoid.EvaluateStateMachine else nil,
	}
	if humanoid then
		humanoid:Move(Vector3.zero)
		humanoid.EvaluateStateMachine = false
	end
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	model:SetAttribute("State", "Following")
	model.Parent = reserves
end

function TeamPresentation.Release(record: AnimalRecord)
	local model = record.model
	local physics = model and stored[model]
	local root = model and model.PrimaryPart
	if not model or not root or not physics then
		return
	end
	stored[model] = nil
	model.Parent = Workspace.Animals
	root.Anchored = physics.anchored
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and physics.evaluate ~= nil then
		humanoid.EvaluateStateMachine = physics.evaluate
	end
	if not root.Anchored then
		root:SetNetworkOwner(nil)
	end
end

function TeamPresentation.Show(player: Player, leader: AnimalRecord?)
	local existing = templates[player]
	if existing and leader and existing:GetAttribute("AnimalId") == leader.id then
		return
	end
	TeamPresentation.Clear(player)
	local model = leader and leader.model
	if not model or not model.PrimaryPart then
		return
	end
	local template = model:Clone()
	template.Name = tostring(player.UserId)
	for _, item in template:GetDescendants() do
		if item:IsA("ProximityPrompt") or item:IsA("BillboardGui") or item:IsA("Humanoid") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
		end
	end
	template:SetAttribute("OwnerUserId", player.UserId)
	template:SetAttribute("State", "Following")
	-- Replication order is not guaranteed: clients wait for the complete rig.
	template:SetAttribute("FollowerDescendants", #template:GetDescendants())
	templates[player] = template
	template.Parent = followers
end

function TeamPresentation.Forget(player: Player, team: { AnimalRecord })
	TeamPresentation.Clear(player)
	for _, record in team do
		if record.model then
			stored[record.model] = nil
		end
	end
	-- HomeService owns removing the real records/models on profile release.
end

function TeamPresentation.Start()
	reserves = Instance.new("Folder")
	reserves.Name = "EquippedPets"
	reserves.Parent = ServerStorage
	followers = Instance.new("Folder")
	followers.Name = "TeamFollowers"
	followers.Parent = ReplicatedStorage
end

return TeamPresentation
