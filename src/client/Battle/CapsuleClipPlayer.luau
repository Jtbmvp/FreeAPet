--!strict
-- Plays retained GLB translation/rotation channels on the reviewed logical rig.
-- Transform cannot represent animated scale: disclose dropped channels, never
-- mark FaP_AnimationPlaybackVerified or fabricate AnimationIds.
local Http = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Player = {}
local function sample(channel: any, time: number): { number }
	local times, values = channel.times, channel.values
	local lo, hi = 1, #times
	while lo < hi do
		local middle = math.ceil((lo + hi) / 2)
		if times[middle] <= time then
			lo = middle
		else
			hi = middle - 1
		end
	end
	local nextIndex = math.min(lo + 1, #times)
	local alpha = if channel.interpolation == "STEP" or nextIndex == lo
		then 0
		else math.clamp((time - times[lo]) / (times[nextIndex] - times[lo]), 0, 1)
	local a, b = values[lo], values[nextIndex]
	local sign = 1
	if channel.path == "rotation" and a[1] * b[1] + a[2] * b[2] + a[3] * b[3] + a[4] * b[4] < 0 then
		sign = -1
	end
	local result = {}
	for i = 1, #a do
		result[i] = a[i] + (b[i] * sign - a[i]) * alpha
	end
	return result
end
function Player.Attach(model: Model): any
	local data = model:FindFirstChild("OriginalClipData", true)
	if not data then
		return nil
	end
	local joints, clips = {}, {}
	for _, node in model:GetDescendants() do
		if node:IsA("Motor6D") or node:IsA("Bone") then
			if joints[node.Name] then
				return nil
			end
			joints[node.Name] = {
				node = node,
				rest = node.Transform,
				frame = if node:IsA("Bone") then node.CFrame else node.C0,
			}
		end
	end
	for _, value in data:GetChildren() do
		if value:IsA("StringValue") then
			local ok, clip = pcall(Http.JSONDecode, Http, value.Value)
			if ok and type(clip) == "table" and type(clip.channels) == "table" then
				local valid, duration = true, 0
				for _, channel in clip.channels do
					if
						not joints[channel.target]
						or type(channel.times) ~= "table"
						or #channel.times == 0
						or #channel.times ~= #channel.values
						or (channel.interpolation ~= "LINEAR" and channel.interpolation ~= "STEP")
					then
						valid = false
						break
					end
					duration = math.max(duration, channel.times[#channel.times])
				end
				if valid and duration > 0 then
					clip.duration = duration
					clips[value.Name] = clip
				end
			end
		end
	end
	local connection: RBXScriptConnection? = nil
	local selected: any = nil
	local started = 0
	local api = {}
	local function stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end
	local function update()
		if not model.Parent or not selected then
			stop()
			return
		end
		local elapsed = math.min(os.clock() - started, selected.duration)
		local poses = {}
		for _, channel in selected.channels do
			local pose = poses[channel.target] or {}
			poses[channel.target] = pose
			if channel.path == "translation" then
				pose.translation = sample(channel, elapsed)
			elseif channel.path == "rotation" then
				pose.rotation = sample(channel, elapsed)
			elseif channel.path == "scale" then
				model:SetAttribute("CapsuleScaleChannelsDropped", true)
			end
		end
		for name, pose in poses do
			local joint = joints[name]
			local position = joint.frame.Position
			if pose.translation then
				local t = pose.translation
				position = Vector3.new(t[1], t[2], t[3]) * model:GetScale()
			end
			local rotation = joint.frame.Rotation
			if pose.rotation then
				local q = pose.rotation
				rotation = CFrame.new(0, 0, 0, q[1], q[2], q[3], q[4])
			end
			joint.node.Transform = joint.frame:Inverse() * (CFrame.new(position) * rotation)
		end
		if elapsed >= selected.duration then
			stop()
		end
	end
	function api.Play(name: string): boolean
		local clip = clips[name]
		if not clip then
			return false
		end
		stop()
		selected = clip
		started = os.clock()
		update()
		connection = RunService.PreRender:Connect(update)
		return true
	end
	function api.Duration(name: string): number?
		return clips[name] and clips[name].duration
	end
	function api.Destroy()
		stop()
		selected = nil
		for _, joint in joints do
			joint.node.Transform = joint.rest
		end
	end
	return api
end
return Player
