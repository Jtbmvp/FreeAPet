--!strict
-- Attack effects (docs/VFX-CATALOGUE.md). Each creature has a module in
-- Fx/Moves named after its SpeciesId, returning { [moveName] = function(ctx) }.
-- A move without an entry uses Common.DefaultAttack. Every move must call
-- ctx.impact() once at the hit: that plays the shared hit effects (sparks,
-- flash, damage number, hitstop, shake) and drains the HP bar. If a move
-- forgets or errors, impact still happens at the end.

local Common = require(script.Common)
local PetAnimator = require(script.Parent.Parent.Controllers.PetAnimator)

export type Ctx = Common.Ctx
type Move = (Ctx) -> ()

local Fx = {}

local registry: { [string]: { [string]: Move } } = {}
for _, module in script.Moves:GetChildren() do
	if module:IsA("ModuleScript") then
		registry[module.Name] = require(module) :: any
	end
end

-- "Acorn Toss" -> "Attack_AcornToss": the clip name a creature's attack uses.
function Fx.ClipName(move: string): string
	return "Attack_" .. move:gsub("[^%w]", "")
end

-- Plays one attack. `ctx.impact` is what the battle screen does at the hit
-- (HP bar); the shared hit effects are added here. Yields until done.
function Fx.Play(ctx: Ctx)
	local onImpact = ctx.impact
	local impacted = false
	ctx.impact = function()
		if impacted then
			return
		end
		impacted = true
		Common.Hit(ctx)
		onImpact()
	end
	ctx.clip = function(name: string)
		if not ctx.attacker then
			return nil, nil
		end
		return PetAnimator.PlayOnce(ctx.attacker, name)
	end
	local moves = registry[ctx.species]
	local play: Move = moves and moves[ctx.move] or Common.DefaultAttack
	local ok, problem = pcall(play, ctx)
	if not ok then
		warn(`[Fx] {ctx.species} {ctx.move}: {problem}`)
	end
	ctx.impact()
end

return Fx
