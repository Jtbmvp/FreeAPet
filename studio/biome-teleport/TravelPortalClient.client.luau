-- TravelPortalClient (StarterPlayerScripts): the portal cinematic for the Travel panel.
-- The server (ServerScriptService.BiomeTeleportServer) validates the trip and sends ("start", biome).
-- Then, on this client only:
--   1. a quick flash, and the character is moved to a hidden stage under the map (night void with stars)
--      where a portal (ReplicatedStorage.TravelPortal, modelled in Blender) opens in the destination colour;
--   2. cinematic camera: the character runs and leaps into the vortex, the vortex speeds up, white flash;
--   3. sky drop: behind the flash we send ("enter") and the server does the real move to TP_* / the base
--      spawn; then a client-only copy of the character skydives onto the destination island from ~190 studs,
--      camera above and behind (Fortnite style): free fall with arms spread, a stud-style parachute opens
--      halfway, it glides down and lands softly on the arrival point (dust ring); the real character waits
--      there anchored and hidden, then takes the copy's place and the controls come back.
-- Other players only see the portal where the trip starts and a dust ring where it ends ("fx" depart/arrive).
-- Safety: everything is undone after SAFETY seconds whatever happens, and on death/respawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Teleport = ReplicatedStorage:WaitForChild("BiomeTeleportRemotes"):WaitForChild("Teleport") :: RemoteEvent
local TEMPLATE = ReplicatedStorage:WaitForChild("TravelPortal") :: Model

local SAFETY = 10
local CENTER = Vector3.new(0, TEMPLATE:GetAttribute("PortalCenterY") or 9.6, 0)

local BIOMES = {
	Base = { name = "My Base", emoji = "🏠", color = Color3.fromRGB(64, 224, 200) },
	Lobby = { name = "Lobby", emoji = "⛲", color = Color3.fromRGB(255, 130, 200) },
	Forest = { name = "Forest", emoji = "🌲", color = Color3.fromRGB(96, 226, 110) },
	Desert = { name = "Desert", emoji = "🏜️", color = Color3.fromRGB(255, 196, 64) },
	Ice = { name = "Ice", emoji = "❄️", color = Color3.fromRGB(120, 214, 255) },
	Kingdom = { name = "Forgotten Kingdom", emoji = "🏰", color = Color3.fromRGB(186, 136, 255) },
}

local function lighter(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end
local function darker(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end
local function backOut(a: number): number
	local c1, c3 = 1.9, 2.9
	return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
end

--------------------------------------------------------------------------------------------
-- Portal: a clone of the Blender model, coloured, scaled and animated by hand every frame
--------------------------------------------------------------------------------------------
type Portal = {
	model: Model,
	pivot: CFrame,
	scale: number,
	speed: number,
	glow: number,
	alive: boolean,
	[string]: any,
}

local SPIN = { RingOuter = 0.7, RingInner = -1.3, Swirl = 2.6, Vortex = 0.9 }

local function newPortal(pivot: CFrame, color: Color3, world: boolean): Portal
	local model = TEMPLATE:Clone()
	local parts, rel, size0 = {}, {}, {}
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
			rel[p] = p.CFrame -- the template sits at the origin
			size0[p] = p.Size
		end
	end
	local atts = {}
	for _, a in model:GetDescendants() do
		if a:IsA("Attachment") then
			atts[a] = a.Position
		end
	end
	local function paint(name: string, c: Color3)
		local p = model:FindFirstChild(name)
		if p then
			(p :: BasePart).Color = c
		end
	end
	paint("Runes", color)
	paint("Crystals", lighter(color, 0.35))
	paint("RingInner", lighter(color, 0.55))
	paint("Swirl", lighter(color, 0.7))
	paint("Vortex", color)
	paint("VortexBack", darker(color, 0.55))
	local fx = model:FindFirstChild("Fx") :: BasePart
	local seq = ColorSequence.new(lighter(color, 0.6), color)
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Beam") then
			d.Color = seq
		elseif d:IsA("PointLight") then
			d.Color = color
		end
	end
	if world then
		(model:FindFirstChild("Base") :: BasePart).Transparency = 1 -- uneven ground: no plinth
	end
	local self: Portal = { model = model, pivot = pivot, scale = 0.01, speed = 1, glow = 1, alive = true }
	local angles = { RingOuter = 0, RingInner = 0, Swirl = 0, Vortex = 0 }
	local light = fx and fx:FindFirstChildOfClass("PointLight")
	local lastScale = -1
	local t = 0
	local cfs = table.create(#parts)
	model.Parent = workspace
	self.conn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		local s = math.max(self.scale, 0.01)
		if s ~= lastScale then
			lastScale = s
			for _, p in parts do
				p.Size = size0[p] * s
			end
			for a, pos in atts do
				a.Position = pos * s
			end
		end
		for name, rate in SPIN do
			angles[name] += dt * rate * self.speed
		end
		for i, p in parts do
			local r = rel[p]
			local a = angles[p.Name]
			if a then
				r = CFrame.new(CENTER) * CFrame.Angles(0, 0, a) * CFrame.new(-CENTER) * r
			end
			cfs[i] = self.pivot * (CFrame.new(r.Position * s) * r.Rotation)
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if light then
			light.Brightness = (1.1 + 0.35 * math.sin(t * 7)) * self.glow
			light.Range = 22 * math.max(s, 0.3)
		end
	end)
	function self.burst(n: number)
		local e = fx and fx:FindFirstChild("Burst") :: ParticleEmitter?
		if e then
			e:Emit(n)
		end
	end
	-- grow (or shrink) the scale with a springy ease
	function self.scaleTo(target: number, time: number, shrink: boolean?)
		local from = self.scale
		local start = os.clock()
		while self.alive do
			local a = math.clamp((os.clock() - start) / time, 0, 1)
			local e = if shrink then a * a * (2.7 * a - 1.7) else backOut(a)
			self.scale = from + (target - from) * e
			if a >= 1 then
				break
			end
			task.wait()
		end
	end
	function self.destroy()
		if not self.alive then
			return
		end
		self.alive = false
		self.conn:Disconnect()
		model:Destroy()
	end
	-- open, wait, close and clean up (used for portals seen in the world)
	function self.play(size: number, hold: number)
		task.spawn(function()
			self.scaleTo(size, 0.35)
			self.burst(14)
			task.wait(hold)
			self.speed = 3
			self.scaleTo(0.01, 0.35, true)
			self.destroy()
		end)
	end
	return self
end

-- a ground point under a position (ignores characters)
local function groundBelow(pos: Vector3, fallback: number): Vector3
	local params = RaycastParams.new()
	local ignore = {}
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -14, 0), params)
	return if hit then hit.Position else pos - Vector3.new(0, fallback, 0)
end
local function flat(cf: CFrame): CFrame
	local look = cf.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(Vector3.zero, look.Unit)
end
-- small portal standing on the ground under cf, its mouth facing cf's look, pushed back by `back`
local function worldPortalAt(cf: CFrame, color: Color3, back: number): Portal
	local g = groundBelow(cf.Position, 3.5)
	local pivot = CFrame.new(g) * flat(cf) * CFrame.new(0, -0.15, back)
	return newPortal(pivot, color, true)
end

--------------------------------------------------------------------------------------------
-- Stage: a private void under the map (only this client builds it)
--------------------------------------------------------------------------------------------
local function stageOrigin(): CFrame
	return CFrame.new(6000 + (player.UserId % 16) * 400, -440, 0)
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function buildStage(o: CFrame, color: Color3): Folder
	local f = Instance.new("Folder")
	f.Name = "TravelPortalStage"
	local night = Color3.fromRGB(26, 18, 64) -- Neon: a flat, unlit deep-night colour
	local W, H = 170, 100
	for _, w in {
		{ CFrame.new(0, -6, 0), Vector3.new(W, 2, W) },
		{ CFrame.new(0, H - 6, 0), Vector3.new(W, 2, W) },
		{ CFrame.new(W / 2, H / 2 - 6, 0), Vector3.new(2, H, W) },
		{ CFrame.new(-W / 2, H / 2 - 6, 0), Vector3.new(2, H, W) },
		{ CFrame.new(0, H / 2 - 6, W / 2), Vector3.new(W, H, 2) },
		{ CFrame.new(0, H / 2 - 6, -W / 2), Vector3.new(W, H, 2) },
	} do
		part({ Name = "Void", CFrame = o * w[1], Size = w[2], Color = night, Material = Enum.Material.Neon, Parent = f })
	end
	-- glossy floor disc + an invisible walkway at the plinth's height
	part({
		Name = "Floor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 64, 64), CFrame = o * CFrame.new(0, -0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(34, 28, 70), Material = Enum.Material.Glass, Reflectance = 0.25, Parent = f,
	})
	part({ Name = "Walk", Size = Vector3.new(60, 1, 60), CFrame = o * CFrame.new(0, 1.4, 0), Transparency = 1, CanCollide = true, CanQuery = true, Parent = f })
	-- a soft nebula behind the portal: a few huge, faint smoke puffs in the biome colour
	local neb = part({ Name = "Nebula", Size = Vector3.new(130, 50, 6), CFrame = o * CFrame.new(0, 26, 62), Transparency = 1, Parent = f })
	local ne = Instance.new("ParticleEmitter")
	ne.Texture = "rbxasset://textures/particles/smoke_main.dds"
	ne.Shape = Enum.ParticleEmitterShape.Box
	ne.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	ne.Rate = 3
	ne.Lifetime = NumberRange.new(6, 8)
	ne.Speed = NumberRange.new(0.5, 1.5)
	ne.SpreadAngle = Vector2.new(180, 180)
	ne.Rotation = NumberRange.new(0, 360)
	ne.RotSpeed = NumberRange.new(-8, 8)
	ne.LightEmission = 1
	ne.Size = NumberSequence.new(34, 46)
	ne.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.8), NumberSequenceKeypoint.new(0.7, 0.8), NumberSequenceKeypoint.new(1, 1) })
	ne.Color = ColorSequence.new(color, lighter(color, 0.3))
	ne.Parent = neb
	-- stars: one emitter filling the void, few particles
	local stars = part({ Name = "Stars", Size = Vector3.new(150, 70, 150), CFrame = o * CFrame.new(0, 34, 0), Transparency = 1, Parent = f })
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	pe.Rate = 60
	pe.Lifetime = NumberRange.new(2, 3.5)
	pe.Speed = NumberRange.new(0, 0.5)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1.4), NumberSequenceKeypoint.new(1, 0) })
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1), lighter(color, 0.3))
	pe.Parent = stars
	-- fill light so the character reads against the void
	local fill = part({ Name = "Fill", Size = Vector3.new(1, 1, 1), CFrame = o * CFrame.new(-6, 14, -18), Transparency = 1, Parent = f })
	local pl = Instance.new("PointLight")
	pl.Range = 34
	pl.Brightness = 0.9
	pl.Color = Color3.fromRGB(235, 230, 255)
	pl.Parent = fill
	f.Parent = workspace
	pe:Emit(80)
	ne:Emit(10)
	return f
end

--------------------------------------------------------------------------------------------
-- Screen: the white flash between phases
--------------------------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "TravelPortalScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 210
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BorderSizePixel = 0
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.ZIndex = 10
flash.Parent = gui

--------------------------------------------------------------------------------------------
-- Sky drop: a client-only copy of the character skydives onto the destination island, seen
-- from above and behind (Fortnite style); halfway down a stud-style parachute opens, the fall
-- slows and it lands softly on the arrival point. Meanwhile the real character is already there
-- (moved by the server), anchored and hidden on this client only.
--------------------------------------------------------------------------------------------
local DROP_H = 190 -- studs above the arrival point
local DROP_BACK = 44 -- starts this far behind the arrival point and glides in
local FREE_T, OPEN_Y, GLIDE_T = 1.3, 60, 2.05
local LAND_T = 0.45
local WIND_N = 18

local function fallCopy(char: Model, at: CFrame, parent: Instance): (Model?, Humanoid?)
	local was = char.Archivable
	char.Archivable = true
	local ok, copy = pcall(char.Clone, char)
	char.Archivable = was
	if not (ok and copy) then
		return nil, nil
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.Anchored = false
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Motor6D") then
			d.Transform = CFrame.identity
		end
	end
	local hum = copy:FindFirstChildOfClass("Humanoid")
	local root = copy:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (hum and root) then
		copy:Destroy()
		return nil, nil
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.EvaluateStateMachine = false
	hum.PlatformStand = true
	root.Anchored = true
	copy.Name = "TravelDropCopy"
	copy:PivotTo(at)
	copy.Parent = parent
	return copy, hum
end

-- arms/legs posed by hand on the copy (R15 and R6): the angle turns the limb out to the side
local LIMBS = {
	RightShoulder = 1, ["Right Shoulder"] = 1, LeftShoulder = -1, ["Left Shoulder"] = -1,
	RightHip = 2, ["Right Hip"] = 2, LeftHip = -2, ["Left Hip"] = -2,
}
local function rigOf(copy: Model): { [Motor6D]: CFrame }
	local m = {}
	for _, d in copy:GetDescendants() do
		if d:IsA("Motor6D") and LIMBS[d.Name] then
			m[d] = d.C0
		end
	end
	return m
end
local function pose(rig: { [Motor6D]: CFrame }, arms: number, legs: number)
	for j, c0 in rig do
		local k = LIMBS[j.Name]
		local a = if math.abs(k) == 1 then arms * k else legs * k / 2
		j.C0 = CFrame.new(c0.Position) * CFrame.Angles(0, 0, a) * c0.Rotation
	end
end

-- dust ring + puff on the ground (the landing; also what other players see on arrival)
local function landPoof(at: Vector3, color: Color3)
	local g = groundBelow(at, 3)
	local ring = part({
		Name = "TravelLandRing", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
		Color = lighter(color, 0.5), Transparency = 0.15, Size = Vector3.new(0.15, 2, 2),
		CFrame = CFrame.new(g + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2), Parent = workspace,
	})
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Size = Vector3.new(0.15, 17, 17), Transparency = 1 }):Play()
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(240, 232, 214))
	pe.Size = NumberSequence.new(1.6, 4)
	pe.Transparency = NumberSequence.new(0.35, 1)
	pe.Lifetime = NumberRange.new(0.6, 0.9)
	pe.Speed = NumberRange.new(9, 14)
	pe.SpreadAngle = Vector2.new(180, 8)
	pe.Drag = 5
	pe.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis is up: Right fans out flat
	pe.Rate = 0
	pe.Parent = ring
	pe:Emit(22)
	task.delay(1.2, ring.Destroy, ring)
end

-- stud-style parachute in root space (forward = -Z): a curved canopy of coloured blocks + 4 lines
local function buildChute(color: Color3, parent: Instance)
	local parts, rel, size0 = {}, {}, {}
	local function add(p: BasePart, cf: CFrame)
		p.Parent = parent
		table.insert(parts, p)
		rel[p] = cf
		size0[p] = p.Size
	end
	local R, top, zc = 8, 9.5, -1.2
	local cy = top - R
	for i = -3, 3 do
		local phi = i * 0.27
		local p = part({
			Name = "Canopy", Material = Enum.Material.Plastic,
			Color = if i % 2 == 0 then color else lighter(color, 0.82),
			Size = Vector3.new(2 * R * math.sin(0.135) * 1.1, 0.5, 5.6),
			TopSurface = Enum.SurfaceType.Studs, BottomSurface = Enum.SurfaceType.Inlet,
		})
		add(p, CFrame.new(R * math.sin(phi), cy + R * math.cos(phi), zc) * CFrame.Angles(0, 0, -phi))
	end
	local ex, ey = R * math.sin(0.81) * 0.98, cy + R * math.cos(0.81) - 0.3
	for _, sx in { -1, 1 } do
		for _, sz in { -2.4, 2.4 } do
			local from = Vector3.new(sx * 1.1, 1.6, 0)
			local to = Vector3.new(sx * ex, ey, zc + sz)
			local p = part({ Name = "Line", Material = Enum.Material.Neon, Color = Color3.new(1, 1, 1), Size = Vector3.new(0.09, 0.09, (to - from).Magnitude) })
			add(p, CFrame.lookAt((from + to) / 2, to))
		end
	end
	return parts, rel, size0
end

local dropFolder: Folder? = nil
local function stopDrop()
	RunService:UnbindFromRenderStep("TravelPortalDrop")
	if dropFolder then
		dropFolder:Destroy()
		dropFolder = nil
	end
end

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function tween(obj: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?)
	local tw = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad), props)
	tw:Play()
	return tw
end

--------------------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------------------
-- Movement/jump input is sunk with a high-priority action (works whatever control script the game
-- uses); the PlayerModule controls are also disabled when the module exists. Never waits.
local ContextActionService = game:GetService("ContextActionService")
local FREEZE_INPUTS = {
	Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward, Enum.PlayerActions.CharacterLeft,
	Enum.PlayerActions.CharacterRight, Enum.PlayerActions.CharacterJump, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S,
	Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Space,
	Enum.KeyCode.Thumbstick1, Enum.KeyCode.ButtonA,
}
local controls = nil
local function setControls(on: boolean)
	if on then
		ContextActionService:UnbindAction("TravelPortalFreeze")
	else
		ContextActionService:BindActionAtPriority("TravelPortalFreeze", function()
			return Enum.ContextActionResult.Sink
		end, false, 3000, table.unpack(FREEZE_INPUTS))
	end
	if not controls then
		local ok, pm = pcall(function()
			local mod = player:WaitForChild("PlayerScripts"):FindFirstChild("PlayerModule")
			return if mod then require(mod :: ModuleScript) :: any else nil
		end)
		if ok and pm and pm.GetControls then
			controls = pm:GetControls()
		end
	end
	if controls then
		pcall(function()
			if on then
				controls:Enable()
			else
				controls:Disable()
			end
		end)
	end
end

--------------------------------------------------------------------------------------------
-- The trip
--------------------------------------------------------------------------------------------
local trip: { [string]: any }? = nil

-- QA only: with the player attribute TravelPortalHold = "stage", "fall" or "glide" (set from the command bar in a
-- playtest) the trip pauses at that moment so it can be screenshotted. Never set by the game.
local function qaHeld(phase: string): boolean
	return player:GetAttribute("TravelPortalHold") == phase
end
local function qaHold(t, phase: string)
	while trip == t and qaHeld(phase) do
		task.wait()
	end
end

local function restoreAtmosphere(t: { [string]: any })
	local a = t.atm
	t.atm = nil
	-- only put the old values back if nobody (zone ambience scripts) changed them meanwhile
	if a and a.inst.Parent and a.inst.Density == a.setD and a.inst.Haze == a.setH then
		a.inst.Density = a.d
		a.inst.Haze = a.h
	end
end

-- the HUD is hidden during the cinematic and comes back at the end (only what we hid, if still hidden)
local function hideHud(t: { [string]: any })
	t.hidden = {}
	for _, g in player:WaitForChild("PlayerGui"):GetChildren() do
		if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
			g.Enabled = false
			table.insert(t.hidden, g)
		end
	end
end
local function showHud(t: { [string]: any })
	for _, g in t.hidden or {} do
		if g.Parent and not g.Enabled then
			g.Enabled = true
		end
	end
	t.hidden = nil
end

local function endTrip(t: { [string]: any })
	if trip ~= t then
		return
	end
	trip = nil
	player:SetAttribute("TravelPortalActive", nil)
	for _, c in t.conns do
		c:Disconnect()
	end
	stopDrop()
	for _, d in t.hiddenParts or {} do
		if d.Parent then
			d.LocalTransparencyModifier = 0
		end
	end
	t.hiddenParts = nil
	if t.root then
		t.root.Anchored = false
		-- never leave anyone on the stage (it is about to go): back to the destination, or to where they were
		if t.root.Parent and t.root.Position.Y < -300 then
			t.char:PivotTo(t.arrived or t.home)
		end
	end
	for _, tr in t.tracks or {} do
		tr:Stop(0.2)
	end
	if t.stage then
		t.stage:Destroy()
	end
	if t.portal then
		t.portal.destroy()
	end
	restoreAtmosphere(t)
	showHud(t)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = t.fov
	local hum = t.hum :: Humanoid
	if hum and hum.Parent then
		cam.CameraSubject = hum
		hum:Move(Vector3.zero)
	end
	flash.BackgroundTransparency = 1
	gui.Enabled = false
	setControls(true)
end

local function camTo(cf: CFrame, time: number)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	return tween(cam, time, { CFrame = cf }, Enum.EasingStyle.Sine)
end

local function waitFor(t, cond: () -> boolean, timeout: number): boolean
	local start = os.clock()
	while trip == t and not cond() do
		if os.clock() - start > timeout then
			return false
		end
		task.wait()
	end
	return trip == t
end

local function play(biome: string)
	local info = BIOMES[biome] or BIOMES.Lobby
	local color = info.color
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and hum and root) then
		return
	end
	if trip then
		endTrip(trip)
	end
	local cam = workspace.CurrentCamera
	local t = { conns = {}, hum = hum, fov = cam.FieldOfView, arrived = nil :: CFrame? }
	t.home = char:GetPivot() -- where we were, in case the trip has to be abandoned
	t.char = char
	trip = t
	player:SetAttribute("TravelPortalActive", true)
	setControls(false)
	hum:Move(Vector3.zero)
	table.insert(t.conns, hum.Died:Connect(function()
		endTrip(t)
	end))
	table.insert(t.conns, player.CharacterRemoving:Connect(function()
		endTrip(t)
	end))
	local function safety()
		if trip ~= t then
			return
		end
		if player:GetAttribute("TravelPortalHold") then
			task.delay(1, safety) -- QA pause (see qaHold): wait
			return
		end
		warn("[TravelPortal] safety timeout, restoring controls")
		endTrip(t)
	end
	task.delay(SAFETY, safety)
	t.onArrive = function(cf: CFrame)
		t.arrived = cf
	end

	-- 1) flash and move to the stage
	gui.Enabled = true
	flash.BackgroundColor3 = lighter(color, 0.85)
	tween(flash, 0.28, { BackgroundTransparency = 0 }).Completed:Wait()
	if trip ~= t then
		return
	end
	hideHud(t)
	local o = stageOrigin()
	t.stage = buildStage(o, color)
	-- the game's thick haze would wash the stage out: thin it while we are there (client only, restored)
	local atm = game:GetService("Lighting"):FindFirstChildOfClass("Atmosphere")
	if atm then
		local saved = { inst = atm, d = atm.Density, h = atm.Haze }
		atm.Density = 0.22
		atm.Haze = 0
		saved.setD, saved.setH = atm.Density, atm.Haze
		t.atm = saved
	end
	local portal = newPortal(o, color, false)
	t.portal = portal
	-- On the stage the character is driven by hand (anchored root + the avatar's own run/jump
	-- animations): it doesn't depend on physics or streaming, which can pause a character far away.
	local feet = hum.HipHeight + root.Size.Y / 2
	local y0 = 1.9 + feet
	local face = CFrame.Angles(0, math.pi, 0) -- looking at the portal (+Z of the stage)
	root.Anchored = true
	t.root = root
	char:PivotTo(o * CFrame.new(0, y0, -9) * face)
	cam.CameraType = Enum.CameraType.Scriptable
	local look = (o * CFrame.new(0, 7.5, -3)).Position
	cam.CFrame = CFrame.lookAt((o * CFrame.new(-17, 4.5, -25)).Position, look)
	camTo(CFrame.lookAt((o * CFrame.new(-10, 4, -19)).Position, look), 1.6)
	tween(flash, 0.35, { BackgroundTransparency = 1 })
	task.spawn(portal.scaleTo, 1, 0.7)
	task.delay(0.3, portal.burst, 24)

	-- 2) run, leap, dive
	task.wait(0.5)
	if trip ~= t then
		return
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	local animate = char:FindFirstChild("Animate")
	local function track(folder: string, speed: number): AnimationTrack?
		local f = animate and animate:FindFirstChild(folder)
		local anim = f and f:FindFirstChildOfClass("Animation")
		if not (animator and anim) then
			return nil
		end
		local ok, tr = pcall(animator.LoadAnimation, animator, anim)
		if ok and tr then
			tr.Priority = Enum.AnimationPriority.Action
			tr:Play(0.1, 1, speed)
			table.insert(t.tracks, tr)
			return tr
		end
		return nil
	end
	t.tracks = {}
	-- drive the root along a path: f(a) -> stage-space CFrame, a in [0, 1]
	local function drive(time: number, f: (number) -> CFrame)
		local start = os.clock()
		while trip == t do
			local a = math.min((os.clock() - start) / time, 1)
			root.CFrame = o * f(a)
			if a >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end
	local run = track("run", 1.3)
	drive(0.5, function(a)
		return CFrame.new(0, y0, -9 + 4.8 * a) * face
	end)
	qaHold(t, "stage")
	if trip ~= t then
		return
	end
	if run then
		run:Stop(0.1)
	end
	track("jump", 1)
	portal.speed = 2.5
	camTo(CFrame.lookAt((o * CFrame.new(-7, 6.5, -13)).Position, (o * CFrame.new(0, 9, 0)).Position), 0.5)
	tween(cam, 0.6, { FieldOfView = t.fov + 18 }, Enum.EasingStyle.Quad)
	-- leap: an arc from z = -4.2 up to the middle of the vortex, leaning forward
	drive(0.5, function(a)
		local z = -4.2 + 4.2 * a
		local y = y0 + 6.2 * math.sin(a * math.pi * 0.62) + 1.2 * a
		return CFrame.new(0, y, z) * face * CFrame.Angles(-0.5 * a, 0, 0)
	end)
	if trip ~= t then
		return
	end
	portal.speed = 6
	portal.glow = 2.5
	portal.burst(30)
	Teleport:FireServer("enter")
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	tween(flash, 0.12, { BackgroundTransparency = 0 }).Completed:Wait()
	if trip ~= t then
		return
	end
	for _, tr in t.tracks do
		tr:Stop(0.2)
	end

	-- 3) behind the white flash, wait until the server has moved the real character
	waitFor(t, function()
		return t.arrived ~= nil
	end, 3)
	if trip ~= t then
		return
	end
	if t.stage then
		t.stage:Destroy()
		t.stage = nil
	end
	restoreAtmosphere(t)
	portal.destroy()
	t.portal = nil
	if not t.arrived then
		endTrip(t) -- the server never confirmed: just give the controls back
		return
	end
	local target = t.arrived :: CFrame

	-- 4) sky drop onto the island: a copy falls, the real character waits hidden at the arrival point
	stopDrop()
	local face = flat(target)
	local d = face.LookVector
	local right = face.RightVector
	local goal = target.Position
	local startPos = goal - d * DROP_BACK + Vector3.new(0, DROP_H, 0)
	local f = Instance.new("Folder")
	f.Name = "TravelSkyDrop"
	dropFolder = f
	local copy = fallCopy(char, CFrame.new(startPos) * face, f)
	local croot = copy and copy:FindFirstChild("HumanoidRootPart") :: BasePart?
	local rig = if copy then rigOf(copy) else {}
	pose(rig, 1.45, 0.5) -- spread eagle
	root.Anchored = true
	char:PivotTo(CFrame.new(goal) * face)
	t.hiddenParts = {}
	for _, x in char:GetDescendants() do
		if x:IsA("BasePart") or x:IsA("Decal") then
			table.insert(t.hiddenParts, x)
		end
	end
	-- a few clouds along the way down
	for i, k in { 0.22, 0.4, 0.55, 0.7 } do
		local side = if i % 2 == 0 then 1 else -1
		local c = startPos:Lerp(goal + Vector3.new(0, OPEN_Y * 0.4, 0), k) + right * side * (10 + i * 4) + d * (i * 3)
		for j = 1, 3 do
			part({
				Name = "Cloud", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic, Color = Color3.new(1, 1, 1),
				Transparency = 0.3, Size = Vector3.one * (12 + j * 4),
				CFrame = CFrame.new(c + right * (j - 2) * 9 + Vector3.new(0, (j % 2) * 3, (j - 2) * 4)), Parent = f,
			})
		end
	end
	-- wind lines rushing up around the copy
	local wind, windCfs = {}, {}
	for i = 1, WIND_N do
		wind[i] = part({
			Name = "Wind", Material = Enum.Material.Neon, Color = if i % 3 == 0 then lighter(color, 0.6) else Color3.new(1, 1, 1),
			Transparency = 0.35, Size = Vector3.new(0.12, 5 + math.random() * 5, 0.12), Parent = f,
		})
	end
	local windA, windR, windO = {}, {}, {}
	for i = 1, WIND_N do
		windA[i], windR[i], windO[i] = math.random() * math.pi * 2, 4 + math.random() * 8, math.random() * 50
	end
	local chuteModel = Instance.new("Model")
	chuteModel.Name = "Parachute"
	local chuteParts, chuteRel, chuteSize = buildChute(color, chuteModel)
	local chuteCfs = table.create(#chuteParts)
	local chuteScale, chuteShown, lastScale = 0, false, -1
	local hinge = Vector3.new(0, 1.6, 0)
	f.Parent = workspace

	local total = FREE_T + GLIDE_T
	local function pathAt(tau: number): (Vector3, number)
		local u = math.clamp(tau / total, 0, 1)
		local h = 1 - (1 - u) ^ 2
		local y, sway = 0, 0
		if tau < FREE_T then
			local a = tau / FREE_T
			y = DROP_H - (DROP_H - OPEN_Y) * (0.35 * a + 0.65 * a * a)
		else
			local a = math.clamp((tau - FREE_T) / GLIDE_T, 0, 1)
			y = OPEN_Y * (1 - a) ^ 1.8 + 2.5 * math.sin(math.min(a / 0.22, 1) * math.pi)
			sway = math.sin(a * math.pi * 2) * 3 * (1 - a)
		end
		local p = startPos:Lerp(goal, h)
		return Vector3.new(p.X, goal.Y + y, p.Z) + right * sway, sway
	end

	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = t.fov + 16
	local tau, landT, done = 0, -1, false
	local camCf: CFrame? = nil
	local function step(dt: number)
		if trip ~= t then
			return
		end
		local held = (qaHeld("fall") and tau > 0.6) or (qaHeld("glide") and tau > FREE_T + 0.7)
		if not held then
			tau += dt
		end
		local pos, sway = pathAt(tau)
		local gliding = tau >= FREE_T
		local g = if gliding then smooth((tau - FREE_T) / 0.35) else 0
		-- body: belly-down and wobbling in free fall, upright under the canopy
		local wob = 1 - g
		local yaw = math.sin(tau * 1.4) * 0.35 * wob
		local roll = math.sin(tau * 2.3) * 0.2 * wob - sway * 0.05
		local pitch = -1.25 * wob - 0.08 * g
		local body = CFrame.new(pos) * face * CFrame.Angles(0, yaw, 0)
		if croot and croot.Parent then
			croot.CFrame = body * CFrame.Angles(pitch, 0, roll)
		end
		-- parachute: opens at FREE_T with a springy pop, folds away on landing
		if gliding and landT < 0 then
			if not chuteShown then
				chuteShown = true
				chuteModel.Parent = f
				pose(rig, 2.7, 0.15) -- arms up holding the lines
			end
			chuteScale = backOut(math.clamp((tau - FREE_T) / 0.4, 0, 1))
		elseif landT >= 0 then
			local a = math.clamp((os.clock() - landT) / 0.35, 0, 1)
			chuteScale = math.max(1 - a * a, 0.01)
		end
		if chuteShown then
			local s = math.max(chuteScale, 0.01)
			if s ~= lastScale then
				lastScale = s
				for _, p in chuteParts do
					p.Size = chuteSize[p] * s
				end
			end
			local frame = CFrame.new(pos) * face * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, -sway * 0.05)
			for i, p in chuteParts do
				local r = chuteRel[p]
				chuteCfs[i] = frame * (CFrame.new(hinge + (r.Position - hinge) * s) * r.Rotation)
			end
			workspace:BulkMoveTo(chuteParts, chuteCfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
		-- wind: fast in free fall, slow and faint under the canopy
		local speed = 150 - 110 * g
		for i, p in wind do
			local y = -25 + ((windO[i] + tau * speed) % 50)
			windCfs[i] = CFrame.new(pos + Vector3.new(math.cos(windA[i]) * windR[i], y, math.sin(windA[i]) * windR[i]))
			p.Transparency = 0.35 + 0.55 * g
		end
		workspace:BulkMoveTo(wind, windCfs, Enum.BulkMoveMode.FireCFrameChanged)
		-- camera above and behind, looking down past the character at the island
		local eye, look
		if not gliding then
			local shake = Vector3.new(math.noise(tau * 8, 1), math.noise(tau * 8, 2), 0) * 0.3
			eye = pos - d * 14 + Vector3.new(0, 13, 0) + shake
			look = pos + d * 6 - Vector3.new(0, 10, 0)
		else
			local a = smooth((tau - FREE_T) / GLIDE_T)
			eye = pos - d * (17 - 5 * a) + Vector3.new(0, 8 - 4 * a, 0)
			look = pos + d * (4 - 4 * a) + Vector3.new(0, -5 + 6.5 * a, 0)
			cam.FieldOfView = t.fov + 16 - 16 * smooth((tau - FREE_T) / 0.8)
		end
		local want = CFrame.lookAt(eye, look)
		camCf = if camCf then camCf:Lerp(want, 1 - math.exp(-dt * 10)) else want
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = camCf :: CFrame
		cam.Focus = CFrame.new(pos)
		-- the real character stays hidden here (the camera scripts may reset the modifier)
		for _, x in t.hiddenParts or {} do
			x.LocalTransparencyModifier = 1
		end
		-- landing
		if tau >= total and landT < 0 then
			landT = os.clock()
			landPoof(goal, color)
			pose(rig, 0.1, 0)
		end
		if landT >= 0 and os.clock() - landT >= LAND_T then
			done = true
		end
	end
	RunService:BindToRenderStep("TravelPortalDrop", Enum.RenderPriority.Camera.Value + 2, step)
	step(0)
	tween(flash, 0.3, { BackgroundTransparency = 1 })
	waitFor(t, function()
		return done
	end, total + LAND_T + 3)
	if trip ~= t then
		return
	end
	-- swap the copy for the real character, standing where it landed
	RunService:UnbindFromRenderStep("TravelPortalDrop")
	for _, x in t.hiddenParts or {} do
		if x.Parent then
			x.LocalTransparencyModifier = 0
		end
	end
	t.hiddenParts = nil
	stopDrop()
	char:PivotTo(CFrame.new(goal) * face)
	endTrip(t)
end

Teleport.OnClientEvent:Connect(function(kind, a, b, c, d)
	if kind == "start" then
		task.spawn(play, a)
	elseif kind == "result" then
		if a == false and trip then
			endTrip(trip) -- the server cancelled the trip: give the controls back
		end
	elseif kind == "fx" then
		local who, cf, biome = b, c, d
		local info = BIOMES[biome] or BIOMES.Lobby
		if who == player then
			if a == "arrive" and trip and trip.onArrive then
				trip.onArrive(cf)
			end
			return
		end
		if typeof(cf) ~= "CFrame" then
			return
		end
		-- other players: the portal on the spot only
		if a == "depart" then
			worldPortalAt(cf, info.color, 0).play(0.5, 0.9)
		elseif a == "arrive" then
			landPoof(cf.Position, info.color)
		end
	end
end)
