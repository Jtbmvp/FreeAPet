--!strict
-- Music and ambience by area (player attribute Zone), with a battle track on
-- top while InBattle. Tracks crossfade. Also the small reactive sounds that
-- come from attributes: picking up / putting down a pet (CarryCount).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Sfx = require(ReplicatedStorage.Shared.Sfx)

local Soundscape = {}

local FADE = TweenInfo.new(1.8, Enum.EasingStyle.Sine)

local MUSIC_BY_ZONE: { [string]: string } = {
	Base = "musicPlaza",
	None = "musicPlaza",
	Forest = "musicForest",
	Desert = "musicDesert",
}
local AMBIENCE_BY_ZONE: { [string]: string } = {
	Forest = "ambienceForest",
}

-- Fades between tracks of one layer (music or ambience).
local function layer()
	local current: Sound? = nil
	return function(name: string?)
		local nextSound = if name then Sfx.Get(name) else nil
		if nextSound == current then
			return
		end
		local old = current
		if old then
			local fade = TweenService:Create(old, FADE, { Volume = 0 })
			fade:Play()
			fade.Completed:Once(function()
				if current ~= old then
					old:Stop()
				end
			end)
		end
		current = nextSound
		if nextSound and name then
			nextSound.Volume = 0
			if not nextSound.IsPlaying then
				nextSound:Play()
			end
			TweenService:Create(nextSound, FADE, { Volume = Config.Sounds[name].volume }):Play()
		end
	end
end

function Soundscape.Start()
	local player = Players.LocalPlayer
	local setMusic = layer()
	local setAmbience = layer()

	local function refresh()
		local zone = player:GetAttribute("Zone")
		zone = if typeof(zone) == "string" then zone else "Base"
		if player:GetAttribute("InBattle") then
			setMusic("musicBattle")
		else
			setMusic(MUSIC_BY_ZONE[zone] or "musicPlaza")
		end
		setAmbience(AMBIENCE_BY_ZONE[zone])
	end
	player:GetAttributeChangedSignal("Zone"):Connect(refresh)
	player:GetAttributeChangedSignal("InBattle"):Connect(function()
		if player:GetAttribute("InBattle") then
			Sfx.Play("battleStart")
		end
		refresh()
	end)
	refresh()

	task.spawn(function()
		local battles = workspace:WaitForChild("Battles")
		local point = battles:WaitForChild("HealPoint", 30)
		local prompt = point and point:WaitForChild("HealPrompt", 5)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Triggered:Connect(function()
				Sfx.Play("heal")
			end)
		end
	end)

	local carrying = player:GetAttribute("CarryCount") or 0
	player:GetAttributeChangedSignal("CarryCount"):Connect(function()
		local count = player:GetAttribute("CarryCount") or 0
		if typeof(count) == "number" and typeof(carrying) == "number" then
			Sfx.Play(if count > carrying then "pickup" else "release")
		end
		carrying = count
	end)
end

return Soundscape
