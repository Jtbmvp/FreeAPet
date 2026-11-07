--!strict
-- Install beside EffectPool/AttackProfiles under Battle/Fx, via Coder only.
-- Fx.Play keeps the sole impact gate and Common.Hit; this module adds art.
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Recipes = require(script.Parent.AttackProfiles)
local EffectPool = require(script.Parent.EffectPool)

local Presentation = {}
local pool: any = nil
local options: any = { mobile = UserInputService.TouchEnabled, reducedMotion = false, onBeat = nil }
local casts: { [any]: boolean } = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function live(model: Model?): boolean
	return model ~= nil and model.Parent ~= nil
end

local function centre(model: Model): Vector3
	local cf = model:GetBoundingBox()
	return cf.Position -- bounding-box centre, not an assumed centred pivot
end

local function cancelled(ctx: any, owner: any): boolean
	return not owner.active
		or not live(ctx.attacker)
		or not live(ctx.target)
		or (ctx.cancelled ~= nil and ctx.cancelled())
end

local function sleep(ctx: any, owner: any, duration: number): boolean
	local deadline = os.clock() + duration
	repeat
		if cancelled(ctx, owner) then
			return false
		end
		if os.clock() >= deadline then
			return true
		end
		RunService.PreRender:Wait()
	until false
end

local function beat(phase: string, ctx: any, recipe: any)
	if options.onBeat then
		local ok, problem = pcall(options.onBeat, phase, ctx, recipe)
		if not ok then
			warn("[BattlePresentation camera] " .. tostring(problem))
		end
	end
end

local function texture(name: string): string
	return "rbxassetid://" .. tostring(Recipes.textures[name])
end

local function ground(ctx: any): (Vector3, Vector3)
	local cf, size = ctx.target:GetBoundingBox()
	local feet = cf.Position - Vector3.yAxis * size.Y * 0.5
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.RespectCanCollide = true
	local map = Workspace:FindFirstChild("Map")
	local collision = map and map:FindFirstChild("Collision")
	params.FilterDescendantsInstances = if collision
		then { collision, Workspace.Terrain }
		else { Workspace.Terrain }
	local hit = Workspace:Raycast(feet + Vector3.yAxis * 2, -Vector3.yAxis * 14, params)
	if hit and hit.Normal.Y >= 0.65 then
		return hit.Position, hit.Normal
	end
	return feet, Vector3.yAxis
end

function Presentation.SetOptions(newOptions: any)
	-- Device choice may be overridden using measured quality, not just touch input.
	if newOptions.mobile ~= nil and newOptions.mobile ~= options.mobile then
		Presentation.CancelAll()
		if pool then
			pool:Destroy()
			pool = nil
		end
	end
	options.onBeat = newOptions.onBeat -- nil explicitly clears an older battle callback
	for key, value in newOptions do
		options[key] = value
	end
end

function Presentation.Has(species: string, move: string): boolean
	return move == "Tackle" or (Recipes.profiles[species] ~= nil and Recipes.profiles[species][move] ~= nil)
end

-- true = recognised; false = retain the existing unknown-move fallback.
-- On battle abort ctx.cancelled must be checked by the caller's final-impact gate.
function Presentation.Play(ctx: any): boolean
	local species = Recipes.profiles[ctx.species]
	local recipe = if ctx.move == "Tackle" then Recipes.default else species and species[ctx.move]
	if not recipe then
		return false
	end
	if not live(ctx.attacker) or not live(ctx.target) then
		return true
	end
	if not pool then
		pool = EffectPool.new(options.mobile)
	end
	local castPool = pool -- a cancelled older cast must never touch a replacement pool
	local budget = if options.mobile then Recipes.budgets.mobile else Recipes.budgets.desktop
	local owner = { active = true, remaining = budget.particlesPerCast }
	casts[owner] = true
	local from, target = centre(ctx.attacker), centre(ctx.target)
	local camera = Workspace.CurrentCamera
	local draw = not camera or (target - camera.CFrame.Position).Magnitude <= budget.maxDistance
	local palette = Recipes.palettes[recipe.palette]
	local color, accent = Color3.fromHex(palette[1]), Color3.fromHex(palette[2])
	local fraction = if options.mobile then 0.5 else 1
	local windup, travel, recovery = recipe.windup, recipe.travel, recipe.recovery
	local ok, problem = xpcall(function()
		local length, markers = ctx.clip(recipe.clip)
		if finite(length) and length > 0 and length <= 4 then
			local marker = if markers and finite(markers.impact) then markers.impact else length * 0.5
			local hitAt = math.clamp(marker, 0.02, length)
			travel = math.min(travel, hitAt)
			windup = hitAt - travel
			recovery = math.max(recipe.recovery, length - hitAt)
		end
		beat("anticipation", ctx, recipe)
		if draw then
			castPool:Burst(owner, from, texture("glow"), accent, math.floor(6 * fraction), 0.7)
		end
		if not sleep(ctx, owner, windup) then
			return
		end
		if draw and (recipe.family == "projectile" or recipe.family == "pulse") then
			local count = if options.mobile then math.min(recipe.count, 3) else recipe.count
			for i = 1, count do
				local stagger = (i - 1) * 0.025
				local offset = (i - (count + 1) * 0.5) * 0.45
				castPool:Projectile(
					owner,
					from + Vector3.new(offset, 0.3, 0),
					target,
					color,
					math.max(0.02, travel - stagger),
					1.4 + math.abs(offset),
					stagger,
					if recipe.texture == "spore" then 0.65 else 0.3
				)
			end
		elseif draw and recipe.family == "beam" then
			castPool:Line(owner, from, target, color, 0.65, travel + 0.18)
			castPool:Line(owner, from, target, accent, 0.2, travel + 0.18)
		end
		if not sleep(ctx, owner, travel) then
			return
		end
		beat("impact", ctx, recipe)
		ctx.impact() -- exactly one call here; Fx.Play owns idempotence and HP feedback
		if not cancelled(ctx, owner) and draw then
			local foot, normal = ground(ctx)
			castPool:Burst(
				owner,
				target,
				texture(recipe.texture),
				color,
				math.floor(recipe.burst * fraction),
				recipe.radius,
				true
			)
			castPool:Burst(owner, target, texture("sparkle"), accent, math.floor(8 * fraction), 1.2)
			castPool:Ring(owner, foot, color, texture("ring"), recipe.radius, 0.42, normal)
			if recipe.family == "slash" then
				local view = Workspace.CurrentCamera
				local right = if view then view.CFrame.RightVector else Vector3.xAxis
				local up = Vector3.yAxis
				for i = 1, math.min(recipe.count, 2) do
					local direction = (right + up * (if i == 1 then 0.55 else -0.55)).Unit
					castPool:Line(
						owner,
						target - direction * recipe.radius * 0.7,
						target + direction * recipe.radius * 0.7,
						if i == 1 then color else accent,
						0.38,
						0.22,
						recipe.radius * 0.4
					)
				end
			elseif recipe.family == "radial" then
				local count = if options.mobile then math.min(recipe.count, 4) else recipe.count
				for i = 1, count do
					local angle = math.pi * 2 * i / count
					local direction = Vector3.new(math.cos(angle), 0.25, math.sin(angle))
					castPool:Line(
						owner,
						target + direction * 0.35,
						target + direction * recipe.radius,
						if i % 2 == 0 then color else accent,
						0.18,
						0.28
					)
				end
			elseif recipe.family == "geyser" then
				for i = -1, 1 do
					castPool:Line(
						owner,
						foot,
						foot + Vector3.new(i * 0.7, recipe.radius, 0),
						color,
						0.28,
						0.34,
						0.6
					)
				end
			elseif recipe.family == "slam" or recipe.family == "pulse" then
				castPool:Ring(
					owner,
					foot + normal * 0.03,
					accent,
					texture("ring"),
					recipe.radius * 0.72,
					0.3,
					normal
				)
			end
		end
		if not sleep(ctx, owner, recovery) then
			return
		end
		beat("recovery", ctx, recipe)
		-- Tail overlaps recovery; it does not add .7 seconds to every turn.
		sleep(ctx, owner, math.max(0.7 - recovery, 0))
	end, debug.traceback)
	ctx.presentationCancelled = cancelled(ctx, owner) -- capture before our normal release disables owner
	castPool:Cancel(owner)
	casts[owner] = nil
	if not ok then
		error(problem, 0)
	end -- caller's protected fallback still owns impact
	return true
end

function Presentation.CancelAll()
	for owner in casts do
		if pool then
			pool:Cancel(owner)
		else
			owner.active = false
		end
	end
	table.clear(casts)
end

function Presentation.Stats()
	return if pool then pool:Stats() else { active = 0, capacity = 0, highWater = 0, misses = 0, emitted = 0 }
end

function Presentation.Destroy()
	Presentation.CancelAll()
	if pool then
		pool:Destroy()
		pool = nil
	end
end

return Presentation
