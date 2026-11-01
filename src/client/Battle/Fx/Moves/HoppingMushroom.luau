--!strict
-- Hopping Mushroom's attacks (docs/VFX-CATALOGUE.md C04-C06). Clips
-- Attack_<Move> play when they exist; until then the body moves by code.

local Common = require(script.Parent.Parent.Common)
local BattleCamera = require(script.Parent.Parent.Parent.BattleCamera)

local FOREST = Color3.fromRGB(110, 220, 90)
local SPORE = Color3.fromRGB(200, 235, 110)

return {
	-- C04: squash, a high bounce onto the target, bounce back.
	["Bounce"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_Bounce") then
			return
		end
		local root = (ctx.attacker :: Model).PrimaryPart :: BasePart
		local start = root.CFrame
		Common.MoveTo(
			root,
			0.22,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out,
			start - Vector3.new(0, 0.4, 0)
		)
		Common.Dust(start.Position, 10, 8)
		Common.Hop(root, Common.InFront(ctx, 2.5), 5, 0.35)
		ctx.impact()
		Common.Shockwave(
			root.Position - Vector3.new(0, (ctx.attacker :: Model):GetExtentsSize().Y / 2, 0),
			5,
			Color3.new(1, 1, 1)
		)
		Common.Hop(root, start, 3, 0.4)
	end,

	-- C05: the cap puffs a drifting cloud of spores over the target.
	["Spore Puff"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_SporePuff") then
			return
		end
		local attacker = ctx.attacker :: Model
		local top = attacker:GetPivot().Position + Vector3.new(0, attacker:GetExtentsSize().Y * 0.4, 0)
		for _ = 1, 5 do
			local puff = Instance.new("Part")
			puff.Shape = Enum.PartType.Ball
			puff.Size = Vector3.one * 0.8
			puff.Color = SPORE
			puff.Material = Enum.Material.Neon
			puff.Transparency = 0.3
			task.spawn(
				Common.Projectile,
				{ from = top, to = ctx.target, arc = 3, time = 0.5, part = puff, trail = SPORE }
			)
			task.wait(0.06)
		end
		task.wait(0.45)
		ctx.impact()
		local target = ctx.target
		if target then
			Common.Emit(target:GetPivot().Position, SPORE, 24, 8)
		end
	end,

	-- C06: charge, a huge jump over the target, a cap-first slam.
	["Cap Slam"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_CapSlam") then
			return
		end
		local attacker = ctx.attacker :: Model
		local root = attacker.PrimaryPart :: BasePart
		local start = root.CFrame
		Common.Charge(attacker, Color3.new(1, 1, 1), 0.5)
		Common.Hop(root, Common.InFront(ctx, 1.5) * CFrame.Angles(math.rad(-150), 0, 0), 9, 0.5)
		ctx.impact()
		Common.Shockwave(root.Position - Vector3.new(0, attacker:GetExtentsSize().Y / 2, 0), 8, FOREST)
		BattleCamera.Shake("heavy")
		task.wait(0.15)
		Common.Hop(root, start, 4, 0.45)
	end,
}
