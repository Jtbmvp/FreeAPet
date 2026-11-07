--!strict
-- Authoritative battle roster. Equipped pets keep their slots, earn no
-- cash and cannot be stolen. Only the leader has a cosmetic follower;
-- every equipped pet remains available to BattleService. Pets UI manages
-- equipping and sending home (no interaction prompts on companions).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local AnimalService = require(script.Parent.AnimalService)
local HomeService = require(script.Parent.HomeService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local FollowerPolicy = require(script.Parent.FollowerPolicy)
local TeamPresentation = require(script.Parent.TeamPresentation)
local ProgressionService = require(script.Parent.ProgressionService)

type AnimalRecord = AnimalService.AnimalRecord

local Guard = require(script.Parent.PlayerMutationGuard)
local TeamService = {}

local teams: { [Player]: { AnimalRecord } } = {}
local paused: { [Player]: boolean } = {} -- in a battle: BattleService places the pets

local function refreshFollower(player: Player)
	local team = teams[player] or {}
	for _, record in team do
		if paused[player] then
			TeamPresentation.Release(record)
		else
			TeamPresentation.Stow(record)
		end
	end
	TeamPresentation.Show(player, if paused[player] then nil else FollowerPolicy.Select(team))
end

-- Hands all real models to the battle, or restores the cosmetic follower.
function TeamService.SetPaused(player: Player, value: boolean)
	paused[player] = if value then true else nil
	refreshFollower(player)
end

function TeamService.GetTeam(player: Player): { AnimalRecord }
	return table.clone(teams[player] or {})
end

-- The team is locked during a battle (and its playback): fighters stay fighters.
local function lockedInBattle(player: Player, quiet: boolean?): boolean
	if player:GetAttribute("InBattle") ~= true then
		return false
	end
	if not quiet then
		NotifyService.Send(player, { text = "You can't change your team during a battle.", kind = "info" })
	end
	return true
end

function TeamService.Equip(player: Player, record: AnimalRecord, quiet: boolean?, internal: boolean?): boolean
	if Guard.IsBusy(player) and not internal then
		return false
	end
	local team = teams[player]
	if
		not team
		or record.ownerUserId ~= player.UserId
		or (record.state ~= "InBase" and record.state ~= "Inventory")
	then
		return false
	end
	if lockedInBattle(player, quiet) then
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
	AnimalService.EnsureModel(record)
	record.state = "Following"
	table.insert(team, record)
	local root = record.model and record.model.PrimaryPart
	local label = root and root:FindFirstChild("IncomeLabel") :: BillboardGui?
	if label then
		label.Enabled = false -- equipped pets earn nothing
	end
	refreshFollower(player)
	HomeService.RefreshIncome(player)
	HomeService.SaveCaught(player, record)
	return true
end

function TeamService.Unequip(player: Player, record: AnimalRecord): boolean
	if Guard.IsBusy(player) then
		return false
	end
	local team = teams[player]
	local index = team and table.find(team, record)
	if not team or not index or lockedInBattle(player) then
		return false
	end
	table.remove(team, index)
	TeamPresentation.Release(record)
	if not HomeService.PlaceBack(player, record) then
		table.insert(team, index :: number, record)
		refreshFollower(player)
		return false
	end
	refreshFollower(player)
	HomeService.SaveCaught(player, record)
	return true
end

-- Internal batch operations; all input validation precedes presentation changes.
function TeamService.Replace(player: Player, selected: { AnimalRecord }): boolean
	if
		not teams[player]
		or player:GetAttribute("InBattle")
		or #selected > Config.Gameplay.team.maxEquipped
	then
		return false
	end
	local seen = {}
	for _, record in selected do
		if
			seen[record.id]
			or record.ownerUserId ~= player.UserId
			or (record.state ~= "InBase" and record.state ~= "Inventory" and record.state ~= "Following")
		then
			return false
		end
		seen[record.id] = true
	end
	for _, record in selected do
		AnimalService.EnsureModel(record)
	end
	for _, record in teams[player] do
		if not seen[record.id] then
			TeamPresentation.Release(record)
			HomeService.PlaceBack(player, record)
		end
	end
	teams[player] = table.clone(selected)
	for _, record in selected do
		record.state = "Following"
		local root = record.model and record.model.PrimaryPart
		local label = root and root:FindFirstChild("IncomeLabel") :: BillboardGui?
		if label then
			label.Enabled = false
		end
	end
	refreshFollower(player)
	HomeService.RefreshIncome(player)
	return true
end

function TeamService.DetachForSale(player: Player, record: AnimalRecord)
	local team = teams[player]
	local index = team and table.find(team, record)
	if team and index then
		table.remove(team, index)
		TeamPresentation.Release(record)
		record.state = "Inventory"
		refreshFollower(player)
	end
end

function TeamService.Start()
	TeamPresentation.Start()
	ProgressionService.OnPetChanged(function(player)
		if not paused[player] then
			TeamPresentation.Clear(player) -- the same leader may have grown
			refreshFollower(player)
		end
	end)
	-- After the base is rebuilt from the save, re-equip the saved team.
	PlayerDataService.OnLoaded(function(player: Player, data: Types.PlayerData)
		local ids = {}
		for id in data.animals do
			table.insert(ids, id)
		end
		table.sort(ids, function(a, b)
			local ao, bo = data.animals[a].teamOrder or math.huge, data.animals[b].teamOrder or math.huge
			return if ao ~= bo then ao < bo else a < b
		end)
		for _, id in ids do
			local saved = data.animals[id]
			if saved.equipped and not saved.unavailableReason then
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
			saved.teamOrder = if saved.equipped and record
				then table.find(teams[player] or {}, record)
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
		TeamPresentation.Forget(player, teams[player] or {})
		teams[player] = nil
		paused[player] = nil
	end)
end

return TeamService
