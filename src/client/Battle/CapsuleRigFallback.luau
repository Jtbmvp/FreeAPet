--!strict
-- Original model clone only. Fallback poses are labelled procedural, not GLB clips.
-- Coder supplies the reviewed original template and real animation adapter.
local RunService = game:GetService("RunService")
local Adapter = {}
Adapter.__index = Adapter

function Adapter.new(template: Model?, parent: Instance, playClip: ((Model, string) -> boolean)?)
	assert(RunService:IsClient(), "capsule presentation is client-only")
	if not template then
		return nil, "Original capsule template unavailable; no static substitute was created"
	end
	local clone = template:Clone()
	if not clone then
		return nil, "Original capsule is not cloneable"
	end
	-- Before naming, transforming or parenting: avoid package edit prompts.
	for _, item in clone:GetDescendants() do
		if item:IsA("PackageLink") or item:IsA("LuaSourceContainer") then
			item:Destroy()
		end
	end
	clone.Name = "LocalOriginalCapsule"
	local joints: { [string]: any } = {}
	for _, item in clone:GetDescendants() do
		if item:IsA("Bone") or item:IsA("Motor6D") then
			joints[item.Name] = { node = item, rest = item.Transform }
		end
		if item:IsA("BasePart") then
			item.CanCollide, item.CanQuery, item.CanTouch = false, false, false
		end
	end
	if clone.PrimaryPart then
		clone.PrimaryPart.Anchored = true
	end
	clone.Parent = parent
	return setmetatable(
		{ model = clone, joints = joints, playClip = playClip, active = true, epoch = 0 },
		Adapter
	),
		nil
end

function Adapter.Play(self: any, name: string): (boolean, string)
	if not self.active then
		return false, "destroyed"
	end
	self.epoch += 1
	if self.playClip and self.playClip(self.model, name) then
		return true, "original clip"
	end
	local lid, left, right = self.joints.jnt_lid, self.joints.jnt_latch_L, self.joints.jnt_latch_R
	if name == "Open" or name == "Close" or name == "Lock" then
		if not lid then
			return false, "original rig binding missing; root motion only available"
		end
		local opened = name == "Open"
		lid.node.Transform = lid.rest * CFrame.Angles(if opened then math.rad(-55) else 0, 0, 0)
		if left then
			left.node.Transform = left.rest * CFrame.Angles(0, 0, if opened then math.rad(-22) else 0)
		end
		if right then
			right.node.Transform = right.rest * CFrame.Angles(0, 0, if opened then math.rad(22) else 0)
		end
		return true, "procedural fallback pose"
	end
	return false, "use AnimateRoot for Throw/Shake fallback; no source clip was fabricated"
end

-- Caller supplies the whole local flight/rocking curve; no duplicate GLB root motion.
function Adapter.AnimateRoot(
	self: any,
	seconds: number,
	curve: (number) -> CFrame,
	cancelled: (() -> boolean)?
)
	self.epoch += 1
	local epoch, started = self.epoch, os.clock()
	while self.active and epoch == self.epoch do
		if cancelled and cancelled() then
			return false
		end
		local t = math.min((os.clock() - started) / math.max(seconds, 0.01), 1)
		self.model:PivotTo(curve(t))
		if t >= 1 then
			return true
		end
		RunService.PreRender:Wait()
	end
	return false
end

function Adapter.Destroy(self: any)
	if not self.active then
		return
	end
	self.active = false
	self.epoch += 1
	self.model:Destroy()
end

return Adapter
