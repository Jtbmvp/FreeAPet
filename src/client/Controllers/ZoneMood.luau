--!strict
-- Client-only V3 lighting and bounded environmental VFX. Reads Terra's applied
-- profiles; never edits geometry, textures, gameplay, server lighting or editor state.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Input = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ZoneMood = {}
local ZONES = { Base = "safe", Forest = "floresta", Desert = "deserto" }
local FIELDS = {
	Lighting = {
		"ClockTime",
		"ColorShift_Bottom",
		"EnvironmentDiffuseScale",
		"EnvironmentSpecularScale",
		"GlobalShadows",
		"GeographicLatitude",
		"Ambient",
		"OutdoorAmbient",
		"ShadowSoftness",
		"Brightness",
		"ColorShift_Top",
		"ExposureCompensation",
	},
	Atmosphere = { "Density", "Haze", "Color", "Decay", "Glare", "Offset" },
	Bloom = { "Threshold", "Intensity", "Size" },
	ColorCorrection = { "TintColor", "Brightness", "Saturation", "Contrast" },
	SunRays = { "Intensity", "Spread", "Enabled" },
	Sky = { "CelestialBodiesShown", "SunAngularSize", "StarCount", "MoonAngularSize" },
}
local function readJson(parent: Instance, name: string): any
	local value = parent:FindFirstChild(name)
	if not value or not value:IsA("StringValue") then
		return nil
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, value.Value)
	return if ok and type(decoded) == "table" then decoded else nil
end
local function convert(value: any): any
	if type(value) == "string" and value:match("^#%x%x%x%x%x%x$") then
		return Color3.fromRGB(
			tonumber(value:sub(2, 3), 16) :: number,
			tonumber(value:sub(4, 5), 16) :: number,
			tonumber(value:sub(6, 7), 16) :: number
		)
	end
	return value
end
local function position(item: Instance): Vector3?
	local parent: Instance? = item.Parent
	while parent do
		if parent:IsA("Attachment") then
			return parent.WorldPosition
		end
		if parent:IsA("BasePart") then
			return parent.Position
		end
		parent = parent.Parent
	end
	return nil
end
local function transparent(keys: any): NumberSequence?
	if type(keys) ~= "table" then
		return nil
	end
	local points = {}
	for _, key in keys do
		table.insert(points, NumberSequenceKeypoint.new(key.t, key.v, key.e or 0))
	end
	return NumberSequence.new(points)
end
function ZoneMood.Start()
	local player = Players.LocalPlayer
	local map = Workspace:WaitForChild("Map", 15)
	local fx = map and map:WaitForChild("FX", 15)
	local data = fx and fx:WaitForChild("V3Presentation", 5)
	if not map or not fx or not data then
		warn("[ZoneMood] V3 presentation unavailable")
		return
	end
	local profiles, mobileOverrides, vfxProfiles =
		readJson(data, "LightingProfiles"), readJson(data, "MobileOverrides"), readJson(data, "VFXProfiles")
	if not profiles or not mobileOverrides or not vfxProfiles then
		warn("[ZoneMood] Invalid V3 presentation profiles")
		return
	end
	local byEffect = {}
	for _, profile in vfxProfiles do
		byEffect[profile.id] = profile
	end
	local targets: { [string]: Instance? } = {
		Lighting = Lighting,
		Atmosphere = Lighting:FindFirstChild("FreeAPetAtmosphere"),
		Bloom = Lighting:FindFirstChild("FreeAPetBloom"),
		ColorCorrection = Lighting:FindFirstChild("FreeAPetColor"),
		SunRays = Lighting:FindFirstChild("FreeAPetSunRays"),
		Sky = Lighting:FindFirstChildOfClass("Sky"),
	}
	local tweens: { Tween } = {}
	local mobile = false
	local function lowProfile(): boolean
		local forced = player:GetAttribute("V3QualityProfile")
		if forced == "Mobile" then
			return true
		elseif forced == "Desktop" then
			return false
		end
		local level = UserSettings():GetService("UserGameSettings").SavedQualityLevel
		return Input.TouchEnabled or (level ~= Enum.SavedQualitySetting.Automatic and level.Value <= 3)
	end
	local function applyProfile()
		mobile = lowProfile()
		for _, tween in tweens do
			tween:Cancel()
		end
		table.clear(tweens)
		local zone = player:GetAttribute("Zone")
		local name = if typeof(zone) == "string" then ZONES[zone] or "safe" else "safe"
		local profile = profiles[name] or profiles.safe
		for group, fields in FIELDS do
			local target = targets[group]
			if not target then
				continue
			end
			local values = profile[group] or {}
			local overrides = if mobile then mobileOverrides[group] or {} else {}
			local goals = {}
			for _, field in fields do
				local value = if overrides[field] ~= nil then overrides[field] else values[field]
				if field == "Enabled" and value == nil then
					value = true
				end
				if value ~= nil then
					value = convert(value)
					if type(value) == "boolean" then
						(target :: any)[field] = value
					else
						goals[field] = value
					end
				end
			end
			if next(goals) then
				local tween = TweenService:Create(
					target,
					TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					goals
				)
				table.insert(tweens, tween)
				tween:Play()
			end
		end
		player:SetAttribute("V3PresentationProfile", name)
		player:SetAttribute("V3MobileProfile", mobile)
	end
	local emitters: { ParticleEmitter } = {}
	local lamps: { PointLight } = {}
	local beams: { Beam } = {}
	local known: { [Instance]: boolean } = {}
	local function collect(item: Instance)
		if known[item] then
			return
		end
		if item:IsA("ParticleEmitter") and item:GetAttribute("FaP_EffectId") then
			table.insert(emitters, item)
		elseif item:IsA("PointLight") and item.Name == "V3WarmLamp" then
			table.insert(lamps, item)
		elseif item:IsA("Beam") and item.Name == "FountainBeacon" then
			table.insert(beams, item)
		else
			return
		end
		known[item] = true
	end
	for _, item in map:GetDescendants() do
		collect(item)
	end
	local connections: { RBXScriptConnection } = {}
	table.insert(connections, map.DescendantAdded:Connect(collect))
	table.insert(
		connections,
		map.DescendantRemoving:Connect(function(item)
			known[item] = nil
			for _, list in { emitters, lamps, beams } do
				local i = table.find(list, item :: any)
				if i then
					table.remove(list, i)
				end
			end
		end)
	)
	local previousMobile: boolean? = nil
	local function update()
		local nextMobile = lowProfile()
		if nextMobile ~= mobile then
			applyProfile()
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local origin = root and root.Position
		local now = Workspace:GetServerTimeNow()
		for _, emitter in emitters do
			local id = emitter:GetAttribute("FaP_EffectId")
			local definition = byEffect[id]
			local overrides = if definition
				then (if mobile then definition.mobileOverrides else definition.desktopOverrides)
				else nil
			local rate = emitter:GetAttribute(if mobile then "FaP_MobileRate" else "FaP_DesktopRate")
			if typeof(rate) == "number" then
				emitter.Rate = rate
			end
			if previousMobile ~= mobile and overrides then
				if overrides.Transparency then
					local sequence = transparent(overrides.Transparency)
					if sequence then
						emitter.Transparency = sequence
					end
				end
				if overrides.Lifetime then
					emitter.Lifetime = NumberRange.new(overrides.Lifetime[1], overrides.Lifetime[2])
				end
			end
			local point = position(emitter)
			local nearby = origin ~= nil
				and point ~= nil
				and ((origin :: Vector3) - (point :: Vector3)).Magnitude <= 150
			local enabled = nearby and emitter.Rate > 0
			if id == "desert_dust" then
				local timing = definition and definition.timing
				enabled = enabled
					and now % (if timing then timing.periodSeconds else 18)
						< (if timing then timing.onSeconds else 6)
			elseif id == "clearing_glow" then
				-- Only the actual local battle near this clearing, never a menu preview.
				enabled = enabled
					and player:GetAttribute("InBattle") == true
					and origin ~= nil
					and point ~= nil
					and ((origin :: Vector3) - (point :: Vector3)).Magnitude <= 45
			end
			emitter.Enabled = enabled
		end
		previousMobile = mobile
		local nearest = {}
		for _, light in lamps do
			local point = position(light)
			local distance = if origin and point then (origin - point).Magnitude else math.huge
			if distance <= 150 then
				table.insert(nearest, { light = light, distance = distance })
			end
			light.Enabled = false
			light.Shadows = false
		end
		table.sort(nearest, function(a, b)
			return a.distance < b.distance
		end)
		for i = 1, math.min(4, #nearest) do
			nearest[i].light.Enabled = true
		end
		local alpha = 0.60 + 0.08 * (0.5 - 0.5 * math.cos((now % 6) / 6 * math.pi * 2))
		for _, beam in beams do
			local point = position(beam)
			beam.Enabled = origin ~= nil
				and point ~= nil
				and ((origin :: Vector3) - (point :: Vector3)).Magnitude <= 150
			beam.Transparency =
				NumberSequence.new({ NumberSequenceKeypoint.new(0, alpha), NumberSequenceKeypoint.new(1, 1) })
		end
	end
	table.insert(connections, player:GetAttributeChangedSignal("Zone"):Connect(applyProfile))
	table.insert(connections, player:GetAttributeChangedSignal("V3QualityProfile"):Connect(applyProfile))
	table.insert(connections, player:GetAttributeChangedSignal("InBattle"):Connect(update))
	applyProfile()
	update()
	player:SetAttribute("V3PresentationReady", true)
	-- 4Hz bounded to the 19 emitters, 26 lamps and one beam; no map scan/frame.
	while map.Parent and player.Parent do
		task.wait(0.25)
		update()
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	for _, tween in tweens do
		tween:Cancel()
	end
end
return ZoneMood
