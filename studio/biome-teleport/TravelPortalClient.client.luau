-- TravelPortalClient (StarterPlayerScripts): the portal cinematic for the Travel panel.
-- The server (ServerScriptService.BiomeTeleportServer) validates the trip and sends ("start", biome).
-- Then, on this client only:
--   1. a quick flash, and the character is moved to a hidden stage under the map (night void with stars)
--      where a portal (ReplicatedStorage.TravelPortal, modelled in Blender) opens in the destination colour;
--   2. cinematic camera: the character runs and leaps into the vortex, the vortex speeds up, white flash;
--   3. fall tunnel: a client-only copy of the character tumbles down a spiral tunnel in the destination
--      colour (rings, speed lines, sparks; camera below it), built next to the hidden stage;
--      meanwhile we send ("enter") and the server does the real move to TP_* / the base spawn;
--   4. on ("fx", "arrive") a small portal opens behind the character at the destination, the character
--      walks out, the camera eases back to normal, the controls come back and the portal closes.
-- Other players only see the portal on the spot ("fx" depart/arrive), never the stage or the tunnel.
-- Safety: everything is undone after SAFETY seconds whatever happens, and on death/respawn.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Teleport = ReplicatedStorage:WaitForChild("BiomeTeleportRemotes"):WaitForChild("Teleport") :: RemoteEvent
local TEMPLATE = ReplicatedStorage:WaitForChild("TravelPortal") :: Model

local SAFETY = 8
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
-- Fall tunnel: a client-only copy of the character falls down a spiral tunnel in the
-- destination colour (built next to the hidden stage), while the server moves the real one.
-- The copy stays put and the tunnel rushes upward past it: rings, speed lines, sparks.
--------------------------------------------------------------------------------------------
local RING_N, RING_SEG, RING_R, RING_GAP, RING_SPEED = 16, 10, 13, 7, 62
local LINE_N, LINE_SPEED = 30, 150
local TUBE_TOP, TUBE_LEN = 44, 16 * 7

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
	copy.Name = "TravelFallCopy"
	copy:PivotTo(at)
	copy.Parent = parent
	if not hum:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = hum
	end
	return copy, hum
end

local fallConn: RBXScriptConnection? = nil
local fallFolder: Folder? = nil
local function stopTunnel()
	if fallConn then
		fallConn:Disconnect()
		fallConn = nil
	end
	if fallFolder then
		fallFolder:Destroy()
		fallFolder = nil
	end
end

-- o: stage origin; the tunnel axis sits 320 studs to the side of the stage (same private slot)
local function startTunnel(color: Color3, char: Model, o: CFrame)
	stopTunnel()
	local axis = o * CFrame.new(0, 0, 320)
	local f = Instance.new("Folder")
	f.Name = "TravelFallTunnel"
	fallFolder = f
	-- outer tube (dark, so the bright rings and the character stand out)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		part({
			Name = "Wall",
			Material = Enum.Material.Neon,
			Color = darker(color, 0.72),
			Size = Vector3.new(2 * (RING_R + 3) * math.tan(math.pi / 16) + 0.4, TUBE_LEN + 20, 1),
			CFrame = axis * CFrame.new(0, TUBE_TOP - TUBE_LEN / 2, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, RING_R + 3),
			Parent = f,
		})
	end
	-- a lid on top (otherwise the sky shows through) and the light at the bottom: where we are going
	part({
		Name = "Lid",
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = darker(color, 0.82),
		Size = Vector3.new(1, 2 * RING_R + 10, 2 * RING_R + 10),
		CFrame = axis * CFrame.new(0, TUBE_TOP + 8, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = f,
	})
	part({
		Name = "Glow",
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = lighter(color, 0.55),
		Size = Vector3.new(1, 2 * RING_R + 6, 2 * RING_R + 6),
		CFrame = axis * CFrame.new(0, TUBE_TOP - TUBE_LEN - 6, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Parent = f,
	})
	-- spiral rings: each one a broken circle of glowing segments
	local moving: { BasePart } = {}
	local segLen = 2 * math.pi * RING_R / RING_SEG * 0.62
	for i = 1, RING_N do
		local c = if i % 2 == 0 then lighter(color, 0.2) else lighter(color, 0.75)
		for _ = 1, RING_SEG do
			table.insert(moving, part({
				Name = "Ring",
				Material = Enum.Material.Neon,
				Color = c,
				Size = Vector3.new(segLen, 0.7, 1.1),
				Parent = f,
			}))
		end
	end
	local lines: { { p: BasePart, a: number, r: number, off: number } } = {}
	for i = 1, LINE_N do
		local p = part({
			Name = "SpeedLine",
			Material = Enum.Material.Neon,
			Color = if i % 3 == 0 then lighter(color, 0.6) else Color3.new(1, 1, 1),
			Transparency = 0.25,
			Size = Vector3.new(0.18, 7 + math.random() * 6, 0.18),
			Parent = f,
		})
		table.insert(lines, { p = p, a = math.random() * math.pi * 2, r = 5 + math.random() * 7, off = math.random() * TUBE_LEN })
	end
	-- sparks rushing up from the bottom
	local sparkBase = part({
		Name = "Sparks",
		Transparency = 1,
		Size = Vector3.new(2 * RING_R, 1, 2 * RING_R),
		CFrame = axis * CFrame.new(0, -30, 0),
		Parent = f,
	})
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1), lighter(color, 0.4))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(0.6, 1)
	pe.Speed = NumberRange.new(55, 90)
	pe.SpreadAngle = Vector2.new(8, 8)
	pe.Rate = 110
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Parent = sparkBase
	-- a light on the character (Neon doesn't light anything up)
	local center = axis
	local lamp = part({ Name = "Lamp", Transparency = 1, Size = Vector3.one, CFrame = center * CFrame.new(0, -6, -5), Parent = f })
	local light = Instance.new("PointLight")
	light.Color = lighter(color, 0.6)
	light.Range = 28
	light.Brightness = 6
	light.Parent = lamp
	f.Parent = workspace

	local copy, chum = fallCopy(char, center, f)
	local croot = copy and copy:FindFirstChild("HumanoidRootPart") :: BasePart?
	if chum then
		local animate = char:FindFirstChild("Animate")
		local folder = animate and animate:FindFirstChild("fall")
		local anim = folder and folder:FindFirstChildOfClass("Animation")
		local animator = chum:FindFirstChildOfClass("Animator")
		if anim and animator then
			local ok, tr = pcall(animator.LoadAnimation, animator, anim)
			if ok and tr then
				tr.Priority = Enum.AnimationPriority.Action
				tr.Looped = true
				tr:Play(0.05, 1, 1.4)
			end
		end
	end

	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local t = 0
	local cfs = table.create(#moving)
	local lineParts = table.create(LINE_N)
	for i, l in lines do
		lineParts[i] = l.p
	end
	local lineCfs = table.create(LINE_N)
	fallConn = RunService.RenderStepped:Connect(function(dt)
		t += dt
		-- rings rise past the character; each ring is turned a bit more than the last: a spiral
		local k = 0
		for i = 1, RING_N do
			local y = TUBE_TOP - ((i * RING_GAP - t * RING_SPEED) % TUBE_LEN)
			local ring = axis * CFrame.new(0, y, 0) * CFrame.Angles(0, i * 0.42 + t * 1.1, 0)
			for s = 1, RING_SEG do
				k += 1
				cfs[k] = ring * CFrame.Angles(0, s / RING_SEG * math.pi * 2, 0) * CFrame.new(0, 0, RING_R)
			end
		end
		workspace:BulkMoveTo(moving, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		for i, l in lines do
			local y = TUBE_TOP - ((l.off - t * LINE_SPEED) % TUBE_LEN)
			lineCfs[i] = axis * CFrame.new(math.cos(l.a) * l.r, y, math.sin(l.a) * l.r)
		end
		workspace:BulkMoveTo(lineParts, lineCfs, Enum.BulkMoveMode.FireCFrameChanged)
		-- the character tumbles slowly: spins, sways and wobbles
		if croot and croot.Parent then
			croot.CFrame = center
				* CFrame.new(math.sin(t * 2.3) * 0.8, math.sin(t * 3.1) * 0.4, math.cos(t * 1.9) * 0.6)
				* CFrame.Angles(math.sin(t * 2.6) * 0.22, t * 1.7, math.cos(t * 2.1) * 0.18)
		end
		-- camera below and in front, looking up at the character, with a light shake
		local shake = Vector3.new(math.noise(t * 9, 1) * 0.25, math.noise(t * 9, 2) * 0.25, 0)
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt((center * CFrame.new(0, -7.5, -9)).Position + shake, (center * CFrame.new(0, 0.6, 0)).Position)
		-- the focus drives lighting/rendering detail: it must be here, not at the real (already moved) character
		cam.Focus = center
	end)
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

-- QA only: with the player attribute TravelPortalHold = "stage", "tunnel" or "arrive" (set from the command bar in a
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
	stopTunnel()
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

	-- 3) tunnel
	startTunnel(color, char, o)
	cam.FieldOfView = t.fov + 12
	tween(flash, 0.3, { BackgroundTransparency = 1 })
	local tunnelStart = os.clock()
	waitFor(t, function()
		return t.arrived ~= nil and os.clock() - tunnelStart > 1.6
	end, 5)
	qaHold(t, "tunnel")
	if trip ~= t then
		return
	end
	-- the stage stays (hidden behind the tunnel) until the server has moved us, so nobody falls
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

	-- 4) arrival: step out of a small portal behind the character
	flash.BackgroundColor3 = lighter(color, 0.85)
	tween(flash, 0.15, { BackgroundTransparency = 0 }).Completed:Wait()
	if trip ~= t then
		return
	end
	stopTunnel()
	cam.FieldOfView = t.fov
	local base = CFrame.new(target.Position) * flat(target)
	local exitPortal = worldPortalAt(target, color, 2.6)
	t.portal = exitPortal
	exitPortal.scale = 0.5
	exitPortal.speed = 2
	root.Anchored = false
	char:PivotTo(base * CFrame.new(0, 0, 1.2))
	hum:MoveTo((base * CFrame.new(0, 0, -5)).Position)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = CFrame.lookAt((base * CFrame.new(4.5, 2.2, -12)).Position, (base * CFrame.new(0, 1, 1)).Position)
	exitPortal.burst(26)
	tween(flash, 0.35, { BackgroundTransparency = 1 })
	qaHold(t, "arrive")
	task.wait(0.6)
	if trip ~= t then
		return
	end
	-- ease back to a normal follow camera, then hand control back
	local behind = root.CFrame * CFrame.new(0, 3.5, 11)
	camTo(CFrame.lookAt(behind.Position, root.Position + Vector3.new(0, 1.5, 0)), 0.45).Completed:Wait()
	if trip ~= t then
		return
	end
	t.portal = nil
	exitPortal.speed = 3
	task.spawn(function()
		exitPortal.scaleTo(0.01, 0.4, true)
		exitPortal.destroy()
	end)
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
			worldPortalAt(cf, info.color, 2.6).play(0.5, 1.1)
		end
	end
end)
