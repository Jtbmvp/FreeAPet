--!strict
-- Wild battles (docs/BATTLES.md). The player selects "Battle" on a wild pet;
-- an arena ring appears where they stand, their first healthy team pet faces
-- the wild one and both stay put. Turn by turn the player picks a move, a
-- Pet Capsule, a switch or running away; the server decides everything
-- (order by Speed, damage, captures, XP) and sends the client a view of the
-- battle plus what happened ("Battle" remote), which the client animates.
-- A target in battle cannot be grabbed by anyone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BattleMath = require(ReplicatedStorage.Shared.BattleMath)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AnimalService = require(script.Parent.AnimalService)
local CarryService = require(script.Parent.CarryService)
local HomeService = require(script.Parent.HomeService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local PlayerStateService = require(script.Parent.PlayerStateService)
local TeamService = require(script.Parent.TeamService)
local ZoneService = require(script.Parent.ZoneService)
local ProgressionService = require(script.Parent.ProgressionService)

type AnimalRecord = AnimalService.AnimalRecord

type Fighter = {
	record: AnimalRecord,
	stats: BattleMath.Stats,
	hp: number,
	uses: { [number]: number }, -- uses left of limited moves, by move index
}

type Battle = {
	player: Player,
	wild: Fighter,
	team: { Fighter },
	active: number, -- index in team
	fought: { [Fighter]: boolean }, -- team pets that got XP
	centre: CFrame, -- looking from the player's side towards the wild pet
	arena: Model,
	deadline: number, -- os.clock() by when the player must act
	ended: boolean,
	kind: string, -- wild encounter
	foeLabel: string, -- "Wild Acorn Squirrel" / "Ana's Acorn Squirrel"
}

-- One line of what happened, for the client to show and animate.
export type BattleEvent = {
	text: string,
	actor: string?, -- "mine" | "wild": who moved
	target: string?, -- "mine" | "wild": who was hit
	damage: number?,
	effect: string?, -- "super" | "weak" | "capture" | "escape" | "faint" | "levelup" | "switch"
	moveType: string?,
}

local Guard = require(script.Parent.PlayerMutationGuard)
local BattleService = {}

local LAYOUT = Config.Battle.layout
-- Arena turns tried (degrees from "player looks at the foe"), best view wins.
local FACING_TRIES = { 0, 30, -30, 60, -60 }
local RING_SEGMENTS = 28
local EVENT_SECONDS = 0.95 -- how long the client shows each event (BattleScreen)
local benchX = LAYOUT.bench.X - math.max(0, Config.Gameplay.team.maxEquipped - 2) * 4
local ARENA_FOOTPRINT_RADIUS = math.max(
	Config.Battle.arenaRadius,
	Vector2.new(LAYOUT.camera.X, LAYOUT.camera.Z).Magnitude,
	Vector2.new(LAYOUT.player.X, LAYOUT.player.Z).Magnitude,
	Vector2.new(benchX, LAYOUT.bench.Z).Magnitude
) + 0.5

local battles: { [Player]: Battle } = {}
-- Ended battles still playing back on the client: no new battle until the
-- player has left the old one (leavePlayer).
local leaving: { [Player]: Battle } = {}
local HEAL_COOLDOWN = 2 -- seconds between fountain heals
local HEAL_DISTANCE = 30 -- existing fountain interaction radius
local lastHealAt: { [Player]: number } = {}
local rng = Random.new()
local battleFolder: Folder

local function fighterOf(record: AnimalRecord): Fighter
	local stats = BattleMath.Stats(record.speciesId, record.level)
	local uses = {}
	for index, move in Config.Battle.species[record.speciesId].moves do
		if move.uses then
			uses[index] = move.uses
		end
	end
	return { record = record, stats = stats, hp = math.clamp(record.hp or stats.hp, 0, stats.hp), uses = uses }
end

local function nameOf(fighter: Fighter): string
	return Config.Species[fighter.record.speciesId].displayName
end

local function groundAt(position: Vector3, ignore: Instance?): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { battleFolder }
	if ignore then
		table.insert(exclude, ignore)
	end
	-- The visual mesh layer sits on the collision parts: only hit the latter.
	for _, name in { "Animals", "Art" } do
		local folder = Workspace:FindFirstChild(name)
			or Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	-- From just above head height: higher up, the ray lands on tree canopies.
	local hit = Workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position else position
end

-- Stands a pet on the ground at `position`, facing `lookAt`, and holds it there.
local function placePet(record: AnimalRecord, position: Vector3, lookAt: Vector3)
	local model = record.model
	if not model or not model.PrimaryPart then
		return
	end
	local ground = groundAt(position)
	local height = model:GetExtentsSize().Y / 2
	local flatLook = Vector3.new(lookAt.X, ground.Y + height, lookAt.Z)
	model.PrimaryPart.Anchored = true
	model:PivotTo(CFrame.lookAt(ground + Vector3.new(0, height, 0), flatLook))
end

local function buildArena(centre: CFrame): Model
	local arena = Instance.new("Model")
	arena.Name = "Arena"
	local radius = Config.Battle.arenaRadius
	local ground = groundAt(centre.Position)
	for i = 1, RING_SEGMENTS do
		local angle = (i / RING_SEGMENTS) * math.pi * 2
		local segment = Instance.new("Part")
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.Material = Enum.Material.Neon
		segment.Color = Color3.fromRGB(120, 210, 255)
		segment.Transparency = 0.25
		segment.Size = Vector3.new(0.5, 0.25, 2 * math.pi * radius / RING_SEGMENTS + 0.3)
		local point = ground + Vector3.new(math.cos(angle) * radius, 0.15, math.sin(angle) * radius)
		segment.CFrame = CFrame.lookAt(point, ground + Vector3.new(0, 0.15, 0))
			* CFrame.Angles(0, math.pi / 2, 0)
		segment.Parent = arena
	end
	arena.Parent = battleFolder
	return arena
end

-- Counts what would block the battle camera if the arena faced this way:
-- trees, rocks and cacti between the camera spot and each pet, and a wall
-- between the centre and where the player will stand.
local function blockers(centre: CFrame): number
	local collision = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Collision")
	if not collision then
		return 0
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { collision }
	local eye = (centre * CFrame.new(LAYOUT.camera)).Position
	local count = 0
	for _, spot in { LAYOUT.mine, LAYOUT.foe, Vector3.zero } do
		local target = (centre * CFrame.new(spot)).Position + Vector3.new(0, 2.5, 0)
		if Workspace:Raycast(eye, target - eye, params) then
			count += 1
		end
	end
	local from = centre.Position + Vector3.new(0, 3, 0)
	local stand = (centre * CFrame.new(LAYOUT.player)).Position
	if Workspace:Raycast(from, stand - from, params) then
		count += 5
	end
	return count
end

-- The arena centre facing the foe, turned up to 60 degrees if that gives
-- the camera a clearer view of the fight.
local function clearestFacing(ground: Vector3, direction: Vector3): CFrame
	local best, bestCount = CFrame.lookAt(ground, ground + direction), math.huge
	for _, degrees in FACING_TRIES do
		local centre = CFrame.lookAt(ground, ground + direction) * CFrame.Angles(0, math.rad(degrees), 0)
		local count = blockers(centre)
		if count < bestCount then
			best, bestCount = centre, count
		end
		if count == 0 then
			break
		end
	end
	return best
end

local function moveView(fighter: Fighter)
	local moves = {}
	for index, move in Config.Battle.species[fighter.record.speciesId].moves do
		table.insert(moves, {
			name = move.name,
			type = move.type,
			power = move.power,
			usesLeft = fighter.uses[index],
			maxUses = move.uses,
		})
	end
	return moves
end

local function fighterView(fighter: Fighter)
	return {
		id = fighter.record.id,
		speciesId = fighter.record.speciesId,
		level = fighter.record.level,
		xp = fighter.record.xp,
		xpToNext = if fighter.record.level >= Config.Progression.pet.maxLevel
			then 0
			else BattleMath.XpToNext(fighter.record.level),
		hp = fighter.hp,
		maxHp = fighter.stats.hp,
		model = fighter.record.model,
	}
end

local function send(battle: Battle, events: { BattleEvent }, result: string?)
	local data = PlayerDataService.Get(battle.player)
	local mine = battle.team[battle.active]
	local team = {}
	for _, fighter in battle.team do
		table.insert(team, fighterView(fighter))
	end
	local mineView: any = fighterView(mine)
	mineView.moves = moveView(mine)
	Remotes.Get("Battle"):FireClient(battle.player, {
		centre = battle.centre,
		arena = battle.arena,
		wild = fighterView(battle.wild),
		mine = mineView,
		team = team,
		capsules = if data then data.capsules else 0,
		capsulePrice = Config.Battle.capsule.price,
		events = events,
		result = result, -- nil while the battle goes on: "won" | "lost" | "captured" | "ran"
		timeout = Config.Battle.choiceTimeoutSeconds,
		role = "attacker",
		kind = battle.kind,
		foeName = battle.foeLabel,
	})
end

local function chooseWildMove(wild: Fighter): number
	local moves = Config.Battle.species[wild.record.speciesId].moves
	-- The strong move (last) has its own chance, so it isn't used too often.
	local strong = #moves
	if (wild.uses[strong] or 0) > 0 and rng:NextNumber() < Config.Battle.wildStrongMoveChance then
		return strong
	end
	local options = {}
	for index, move in moves do
		if index ~= strong and (not move.uses or (wild.uses[index] or 0) > 0) then
			table.insert(options, index)
		end
	end
	return options[rng:NextInteger(1, #options)]
end

local function labelOf(battle: Battle, fighter: Fighter): string
	return if fighter == battle.wild then battle.foeLabel else nameOf(fighter)
end

-- One attack. Appends what happened; returns true if the target fainted.
local function attack(
	battle: Battle,
	attacker: Fighter,
	defender: Fighter,
	moveIndex: number,
	actor: string,
	events: { BattleEvent }
): boolean
	local move = Config.Battle.species[attacker.record.speciesId].moves[moveIndex]
	if move.uses then
		attacker.uses[moveIndex] = (attacker.uses[moveIndex] or 0) - 1
	end
	local defenderType = Config.Battle.species[defender.record.speciesId].type
	local typeMultiplier = BattleMath.TypeMultiplier(move.type, defenderType)
	local damage = BattleMath.Damage(
		move.power,
		attacker.stats.attack,
		defender.stats.defense,
		typeMultiplier,
		rng:NextNumber()
	)
	defender.hp = math.max(0, defender.hp - damage)
	table.insert(events, {
		text = `{labelOf(battle, attacker)} used {move.name}!`,
		actor = actor,
		target = if actor == "wild" then "mine" else "wild",
		damage = damage,
		effect = if typeMultiplier > 1 then "super" elseif typeMultiplier < 1 then "weak" else nil,
		moveType = move.type,
		move = move.name, -- picks the attack's own animation and effects
	})
	if typeMultiplier > 1 then
		table.insert(events, { text = "It's super effective!" })
	elseif typeMultiplier < 1 then
		table.insert(events, { text = "It's not very effective..." })
	end
	if defender.hp <= 0 then
		table.insert(events, {
			text = `{labelOf(battle, defender)} fainted!`,
			target = if actor == "wild" then "mine" else "wild",
			effect = "faint",
		})
		return true
	end
	return false
end

local function nextAlive(battle: Battle): number?
	for index, fighter in battle.team do
		if fighter.hp > 0 then
			return index
		end
	end
	return nil
end

local function leavePlayer(battle: Battle)
	local player = battle.player
	player:SetAttribute("InBattle", nil)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local walkSpeed = player:GetAttribute("WalkSpeed")
		humanoid.WalkSpeed = if typeof(walkSpeed) == "number"
			then walkSpeed
			else Config.Gameplay.player.walkSpeed
		humanoid.JumpHeight = 7.2
	end
	for _, fighter in battle.team do
		local model = fighter.record.model
		if model and model.PrimaryPart then
			model.PrimaryPart.Anchored = false
		end
		AnimalService.Rescale(fighter.record)
	end
	TeamService.SetPaused(player, false)
end

local function grantOutcome(battle: Battle, kind: string, events: { BattleEvent })
	local participants = {}
	local levels: { [AnimalRecord]: number } = {}
	for fighter in battle.fought do
		fighter.record.hp = fighter.hp
		levels[fighter.record] = fighter.record.level
		table.insert(participants, fighter.record)
	end
	if
		not ProgressionService.Outcome(
			battle.player,
			kind,
			battle.wild.record.level,
			participants,
			battle.wild.record.id
		)
	then
		return
	end
	for fighter in battle.fought do
		local record = fighter.record
		fighter.hp = record.hp or fighter.hp
		fighter.stats = BattleMath.Stats(record.speciesId, record.level)
		if record.level > levels[record] then
			table.insert(
				events,
				{ text = `{nameOf(fighter)} grew to Lv {record.level}!`, effect = "levelup" }
			)
		end
	end
end

local function finish(battle: Battle, result: string, events: { BattleEvent })
	if battle.ended then
		return
	end
	battle.ended = true
	battles[battle.player] = nil
	local player = battle.player
	local wild = battle.wild

	if result == "captured" then
		local record = wild.record
		record.hp = if wild.hp >= wild.stats.hp then nil else wild.hp
		record.origin = record.origin
			or {
				ownerUserId = player.UserId,
				ownerName = player.DisplayName,
				capturedAt = os.time(),
				place = if record.model and record.model.PrimaryPart
					then ZoneService.ZoneAt(record.model.PrimaryPart.Position)
					else Config.Species[record.speciesId].biome or "Starter",
			}
		if not HomeService.ReserveAcquisition(player, record) then
			result = "ran"
		end
	end
	-- Health and confirmed capture ownership are present before the EXP snapshot.
	for _, fighter in battle.team do
		fighter.record.hp = fighter.hp
	end
	if result == "won" then
		grantOutcome(battle, "win", events)
	elseif result == "captured" then
		grantOutcome(battle, "capture", events)
	end
	-- Team health is kept until healed at the fountain (nil = full).
	for _, fighter in battle.team do
		fighter.record.hp = if fighter.hp >= fighter.stats.hp then nil else fighter.hp
	end

	if player.Parent then
		send(battle, events, result)
	end
	-- The world catches up once the client has played the events (so the
	-- capsule still lands on the pet); the player stays protected until then.
	local playback = if player.Parent then #events * EVENT_SECONDS + 1.8 else 0
	leaving[player] = battle
	task.delay(playback, function()
		if player.Parent and not battles[player] then
			leavePlayer(battle)
		end
		if leaving[player] == battle then
			leaving[player] = nil
		end
		if result == "lost" then
			NotifyService.Send(player, {
				text = "Your team fainted! Heal it at the Spawn Fountain.",
				kind = "warning",
				icon = "warning",
			})
		end

		local record = wild.record
		local model = record.model
		if result == "won" then
			task.delay(1.5, function()
				AnimalService.Remove(record) -- fainted: it runs away (a new one spawns)
			end)
		elseif result == "captured" then
			if model and model.PrimaryPart then
				model.PrimaryPart.Anchored = false
			end
			if PlayerDataService.IsReady(player) then
				HomeService.PlaceBack(player, record) -- display pad or persistent reserve
				HomeService.SaveCaught(player, record)
			else
				AnimalService.Remove(record) -- already in the departed owner's save
			end
		else
			-- Ran or lost: the wild pet goes back to roaming, healed.
			record.state = "Wild"
			record.hp = nil
			if model and model.PrimaryPart then
				model.PrimaryPart.Anchored = false
			end
			record.nextMoveAt = os.clock() + 2
		end

		battle.arena:Destroy()
	end)
end

-- The wild pet's turn (after the player's action). Returns true if the battle ended.
local function wildTurn(battle: Battle, events: { BattleEvent }): boolean
	local mine = battle.team[battle.active]
	if attack(battle, battle.wild, mine, chooseWildMove(battle.wild), "wild", events) then
		local nextIndex = nextAlive(battle)
		if not nextIndex then
			finish(battle, "lost", events)
			return true
		end
		battle.active = nextIndex
		battle.fought[battle.team[nextIndex]] = true
		-- The fainted pet lies down behind the player; the next one steps in.
		placePet(mine.record, (battle.centre * CFrame.new(LAYOUT.bench)).Position, battle.centre.Position)
		placePet(
			battle.team[nextIndex].record,
			(battle.centre * CFrame.new(LAYOUT.mine)).Position,
			battle.centre.Position
		)
		table.insert(events, { text = `Go, {nameOf(battle.team[nextIndex])}!`, effect = "switch" })
	end
	return false
end

local function resolve(battle: Battle, action: any)
	local player = battle.player
	local kind = action.kind
	local events: { BattleEvent } = {}
	local mine = battle.team[battle.active]
	local wild = battle.wild

	if kind == "move" then
		local index = (action :: any).index
		local moves = Config.Battle.species[mine.record.speciesId].moves
		if typeof(index) ~= "number" or not moves[index] then
			return
		end
		if moves[index].uses and (mine.uses[index] or 0) <= 0 then
			return
		end
		battle.fought[mine] = true
		-- Faster pet first; a tie is a coin flip.
		local mineFirst = mine.stats.speed > wild.stats.speed
			or (mine.stats.speed == wild.stats.speed and rng:NextNumber() < 0.5)
		if mineFirst then
			if attack(battle, mine, wild, index, "mine", events) then
				finish(battle, "won", events)
				return
			end
			if wildTurn(battle, events) then
				return
			end
		else
			if wildTurn(battle, events) then
				return
			end
			if battle.team[battle.active] == mine then -- not knocked out first
				if attack(battle, mine, wild, index, "mine", events) then
					finish(battle, "won", events)
					return
				end
			end
		end
	elseif kind == "capsule" and battle.kind == "wild" then
		local data = PlayerDataService.Get(player)
		if not data then
			return
		end
		if not HomeService.CanAcquire(player) then
			NotifyService.Send(player, { text = "Your pet reserve is full.", kind = "info" })
			return
		end
		if data.capsules <= 0 then
			if not PlayerStateService.TrySpend(player, Config.Battle.capsule.price) then
				NotifyService.Send(player, {
					text = `A Pet Capsule costs ${Format.Short(Config.Battle.capsule.price)}.`,
					kind = "info",
				})
				return
			end
			data.capsules += 1
		end
		data.capsules -= 1
		local rarity = Config.Species[wild.record.speciesId].rarity
		local chance = BattleMath.CaptureChance(rarity, wild.hp / wild.stats.hp)
		local caught = rng:NextNumber() < chance
		-- Shakes: more when the chance was better (purely for show).
		local shakes = if caught then 3 else math.clamp(math.floor(chance * 4), 1, 2)
		table.insert(events, {
			text = `You threw a Pet Capsule!`,
			actor = "mine",
			target = "wild",
			effect = if caught then "capture" else "escape",
			damage = shakes,
		})
		if caught then
			table.insert(events, { text = `Gotcha! {nameOf(wild)} was caught!` })
			finish(battle, "captured", events)
			return
		end
		table.insert(events, { text = `Oh no! {nameOf(wild)} broke free!` })
		if wildTurn(battle, events) then
			return
		end
	elseif kind == "switch" then
		local petId = (action :: any).petId
		local target: number? = nil
		for index, fighter in battle.team do
			if fighter.record.id == petId and fighter.hp > 0 and index ~= battle.active then
				target = index
			end
		end
		if not target then
			return
		end
		battle.active = target
		battle.fought[battle.team[target]] = true
		placePet(
			battle.team[target].record,
			(battle.centre * CFrame.new(LAYOUT.mine)).Position,
			battle.centre.Position
		)
		-- The pet that left goes back to the bench beside the player.
		placePet(mine.record, (battle.centre * CFrame.new(LAYOUT.bench)).Position, battle.centre.Position)
		table.insert(
			events,
			{ text = `Come back, {nameOf(mine)}! Go, {nameOf(battle.team[target])}!`, effect = "switch" }
		)
		if wildTurn(battle, events) then
			return
		end
	elseif kind == "run" then
		table.insert(events, { text = "You got away safely." })
		finish(battle, "ran", events)
		return
	else
		return
	end

	battle.deadline = os.clock() + Config.Battle.choiceTimeoutSeconds
	send(battle, events, nil)
end

local function onAction(player: Player, action: unknown)
	if typeof(action) ~= "table" then
		return
	end
	local battle = battles[player]
	if not battle or battle.ended then
		return
	end
	resolve(battle, action)
end

function BattleService.Begin(player: Player, record: AnimalRecord)
	local data = PlayerDataService.Get(player)
	if not data or #data.starters.choices == 0 or Guard.IsBusy(player) then
		return
	end
	if not BattleMath.Enabled() or battles[player] or leaving[player] or not record.model then
		return
	end
	if not PlayerDataService.IsReady(player) or record.state ~= "Wild" or record.ownerUserId then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local wildRoot = record.model.PrimaryPart
	if not root or not humanoid or humanoid.Health <= 0 or not wildRoot then
		return
	end
	if
		(root.Position - wildRoot.Position).Magnitude - AnimalService.Radius(record.model)
		> Config.Gameplay.capture.maxDistance
	then
		return
	end
	if #CarryService.GetCarried(player) > 0 then
		NotifyService.Send(player, { text = "Put down what you carry before battling.", kind = "info" })
		return
	end

	local team = {}
	for _, teamRecord in TeamService.GetTeam(player) do
		table.insert(team, fighterOf(teamRecord))
	end
	if #team == 0 then
		NotifyService.Send(player, {
			text = "Add a pet to your team first: open the Tablet (T) > Inventory.",
			kind = "info",
			icon = "info",
		})
		return
	end
	local battle: Battle = {
		player = player,
		wild = fighterOf(record),
		team = team,
		active = 0,
		fought = {},
		centre = CFrame.new(),
		arena = nil :: any,
		deadline = os.clock() + Config.Battle.choiceTimeoutSeconds,
		ended = false,
		kind = "wild",
		foeLabel = "",
	}
	local speciesName = nameOf(battle.wild)
	battle.foeLabel = `Wild {speciesName}`
	local first = nextAlive(battle)
	if not first then
		NotifyService.Send(player, {
			text = "Your team needs healing at the Spawn Fountain.",
			kind = "info",
			icon = "warning",
		})
		return
	end
	battle.active = first
	battle.fought[team[first]] = true

	-- Arena between the player and the wild pet, looking from the player's side.
	local middle = (root.Position + wildRoot.Position) / 2
	local flatDirection =
		Vector3.new(wildRoot.Position.X - root.Position.X, 0, wildRoot.Position.Z - root.Position.Z)
	if flatDirection.Magnitude < 0.1 then
		flatDirection = Vector3.new(0, 0, -1)
	end
	local ground = groundAt(middle)
	-- -Z points at the wild pet, so the player's side is +Z.
	local safeGround = ZoneService.FindArenaCenter(ground, ARENA_FOOTPRINT_RADIUS, ARENA_FOOTPRINT_RADIUS + 1)
	if not safeGround then
		NotifyService.Send(player, {
			text = "There's not enough space here for a battle. Move the pet farther from the base and try again.",
			kind = "info",
			icon = "warning",
		})
		return
	end
	ground = groundAt(safeGround)
	battle.centre = clearestFacing(ground, flatDirection.Unit)
	battle.arena = buildArena(battle.centre)

	record.state = "Battling"
	battles[player] = battle
	player:SetAttribute("InBattle", true)
	TeamService.SetPaused(player, true)
	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	local standAt = groundAt((battle.centre * CFrame.new(LAYOUT.player)).Position) + Vector3.new(0, 3, 0)
	character:PivotTo(CFrame.lookAt(standAt, (battle.centre * CFrame.new(0, 3, 0)).Position))
	local mineSpot = (battle.centre * CFrame.new(LAYOUT.mine)).Position
	placePet(record, (battle.centre * CFrame.new(LAYOUT.foe)).Position, mineSpot)
	placePet(team[first].record, mineSpot, (battle.centre * CFrame.new(LAYOUT.foe)).Position)
	-- The rest of the team waits on the bench, left of the player (off camera).
	local benched = 0
	for index, fighter in team do
		if index ~= first then
			local spot = battle.centre * CFrame.new(LAYOUT.bench - Vector3.new(benched * 4, 0, 0))
			benched += 1
			placePet(fighter.record, spot.Position, battle.centre.Position)
		end
	end

	local intro = `A wild {speciesName} (Lv {record.level}) appeared!`
	send(battle, {
		{ text = intro, effect = "intro" },
		{ text = `Go, {nameOf(team[first])}!` },
	}, nil)
end

-- Debug: turns battles on or off for this server (running battles finish).
function BattleService.SetEnabled(value: boolean)
	BattleMath.SetOverride(value)
	Workspace:SetAttribute("BattlesEnabled", value)
	CarryService.SetBattleHandler(if value then BattleService.Begin else nil)
end

function BattleService.IsBattling(player: Player): boolean
	return battles[player] ~= nil
end

-- Includes post-battle playback as well as the active fight.
function BattleService.IsBusy(player: Player): boolean
	return battles[player] ~= nil or leaving[player] ~= nil or player:GetAttribute("InBattle") == true
end

local function onLeaving(player: Player)
	lastHealAt[player] = nil
	local battle = battles[player]
	if battle then
		finish(battle, "ran", {})
	end
end

-- Heals every pet the player owns (Spawn Fountain). Silent when nothing
-- was hurt, so repeating the GUI action does not spam notifications.
function BattleService.HealAll(player: Player): boolean
	local now = os.clock()
	if now - (lastHealAt[player] or 0) < HEAL_COOLDOWN then
		return false
	end
	lastHealAt[player] = now
	local data = PlayerDataService.Get(player)
	if not data then
		return false
	end
	local healed = 0
	for id, saved in data.animals do
		local record = AnimalService.Get(id)
		if (record and record.hp ~= nil) or saved.hp ~= nil then
			healed += 1
		end
		if record then
			record.hp = nil
		end
		saved.hp = nil
	end
	if healed > 0 then
		NotifyService.Send(
			player,
			{ text = "Your pets are fully healed!", kind = "success", icon = "success" }
		)
	end
	return healed > 0
end

-- GUI entry point; debug HealAll remains a separate server-only operation.
function BattleService.HealAtFountain(player: Player): (boolean, string)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local point = battleFolder and battleFolder:FindFirstChild("HealPoint") :: BasePart?
	if not root or not humanoid or humanoid.Health <= 0 or BattleService.IsBusy(player) then
		return false, "You cannot heal right now."
	end
	if not point or (root.Position - point.Position).Magnitude > HEAL_DISTANCE then
		return false, "Get closer to the Spawn Fountain."
	end
	if not PlayerDataService.IsReady(player) then
		return false, "Your pets are still loading."
	end
	if os.clock() - (lastHealAt[player] or 0) < HEAL_COOLDOWN then
		return false, "Please wait before healing again."
	end
	local healed = BattleService.HealAll(player)
	return true, if healed then "Your pets are fully healed!" else "Your pets are already fully healed."
end

local function addHealingPoint()
	local map = Workspace:WaitForChild("Map", 10)
	local fountain = map and map:FindFirstChild("spawn_fountain", true)
	if not fountain then
		warn("[BattleService] No spawn_fountain in the map: no healing point")
		return
	end
	local centre = if fountain:IsA("Model") then fountain:GetPivot() else (fountain :: BasePart).CFrame
	local point = Instance.new("Part")
	point.Name = "HealPoint"
	point.Anchored = true
	point.CanCollide = false
	point.CanQuery = false
	point.CanTouch = false
	point.Transparency = 1
	point.Size = Vector3.one
	-- On the plaza floor under the fountain (its bounding box includes the jets).
	local floor = groundAt(centre.Position, fountain)
	point.CFrame = CFrame.new(floor + Vector3.new(0, 4, 0))
	point:SetAttribute("InteractionRadius", HEAL_DISTANCE)
	point.Parent = battleFolder
end

function BattleService.Start()
	local folder = Instance.new("Folder")
	folder.Name = "Battles"
	folder.Parent = Workspace
	battleFolder = folder
	Workspace:SetAttribute("BattlesEnabled", BattleMath.Enabled())

	if BattleMath.Enabled() then
		CarryService.SetBattleHandler(BattleService.Begin)
	end
	Remotes.Get("BattleAction").OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(onLeaving)
	task.spawn(addHealingPoint)

	-- Timeouts, deaths and players pulled away end the battle as a run.
	task.spawn(function()
		while true do
			task.wait(1)
			for player, battle in battles do
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local gone = not humanoid
					or humanoid.Health <= 0
					or not root
					or (root.Position - battle.centre.Position).Magnitude > Config.Battle.arenaRadius * 3
				if gone or os.clock() > battle.deadline then
					finish(battle, "ran", { { text = "The battle is over: you ran away." } })
				end
			end
		end
	end)
end

return BattleService
