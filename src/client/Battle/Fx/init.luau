--!strict
-- Presentation only. One impact gate for pooled V3 and unknown legacy moves;
-- cancelled visual jobs never replay a late HP update or start another renderer.
local Common = require(script.Common)
local Presentation = require(script.AttackPresentation)
local PetAnimator = require(script.Parent.Parent.Controllers.PetAnimator)
local Settings = require(script.Parent.BattleSettings)
local Input = game:GetService("UserInputService")
local Players = game:GetService("Players")
export type Ctx = Common.Ctx
type Move = (Ctx) -> ()
local Fx = {}
local epoch = 0
local registry: { [string]: { [string]: Move } } = {}
for _, module in script.Moves:GetChildren() do
	if module:IsA("ModuleScript") then
		registry[module.Name] = require(module) :: any
	end
end
function Fx.ClipName(move: string): string
	return "Attack_" .. move:gsub("[^%w]", "")
end
function Fx.CancelAll()
	epoch += 1
	Presentation.CancelAll()
	Common.ClearVisuals()
end
function Fx.Destroy()
	Fx.CancelAll()
	Presentation.Destroy()
end
function Fx.Stats()
	return Presentation.Stats()
end
function Fx.Play(ctx: Ctx)
	local generation = epoch
	ctx.presentationCancelled = false
	local upstream = ctx.cancelled
	ctx.cancelled = function()
		return ctx.presentationCancelled == true
			or generation ~= epoch
			or (upstream ~= nil and upstream())
			or not ctx.attacker
			or not ctx.attacker.Parent
			or not ctx.target
			or not ctx.target.Parent
	end
	local onImpact, impacted = ctx.impact, false
	ctx.pooled = Presentation.Has(ctx.species, ctx.move)
	ctx.reducedMotion = Settings.reducedMotion
	ctx.impact = function()
		if impacted or (ctx.cancelled :: () -> boolean)() then
			return
		end
		impacted = true
		local ok, problem = pcall(Common.Hit, ctx)
		if not ok then
			warn("[Fx hit feedback] " .. tostring(problem))
		end
		if not (ctx.cancelled :: () -> boolean)() then
			onImpact()
		end
	end
	ctx.clip = function(name: string)
		if (ctx.cancelled :: () -> boolean)() or not ctx.attacker then
			return nil, nil
		end
		return PetAnimator.PlayOnce(ctx.attacker, name)
	end
	local quality = Players.LocalPlayer:GetAttribute("V3MobileProfile")
	local mobile = if typeof(quality) == "boolean" then quality else Input.TouchEnabled
	Presentation.SetOptions({ mobile = mobile, reducedMotion = Settings.reducedMotion, onBeat = ctx.onBeat })
	local ok, problem = pcall(function()
		if (ctx.cancelled :: () -> boolean)() then
			return
		end
		if Presentation.Play(ctx) then
			return
		end
		local moves = registry[ctx.species]
		local play: Move = moves and moves[ctx.move] or Common.DefaultAttack
		play(ctx)
	end)
	if not ok then
		warn(`[Fx] {ctx.species} {ctx.move}: {problem}`)
	end
	ctx.impact() -- idempotent and cancellation guarded, including a renderer error
end
return Fx
