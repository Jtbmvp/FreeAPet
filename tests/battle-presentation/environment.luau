--!nocheck
RaycastParams = {
	new = function()
		return {}
	end,
}
TweenInfo = {
	new = function(...)
		return { ... }
	end,
}
local checks = 0
local function check(value, why)
	checks += 1
	assert(value, why or `check {checks}`)
end
local function near(a, b, why)
	check(math.abs(a - b) < 1e-5, why or `{a} ~= {b}`)
end
local function event()
	local handlers = {}
	return {
		Connect = function(_, fn)
			local h = { active = true, fn = fn }
			table.insert(handlers, h)
			return {
				Disconnect = function()
					h.active = false
				end,
			}
		end,
		Fire = function(_, ...)
			for _, h in table.clone(handlers) do
				if h.active then
					h.fn(...)
				end
			end
		end,
		Count = function()
			local n = 0
			for _, h in handlers do
				if h.active then
					n += 1
				end
			end
			return n
		end,
	}
end
local vector = {}
vector.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2)
	elseif k == "Unit" then
		return v / v.Magnitude
	end
	return vector[k]
end
function vector:Dot(b)
	return self.X * b.X + self.Y * b.Y + self.Z * b.Z
end
function vector:Cross(b)
	return Vector3.new(self.Y * b.Z - self.Z * b.Y, self.Z * b.X - self.X * b.Z, self.X * b.Y - self.Y * b.X)
end
function vector:Lerp(b, a)
	return self + (b - self) * a
end
vector.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
vector.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
vector.__unm = function(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
vector.__mul = function(a, b)
	if type(a) == "number" then
		return b * a
	end
	if type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
vector.__div = function(a, b)
	return a * (1 / b)
end
Vector3.new = function(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z }, vector)
end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
Vector3.xAxis = Vector3.new(1, 0, 0)
Vector3.yAxis = Vector3.new(0, 1, 0)
Vector3.zAxis = Vector3.new(0, 0, 1)
local frame
local cf = {}
cf.__index = function(f, key)
	if key == "Rotation" then
		return frame(Vector3.zero, f.RightVector, f.UpVector, -f.LookVector)
	end
	return cf[key]
end
frame = function(p, r, u, b)
	return setmetatable({ Position = p, RightVector = r, UpVector = u, LookVector = -b, Rotation = nil }, cf)
end
function cf:VectorToWorldSpace(v)
	return self.RightVector * v.X + self.UpVector * v.Y - self.LookVector * v.Z
end
function cf:PointToWorldSpace(v)
	return self.Position + self:VectorToWorldSpace(v)
end
function cf:PointToObjectSpace(v)
	local d = v - self.Position
	return Vector3.new(d:Dot(self.RightVector), d:Dot(self.UpVector), -d:Dot(self.LookVector))
end
function cf:Inverse()
	local r, u, b = self.RightVector, self.UpVector, -self.LookVector
	local inv = frame(
		Vector3.zero,
		Vector3.new(r.X, u.X, b.X),
		Vector3.new(r.Y, u.Y, b.Y),
		Vector3.new(r.Z, u.Z, b.Z)
	)
	inv.Position = inv:VectorToWorldSpace(-self.Position)
	return inv
end
function cf:ToObjectSpace(other)
	return self:Inverse() * other
end
function cf:Lerp(other, a)
	return frame(self.Position:Lerp(other.Position, a), other.RightVector, other.UpVector, -other.LookVector)
end
cf.__mul = function(a, b)
	if getmetatable(b) == vector then
		return a:PointToWorldSpace(b)
	end
	return frame(
		a:PointToWorldSpace(b.Position),
		a:VectorToWorldSpace(b.RightVector),
		a:VectorToWorldSpace(b.UpVector),
		a:VectorToWorldSpace(-b.LookVector)
	)
end
CFrame = {
	new = function(x, y, z, ...)
		local p = if type(x) == "table" then x else Vector3.new(x or 0, y or 0, z or 0)
		return frame(p, Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
	end,
	fromMatrix = function(p, r, u)
		return frame(p, r, u, r:Cross(u))
	end,
	lookAt = function(eye, focus)
		local back = (eye - focus).Unit
		local right = Vector3.yAxis:Cross(back).Unit
		return frame(eye, right, back:Cross(right), back)
	end,
	Angles = function()
		return frame(Vector3.zero, Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
	end,
}
CFrame.identity = CFrame.new()
local props = {}
local methods = {}
local objectMeta = {
	__index = function(o, k)
		local d = props[o]
		if d[k] ~= nil then
			return d[k]
		end
		if k == "Position" and d.CFrame then
			return d.CFrame.Position
		end
		return methods[k]
	end,
	__newindex = function(o, k, v)
		local d = props[o]
		if k == "Parent" then
			local previous = d.Parent
			if previous and props[previous] then
				local list = props[previous].children
				local i = table.find(list, o)
				if i then
					table.remove(list, i)
				end
			end
			if v and props[v] then
				table.insert(props[v].children, o)
			end
		end
		d[k] = v
	end,
}
local created = 0
Instance = {
	new = function(class)
		local o = setmetatable({}, objectMeta)
		props[o] = {
			ClassName = class,
			Name = class,
			children = {},
			attrs = {},
			signals = {},
			Destroying = event(),
			CFrame = CFrame.identity,
			Size = Vector3.one,
		}
		created += 1
		return o
	end,
}
function methods:IsA(class)
	return class == self.ClassName
		or (class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart"))
end
function methods:GetChildren()
	return table.clone(props[self].children)
end
function methods:GetDescendants()
	local out = {}
	for _, c in self:GetChildren() do
		table.insert(out, c)
		for _, d in c:GetDescendants() do
			table.insert(out, d)
		end
	end
	return out
end
function methods:FindFirstChild(name)
	for _, c in self:GetChildren() do
		if c.Name == name then
			return c
		end
	end
	return nil
end
function methods:GetAttribute(k)
	return props[self].attrs[k]
end
function methods:SetAttribute(k, v)
	props[self].attrs[k] = v
end
function methods:Destroy()
	if props[self].destroyed then
		return
	end
	props[self].destroyed = true
	self.Destroying:Fire()
	for _, c in self:GetChildren() do
		c:Destroy()
	end
	self.Parent = nil
end
function methods:Clear()
	self.cleared = (self.cleared or 0) + 1
end
function methods:Emit(n)
	self.emitted = (self.emitted or 0) + n
end
function methods:GetPivot()
	return props[self].pivot or self.CFrame
end
function methods:GetBoundingBox()
	return self:GetPivot(), self.Size
end
function methods:GetExtentsSize()
	return self.Size
end
function methods:GetScale()
	return self.scale or 1
end
function methods:Clone()
	local mapping = {}
	local function clone(node)
		local copy = Instance.new(node.ClassName)
		mapping[node] = copy
		for key, value in props[node] do
			if
				key ~= "children"
				and key ~= "signals"
				and key ~= "Parent"
				and key ~= "Destroying"
				and key ~= "destroyed"
			then
				copy[key] = if key == "attrs" then table.clone(value) else value
			end
		end
		for _, child in node:GetChildren() do
			clone(child).Parent = copy
		end
		return copy
	end
	local result = clone(self)
	for original, copy in mapping do
		if original.PrimaryPart then
			copy.PrimaryPart = mapping[original.PrimaryPart]
		end
	end
	return result
end
function methods:PivotTo(at)
	props[self].pivot = at
end
local function model(size, at)
	local m = Instance.new("Model")
	m.Size = size
	m.Parent = Instance.new("Folder")
	m:PivotTo(CFrame.new(at))
	local p = Instance.new("Part")
	p.Parent = m
	m.PrimaryPart = p
	return m
end
local function sequence(...)
	return { ... }
end
NumberSequence = { new = sequence }
NumberSequenceKeypoint = { new = sequence }
NumberRange = { new = sequence }
ColorSequence = { new = sequence }
UDim2 = { fromScale = sequence }
Color3.fromHex = function()
	return {}
end
local render = event()
local onAdvance = nil
local function advance(seconds)
	clock += seconds
	if onAdvance then
		onAdvance()
	end
	render:Fire()
end
function render:Wait()
	advance(0.05)
end
task.wait = function(seconds)
	advance(seconds or 0.05)
	return seconds or 0.05
end
services.RunService.PreRender = render
services.RunService.IsClient = function()
	return true
end
services.UserInputService = { TouchEnabled = false, InputBegan = event() }
services.TweenService = {
	GetValue = function(_, alpha)
		return alpha
	end,
}
local cameraChanged = event()
local world = Instance.new("Folder")
function world:FindFirstChild()
	return nil
end
function world:GetPropertyChangedSignal()
	return cameraChanged
end
world.Terrain = setmetatable({}, {
	__index = function(_, key)
		if key == "Size" then
			error("Terrain.Size must not be read")
		end
	end,
})
world.Raycast = function()
	return nil
end
local function makeCamera(fov)
	local c = Instance.new("Camera")
	c.CameraType = "Custom"
	c.CameraSubject = Instance.new("Humanoid")
	c.CameraSubject.Parent = world
	c.FieldOfView = fov
	c.Focus = CFrame.new(1, 2, 3)
	c.CFrame = CFrame.new(0, 5, 20)
	c.ViewportSize = Vector2.new(1280, 720)
	return c
end
world.CurrentCamera = makeCamera(70)
services.Workspace = world
Players.LocalPlayer = player(701)
Players.LocalPlayer.Character = Instance.new("Model")
local characterRoot = Instance.new("Part")
characterRoot.Name = "HumanoidRootPart"
characterRoot.Parent = Players.LocalPlayer.Character
local attrs = Players.LocalPlayer.attrs
local clips = 0
mocks["Client.Controllers.PetAnimator"] = {
	PlayOnce = function(_, name)
		clips += 1
		return 1, { impact = 0.4 }
	end,
	Freeze = function() end,
}
local legacy = {}
local originalNode = node
node = function(path)
	local n = originalNode(path)
	if path == "Client.Battle.Fx" then
		local moves = originalNode(path .. ".Moves")
		function moves:GetChildren()
			local mod = originalNode(self.path .. ".Unknown")
			function mod:IsA(c)
				return c == "ModuleScript"
			end
			return { mod }
		end
		rawset(n, "Moves", moves)
	end
	return n
end
mocks["Client.Battle.Fx.Moves.Unknown"] = {
	Unknown = function(ctx)
		table.insert(legacy, "old")
		ctx.impact()
		ctx.impact()
	end,
}
local oldImpact, oldFlash, oldNumbers = 0, 0, 0
local Common = {
	Impact = function()
		oldImpact += 1
	end,
	HitFlash = function()
		oldFlash += 1
	end,
	DamageNumber = function()
		oldNumbers += 1
	end,
}
Common.DefaultAttack = function(ctx)
	table.insert(legacy, "fallback")
	ctx.impact()
	ctx.impact()
end
local PetAnimator = mocks["Client.Controllers.PetAnimator"]
local BattleCamera = load("Client.Battle.BattleCamera")
local Format = { Short = tostring }
local UITheme = {
	Label = function()
		return Instance.new("TextLabel")
	end,
}
local RunService = services.RunService
local screenRoot = Instance.new("ScreenGui")
screenRoot.Parent = world
local function screen()
	return screenRoot
end
local HITSTOP = { normal = 0.06, super = 0.1 }
-- COMMON_HIT_SECTION
Common.ClearVisuals = Common.ClearHitFeedback
mocks["Client.Battle.Fx.Common"] = Common
