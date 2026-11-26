--!strict
-- IceAmbience (Astra/MIDAS, 2026-11-22). LocalScript in StarterPlayer.StarterPlayerScripts,
-- deliberately OUTSIDE the Client folder (the JB team's sync replaces that folder).
--
-- While the local player is on the ice island (player attribute Zone == "Ice", set by the server
-- ZoneService from Map.Zones.Zone_Ice), it:
--   * tweens the global lighting (~2 s) to a cold, bright, light-blue look with light fog
--     (Atmosphere, ColorCorrection, Bloom kept soft so the snow does not burn out);
--   * turns on the island's snowfall and blown-snow emitters (tag IceAmbienceFx, in
--     Workspace.Map.Collision.NewMap_V6.Ice.Ambience);
--   * fades in a slow pulsing glow on the crystal clusters (PointLights tagged IceGlow).
--
-- Same coexistence rule as KingdomAmbience: on exit it only cancels its own tweens and never
-- writes lighting values, so ZoneMood / MapV6Mood tween the destination's normal look back.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local ZONE_ID = "Ice"
local ENTER_SECONDS = 2
local REASSERT_SECONDS = 1.2
local hex = Color3.fromHex

local function find(className: string, name: string): Instance?
	return Lighting:FindFirstChild(name) or Lighting:FindFirstChildOfClass(className)
end

type Goals = { [string]: any }
-- Cold, clean daylight; light blue fog, lighter than the Kingdom's.
local PROFILE: { [string]: Goals } = {
	Lighting = {
		ClockTime = 13.2,
		Brightness = 2.4,
		Ambient = hex("#7A8CA8"),
		OutdoorAmbient = hex("#A9BCD6"),
		ExposureCompensation = -0.05,
	},
	Atmosphere = {
		Density = 0.4,
		Haze = 2.2,
		Glare = 0.1,
		Offset = 0.08,
		Color = hex("#D4EBFF"),
		Decay = hex("#94B8DE"),
	},
	ColorCorrection = {
		TintColor = hex("#E8F3FF"),
		Saturation = -0.12,
		Contrast = 0.05,
		Brightness = -0.03,
	},
	Bloom = { Intensity = 0.25, Size = 20, Threshold = 2 },
	SunRays = { Intensity = 0.02 },
}

local targets: { [string]: Instance? } = {
	Lighting = Lighting,
	Atmosphere = find("Atmosphere", "FreeAPetAtmosphere"),
	ColorCorrection = find("ColorCorrectionEffect", "FreeAPetColor"),
	Bloom = find("BloomEffect", "FreeAPetBloom"),
	SunRays = find("SunRaysEffect", "FreeAPetSunRays"),
}

local tweens: { Tween } = {}
local function cancelTweens()
	for _, tween in tweens do
		tween:Cancel()
	end
	table.clear(tweens)
end

local function applyProfile(seconds: number)
	cancelTweens()
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for group, goals in PROFILE do
		local target = targets[group]
		if target then
			local tween = TweenService:Create(target, info, goals)
			table.insert(tweens, tween)
			tween:Play()
		end
	end
end

local function tweening(): boolean
	for _, tween in tweens do
		if tween.PlaybackState == Enum.PlaybackState.Playing then
			return true
		end
	end
	return false
end

local function drifted(): boolean
	local atmosphere = targets.Atmosphere :: Atmosphere?
	if atmosphere and math.abs(atmosphere.Density - PROFILE.Atmosphere.Density) > 0.02 then
		return true
	end
	if math.abs(Lighting.Brightness - PROFILE.Lighting.Brightness) > 0.05 then
		return true
	end
	if math.abs(Lighting.ClockTime - PROFILE.Lighting.ClockTime) > 0.1 then
		return true
	end
	local color = targets.ColorCorrection :: ColorCorrectionEffect?
	return color ~= nil and math.abs(color.Saturation - PROFILE.ColorCorrection.Saturation) > 0.03
end

local function setEffects(on: boolean)
	for _, item in CollectionService:GetTagged("IceAmbienceFx") do
		if item:IsA("ParticleEmitter") then
			item.Enabled = on
			if not on then
				item:Clear()
			end
		end
	end
end

local glow = 0 -- 0..1 fade of the crystal lights
local inside = false
local generation = 0

local function refresh()
	local now = player:GetAttribute("Zone") == ZONE_ID
	if now == inside then
		return
	end
	inside = now
	generation += 1
	local myGeneration = generation
	if now then
		task.delay(0.15, function()
			if inside and generation == myGeneration then
				applyProfile(ENTER_SECONDS)
			end
		end)
	else
		cancelTweens()
	end
	setEffects(now)
	player:SetAttribute("IceAmbience", now)
end

player:GetAttributeChangedSignal("Zone"):Connect(refresh)
setEffects(false)
refresh()

local lastCheck = 0
while player.Parent do
	local dt = task.wait(0.1)
	local t = os.clock()
	local goal = if inside then 1 else 0
	if glow ~= goal then
		glow = math.clamp(glow + (if inside then dt else -dt) / ENTER_SECONDS, 0, 1)
	end
	if glow > 0 or not inside then
		for i, light in CollectionService:GetTagged("IceGlow") do
			if light:IsA("PointLight") then
				local base = light:GetAttribute("BaseBrightness")
				base = if typeof(base) == "number" then base else 0.9
				local pulse = 0.75 + 0.25 * math.sin(t * 0.9 + i * 1.3)
				light.Brightness = (base :: number) * pulse * glow
			end
		end
	end
	if inside then
		lastCheck += dt
		if lastCheck >= 0.5 then
			lastCheck = 0
			if not tweening() and drifted() then
				applyProfile(REASSERT_SECONDS)
			end
		end
	end
end
