--!strict
-- Sun Camel's attacks (docs/VFX-CATALOGUE.md C16-C18): heavy stomps and the
-- glowing sun disc on its crown.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Common = require(script.Parent.Parent.Common)
local BattleCamera = require(script.Parent.Parent.Parent.BattleCamera)

local GOLD = Color3.fromRGB(255, 200, 80)
local SAND = Color3.fromRGB(225, 200, 150)

-- The crown: the top of the head, a little forward.
local function crown(ctx: Common.Ctx): Vector3
	local attacker = ctx.attacker :: Model
	local direction = Common.Between(attacker, ctx.target)
	local size = attacker:GetExtentsSize()
	return attacker:GetPivot().Position
		+ direction * (math.max(size.X, size.Z) * 0.35)
		+ Vector3.new(0, size.Y * 0.5, 0)
end

return {
	-- C16: rears up and slams down; a shockwave runs along the ground to the target.
	["Stomp"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_Stomp") then
			return
		end
		local attacker = ctx.attacker :: Model
		local root = attacker.PrimaryPart :: BasePart
		local start = root.CFrame
		Common.MoveTo(
			root,
			0.4,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out,
			start * CFrame.Angles(math.rad(20), 0, 0)
		)
		Common.MoveTo(root, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In, start)
		local feet = start.Position - Vector3.new(0, attacker:GetExtentsSize().Y / 2, 0)
		local direction, distance = Common.Between(attacker, ctx.target)
		for step = 1, 3 do
			Common.Shockwave(feet + direction * distance * (step / 3), 3 + step, SAND)
			task.wait(0.08)
		end
		ctx.impact()
		BattleCamera.Shake("medium")
	end,

	-- C17: the sun disc lights up and fires a golden beam.
	["Sun Beam"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_SunBeam") then
			return
		end
		Common.Charge(ctx.attacker, GOLD, 0.3)
		Common.Ray(crown(ctx), ctx.target, GOLD, 1.6, 0.4, ctx.impact)
	end,

	-- C18: a long charge grows a little sun above the crown; it flies and explodes.
	["Solar Flare"] = function(ctx: Common.Ctx)
		if Common.PlayClip(ctx, "Attack_SolarFlare") then
			return
		end
		local from = crown(ctx) + Vector3.new(0, 1.5, 0)
		local sun = Instance.new("Part")
		sun.Shape = Enum.PartType.Ball
		sun.Material = Enum.Material.Neon
		sun.Color = GOLD
		sun.Size = Vector3.one * 0.2
		sun.Anchored = true
		sun.CanCollide = false
		sun.CanQuery = false
		sun.CFrame = CFrame.new(from)
		sun.Parent = workspace
		TweenService:Create(sun, TweenInfo.new(0.7), { Size = Vector3.one * 2.2 }):Play()
		Common.Charge(ctx.attacker, GOLD, 0.7)
		sun.Parent = nil
		sun.Size = Vector3.one * 2.2
		Common.Projectile({ from = from, to = ctx.target, arc = 2, time = 0.4, part = sun, trail = GOLD })
		ctx.impact()
		local target = ctx.target
		if target then
			Common.Shockwave(
				target:GetPivot().Position - Vector3.new(0, target:GetExtentsSize().Y / 2, 0),
				10,
				GOLD
			)
			Common.Emit(target:GetPivot().Position, GOLD, 30, 22)
		end
		local warm = Instance.new("ColorCorrectionEffect")
		warm.TintColor = Color3.fromRGB(255, 220, 170)
		warm.Brightness = 0.15
		warm.Parent = Lighting
		TweenService:Create(warm, TweenInfo.new(0.35), { TintColor = Color3.new(1, 1, 1), Brightness = 0 })
			:Play()
		task.delay(0.4, warm.Destroy, warm)
		BattleCamera.Shake("heavy")
	end,
}
