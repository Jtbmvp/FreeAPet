--!nonstrict
-- PvpBattle (ServerScriptService, ModuleScript): turn-based pet battle between two players,
-- shown with the game's own battle screen. It uses the same remotes as the wild battles
-- ("Battle" view to the client, "BattleAction" from it) with kind = "pvp", so the client shows
-- "FOE" instead of "WILD" and hides the capsules. BattleService ignores BattleAction from
-- players it is not battling, so both listen side by side without touching each other.
--
-- Rules (same maths as the wild battles: BattleMath stats, damage and type chart):
--   * both players pick an action at the same time (move, switch or forfeit);
--   * switches happen first, then the faster active pet attacks (speed tie: coin flip);
--   * a fainted pet is replaced by the next healthy one; no healthy pet left = defeat;
--   * every pet starts at full HP and nothing is saved: no HP loss, XP or items change;
--   * no choice before the timer ends = a random move; two timeouts in a row = forfeit;
--   * leaving the game = forfeit.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattleMath = require(Shared:WaitForChild("BattleMath"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
local TeamService = require(Services:WaitForChild("TeamService"))
local AnimalService = require(Services:WaitForChild("AnimalService"))

local LAYOUT = Config.Battle.layout
-- Each trainer stands right beside their own pet (to its left, seen from their own side), so
-- the opponent sees the other player next to the pet they are fighting.
local TRAINER = Vector3.new(LAYOUT.mine.X - 4, 0, LAYOUT.mine.Z + 1)
local TURN_TIMEOUT = 30
local MAX_TIMEOUTS = 2
local EVENT_SECONDS = 0.95 -- how long the client shows each event (BattleScreen)
local rng = Random.new()

-- Rough time the battle screen takes to play a list of events (attacks run their effects).
local function playbackSeconds(raw): number
	local t = 0
	for _, e in raw do
		t += if e.t == "attack" then 1.7 else EVENT_SECONDS
	end
	return t
end

local PvpBattle = {}

local active: { [Player]: any } = {} -- player -> battle

local function speciesName(record): string
	local s = Config.Species[record.speciesId]
	return s and s.displayName or tostring(record.speciesId)
end

local function fighterOf(record)
	local stats = BattleMath.Stats(record.speciesId, record.level)
	local uses = {}
	for index, move in Config.Battle.species[record.speciesId].moves do
		if move.uses then
			uses[index] = move.uses
		end
	end
	return { record = record, stats = stats, hp = stats.hp, uses = uses }
end

local function fighterView(f)
	return {
		id = f.record.id,
		speciesId = f.record.speciesId,
		level = f.record.level,
		xp = f.record.xp or 0,
		xpToNext = if f.record.level >= Config.Progression.pet.maxLevel then 0 else BattleMath.XpToNext(f.record.level),
		hp = f.hp,
		maxHp = f.stats.hp,
		model = f.record.model,
	}
end

local function moveView(f)
	local moves = {}
	for index, move in Config.Battle.species[f.record.speciesId].moves do
		table.insert(moves, { name = move.name, type = move.type, power = move.power, usesLeft = f.uses[index], maxUses = move.uses })
	end
	return moves
end

local function groundAt(battle, position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, name in { "Animals", "Art", "Battles" } do
		local folder = Workspace:FindFirstChild(name) or (Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild(name))
		if folder then
			table.insert(exclude, folder)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	for _, side in battle.sides do
		for _, f in side.team do
			if f.record.model then
				table.insert(exclude, f.record.model)
			end
		end
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position else position
end

local function placePet(battle, record, position: Vector3, lookAt: Vector3)
	local model = record.model
	if not model or not model.PrimaryPart then
		return
	end
	local ground = groundAt(battle, position)
	-- Height of the pivot above the pet's lowest VISIBLE part. The model's extents include an
	-- invisible RootPart that reaches below the feet, so extents/2 left pets floating.
	local pivotY = model:GetPivot().Position.Y
	local lowest = math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			-- vertical half-extent of the (possibly rotated) part
			local c, h = part.CFrame, part.Size / 2
			local dy = math.abs(c.RightVector.Y) * h.X + math.abs(c.UpVector.Y) * h.Y + math.abs(c.LookVector.Y) * h.Z
			lowest = math.min(lowest, part.Position.Y - dy)
		end
	end
	local height = if lowest < math.huge then pivotY - lowest else model:GetExtentsSize().Y / 2
	model.PrimaryPart.Anchored = true
	model:PivotTo(CFrame.lookAt(ground + Vector3.new(0, height, 0), Vector3.new(lookAt.X, ground.Y + height, lookAt.Z)))
end

local function otherSide(battle, side)
	return if battle.sides[1] == side then battle.sides[2] else battle.sides[1]
end

local function current(side)
	return side.team[side.active]
end

local function nextAlive(side): number?
	for i, f in side.team do
		if f.hp > 0 then
			return i
		end
	end
	return nil
end

local function stage(battle, side)
	-- active pet on its mark, the rest on the bench behind its trainer
	local centre = side.centre
	local benched = 0
	for i, f in side.team do
		local spot
		if i == side.active then
			spot = (centre * CFrame.new(LAYOUT.mine)).Position
		else
			spot = (centre * CFrame.new(LAYOUT.bench - Vector3.new(benched * 4, 0, 0))).Position
			benched += 1
		end
		placePet(battle, f.record, spot, centre.Position)
	end
end

-- Events are stored neutrally (by side) and rendered for each viewer: "Spoutle used X!" for
-- your own pet, "Ana's Spoutle used X!" for the opponent's, actor/target "mine" or "wild".
local function render(battle, viewer, raw)
	local opp = otherSide(battle, viewer)
	local out = {}
	local function who(side, name)
		return if side == viewer then name else (opp.name .. "'s " .. name)
	end
	local function rel(side)
		return if side == viewer then "mine" else "wild"
	end
	for _, e in raw do
		if e.t == "text" then
			table.insert(out, { text = e.text, effect = e.effect })
		elseif e.t == "attack" then
			table.insert(out, {
				text = who(e.side, e.name) .. " used " .. e.move .. "!",
				actor = rel(e.side),
				target = rel(otherSide(battle, e.side)),
				damage = e.damage,
				effect = e.effect,
				moveType = e.moveType,
				move = e.move,
			})
		elseif e.t == "faint" then
			table.insert(out, { text = who(e.side, e.name) .. " fainted!", target = rel(e.side), effect = "faint" })
		elseif e.t == "switch" then
			table.insert(out, {
				text = if e.side == viewer then ("Go, " .. e.name .. "!") else (opp.name .. " sent out " .. e.name .. "!"),
				effect = "switch",
			})
		elseif e.t == "forfeit" then
			table.insert(out, { text = if e.side == viewer then "You forfeited the battle." else (opp.name .. " forfeited!") })
		end
	end
	return out
end

local function send(battle, side, raw, result: string?)
	local p = side.player
	if not p or p.Parent ~= Players then
		return
	end
	local opp = otherSide(battle, side)
	local mine: any = fighterView(current(side))
	mine.moves = moveView(current(side))
	local team = {}
	for _, f in side.team do
		table.insert(team, fighterView(f))
	end
	Remotes.Get("Battle"):FireClient(p, {
		centre = side.centre,
		arena = battle.arena,
		wild = fighterView(current(opp)),
		mine = mine,
		team = team,
		capsules = 0,
		capsulePrice = 0,
		events = render(battle, side, raw),
		result = result,
		timeout = TURN_TIMEOUT,
		role = "attacker",
		kind = "pvp",
		foeName = speciesName(current(opp).record), -- the trainer's name is in the battle texts
		foeTrainer = if opp.player then opp.player.Character else battle.botTrainer,
	})
end

local function sendBoth(battle, raw, results)
	for _, side in battle.sides do
		send(battle, side, raw, results and results[side] or nil)
	end
end

local function attack(battle, side, moveIndex: number, raw): boolean
	local opp = otherSide(battle, side)
	local attacker, defender = current(side), current(opp)
	local move = Config.Battle.species[attacker.record.speciesId].moves[moveIndex]
	if move.uses then
		attacker.uses[moveIndex] = (attacker.uses[moveIndex] or 0) - 1
	end
	local mult = BattleMath.TypeMultiplier(move.type, Config.Battle.species[defender.record.speciesId].type)
	local damage = BattleMath.Damage(move.power, attacker.stats.attack, defender.stats.defense, mult, rng:NextNumber())
	defender.hp = math.max(0, defender.hp - damage)
	table.insert(raw, {
		t = "attack",
		side = side,
		name = speciesName(attacker.record),
		move = move.name,
		moveType = move.type,
		damage = damage,
		effect = if mult > 1 then "super" elseif mult < 1 then "weak" else nil,
	})
	if mult > 1 then
		table.insert(raw, { t = "text", text = "It's super effective!" })
	elseif mult < 1 then
		table.insert(raw, { t = "text", text = "It's not very effective..." })
	end
	if defender.hp <= 0 then
		table.insert(raw, { t = "faint", side = opp, name = speciesName(defender.record) })
		return true
	end
	return false
end

local function randomMove(f): number
	local moves = Config.Battle.species[f.record.speciesId].moves
	local options = {}
	for index, move in moves do
		if not move.uses or (f.uses[index] or 0) > 0 then
			table.insert(options, index)
		end
	end
	return options[rng:NextInteger(1, #options)]
end

local function validChoice(side, action): any
	if type(action) ~= "table" then
		return nil
	end
	if action.kind == "move" then
		local f = current(side)
		local moves = Config.Battle.species[f.record.speciesId].moves
		local i = action.index
		if typeof(i) ~= "number" or not moves[i] then
			return nil
		end
		if moves[i].uses and (f.uses[i] or 0) <= 0 then
			return nil
		end
		return { kind = "move", index = i }
	elseif action.kind == "switch" then
		for i, f in side.team do
			if f.record.id == action.petId and f.hp > 0 and i ~= side.active then
				return { kind = "switch", index = i }
			end
		end
		return nil
	elseif action.kind == "run" then
		return { kind = "run" }
	end
	return nil
end

local function release(battle)
	for _, side in battle.sides do
		local p = side.player
		if p then
			active[p] = nil
			p:SetAttribute("InBattle", nil)
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				local ws = p:GetAttribute("WalkSpeed")
				hum.WalkSpeed = if typeof(ws) == "number" then ws else Config.Gameplay.player.walkSpeed
				hum.JumpHeight = 7.2
			end
			pcall(TeamService.SetPaused, p, false)
		end
		for _, f in side.team do
			local model = f.record.model
			if side.bot then
				if model then
					model:Destroy()
				end
			else
				if model and model.PrimaryPart then
					model.PrimaryPart.Anchored = false
				end
				pcall(AnimalService.Rescale, f.record)
			end
		end
	end
	if battle.arena then
		battle.arena:Destroy()
	end
	for _, c in battle.connections do
		c:Disconnect()
	end
end

local function finish(battle, winner, raw, reason: string)
	if battle.ended then
		return
	end
	battle.ended = true
	local loser = otherSide(battle, winner)
	local results = { [winner] = "won", [loser] = if reason == "forfeit" then "ran" else "lost" }
	sendBoth(battle, raw, results)
	local playback = #raw * EVENT_SECONDS + 2.5
	task.delay(playback, function()
		release(battle)
		if battle.onEnd then
			battle.onEnd(winner.player, loser.player, reason)
		end
	end)
end

local function resolveTurn(battle)
	local raw = {}
	local a, b = battle.sides[1], battle.sides[2]

	-- forfeits
	local aRun, bRun = a.choice.kind == "run", b.choice.kind == "run"
	if aRun or bRun then
		local quitter = if aRun then a else b
		table.insert(raw, { t = "forfeit", side = quitter })
		finish(battle, otherSide(battle, quitter), raw, "forfeit")
		return
	end

	-- switches go first; if any, they get their own update so the client re-targets its camera
	local switched = false
	for _, side in { a, b } do
		if side.choice.kind == "switch" then
			side.active = side.choice.index
			table.insert(raw, { t = "switch", side = side, name = speciesName(current(side).record) })
			stage(battle, side)
			switched = true
		end
	end
	if switched then
		sendBoth(battle, raw, nil)
		raw = {}
	end

	-- attacks, faster first
	local movers = {}
	for _, side in { a, b } do
		if side.choice.kind == "move" then
			table.insert(movers, side)
		end
	end
	if #movers == 2 then
		local sa, sb = current(movers[1]).stats.speed, current(movers[2]).stats.speed
		if sb > sa or (sa == sb and rng:NextNumber() < 0.5) then
			movers[1], movers[2] = movers[2], movers[1]
		end
	end
	local fainted = {}
	for _, side in movers do
		if current(side).hp > 0 and not fainted[side] then
			if attack(battle, side, side.choice.index, raw) then
				fainted[otherSide(battle, side)] = true
			end
		end
	end

	-- replace fainted pets / decide the winner
	local replace = {}
	for side in fainted do
		local nextIndex = nextAlive(side)
		if not nextIndex then
			finish(battle, otherSide(battle, side), raw, "knockout")
			return
		end
		replace[side] = nextIndex
	end
	if next(replace) == nil then
		sendBoth(battle, raw, nil)
		return
	end

	-- Two updates: first the attacks and the faint, still showing the pet that fell (the
	-- battle screen animates the faint on the foe pet of the update it is playing), then,
	-- once that has played, the next pet steps in with its own update.
	sendBoth(battle, raw, nil)
	local delay = playbackSeconds(raw) + 0.4
	battle.busyUntil = os.clock() + delay + 0.5
	task.delay(delay, function()
		if battle.ended then
			return
		end
		local entering = {}
		for side, nextIndex in replace do
			side.active = nextIndex
			table.insert(entering, { t = "switch", side = side, name = speciesName(current(side).record) })
			stage(battle, side)
		end
		sendBoth(battle, entering, nil)
	end)
end

local function botChoice(side)
	return { kind = "move", index = randomMove(current(side)) }
end

local function loop(battle)
	while not battle.ended do
		-- a replacement pet may still be stepping in
		while not battle.ended and os.clock() < (battle.busyUntil or 0) do
			task.wait(0.1)
		end
		for _, side in battle.sides do
			side.choice = if side.bot then botChoice(side) else nil
		end
		battle.awaiting = true
		local deadline = os.clock() + TURN_TIMEOUT + 1
		while not battle.ended do
			if battle.sides[1].choice and battle.sides[2].choice then
				break
			end
			if os.clock() > deadline then
				break
			end
			task.wait(0.1)
		end
		battle.awaiting = false
		if battle.ended then
			return
		end
		-- timeouts: random move; two in a row = forfeit
		for _, side in battle.sides do
			if not side.choice then
				side.timeouts += 1
				if side.timeouts >= MAX_TIMEOUTS then
					side.choice = { kind = "run" }
				else
					side.choice = { kind = "move", index = randomMove(current(side)) }
				end
			else
				side.timeouts = 0
			end
		end
		resolveTurn(battle)
		-- let the clients play the turn before taking new choices
		task.wait(0.5)
	end
end

-- Builds a side; returns nil, reason when the player cannot battle.
local function sideOf(player: Player, centre: CFrame)
	local team = {}
	local ok, records = pcall(TeamService.GetTeam, player)
	if ok and records then
		for _, record in records do
			if record.model and Config.Battle.species[record.speciesId] then
				table.insert(team, fighterOf(record))
			end
		end
	end
	if #team == 0 then
		return nil
	end
	return { player = player, name = player.DisplayName, team = team, active = 1, centre = centre, timeouts = 0 }
end

function PvpBattle.HasTeam(player: Player): boolean
	local ok, records = pcall(TeamService.GetTeam, player)
	if not ok or not records then
		return false
	end
	for _, record in records do
		if Config.Battle.species[record.speciesId] then
			return true
		end
	end
	return false
end

-- Waits up to `timeout` seconds for the player's team pets to exist in the world.
function PvpBattle.WaitForTeam(player: Player, timeout: number): boolean
	local deadline = os.clock() + timeout
	while os.clock() < deadline and player.Parent == Players do
		local ok, records = pcall(TeamService.GetTeam, player)
		if ok and records and #records > 0 then
			local ready = true
			for _, r in records do
				if not r.model then
					ready = false
				end
			end
			if ready then
				return true
			end
		end
		task.wait(0.5)
	end
	return false
end

function PvpBattle.IsBattling(player: Player): boolean
	return active[player] ~= nil
end

-- centre: the battle centre seen from side 1 (-Z looks at side 2), on the arena floor.
-- onEnd(winner: Player?, loser: Player?, reason: "knockout" | "forfeit")
-- opts.bot = true: side 2 is a Studio test bot that copies side 1's team (no second player).
function PvpBattle.Start(p1: Player, p2: Player?, centre: CFrame, onEnd, opts)
	opts = opts or {}
	-- side 2 looks the other way; shifted so both pets keep their own spots (see LAYOUT)
	-- (side 2's "mine" spot lands on side 1's "foe" spot and the other way round)
	local centre2 = centre
		* CFrame.Angles(0, math.pi, 0)
		* CFrame.new(-(LAYOUT.foe.X + LAYOUT.mine.X), 0, -(LAYOUT.foe.Z + LAYOUT.mine.Z))
	local s1 = sideOf(p1, centre)
	if not s1 then
		return false, "no_team"
	end
	local s2
	if opts.bot then
		s2 = { name = "Test Bot", team = {}, active = 1, centre = centre2, timeouts = 0, bot = true }
		local folder = Workspace:FindFirstChild("Battles") or Workspace
		-- workspace.MM_StudioBotTeam = n gives the bot n copies of the team (to test switches)
		local copies = math.clamp(tonumber(Workspace:GetAttribute("MM_StudioBotTeam")) or 1, 1, 3)
		for c = 1, copies do
			for i, f in s1.team do
				local m = f.record.model:Clone()
				m.Name = "PvpBotPet" .. c .. "_" .. i
				m.Parent = folder
				local rec = { id = "bot" .. c .. "_" .. i, speciesId = f.record.speciesId, level = f.record.level, xp = 0, model = m }
				table.insert(s2.team, fighterOf(rec))
			end
		end
	else
		s2 = sideOf(p2 :: Player, centre2)
		if not s2 then
			return false, "no_team_2"
		end
	end
	local battle = { sides = { s1, s2 }, ended = false, awaiting = false, onEnd = onEnd, connections = {} }
	local arena = Instance.new("Model")
	arena.Name = "PvpBattle"
	arena:PivotTo(centre)
	arena.Parent = Workspace:FindFirstChild("Battles") or Workspace
	battle.arena = arena

	for _, side in battle.sides do
		local p = side.player
		if p then
			active[p] = battle
			p:SetAttribute("InBattle", true)
			pcall(TeamService.SetPaused, p, true)
			local char = p.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.Anchored = false
			end
			if hum then
				hum.WalkSpeed = 0
				hum.JumpHeight = 0
			end
			if char then
				local standAt = groundAt(battle, (side.centre * CFrame.new(TRAINER)).Position) + Vector3.new(0, 3, 0)
				local opp = otherSide(battle, side)
				local facing = (opp.centre * CFrame.new(LAYOUT.mine)).Position -- the opponent pet
				char:PivotTo(CFrame.lookAt(standAt, Vector3.new(facing.X, standAt.Y, facing.Z)))
			end
		end
		stage(battle, side)
	end

	table.insert(battle.connections, Remotes.Get("BattleAction").OnServerEvent:Connect(function(player, action)
		if battle.ended or not battle.awaiting then
			return
		end
		for _, side in battle.sides do
			if side.player == player and not side.choice then
				side.choice = validChoice(side, action)
			end
		end
	end))
	table.insert(battle.connections, Players.PlayerRemoving:Connect(function(player)
		for _, side in battle.sides do
			if side.player == player and not battle.ended then
				finish(battle, otherSide(battle, side), { { t = "forfeit", side = side } }, "forfeit")
			end
		end
	end))

	-- Studio test bot: a copy of the player stands as the bot's trainer (gone with the arena)
	if opts.bot and p1.Character then
		p1.Character.Archivable = true
		local stand = p1.Character:Clone()
		p1.Character.Archivable = false
		if stand then
			for _, d in stand:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
				elseif d:IsA("Script") or d:IsA("LocalScript") then
					d:Destroy()
				end
			end
			stand.Name = "TestBotTrainer"
			local at = groundAt(battle, (s2.centre * CFrame.new(TRAINER)).Position) + Vector3.new(0, 3, 0)
			local look = (s1.centre * CFrame.new(LAYOUT.mine)).Position
			stand:PivotTo(CFrame.lookAt(at, Vector3.new(look.X, at.Y, look.Z)))
			stand.Parent = arena
			battle.botTrainer = stand
		end
	end

	-- intro
	for _, side in battle.sides do
		local opp = otherSide(battle, side)
		send(battle, side, {
			{ t = "text", text = opp.name .. " wants to battle!", effect = "intro" },
			{ t = "text", text = opp.name .. " sent out " .. speciesName(current(opp).record) .. "!" },
			{ t = "text", text = "Go, " .. speciesName(current(side).record) .. "!" },
		}, nil)
	end
	task.spawn(function()
		task.wait(4) -- intro playback
		loop(battle)
	end)
	return true
end

return PvpBattle
