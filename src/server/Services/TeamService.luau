--!strict
-- Battle team: up to Config.Gameplay.team.maxEquipped pets walk behind their
-- owner. Equipped pets keep their base slot (they come back to it), earn no
-- cash and cannot be stolen. Equipping is a prompt on a base pet ("Equip",
-- key F) and "Send home" on a following pet, both shown only to the owner;
-- the tablet will replace these prompts later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local AnimalService = require(script.Parent.AnimalService)
local HomeService = require(script.Parent.HomeService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)

type AnimalRecord = AnimalService.AnimalRecord

local TeamService = {}

local TICK_SECONDS = 0.25
-- Per team position: X = side (in pet widths), Y = distance back (x followDistance).
local FORMATION = { Vector2.new(-1, 0.6), Vector2.new(1, 0.6), Vector2.new(-2, 1.3) }

local teams: { [Player]: { AnimalRecord } } = {}
local paused: { [Player]: boolean } = {} -- in a battle: BattleService places the pets

local function setPrompt(
	record: AnimalRecord,
	name: string,
	action: string,
	key: Enum.KeyCode,
	onTrigger: (Player) -> ()
)
	local root = record.model and record.model.PrimaryPart
	if not root then
		return
	end
	local existing = root:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = action
	prompt.ObjectText = Config.Species[record.speciesId].displayName
	prompt.KeyboardKeyCode = key
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 8 + AnimalService.Radius(record.model :: Model)
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OwnerUserId", record.ownerUserId)
	prompt.Parent = root
	prompt.Triggered:Connect(onTrigger)
end

local function removePrompt(record: AnimalRecord, name: string)
	local root = record.model and record.model.PrimaryPart
	local prompt = root and root:FindFirstChild(name)
	if prompt then
		prompt:Destroy()
	end
end

-- Stops (or resumes) moving a player's team, e.g. during a battle.
function TeamService.SetPaused(player: Player, value: boolean)
	paused[player] = if value then true else nil
end

function TeamService.GetTeam(player: Player): { AnimalRecord }
	return table.clone(teams[player] or {})
end

function TeamService.Equip(player: Player, record: AnimalRecord, quiet: boolean?): boolean
	local team = teams[player]
	if not team or record.ownerUserId ~= player.UserId or record.state ~= "InBase" then
		return false
	end
	if #team >= Config.Gameplay.team.maxEquipped then
		if not quiet then
			NotifyService.Send(player, {
				text = `Your team is full ({Config.Gameplay.team.maxEquipped} pets). Send one home first.`,
				kind = "info",
			})
		end
		return false
	end
	record.state = "Following"
	table.insert(team, record)
	removePrompt(record, "PickUpPrompt")
	removePrompt(record, "EquipPrompt")
	local root = record.model and record.model.PrimaryPart
	local label = root and root:FindFirstChild("IncomeLabel") :: BillboardGui?
	if label then
		label.Enabled = false -- equipped pets earn nothing
	end
	setPrompt(record, "UnequipPrompt", "Send home", Enum.KeyCode.E, function(who)
		if who == player then
			TeamService.Unequip(player, record)
		end
	end)
	local character = player.Character
	local ownerRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if ownerRoot and record.model then
		record.model:PivotTo(ownerRoot.CFrame * CFrame.new(0, 0, Config.Gameplay.team.followDistance))
	end
	HomeService.RefreshIncome(player)
	return true
end

function TeamService.Unequip(player: Player, record: AnimalRecord): boolean
	local team = teams[player]
	local index = team and table.find(team, record)
	if not team or not index then
		return false
	end
	table.remove(team, index)
	removePrompt(record, "UnequipPrompt")
	HomeService.PlaceBack(player, record) -- back to its slot: wanders and earns again
	return true
end

-- Walk each equipped pet to its spot behind the owner (a small V formation).
local function follow(player: Player, team: { AnimalRecord })
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local settings = Config.Gameplay.team
	for i, record in team do
		local model = record.model
		local petRoot = model and model.PrimaryPart
		local petHumanoid = model and model:FindFirstChildOfClass("Humanoid")
		if petRoot and petHumanoid then
			-- Pets walk beside and behind the owner, never straight behind, so
			-- they stay out of the camera's line; spacing grows with the pet.
			local radius = AnimalService.Radius(model :: Model)
			local slot = FORMATION[i] or FORMATION[#FORMATION]
			local side = slot.X * (2 + radius)
			local back = settings.followDistance * slot.Y + radius
			local goal = (root.CFrame * CFrame.new(side, 0, back)).Position
			local distance = (petRoot.Position - root.Position).Magnitude
			if distance > settings.teleportDistance then
				model:PivotTo(CFrame.new(goal + Vector3.new(0, 2, 0)) * root.CFrame.Rotation)
			end
			petHumanoid.WalkSpeed = math.max(humanoid.WalkSpeed * 1.15, 8)
			if (petRoot.Position - goal).Magnitude > 2 then
				petHumanoid:MoveTo(goal)
			end
		end
	end
end

function TeamService.Start()
	-- After the base is rebuilt from the save, re-equip the saved team.
	PlayerDataService.OnLoaded(function(player: Player, data: Types.PlayerData)
		for id, saved in data.animals do
			if saved.equipped then
				local record = AnimalService.Get(id)
				if record then
					TeamService.Equip(player, record, true)
				end
			end
		end
	end)
	PlayerDataService.OnBeforeSave(function(player: Player, data: Types.PlayerData)
		for id, saved in data.animals do
			local record = AnimalService.Get(id)
			saved.equipped = if record
					and record.ownerUserId == player.UserId
					and record.state == "Following"
				then true
				else nil
		end
	end)

	local function onPlayerAdded(player: Player)
		teams[player] = {}
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	-- The records themselves leave with HomeService (they keep their slot).
	PlayerDataService.OnReleasing(function(player)
		teams[player] = nil
		paused[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			for player, team in teams do
				if #team > 0 and not paused[player] then
					follow(player, team)
				end
			end
		end
	end)
end

return TeamService
