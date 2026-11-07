--!strict
-- Client presentation of an already-authoritative capture result. No purchases,
-- asset loading or reward decisions. Original template first; legacy ball explicit.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Sfx = require(RS.Shared.Sfx)
local Camera = require(script.Parent.BattleCamera)
local Adapter = require(script.Parent.CapsuleRigFallback)
local Clips = require(script.Parent.CapsuleClipPlayer)
local Sequence = {}
local jobs: { [any]: boolean } = {}
local template: Model? = nil
local warned = false
local function reviewed(model: Instance?): boolean
	return model ~= nil
		and model:IsA("Model")
		and model:GetAttribute("FaP_SourceAssetId") == "82152145130743"
		and model:GetAttribute("FaP_SourceSHA256") == "3f08246c02d7f763f128918a11b128172522762938da57f6b15f220fe2092808"
		and model:GetAttribute("FaP_OriginalLogicalJointsRestored") == 5
end
function Sequence.SetTemplate(model: Model)
	assert(reviewed(model), "Unreviewed capsule template")
	template = model
end
local function findTemplate(): Model?
	if template and template.Parent then
		return template
	end
	local assets = RS:FindFirstChild("Assets")
	local replicated = assets and assets:FindFirstChild("BattleCapsule")
	if reviewed(replicated) then
		template = replicated :: Model
		return template
	end
	local map = Workspace:FindFirstChild("Map")
	local data = map and map:FindFirstChild("OriginalClipData", true)
	local model = data and data.Parent
	if reviewed(model) then
		template = model :: Model
		return template
	end
	return nil
end
function Sequence.CancelAll()
	for job in jobs do
		job.active = false
		job.cleanup()
	end
	table.clear(jobs)
end
function Sequence.Play(from: Vector3, wild: Model?, shakes: number, caught: boolean, cancelled: () -> boolean)
	if not wild or not wild.Parent or not wild.PrimaryPart then
		return
	end
	local native: any = nil
	local adapter: any = nil
	local original = findTemplate()
	if original then
		adapter = Adapter.new(original, Workspace, function(model, name)
			native = native or Clips.Attach(model)
			return native ~= nil and native.Play(name)
		end)
	end
	local legacy: Part? = nil
	if not adapter then
		if not warned then
			warn("[Capsule] Original template unavailable: explicit legacy ball fallback")
			warned = true
		end
		legacy = Instance.new("Part")
		legacy.Name = "LegacyCapsuleFallback"
		legacy.Shape = Enum.PartType.Ball
		legacy.Size = Vector3.one * 1.4
		legacy.Anchored = true
		legacy.CanCollide = false
		legacy.CanQuery = false
		legacy.CanTouch = false
		legacy.Color = Color3.fromRGB(120, 200, 255)
		legacy.Parent = Workspace
	end
	local job: any = { active = true, cleaned = false }
	local hidden: { [BasePart]: number } = {}
	function job.cleanup()
		if job.cleaned then
			return
		end
		job.cleaned = true
		job.active = false
		for part, before in hidden do
			if part.Parent then
				part.LocalTransparencyModifier = before
			end
		end
		if native then
			native.Destroy()
		end
		if adapter then
			Camera.Forget(adapter.model)
			adapter:Destroy()
		end
		if legacy then
			legacy:Destroy()
		end
		jobs[job] = nil
	end
	jobs[job] = true
	local function aborted(): boolean
		return not job.active or cancelled() or not wild.Parent
	end
	local function sleep(seconds: number): boolean
		local deadline = os.clock() + seconds
		repeat
			if aborted() then
				return false
			end
			if os.clock() >= deadline then
				return true
			end
			RunService.PreRender:Wait()
		until false
	end
	local function place(at: CFrame)
		if adapter then
			adapter.model:PivotTo(at)
		elseif legacy then
			legacy.CFrame = at
		end
	end
	local function clip(name: string): number?
		if not adapter then
			return nil
		end
		local ok, kind = adapter:Play(name)
		return if ok and kind == "original clip" and native then native.Duration(name) else nil
	end
	local ok, problem = xpcall(function()
		local box, size = wild:GetBoundingBox()
		local landing = box.Position - Vector3.new(0, size.Y / 2 - 0.7, 0)
		place(CFrame.new(from))
		if adapter then
			Camera.Move(Camera.CaptureCapsule(adapter.model, wild), 0.2)
		end
		local duration = clip("Throw")
		local flight = duration or 0.33
		local started = os.clock()
		repeat
			if aborted() then
				return
			end
			local t = math.min((os.clock() - started) / flight, 1)
			local point = from:Lerp(landing, t)
			if not duration then
				point += Vector3.yAxis * (4 * 6 * t * (1 - t))
			end -- source Throw already owns its bounce
			place(CFrame.new(point))
			if t >= 1 then
				break
			end
			RunService.PreRender:Wait()
		until false
		clip("Close")
		for _, part in wild:GetDescendants() do
			if part:IsA("BasePart") then
				hidden[part] = part.LocalTransparencyModifier
				part.LocalTransparencyModifier = 1
			end
		end
		if not sleep(0.3) then
			return
		end
		-- The retained Shake clip already contains a grouped sequence; play it
		-- once rather than multiplying its2.8s by each server shake count.
		local count = math.clamp(shakes, 1, 4)
		local shakeLength = clip("Shake")
		if shakeLength then
			for _ = 1, count do
				Sfx.Play("capsuleShake")
				if not sleep(shakeLength / count) then
					return
				end
			end
		else
			for _ = 1, count do
				Sfx.Play("capsuleShake")
				local shakeStarted = os.clock()
				repeat
					if aborted() then
						return
					end
					local t = math.min((os.clock() - shakeStarted) / 0.6, 1)
					place(CFrame.new(landing) * CFrame.Angles(0, 0, math.sin(t * math.pi * 4) * math.rad(25)))
					if t >= 1 then
						break
					end
					RunService.PreRender:Wait()
				until false
			end
		end
		local final = clip(if caught then "Lock" else "Open")
		if caught then
			Sfx.Play("captured")
		end
		sleep(final or 0.6)
	end, debug.traceback)
	job.cleanup()
	if not cancelled() then
		Camera.Move(Camera.Gameplay(), 0.25)
	end
	if not ok then
		warn("[Capsule presentation] " .. tostring(problem))
	end
end
return Sequence
