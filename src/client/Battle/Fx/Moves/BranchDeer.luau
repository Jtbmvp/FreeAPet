--!strict
-- Branch Deer's attacks (docs/VFX-CATALOGUE.md C07-C09): antlers, its ivy
-- leaves in green, gold and red.

local Common = require(script.Parent.Parent.Common)
local BattleCamera = require(script.Parent.Parent.Parent.BattleCamera)

local IVORY = Color3.fromRGB(245, 235, 210)
local LEAVES = { Color3.fromRGB(110, 200, 70), Color3.fromRGB(240, 190, 60), Color3.fromRGB(220, 90, 50) }

local function leafBurst(target: Model?, count: number)
	if target then
		for _, color in LEAVES do
			Common.Emit(target:GetPivot().Position, color, math.ceil(count / 3), 16)
		end
	end
end

return {
	-- C07: head down, a charge, the antlers hit in a crossing pair of slashes.
	["Antler Charge"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_AntlerCharge") then
			return
		end
		local impact = ctx.impact
		ctx.impact = function()
			impact()
			Common.Slash(ctx.target, 25, IVORY)
			Common.Slash(ctx.target, -25, IVORY)
		end
		Common.DefaultAttack(ctx)
	end,

	-- C08: leaves come loose from the antlers and slice through the target.
	["Leaf Blade"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_LeafBlade") then
			return
		end
		local attacker = ctx.attacker :: Model
		local top = attacker:GetPivot().Position + Vector3.new(0, attacker:GetExtentsSize().Y * 0.45, 0)
		for index = 1, 6 do
			local leaf = Instance.new("Part")
			leaf.Size = Vector3.new(0.9, 0.1, 0.5)
			leaf.Color = LEAVES[(index % 3) + 1]
			leaf.Material = Enum.Material.SmoothPlastic
			task.spawn(
				Common.Projectile,
				{ from = top, to = ctx.target, arc = 1.5, time = 0.35, part = leaf, spin = true }
			)
			task.wait(0.04)
		end
		task.wait(0.32)
		ctx.impact()
		Common.Slash(ctx.target, 10, LEAVES[2])
		leafBurst(ctx.target, 18)
	end,

	-- C09: rears up glowing, then a full charge in a storm of leaves.
	["Forest Rush"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_ForestRush") then
			return
		end
		local attacker = ctx.attacker :: Model
		local root = attacker.PrimaryPart :: BasePart
		local start = root.CFrame
		Common.MoveTo(
			root,
			0.3,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out,
			start * CFrame.Angles(math.rad(25), 0, 0)
		)
		Common.Charge(attacker, LEAVES[1], 0.45)
		local removeTrail = Common.Trail(attacker, LEAVES[1])
		Common.MoveTo(root, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, Common.InFront(ctx, 3))
		ctx.impact()
		removeTrail()
		local size = attacker:GetExtentsSize()
		Common.Shockwave(root.Position - Vector3.new(0, size.Y / 2, 0), 9, LEAVES[1])
		leafBurst(ctx.target, 30)
		BattleCamera.Shake("heavy")
		Common.MoveTo(root, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, start)
	end,
}
