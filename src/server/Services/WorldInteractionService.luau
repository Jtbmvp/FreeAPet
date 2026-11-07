--!strict
-- GUI intents only. The server resolves targets, permissions and outcomes.
-- Direct wild capture keeps its server-timed window; Challenge/Heal use GUI activation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BattleMath = require(ReplicatedStorage.Shared.BattleMath)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AnimalService = require(script.Parent.AnimalService)
local BattleService = require(script.Parent.BattleService)
local CarryService = require(script.Parent.CarryService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local TeamService = require(script.Parent.TeamService)
local FollowerPolicy = require(script.Parent.FollowerPolicy)

type AnimalRecord = AnimalService.AnimalRecord
type Capture = {
	requestId: number,
	record: AnimalRecord,
	model: Model,
	character: Model,
	ownerUserId: number?,
	state: string,
	endsAt: number,
	recipientId: string?,
}

local Guard = require(script.Parent.PlayerMutationGuard)
local WorldInteractionService = {}
local captures: { [Player]: Capture } = {}
local lastRequest: { [Player]: number } = {}
local REQUEST_SECONDS = 0.25
local CHECK_SECONDS = 0.1

local function answer(player: Player, requestId: number, accepted: boolean, message: string)
	if player.Parent == Players then
		Remotes.Get("WorldActionResult"):FireClient(player, requestId, accepted, message)
	end
end

local function ready(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil
		and humanoid.Health > 0
		and PlayerDataService.IsReady(player)
		and not BattleService.IsBusy(player)
		and not Guard.IsBusy(player)
end

local function reachable(player: Player, record: AnimalRecord): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local model = record.model
	local petRoot = model and model.PrimaryPart
	if
		not ready(player)
		or not root
		or not model
		or not petRoot
		or not model:IsDescendantOf(Workspace)
		or (record.state ~= "Wild" or record.ownerUserId ~= nil)
	then
		return false
	end
	local distance = (root.Position - petRoot.Position).Magnitude - AnimalService.Radius(model)
	return distance == distance and distance <= Config.Gameplay.capture.maxDistance
end

local function cancel(player: Player, capture: Capture, message: string)
	if captures[player] == capture then
		captures[player] = nil
		answer(player, capture.requestId, false, message)
	end
end

local function poll(player: Player, capture: Capture)
	if captures[player] ~= capture then
		return
	end
	local record = capture.record
	if
		player.Parent ~= Players
		or player.Character ~= capture.character
		or AnimalService.Get(record.id) ~= record
		or record.model ~= capture.model
		or record.state ~= capture.state
		or record.ownerUserId ~= capture.ownerUserId
		or BattleMath.Enabled()
		or not reachable(player, record)
	then
		cancel(player, capture, "Capture cancelled: the target or your position changed.")
		return
	end
	if os.clock() < capture.endsAt then
		task.delay(CHECK_SECONDS, poll, player, capture)
		return
	end
	captures[player] = nil -- no yield between final validation and mutation
	local accepted = CarryService.TryCatch(player, record, capture.recipientId)
	answer(
		player,
		capture.requestId,
		accepted,
		if accepted then "Pet picked up." else "This pet cannot be picked up right now."
	)
end

local function onAction(player: Player, requestId: unknown, kind: unknown, targetId: unknown)
	if
		typeof(requestId) ~= "number"
		or requestId ~= requestId
		or requestId % 1 ~= 0
		or requestId < 1
		or requestId > 2147483647
		or typeof(kind) ~= "string"
		or #kind > 8
	then
		return
	end
	if kind == "cancel" then
		local capture = captures[player]
		if capture and capture.requestId == requestId then
			cancel(player, capture, "Capture cancelled.")
		end
		return
	end
	if kind ~= "pet" and kind ~= "heal" then
		return
	end
	if kind == "pet" and (typeof(targetId) ~= "string" or #targetId > 64 or #targetId == 0) then
		return
	end
	local now = os.clock()
	if now - (lastRequest[player] or -math.huge) < REQUEST_SECONDS then
		answer(player, requestId, false, "Please wait before trying again.")
		return
	end
	lastRequest[player] = now
	if not ready(player) or captures[player] then
		answer(player, requestId, false, "You cannot interact right now.")
		return
	end
	if kind == "heal" then
		local accepted, message = BattleService.HealAtFountain(player)
		answer(player, requestId, accepted, message)
		return
	end
	local record = AnimalService.Get(targetId :: string)
	if not record or not reachable(player, record) then
		answer(player, requestId, false, "This pet is no longer available or is out of reach.")
		return
	end
	-- Carry/Battle retain capacity, team, arena and capture-result checks.
	if BattleMath.Enabled() then
		local accepted = CarryService.TryCatch(player, record)
		answer(
			player,
			requestId,
			accepted,
			if accepted
				then "Action started."
				else "This action is unavailable. Check your team and carrying capacity."
		)
		return
	end
	local leader = FollowerPolicy.Select(TeamService.GetTeam(player))
	local capture: Capture = {
		requestId = requestId,
		record = record,
		model = record.model :: Model,
		character = player.Character :: Model,
		ownerUserId = record.ownerUserId,
		state = record.state,
		endsAt = now + Config.Gameplay.capture.holdSeconds,
		recipientId = if leader then leader.id else nil,
	}
	captures[player] = capture
	poll(player, capture)
end

function WorldInteractionService.Start()
	Remotes.Get("WorldAction").OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		captures[player] = nil
		lastRequest[player] = nil
	end)
end

return WorldInteractionService
