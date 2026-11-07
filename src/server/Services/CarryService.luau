--!strict
-- Only wild captures use transport. Owned pets cannot be released or stolen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local AnimalService = require(script.Parent.AnimalService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionService = require(script.Parent.ProgressionService)
local ZoneService = require(script.Parent.ZoneService)

type AnimalRecord = AnimalService.AnimalRecord
local CarryService = {}
local carriedByPlayer: { [Player]: { AnimalRecord } } = {}
local pending: { [string]: { player: Player, recipientId: string? } } = {}
local battleHandler: ((Player, AnimalRecord) -> ())? = nil
local acquisitionGuard: ((Player) -> boolean)? = nil

local function updateCount(player: Player)
	player:SetAttribute("CarryCount", #(carriedByPlayer[player] or {}))
end

function CarryService.SetAcquisitionGuard(handler: (Player) -> boolean)
	acquisitionGuard = handler
end

function CarryService.SetBattleHandler(handler: ((Player, AnimalRecord) -> ())?)
	battleHandler = handler
end

function CarryService.TryCatch(player: Player, record: AnimalRecord, recipientId: string?): boolean
	if not PlayerDataService.IsReady(player) or record.state ~= "Wild" or record.ownerUserId then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local model = record.model
	if not humanoid or humanoid.Health <= 0 or not root or not model or not model.PrimaryPart then
		return false
	end
	local distance = (root.Position - model.PrimaryPart.Position).Magnitude - AnimalService.Radius(model)
	if distance ~= distance or distance > Config.Gameplay.capture.maxDistance then
		return false
	end
	if battleHandler then
		battleHandler(player, record)
		return player:GetAttribute("InBattle") == true
	end
	if acquisitionGuard and not acquisitionGuard(player) then
		return false
	end
	local carried = carriedByPlayer[player] or {}
	local publishedCapacity = player:GetAttribute("CarryCapacity")
	local capacity = if typeof(publishedCapacity) == "number"
		then publishedCapacity
		else Config.Gameplay.carry.startingCapacity
	if #carried >= capacity then
		NotifyService.Send(
			player,
			{ text = "Your hands are full! Take the pet to your base first.", kind = "info", icon = "carry" }
		)
		return false
	end
	record.origin = record.origin
		or {
			ownerUserId = player.UserId,
			ownerName = player.DisplayName,
			capturedAt = os.time(),
			place = ZoneService.ZoneAt(root.Position),
		}
	record.state, record.carrier = "Carried", player
	pending[record.id] = { player = player, recipientId = recipientId }
	table.insert(carried, record)
	carriedByPlayer[player] = carried
	local petRoot = model.PrimaryPart
	local petHumanoid = model:FindFirstChildOfClass("Humanoid")
	if petHumanoid then
		petHumanoid.EvaluateStateMachine = false
	end
	petRoot.CanCollide, petRoot.Massless = false, true
	local height = model:GetExtentsSize().Y
	model:PivotTo(root.CFrame * CFrame.new(0, 3 + height / 2 + (#carried - 1) * height, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Name, weld.Part0, weld.Part1, weld.Parent = "CarryWeld", root, petRoot, petRoot
	updateCount(player)
	return true
end

-- Only HomeService calls this after the acquisition is in the owner's save.
function CarryService.ConfirmCapture(player: Player, record: AnimalRecord)
	local capture = pending[record.id]
	pending[record.id] = nil
	if not capture or capture.player ~= player then
		return
	end
	local recipient = capture.recipientId and AnimalService.Get(capture.recipientId)
	local recipients = {}
	if recipient and recipient.ownerUserId == player.UserId and recipient ~= record then
		table.insert(recipients, recipient)
	end
	ProgressionService.Outcome(player, "capture", record.level, recipients, record.id)
end

function CarryService.GetCarried(player: Player): { AnimalRecord }
	return table.clone(carriedByPlayer[player] or {})
end

function CarryService.Take(player: Player, record: AnimalRecord): boolean
	local carried = carriedByPlayer[player]
	local index = carried and table.find(carried, record)
	if not carried or not index then
		return false
	end
	table.remove(carried, index)
	record.carrier = nil
	local model = record.model
	local weld = model and model.PrimaryPart and model.PrimaryPart:FindFirstChild("CarryWeld")
	if weld then
		weld:Destroy()
	end
	updateCount(player)
	return true
end

function CarryService.ReturnAllHome(player: Player)
	for _, record in CarryService.GetCarried(player) do
		CarryService.Take(player, record)
		pending[record.id] = nil
		AnimalService.ReturnHome(record) -- unconfirmed wild catches stay wild, no EXP
	end
	carriedByPlayer[player] = nil
	if player.Parent then
		updateCount(player)
	end
end

function CarryService.Start()
	local function added(player: Player)
		updateCount(player)
		local function characterAdded(character: Model)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.Died:Connect(function()
				CarryService.ReturnAllHome(player)
			end)
		end
		player.CharacterAdded:Connect(characterAdded)
		if player.Character then
			task.spawn(characterAdded, player.Character)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, player in Players:GetPlayers() do
		added(player)
	end
	Players.PlayerRemoving:Connect(CarryService.ReturnAllHome)
end

return CarryService
