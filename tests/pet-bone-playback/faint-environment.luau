--!nocheck
local native, tips, bursts = true, 0, 0
local model = { PrimaryPart = {} }
local PetAnimator = {
	PlayOnce = function(m, name, hold)
		assert(m == model and name == "Faint" and hold == true)
		return if native then 1.2 else nil
	end,
}
local TweenService = {
	Create = function()
		tips += 1
		return { Play = function() end }
	end,
}
local TweenInfo = { new = function() end }
local CFrame = {
	Angles = function()
		return 0
	end,
}
local Vector3 = {
	new = function()
		return 0
	end,
}
local Color3 = { fromRGB = function() end }
local SMOKE = "smoke"
local function burst()
	bursts += 1
end
-- ACTUAL_FAINT_FUNCTION
faint(model)
assert(tips == 0 and bursts == 1, "clip fall never doubles the root rotation; smoke retained")
native = false
model.PrimaryPart.CFrame = 0
faint(model)
assert(tips == 1 and bursts == 2, "legacy procedural fallback retained")
print("PASS 2 BattleScreen Faint regression assertions")

local effects = {}
Color3.new = function()
	return 0
end
local Common = {
	PlayClip = function(_, name)
		table.insert(effects, name)
		return true
	end,
	Between = function()
		return 0, 0
	end,
	Trail = function()
		return function() end
	end,
	Impact = function() end,
	HitFlash = function() end,
	DamageNumber = function() end,
}
PetAnimator.PlayOnce = function(_, name)
	table.insert(effects, name)
	return 1
end
PetAnimator.Freeze = function()
	table.insert(effects, "Freeze")
end
local function moveTo() end
local HITSTOP = { normal = 0.1 }
local BattleCamera = { Shake = function() end }
-- ACTUAL_DEFAULT_ATTACK
-- ACTUAL_HIT
local impacts = 0
local ctx = {
	move = "Hop Kick",
	attacker = model,
	target = model,
	effect = "normal",
	impact = function()
		impacts += 1
	end,
}
Common.DefaultAttack(ctx)
assert(effects[1] == "Attack_HopKick" and impacts == 0, "starter signature uses its own clip")
ctx.move = "Tackle"
Common.DefaultAttack(ctx)
assert(
	effects[2] == "Attack_Tackle" and impacts == 1,
	"Tackle clip retains the single procedural dash/impact"
)
Common.Hit(ctx)
assert(effects[3] == "Hit" and effects[4] == "Freeze" and effects[5] == "Freeze", "Hit starts before hitstop")
print("PASS 3 Common attack/Hit integration assertions")
