--!strict
-- KingdomAmbience (MIDAS, 2026-11-22). LocalScript in StarterPlayer.StarterPlayerScripts,
-- deliberately OUTSIDE the Client folder (the JB team's sync replaces that folder).
--
-- While the local player is on the Forgotten Kingdom island (player attribute Zone == "Kingdom",
-- set by the server ZoneService from Map.Zones.Zone_Kingdom), it:
--   * tweens the global lighting to a cold grey-lilac fog (Atmosphere, ColorCorrection, Bloom,
--     SunRays, Lighting) in ~2 s;
--   * turns on the island's ground mist / leaves / dust emitters (tag KingdomAmbienceFx);
--   * makes the lantern lights flicker (tag KingdomFlicker, attribute BaseBrightness);
--   * (optional, off) wind loop and raven calls.
--
-- Coexistence with the JB team's ZoneMood and MIDAS's MapV6Mood:
--   * Only touches fields that ZoneMood already tweens on every Zone change, so when the player
--     leaves the island (Zone changes) ZoneMood/MapV6Mood tween the normal look back by themselves.
--     On exit this script only cancels its own tweens; it never writes values on exit, so it can
--     never fight the destination's profile.
--   * On entry ZoneMood (3 s, "safe" profile for unknown zones) and MapV6Mood (2 s restore when
--     leaving its V6 boxes) also start tweens. A newer tween on the same property cancels the
--     older one, so this script applies a moment after the Zone change and then re-asserts every
--     0.5 s if something else moved the lighting away from the Kingdom profile.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local ZONE_ID = "Kingdom"
local ENTER_SECONDS = 2
local REASSERT_SECONDS = 1.2

-- Game sound is switched off by the developer (ReplicatedStorage.Shared.Sfx ENABLED = false).
-- Flip this to true when sound comes back.
local SOUND_ENABLED = false
local WIND_ID = "rbxassetid://9114625745" -- ProSoundEffects "Gods Wind Spooky Eerie 2" (66 s)
local RAVEN_IDS = { "rbxassetid://9118067222", "rbxassetid://9118066673", "rbxassetid://9118066003" } -- ProSoundEffects Raven 12/8/5

local hex = Color3.fromHex

local function find(className: string, name: string): Instance?
	return Lighting:FindFirstChild(name) or Lighting:FindFirstChildOfClass(className)
end

type Goals = { [string]: any }
-- Cold, washed-out, grey-lilac fog; darker than the other islands but still daytime.
local PROFILE: { [string]: Goals } = {
	Lighting = {
		ClockTime = 16.4,
		Brightness = 1.45,
		Ambient = hex("#5F607A"),
		OutdoorAmbient = hex("#80829C"),
		ExposureCompensation = -0.1,
	},
	Atmosphere = {
		Density = 0.62,
		Haze = 4.2,
		Glare = 0,
		Offset = 0.02,
		Color = hex("#B7B4CB"),
		Decay = hex("#6C6987"),
	},
	ColorCorrection = {
		TintColor = hex("#E2E0F3"),
		Saturation = -0.28,
		Contrast = 0.06,
		Brightness = -0.02,
	},
	Bloom = { Intensity = 0.7, Size = 28, Threshold = 1.25 },
	SunRays = { Intensity = 0.015 },
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

-- Island effects -------------------------------------------------------------------------
local function setEffects(on: boolean)
	for _, item in CollectionService:GetTagged("KingdomAmbienceFx") do
		if item:IsA("ParticleEmitter") then
			item.Enabled = on
			if not on then
				item:Clear()
			end
		end
	end
end

local wind: Sound? = nil
local function setSound(on: boolean)
	if not SOUND_ENABLED then
		return
	end
	if not wind then
		local sound = Instance.new("Sound")
		sound.Name = "KingdomWind"
		sound.SoundId = WIND_ID
		sound.Looped = true
		sound.Volume = 0
		sound.Parent = SoundService
		wind = sound
	end
	local sound = wind :: Sound
	if on and not sound.IsPlaying then
		sound:Play()
	end
	local fade = TweenService:Create(sound, TweenInfo.new(ENTER_SECONDS), { Volume = if on then 0.25 else 0 })
	fade:Play()
	if not on then
		fade.Completed:Once(function()
			if sound.Volume < 0.01 then
				sound:Stop()
			end
		end)
	end
end

local function ravenCall()
	if not SOUND_ENABLED then
		return
	end
	local map = Workspace:FindFirstChild("Map")
	local crows = map and map:FindFirstChild("Collision")
	crows = crows and crows:FindFirstChild("NewMap_V6")
	crows = crows and crows:FindFirstChild("Kingdom")
	crows = crows and crows:FindFirstChild("Ambience")
	crows = crows and crows:FindFirstChild("Crows")
	local list = crows and crows:GetChildren() or {}
	if #list == 0 then
		return
	end
	local crow = list[math.random(1, #list)]
	local body = crow:FindFirstChild("Body")
	if not body then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = RAVEN_IDS[math.random(1, #RAVEN_IDS)]
	sound.Volume = 0.35
	sound.PlaybackSpeed = 0.9 + math.random() * 0.2
	sound.RollOffMaxDistance = 220
	sound.Parent = body
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(10, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- State ---------------------------------------------------------------------------------------
local inside = false
local generation = 0

local function isInKingdom(): boolean
	return player:GetAttribute("Zone") == ZONE_ID
end

local function refresh()
	local now = isInKingdom()
	if now == inside then
		return
	end
	inside = now
	generation += 1
	local myGeneration = generation
	if now then
		-- Let ZoneMood / MapV6Mood start their own tweens for this Zone change first, then
		-- override them (the newest tween on a property wins).
		task.delay(0.15, function()
			if inside and generation == myGeneration then
				applyProfile(ENTER_SECONDS)
			end
		end)
		setEffects(true)
		setSound(true)
	else
		-- ZoneMood (and MapV6Mood on the V6 islands) tween the normal look back on this Zone change.
		cancelTweens()
		setEffects(false)
		setSound(false)
	end
	player:SetAttribute("KingdomAmbience", now)
end

player:GetAttributeChangedSignal("Zone"):Connect(refresh)
setEffects(false)
refresh()

local nextRaven = os.clock() + 8
local lights: { PointLight } = {}
local function collectLights()
	table.clear(lights)
	for _, item in CollectionService:GetTagged("KingdomFlicker") do
		if item:IsA("PointLight") then
			table.insert(lights, item)
		end
	end
end
collectLights()
CollectionService:GetInstanceAddedSignal("KingdomFlicker"):Connect(collectLights)
CollectionService:GetInstanceRemovedSignal("KingdomFlicker"):Connect(collectLights)

local lastCheck = 0
while player.Parent do
	local dt = task.wait(0.1)
	local t = os.clock()
	if inside then
		-- Lantern flicker: smooth noise around the base brightness, per light.
		for i, light in lights do
			local base = light:GetAttribute("BaseBrightness")
			base = if typeof(base) == "number" then base else 0.9
			local n = math.noise(t * 2.3, i * 1.7) * 0.5 + math.noise(t * 7.1, i * 3.1) * 0.25
			light.Brightness = math.max(0.1, (base :: number) * (1 + n))
		end
		lastCheck += dt
		if lastCheck >= 0.5 then
			lastCheck = 0
			if not tweening() and drifted() then
				applyProfile(REASSERT_SECONDS)
			end
		end
		if t >= nextRaven then
			nextRaven = t + 12 + math.random() * 16
			ravenCall()
		end
	end
end
