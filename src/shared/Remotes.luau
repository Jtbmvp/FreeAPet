--!strict
-- Every RemoteEvent in one place. The server creates them; the client
-- waits for them. Payload shapes are documented next to each name.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

export type Notification = {
	text: string,
	kind: "info" | "warning" | "success",
	-- A trade notification action; animalId holds the requester's UserId.
	action: { label: string, animalId: string, kind: string? }?,
	icon: string?, -- key in Config.UI.icons; default depends on kind
}

local NAMES = {
	"ChooseStarter", -- (expectedIndex: 1|2|3, speciesId: string)
	"StarterResult", -- Pending | Committed; grant and marker in one profile
	"HudCommerceAction", -- Nova v1 Intent
	"HudCommerceResult", -- Nova v1 Result; Committed only after OnAfterSave
	-- client -> server: (requestId: integer, kind: "pet" | "heal" | "cancel", animalId: string?)
	-- No prompt/key transport. Pet intent is resolved from current server state.
	"WorldAction",
	-- server -> client: authoritative progression delta (session/sequence/source)
	"ProgressionChanged",
	-- client -> server: (missionId, ownedPetId). Amounts and completion are server-only.
	"ClaimMission",
	-- server -> client: (requestId: integer, accepted: boolean, message: string)
	"WorldActionResult",
	-- server -> client: (Notification)
	"Notify",
	-- client -> server: () the client is listening; queued notifications can be sent
	"ClientReady",
	-- client -> server: (nodeId: string) start the next level of a research node
	"StartResearch",
	-- client -> server: (animalId: string, equip: boolean) add to / remove from the battle team
	"SetEquipped",
	-- server -> client: (BattleView) a battle started, changed or ended (see BattleService)
	"Battle",
	-- client -> server: (action: { kind: "move", index: number } | { kind: "capsule" }
	--   | { kind: "switch", petId: string } | { kind: "run" })
	"BattleAction",
	-- client -> server: (targetUserId: number) ask a player to trade
	"TradeRequest",
	-- client -> server: (requesterUserId: string) accept a trade request
	"TradeRespond",
	-- client -> server: ({ kind: "add" | "remove", id: string } | { kind: "ready" | "confirm" | "cancel" })
	"TradeAction",
	-- server -> client: (TradeView) the trade window state (see TradeService)
	"TradeUpdate",
}

-- RemoteFunctions (client asks, server answers).
local FUNCTIONS = {
	"GetStarters",
	"GetHudCommerce", -- (pendingRequestId: string?) -> Nova v1 Snapshot?
	-- () -> TabletView (see TabletService): the player's pets and Index
	"GetTablet",
	-- () -> player progression, unlocks and mission state (nil until Ready)
	"GetProgression",
}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.Get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.GetFunction(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
