--!strict
-- Plays a named sound (Config.Sounds) on this client. Shared so UI helpers
-- can use it; does nothing on the server. Sounds are created once and
-- reused (a new one only when the same sound overlaps itself).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local Sfx = {}

local groups: { [string]: SoundGroup } = {}
local cache: { [string]: Sound } = {}

local GROUP_VOLUMES = { SFX = 0.8, Music = 0.6, Ambience = 0.7 }

-- Sound is switched off for now (developer's call: it comes back later).
-- Turn this on and add Soundscape back to Main.client to bring it all back.
local ENABLED = false

function Sfx.Group(name: string): SoundGroup
	local group = groups[name]
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = name
		group.Volume = GROUP_VOLUMES[name] or 1
		group.Parent = SoundService
		groups[name] = group
	end
	return group
end

-- A Sound object for a name (for music/ambience the caller controls it).
function Sfx.Get(name: string): Sound?
	local def = Config.Sounds[name]
	if not ENABLED or not def or def.id == "" or not RunService:IsClient() then
		return nil
	end
	local sound = cache[name]
	if not sound then
		local newSound = Instance.new("Sound")
		newSound.Name = name
		newSound.SoundId = def.id
		newSound.Volume = def.volume
		newSound.Looped = def.looped == true
		newSound.SoundGroup = Sfx.Group(def.group)
		newSound.Parent = SoundService
		cache[name] = newSound
		sound = newSound
	end
	return sound
end

function Sfx.Play(name: string)
	local sound = Sfx.Get(name)
	if not sound then
		return
	end
	if sound.IsPlaying and sound.TimePosition < 0.1 then
		return -- the same sound twice in a row: once is enough
	end
	if sound.IsPlaying then
		local copy = sound:Clone()
		copy.Parent = SoundService
		copy:Play()
		copy.Ended:Once(function()
			copy:Destroy()
		end)
		return
	end
	sound:Play()
end

return Sfx
