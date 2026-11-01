--!strict
-- Ball Scorpion's attacks (docs/VFX-CATALOGUE.md C13-C15): serrated
-- pincers, the stinger and its glowing amber seams. Venom is only a look:
-- there is no poison status in battles.

local Common = require(script.Parent.Parent.Common)
local BattleCamera = require(script.Parent.Parent.Parent.BattleCamera)

local AMBER = Color3.fromRGB(255, 170, 40)
local SAND = Color3.fromRGB(220, 180, 110)

local function withImpact(ctx: Common.Ctx, after: () -> ())
	local impact = ctx.impact
	ctx.impact = function()
		impact()
		after()
	end
end

return {
	-- C13: scuttles in and snaps both pincers in an X.
	["Pinch"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_Pinch") then
			return
		end
		withImpact(ctx, function()
			Common.Slash(ctx.target, 45, AMBER)
			task.delay(0.05, Common.Slash, ctx.target, -45, AMBER)
		end)
		Common.DefaultAttack(ctx)
	end,

	-- C14: the tail strikes down and sand bursts up under the target.
	["Sand Sting"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_SandSting") then
			return
		end
		withImpact(ctx, function()
			local target = ctx.target
			if target then
				local feet = target:GetPivot().Position - Vector3.new(0, target:GetExtentsSize().Y / 2, 0)
				Common.Emit(feet, SAND, 30, 24)
				Common.Shockwave(feet, 4, AMBER)
			end
		end)
		Common.DefaultAttack(ctx)
	end,

	-- C15: the seams blaze, then a huge overhead strike splashes amber.
	["Venom Tail"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_VenomTail") then
			return
		end
		Common.Charge(ctx.attacker, AMBER, 0.6)
		withImpact(ctx, function()
			local target = ctx.target
			if target then
				Common.Emit(target:GetPivot().Position, AMBER, 40, 20)
				Common.Shockwave(
					target:GetPivot().Position - Vector3.new(0, target:GetExtentsSize().Y / 2, 0),
					7,
					AMBER
				)
			end
			BattleCamera.Shake("heavy")
		end)
		Common.DefaultAttack(ctx)
	end,
}
