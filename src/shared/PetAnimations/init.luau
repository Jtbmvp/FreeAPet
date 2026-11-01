--!strict
-- Pet rigs and clips, one generated module per species (scripts/export-pet-anims.py
-- reads the design GLBs). The server builds the joints from `joints`
-- (AnimalFactory); each client plays `clips` on them (PetAnimator).
--
-- Frames are CFrame components {x, y, z, R00..R22} relative to the art
-- model's pivot. Clip tracks are Motor6D.Transform values per frame: `r` is a
-- flat list of quaternions (x, y, z, w), `t` (optional) of translations in
-- studs at the art's imported scale.

export type Joint = { name: string, parent: string, frame: { number } }
export type Track = { r: { number }, t: { number }? }
-- markers: named moments in seconds, e.g. { impact = 0.42 } on attack clips.
export type Clip = {
	duration: number,
	frames: number,
	loop: boolean,
	tracks: { [string]: Track },
	markers: { [string]: number }?,
}
export type Rig = { fps: number, root: { number }, joints: { Joint }, clips: { [string]: Clip } }

local PetAnimations = {}

local cache: { [string]: Rig } = {}

function PetAnimations.Get(speciesId: string): Rig?
	local cached = cache[speciesId]
	if cached then
		return cached
	end
	local module = script:FindFirstChild(speciesId)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local rig = (require :: any)(module) :: Rig
	cache[speciesId] = rig
	return rig
end

function PetAnimations.ToCFrame(n: { number }): CFrame
	return CFrame.new(n[1], n[2], n[3], n[4], n[5], n[6], n[7], n[8], n[9], n[10], n[11], n[12])
end

return PetAnimations
