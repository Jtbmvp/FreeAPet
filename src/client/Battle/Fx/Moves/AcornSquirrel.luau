--!strict
-- Acorn Squirrel's attacks (docs/VFX-CATALOGUE.md C01-C03). Each one plays
-- its Attack_<Move> clip when the creature has it; until then the body
-- moves procedurally and the effects are the same.

local Common = require(script.Parent.Parent.Common)
local BattleCamera = require(script.Parent.Parent.Parent.BattleCamera)

local AMBER = Color3.fromRGB(255, 190, 80)
local ACORN = Color3.fromRGB(150, 95, 45)
local LEAF = Color3.fromRGB(120, 200, 80)

-- A small acorn to throw: a nut with a darker cap.
local function acorn(size: number): BasePart
	local nut = Instance.new("Part")
	nut.Shape = Enum.PartType.Ball
	nut.Size = Vector3.one * size
	nut.Color = ACORN
	nut.Material = Enum.Material.SmoothPlastic
	local cap = Instance.new("Part")
	cap.Size = Vector3.new(size * 1.05, size * 0.4, size * 1.05)
	cap.Color = Color3.fromRGB(95, 60, 30)
	cap.Material = Enum.Material.SmoothPlastic
	cap.CanCollide = false
	cap.CanQuery = false
	cap.CanTouch = false
	cap.Massless = true
	cap.CFrame = CFrame.new(0, size * 0.35, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = nut, cap
	weld.Parent = nut
	cap.Parent = nut
	return nut
end

-- Where a thrown thing leaves the attacker: chest height, a little forward.
local function hands(ctx: Common.Ctx): Vector3
	local attacker = ctx.attacker :: Model
	local direction = Common.Between(attacker, ctx.target)
	return attacker:GetPivot().Position
		+ direction * 1
		+ Vector3.new(0, attacker:GetExtentsSize().Y * 0.15, 0)
end

-- Lean back before a throw.
local function windUp(ctx: Common.Ctx): CFrame?
	local root = ctx.attacker and ctx.attacker.PrimaryPart
	if not root then
		return nil
	end
	local start = root.CFrame
	local direction = Common.Between(ctx.attacker, ctx.target)
	Common.MoveTo(root, 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, start - direction * 0.8)
	return start
end

return {
	-- C01: spins round and whips the target with its banded tail.
	["Tail Smack"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_TailSmack") then
			return
		end
		local impact = ctx.impact
		ctx.impact = function()
			impact()
			Common.Slash(ctx.target, 30, AMBER)
		end
		Common.DefaultAttack(ctx, 360)
	end,

	-- C02: throws the acorn in an arc; it bursts into shell and leaves.
	["Acorn Toss"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_AcornToss") then
			return
		end
		local start = windUp(ctx)
		local root = ctx.attacker and ctx.attacker.PrimaryPart
		if root and start then
			Common.MoveTo(root, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, start)
		end
		Common.Projectile({
			from = hands(ctx),
			to = ctx.target,
			arc = 4,
			time = 0.4,
			part = acorn(0.9),
			trail = LEAF,
			spin = true,
		})
		ctx.impact()
		local target = ctx.target
		if target then
			Common.Emit(target:GetPivot().Position, LEAF, 10, 14)
		end
	end,

	-- C03: the tail's amber rings glow, a volley of small acorns, then a big one.
	["Nut Barrage"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_NutBarrage") then
			return
		end
		local attacker = ctx.attacker
		local root = attacker and attacker.PrimaryPart
		if root then
			local glow = Instance.new("PointLight")
			glow.Color = AMBER
			glow.Range = 0
			glow.Brightness = 3
			glow.Parent = root
			for step = 1, 10 do
				glow.Range = step * 1.2
				task.wait(0.045)
			end
			glow:Destroy()
		end
		local from = hands(ctx)
		for _ = 1, 6 do
			task.spawn(function()
				Common.Projectile({
					from = from,
					to = ctx.target,
					arc = 2.5,
					time = 0.25,
					part = acorn(0.5),
					trail = LEAF,
					spin = true,
				})
				local target = ctx.target
				if target then
					Common.Emit(target:GetPivot().Position, LEAF, 4, 10)
				end
				BattleCamera.Shake("light")
			end)
			task.wait(0.08)
		end
		Common.Projectile({
			from = from,
			to = ctx.target,
			arc = 4,
			time = 0.35,
			part = acorn(1.6),
			trail = AMBER,
			spin = true,
		})
		ctx.impact()
		BattleCamera.Shake("heavy")
	end,
}
