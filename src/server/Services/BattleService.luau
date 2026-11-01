--!strict
-- Wild battles (docs/BATTLES.md). The player holds "Battle" on a wild pet;
-- an arena ring appears where they stand, their first healthy team pet faces
-- the wild one and both stay put. Turn by turn the player picks a move, a
-- Pet Capsule, a switch or running away; the server decides everything
-- (order by Speed, damage, captures, XP) and sends the client a view of the
-- battle plus what happened ("Battle" remote), which the client animates.
-- While battling the player is protected: no exposure, and the pet being
-- fought can't be grabbed by anyone.

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
	kind: string, -- "wild" | "steal" (another player's loose pet)
	foeLabel: string, -- "Wild Acorn Squirrel" / "Ana's Acorn Squirrel"
	defender: Player?, -- the owner, once they joined to control their pet
	defenderChoice: number?, -- move the defender picked for the next turn
	pending: any?, -- the attacker's action, waiting for the defender's choice
	pendingDeadline: number,
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

local BattleService = {}

local LAYOUT = Config.Battle.layout
-- Arena turns tried (degrees from "player looks at the foe"), best view wins.
local FACING_TRIES = { 0, 30, -30, 60, -60 }
local RING_SEGMENTS = 28
local EVENT_SECONDS = 0.95 -- how long the client shows each event (BattleScreen)
local DEFEND_DISTANCE = 120 -- studs from the arena the owner must be to defend
local DEFENDER_SECONDS = 10 -- the defender's time to pick a move, then the pet decides

local battles: { [Player]: Battle } = {}
local defenders: { [Player]: Battle } = {} -- owners controlling their pet's defence
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
		xpToNext = BattleMath.XpToNext(fighter.record.level),
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

	-- The owner defending sees the same battle from the other side.
	local defender = battle.defender
	if defender and defender.Parent then
		local own: any = fighterView(battle.wild)
		own.moves = moveView(battle.wild)
		local flipped = {}
		for _, event in events do
			local copy = table.clone(event)
			copy.actor = if event.actor == "mine" then "wild" elseif event.actor == "wild" then "mine" else nil
			copy.target = if event.target == "mine"
				then "wild"
				elseif event.target == "wild" then "mine"
				else nil
			table.insert(flipped, copy)
		end
		local flippedResult = if result == "won" then "lost" elseif result == "lost" then "won" else result
		Remotes.Get("Battle"):FireClient(defender, {
			centre = battle.centre * CFrame.Angles(0, math.pi, 0),
			arena = battle.arena,
			wild = fighterView(mine),
			mine = own,
			team = { own },
			capsules = 0,
			capsulePrice = 0,
			events = flipped,
			result = flippedResult,
			timeout = DEFENDER_SECONDS,
			role = "defender",
			foeTrainer = battle.player.Character, -- never hidden from the defender's view
			kind = battle.kind,
			foeName = `{battle.player.DisplayName}'s {nameOf(mine)}`,
		})
	end
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

-- The defending pet's move: the owner's choice when they control it, else its own.
local function defenderMove(battle: Battle): number
	local choice = battle.defenderChoice
	battle.defenderChoice = nil
	local moves = Config.Battle.species[battle.wild.record.speciesId].moves
	if choice and moves[choice] and (not moves[choice].uses or (battle.wild.uses[choice] or 0) > 0) then
		return choice
	end
	return chooseWildMove(battle.wild)
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
	TeamService.SetPaused(player, false)
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
	end
end

local function grantXp(battle: Battle, amount: number, events: { BattleEvent })
	for fighter in battle.fought do
		local record = fighter.record
		if record.level < Config.Battle.maxLevel then
			record.xp += amount
			while record.level < Config.Battle.maxLevel and record.xp >= BattleMath.XpToNext(record.level) do
				record.xp -= BattleMath.XpToNext(record.level)
				record.level += 1
				local newStats = BattleMath.Stats(record.speciesId, record.level)
				fighter.hp += newStats.hp - fighter.stats.hp -- keeps the missing health
				fighter.stats = newStats
				table.insert(
					events,
					{ text = `{nameOf(fighter)} grew to Lv {record.level}!`, effect = "levelup" }
				)
			end
		end
	end
	table.insert(events, { text = `Your team got {amount} XP.` })
end

local function finish(battle: Battle, result: string, events: { BattleEvent })
	if battle.ended then
		return
	end
	battle.ended = true
	battles[battle.player] = nil
	local player = battle.player
	local wild = battle.wild

	if result == "won" then
		grantXp(battle, BattleMath.XpForWin(wild.record.level), events)
	elseif result == "captured" then
		grantXp(
			battle,
			math.floor(BattleMath.XpForWin(wild.record.level) * Config.Battle.xp.captureFactor),
			events
		)
	end
	-- Team health is kept until healed at the fountain (nil = full).
	for _, fighter in battle.team do
		fighter.record.hp = if fighter.hp >= fighter.stats.hp then nil else fighter.hp
	end

	if player.Parent then
		send(battle, events, result)
	end
	if battle.defender then
		defenders[battle.defender] = nil
	end
	-- The world catches up once the client has played the events (so the
	-- capsule still lands on the pet); the player stays protected until then.
	local playback = if player.Parent then #events * EVENT_SECONDS + 1.8 else 0
	task.delay(playback, function()
		if player.Parent then
			leavePlayer(battle)
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
		if battle.kind == "steal" then
			-- Another player's pet: it keeps its wounds (healed at its owner's fountain).
			record.hp = if wild.hp >= wild.stats.hp then nil else wild.hp
			if model and model.PrimaryPart then
				model.PrimaryPart.Anchored = false
			end
			record.state = "Loose"
			local owner = record.ownerUserId and Players:GetPlayerByUserId(record.ownerUserId)
			if result == "won" and player.Parent then
				CarryService.TakeWon(player, record) -- carried pets can't be taken back
			else
				local prompt = model and model.PrimaryPart and model.PrimaryPart:FindFirstChild("CatchPrompt")
				if prompt and prompt:IsA("ProximityPrompt") then
					prompt.Enabled = true
				end
				record.nextMoveAt = os.clock() + 2
				if owner and result == "lost" then
					NotifyService.Send(owner, {
						text = `Your {nameOf(wild)} fought off {player.DisplayName}!`,
						kind = "success",
						icon = "shield",
					})
				end
			end
		elseif result == "won" then
			task.delay(1.5, function()
				AnimalService.Remove(record) -- fainted: it runs away (a new one spawns)
			end)
		elseif result == "captured" then
			record.hp = if wild.hp >= wild.stats.hp then nil else wild.hp
			record.origin = {
				ownerUserId = player.UserId,
				ownerName = player.DisplayName,
				capturedAt = os.time(),
				place = if record.model and record.model.PrimaryPart
					then ZoneService.ZoneAt(record.model.PrimaryPart.Position)
					else Config.Species[record.speciesId].biome,
			}
			if model and model.PrimaryPart then
				model.PrimaryPart.Anchored = false
			end
			if not (player.Parent and HomeService.Receive(player, record)) then
				-- Base full (or the player left): it waits loose, owned, near the arena.
				record.ownerUserId = if player.Parent then player.UserId else nil
				if model and model.PrimaryPart then
					AnimalService.DropAt(record, model.PrimaryPart.Position)
				end
				if player.Parent then
					NotifyService.Send(player, {
						text = "Your base is full: your new pet waits here. Carry it home!",
						kind = "info",
					})
				end
			end
		else
			-- Ran or lost: the wild pet goes back to roaming, healed.
			record.state = "Wild"
			record.hp = nil
			if model and model.PrimaryPart then
				model.PrimaryPart.Anchored = false
				local prompt = model.PrimaryPart:FindFirstChild("CatchPrompt") :: ProximityPrompt?
				if prompt then
					prompt.Enabled = true
				end
			end
			record.nextMoveAt = os.clock() + 2
		end

		battle.arena:Destroy()
	end)
end

-- The wild pet's turn (after the player's action). Returns true if the battle ended.
local function wildTurn(battle: Battle, events: { BattleEvent }): boolean
	local mine = battle.team[battle.active]
	if attack(battle, battle.wild, mine, defenderMove(battle), "wild", events) then
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
	local defended = defenders[player]
	if defended then
		-- The owner picks their pet's next move; it is used on the next turn.
		local index = (action :: any).index
		local moves = Config.Battle.species[defended.wild.record.speciesId].moves
		if
			defended.ended
			or (action :: any).kind ~= "move"
			or typeof(index) ~= "number"
			or not moves[index]
		then
			return
		end
		defended.defenderChoice = index
		local pending = defended.pending
		if pending then
			defended.pending = nil
			resolve(defended, pending)
		end
		return
	end
	local battle = battles[player]
	if not battle or battle.ended or battle.pending then
		return
	end
	local kind = (action :: any).kind
	if battle.defender and not battle.defenderChoice and kind ~= "run" then
		-- Wait (a little) for the owner to choose their pet's move.
		battle.pending = action
		battle.pendingDeadline = os.clock() + DEFENDER_SECONDS
		send(battle, { { text = `Waiting for {battle.defender.DisplayName} to choose...` } }, nil)
		return
	end
	resolve(battle, action)
end

function BattleService.Begin(player: Player, record: AnimalRecord)
	if not BattleMath.Enabled() or battles[player] or defenders[player] or not record.model then
		return
	end
	-- Wild pets, or another player's loose pet (stealing, DESIGN-v2 §7).
	local stealing = record.state == "Loose"
		and record.ownerUserId ~= nil
		and record.ownerUserId ~= player.UserId
	if record.state ~= "Wild" and not stealing then
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
		kind = if stealing then "steal" else "wild",
		foeLabel = "",
		defender = nil,
		defenderChoice = nil,
		pending = nil,
		pendingDeadline = 0,
	}
	local speciesName = nameOf(battle.wild)
	local owner = if stealing then Players:GetPlayerByUserId(record.ownerUserId :: number) else nil
	battle.foeLabel = if not stealing
		then `Wild {speciesName}`
		elseif owner then `{owner.DisplayName}'s {speciesName}`
		else `Loose {speciesName}`
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
	record.state = "Battling"
	local prompt = wildRoot:FindFirstChild("CatchPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Enabled = false
	end
	local middle = (root.Position + wildRoot.Position) / 2
	local flatDirection =
		Vector3.new(wildRoot.Position.X - root.Position.X, 0, wildRoot.Position.Z - root.Position.Z)
	if flatDirection.Magnitude < 0.1 then
		flatDirection = Vector3.new(0, 0, -1)
	end
	local ground = groundAt(middle)
	-- -Z points at the wild pet, so the player's side is +Z.
	battle.centre = clearestFacing(ground, flatDirection.Unit)
	battle.arena = buildArena(battle.centre)

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

	local intro = if stealing
		then `You challenged {battle.foeLabel} (Lv {record.level})! It fights back on its own.`
		else `A wild {speciesName} (Lv {record.level}) appeared!`
	send(battle, {
		{ text = intro, effect = "intro" },
		{ text = `Go, {nameOf(team[first])}!` },
	}, nil)
	-- The owner, if in this server, can come and control the defence.
	if owner then
		NotifyService.Send(owner, {
			text = `{player.DisplayName} is battling your {speciesName}! Come and defend it.`,
			kind = "warning",
			icon = "theft",
			action = { label = "Defend!", animalId = record.id, kind = "defend" },
		})
	end
end

function BattleService.IsBattling(player: Player): boolean
	return battles[player] ~= nil
end

local function onLeaving(player: Player)
	local battle = battles[player]
	if battle then
		finish(battle, "ran", {})
	end
	local defended = defenders[player]
	if defended then
		defenders[player] = nil
		defended.defender = nil -- the pet fights on its own again
	end
end

-- The owner answers the "Defend!" notification: they control their pet's
-- moves from now on, if they are close enough to the arena.
local function onDefend(owner: Player, animalId: unknown)
	if typeof(animalId) ~= "string" or defenders[owner] or battles[owner] then
		return
	end
	for _, battle in battles do
		local record = battle.wild.record
		if record.id == animalId and battle.kind == "steal" and not battle.ended and not battle.defender then
			if record.ownerUserId ~= owner.UserId then
				return
			end
			local character = owner.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or (root.Position - battle.centre.Position).Magnitude > DEFEND_DISTANCE then
				NotifyService.Send(owner, {
					text = `Get closer to the battle to defend (within {DEFEND_DISTANCE} studs).`,
					kind = "info",
					icon = "shield",
				})
				return
			end
			battle.defender = owner
			defenders[owner] = battle
			send(battle, { { text = `{owner.DisplayName} is defending {nameOf(battle.wild)}!` } }, nil)
			return
		end
	end
end

-- Heals every pet the player owns (Spawn Fountain).
function BattleService.HealAll(player: Player)
	local data = PlayerDataService.Get(player)
	if not data then
		return
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
	NotifyService.Send(player, {
		text = if healed > 0 then "Your pets are fully healed!" else "Your pets are already healthy.",
		kind = "success",
		icon = "success",
	})
end

local function addFountainPrompt()
	local map = Workspace:WaitForChild("Map")
	local fountain = map:FindFirstChild("spawn_fountain", true)
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
	point.Parent = battleFolder
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HealPrompt"
	prompt.ActionText = "Heal team"
	prompt.ObjectText = "Spawn Fountain"
	prompt.HoldDuration = 0.5
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 30 -- from the fountain's centre: anywhere around its pool
	prompt.Parent = point
	prompt.Triggered:Connect(BattleService.HealAll)
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
	Remotes.Get("DefendBattle").OnServerEvent:Connect(onDefend)
	Players.PlayerRemoving:Connect(onLeaving)
	task.spawn(addFountainPrompt)

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
				local defender = battle.defender
				if defender then
					local defenderRoot = defender.Character
						and defender.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if
						not defenderRoot
						or (defenderRoot.Position - battle.centre.Position).Magnitude
							> DEFEND_DISTANCE * 1.5
					then
						-- The owner walked away: the pet fights on its own.
						defenders[defender] = nil
						battle.defender = nil
					end
				end
				if battle.pending and (os.clock() > battle.pendingDeadline or not battle.defender) then
					local pending = battle.pending
					battle.pending = nil
					resolve(battle, pending) -- the pet picks its own move
				elseif gone or (not battle.pending and os.clock() > battle.deadline) then
					finish(battle, "ran", { { text = "The battle is over: you ran away." } })
				end
			end
		end
	end)
end

return BattleService
