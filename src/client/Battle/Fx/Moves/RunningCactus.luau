--!strict
-- Running Cactus's attacks (docs/VFX-CATALOGUE.md C10-C12): cream spines and
-- its glowing pink bloom.

local Common = require(script.Parent.Parent.Common)
local BattleCamera = require(script.Parent.Parent.Parent.BattleCamera)

local CREAM = Color3.fromRGB(240, 230, 200)
local ORANGE = Color3.fromRGB(255, 160, 70)
local PINK = Color3.fromRGB(255, 120, 190)

local function needle(): BasePart
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.15, 0.15, 0.9)
	part.Color = CREAM
	part.Material = Enum.Material.SmoothPlastic
	return part
end

-- Fires `count` needles from points around `centre` (radius 0 = one point).
local function volley(ctx: Common.Ctx, count: number, radius: number, gap: number)
	local attacker = ctx.attacker :: Model
	local centre = attacker:GetPivot().Position + Vector3.new(0, attacker:GetExtentsSize().Y * 0.15, 0)
	for index = 1, count do
		local angle = index / count * math.pi * 2
		local from = centre + Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius * 0.6, 0)
		local last = index == count
		local fly = function()
			Common.Projectile({
				from = from,
				to = ctx.target,
				arc = radius * 0.5,
				time = 0.25 + math.random() * 0.15,
				part = needle(),
				trail = ORANGE,
			})
		end
		if last then
			fly()
		else
			task.spawn(fly)
			task.wait(gap)
		end
	end
end

return {
	-- C10: pumps its arms, then spins into the target like a top.
	["Spin Dash"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_SpinDash") then
			return
		end
		local impact = ctx.impact
		ctx.impact = function()
			impact()
			local target = ctx.target
			if target then
				Common.Emit(target:GetPivot().Position, CREAM, 10, 18)
			end
		end
		Common.DefaultAttack(ctx, 720)
	end,

	-- C11: a quick volley of five spines.
	["Needle Shot"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_NeedleShot") then
			return
		end
		volley(ctx, 5, 0, 0.06)
		ctx.impact()
	end,

	-- C12: the bloom glows, spines burst out all round and curve onto the target.
	["Thorn Storm"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_ThornStorm") then
			return
		end
		Common.Charge(ctx.attacker, PINK, 0.55)
		volley(ctx, 24, 3, 0.02)
		ctx.impact()
		local target = ctx.target
		if target then
			Common.Emit(target:GetPivot().Position, Color3.fromRGB(220, 180, 110), 20, 14)
		end
		BattleCamera.Shake("heavy")
	end,
}
