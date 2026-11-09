--!strict
-- Client-only fog and lighting per area of the V6 map (Workspace.Map.Collision.NewMap_V6):
-- Lobby, Forest, Dark Forest (MushroomGrove) and Desert.
-- Entering an area tweens to its "entry" profile; walking deeper blends towards its "deep" profile,
-- so the Dark Forest fog and the Desert haze build up as the player goes in.
-- Only acts while the local player is inside the V6 bounds and restores the previous lighting on exit,
-- so ZoneMood keeps working elsewhere. Never edits geometry, gameplay or server state.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local function findMap(): Instance?
	local mapRoot = Workspace:WaitForChild("Map", 30)
	local collision = mapRoot and mapRoot:WaitForChild("Collision", 30)
	return collision and collision:WaitForChild("NewMap_V6", 30)
end
local map = findMap()
if not map then
	return
end

-- World-space bounds (studs), matching Map.Zones: Base x500..770, Forest 770..1060, Desert 1060..1340, z3380..3720.
local BOUNDS = { minX = 500, maxX = 1340, minZ = 3380, maxZ = 3720, minY = -80, maxY = 220 }
local LOBBY_MAX_X = 770
local FOREST_MAX_X = 1060
-- Dark Forest (MushroomGrove) rectangle inside the forest.
local DARK = { minX = 932, maxX = 1060, minZ = 3512, maxZ = 3684 }
-- How far in (studs) until the deep profile is fully reached.
local DARK_DEPTH = 40
local DESERT_DEPTH = 120

local function ensure(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name) or Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = Lighting
	return created
end
local atmosphere = ensure("Atmosphere", "FreeAPetAtmosphere") :: Atmosphere
local color = ensure("ColorCorrectionEffect", "FreeAPetColor") :: ColorCorrectionEffect
local bloom = ensure("BloomEffect", "FreeAPetBloom") :: BloomEffect

type Group = { [string]: any }
type Profile = { Lighting: Group, Atmosphere: Group, Color: Group, Bloom: Group }
local hex = Color3.fromHex

local lobby: Profile = {
	Lighting = { ClockTime = 13.5, Brightness = 2.8, OutdoorAmbient = hex("#A3ACC2"), Ambient = hex("#727C94"), ExposureCompensation = 0.15 },
	Atmosphere = { Density = 0.22, Haze = 0.9, Glare = 0.15, Color = hex("#CFE9FF"), Decay = hex("#9CC3EA"), Offset = 0.15 },
	Color = { TintColor = hex("#FFF8EE"), Saturation = 0.15, Contrast = 0.05, Brightness = 0.02 },
	Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.6 },
}
local forest: Profile = {
	Lighting = { ClockTime = 15, Brightness = 2.2, OutdoorAmbient = hex("#86A391"), Ambient = hex("#5A7464"), ExposureCompensation = 0 },
	Atmosphere = { Density = 0.38, Haze = 2.0, Glare = 0, Color = hex("#CDEBD2"), Decay = hex("#6FA37E"), Offset = 0.1 },
	Color = { TintColor = hex("#EEFFEA"), Saturation = 0.2, Contrast = 0.08, Brightness = 0 },
	Bloom = { Intensity = 0.6, Size = 26, Threshold = 1.5 },
}
-- Dark Forest: dusk light, violet fog that thickens towards the centre, glows bloom more.
local darkEntry: Profile = {
	Lighting = { ClockTime = 17.2, Brightness = 1.8, OutdoorAmbient = hex("#7C7FA4"), Ambient = hex("#5C5A80"), ExposureCompensation = -0.05 },
	Atmosphere = { Density = 0.46, Haze = 2.4, Glare = 0, Color = hex("#8A88B4"), Decay = hex("#3E3660"), Offset = 0.05 },
	Color = { TintColor = hex("#E6DEF6"), Saturation = -0.02, Contrast = 0, Brightness = 0 },
	Bloom = { Intensity = 1.0, Size = 30, Threshold = 1.0 },
}
local darkDeep: Profile = {
	Lighting = { ClockTime = 17.8, Brightness = 1.3, OutdoorAmbient = hex("#65678F"), Ambient = hex("#4A4870"), ExposureCompensation = -0.15 },
	Atmosphere = { Density = 0.62, Haze = 3.2, Glare = 0, Color = hex("#6E6A9E"), Decay = hex("#2C2448"), Offset = 0 },
	Color = { TintColor = hex("#D9D0F2"), Saturation = -0.08, Contrast = 0.04, Brightness = -0.02 },
	Bloom = { Intensity = 1.3, Size = 34, Threshold = 0.85 },
}
-- Desert: hot golden haze that gets thicker and brighter deeper in.
local desertEntry: Profile = {
	Lighting = { ClockTime = 13, Brightness = 3.2, OutdoorAmbient = hex("#C4AE92"), Ambient = hex("#8E7B62"), ExposureCompensation = 0.2 },
	Atmosphere = { Density = 0.3, Haze = 2.4, Glare = 0.5, Color = hex("#FFE0A8"), Decay = hex("#E89A4A"), Offset = 0.12 },
	Color = { TintColor = hex("#FFEED6"), Saturation = 0.1, Contrast = 0.1, Brightness = 0.02 },
	Bloom = { Intensity = 0.55, Size = 24, Threshold = 1.4 },
}
local desertDeep: Profile = {
	Lighting = { ClockTime = 12.6, Brightness = 3.6, OutdoorAmbient = hex("#CDB08C"), Ambient = hex("#97805F"), ExposureCompensation = 0.3 },
	Atmosphere = { Density = 0.44, Haze = 3.0, Glare = 0.9, Color = hex("#FFD99A"), Decay = hex("#E08A3C"), Offset = 0.06 },
	Color = { TintColor = hex("#FFE6C4"), Saturation = 0.14, Contrast = 0.12, Brightness = 0.03 },
	Bloom = { Intensity = 0.6, Size = 26, Threshold = 1.3 },
}

local function lerpValue(a: any, b: any, t: number): any
	if typeof(a) == "number" then
		return a + (b - a) * t
	elseif typeof(a) == "Color3" then
		return (a :: Color3):Lerp(b, t)
	end
	return if t < 0.5 then a else b
end
local function blend(a: Profile, b: Profile, t: number): Profile
	local out: Profile = { Lighting = {}, Atmosphere = {}, Color = {}, Bloom = {} }
	for group, values in a :: any do
		for key, value in values do
			(out :: any)[group][key] = lerpValue(value, (b :: any)[group][key], t)
		end
	end
	return out
end

-- Returns the area name and how deep (0..1) the player is in it.
local function areaAt(position: Vector3): (string?, number)
	if position.X < BOUNDS.minX or position.X > BOUNDS.maxX or position.Z < BOUNDS.minZ or position.Z > BOUNDS.maxZ then
		return nil, 0
	end
	if position.Y < BOUNDS.minY or position.Y > BOUNDS.maxY then
		return nil, 0
	end
	if position.X < LOBBY_MAX_X then
		return "lobby", 0
	elseif position.X < FOREST_MAX_X then
		if position.X > DARK.minX and position.Z > DARK.minZ and position.Z < DARK.maxZ then
			local depth = math.min(position.X - DARK.minX, position.Z - DARK.minZ, DARK.maxX - position.X, DARK.maxZ - position.Z)
			return "dark", math.clamp(depth / DARK_DEPTH, 0, 1)
		end
		return "forest", 0
	end
	return "desert", math.clamp((position.X - FOREST_MAX_X) / DESERT_DEPTH, 0, 1)
end

local function profileFor(area: string, depth: number): Profile
	if area == "dark" then
		return blend(darkEntry, darkDeep, depth)
	elseif area == "desert" then
		return blend(desertEntry, desertDeep, depth)
	elseif area == "forest" then
		return forest
	end
	return lobby
end

local function capture(): Profile
	local snap: Profile = { Lighting = {}, Atmosphere = {}, Color = {}, Bloom = {} }
	for key in lobby.Lighting do
		snap.Lighting[key] = (Lighting :: any)[key]
	end
	for key in lobby.Atmosphere do
		snap.Atmosphere[key] = (atmosphere :: any)[key]
	end
	for key in lobby.Color do
		snap.Color[key] = (color :: any)[key]
	end
	for key in lobby.Bloom do
		snap.Bloom[key] = (bloom :: any)[key]
	end
	return snap
end

local tweens: { Tween } = {}
local function apply(profile: Profile, seconds: number)
	for _, tween in tweens do
		tween:Cancel()
	end
	table.clear(tweens)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	for target, goals in { [Lighting] = profile.Lighting, [atmosphere] = profile.Atmosphere, [color] = profile.Color, [bloom] = profile.Bloom } do
		local tween = TweenService:Create(target :: Instance, info, goals)
		table.insert(tweens, tween)
		tween:Play()
	end
end

local current: string? = nil
local currentDepth = 0
local saved: Profile? = nil
-- ZoneMood re-tweens the lighting when the player's Zone attribute changes; while inside the V6 map,
-- re-assert this map's profile after ZoneMood's 3 s transition so the two never fight for long.
player:GetAttributeChangedSignal("Zone"):Connect(function()
	if current then
		task.delay(3.2, function()
			if current then
				apply(profileFor(current, currentDepth), 1.5)
			end
		end)
	end
end)

local lastBrightness = -1
while map.Parent and player.Parent do
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local area, depth = nil, 0
	if root then
		area, depth = areaAt(root.Position)
	end
	if area ~= current then
		if area and not current then
			saved = capture()
		end
		if area then
			apply(profileFor(area, depth), 3)
		elseif saved then
			apply(saved, 2)
			saved = nil
		end
		current = area
		currentDepth = depth
		player:SetAttribute("MapV6Zone", area)
	elseif area then
		-- Deeper in: blend smoothly. Also re-assert if something else changed the lighting.
		local goal = profileFor(area, depth)
		local drifted = math.abs(Lighting.Brightness - (goal.Lighting.Brightness :: number)) > 0.05
		if math.abs(depth - currentDepth) > 0.04 or (drifted and Lighting.Brightness == lastBrightness) then
			currentDepth = depth
			apply(goal, 1.2)
		end
	end
	lastBrightness = Lighting.Brightness
	task.wait(0.4)
end
