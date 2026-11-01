--!strict
-- Every sound in the game, by name. Only licensed library audio (free on the
-- Creator Store, verified uploaders: ProSoundEffects "(SFX)" and APMOfficial; others
-- may not be cleared for public use). Picked from their descriptions: listen in Studio and
-- swap any id that doesn't fit. "" = silent.

export type SoundDef = { id: string, volume: number, group: "SFX" | "Music" | "Ambience", looped: boolean? }

local function sfx(id: number, volume: number): SoundDef
	return { id = `rbxassetid://{id}`, volume = volume, group = "SFX" }
end

local function music(id: number, volume: number): SoundDef
	return { id = `rbxassetid://{id}`, volume = volume, group = "Music", looped = true }
end

local Sounds: { [string]: SoundDef } = {
	-- Interface
	click = sfx(9119717523, 0.5), -- Switch Click On Or Off Toggle Button 2
	open = sfx(9126283592, 0.35), -- Wood Swish Ruler Whoosh
	notify = sfx(9119717529, 0.4), -- Switch Click On Or Off Toggle Button 1

	-- Pets
	pickup = sfx(9112872239, 0.6), -- Small Bubbles Water Surface Pop 5
	release = sfx(9112872239, 0.6),
	heal = sfx(9119293555, 0.7), -- Small Splash Shallow Water Fountain Pool 1

	-- Battle
	battleStart = sfx(9120733724, 0.6), -- Whoosh Rising Swish Airy
	attack = sfx(9126047581, 0.5), -- Synth Air Whoosh Karate Swishes
	hit = sfx(9117969687, 0.6), -- Punch Kit Beefy Hit 2
	strongHit = sfx(9117969717, 0.75), -- Punch Kit Beefy Hit 3
	capsuleShake = sfx(9119717529, 0.6),
	captured = sfx(1840076509, 0.6), -- Through the Roof (sting)
	won = sfx(1839881844, 0.6), -- Spinning Around (b)
	levelUp = sfx(9044739323, 0.6), -- Sugar Crash (sting)

	-- Music (one track per area, the battle one on top)
	musicPlaza = music(1839886740, 0.3), -- Lucky Jim (whistling, childlike)
	musicForest = music(1843279222, 0.3), -- Butterfly Valley (ukulele)
	musicDesert = music(1839886740, 0.25), -- PLACEHOLDER: same as the plaza
	musicBattle = music(9041912631, 0.35), -- Cloak and Dagger (playful mystery)

	-- Ambience
	ambienceForest = { id = "rbxassetid://9112831284", volume = 0.3, group = "Ambience", looped = true }, -- Morning Birds 1 (loop)
}

return Sounds
