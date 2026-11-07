--!strict
-- INACTIVE preparation: no imports, species registration, model edits or playback.
-- Binding evidence is authored configuration, never an authority/reward boundary.
local AnimalMath = require(script.Parent.Parent.AnimalMath)
local Stages = require(script.Parent.Parent.Config.Progression).pet.stages

export type Clip = {
	duration: number,
	loop: boolean,
	scaleChannels: { string },
	knownRotationSeamDegrees: number,
}
export type Variant = {
	key: string,
	slug: string,
	stage: string,
	runtimeSpeciesId: string?,
	modelAssetId: string,
	sourceSha256: string,
	sourceFile: string,
	sourceHeightMetres: number,
	adultHeightStuds: number?,
	visualYawDegrees: number,
	bones: { string },
	boneParents: { [string]: string },
	clips: { [string]: Clip },
}
export type AnimationBinding = {
	assetId: string,
	sourceSha256: string,
	clipName: string,
	verifiedAssetType: string,
}
export type Binding = {
	variantKey: string,
	sourceSha256: string,
	modelAssetId: string,
	clips: { [string]: AnimationBinding },
}
local catalog = require(script.Parent.Catalog) :: any
local variants: { [string]: Variant } = catalog.variants
local Contract = {}

local function positive(value: number): boolean
	return value == value and value > 0 and value < math.huge
end

function Contract.Get(key: string): Variant?
	return variants[key]
end

-- A legacy Adult floor must not select a Baby shape after migration.
function Contract.Stage(level: number, legacyScaleFloor: number?): string
	local current = Stages[1].id
	local floor = legacyScaleFloor or 0
	for _, stage in Stages do
		if level >= stage.level or floor >= stage.scale then
			current = stage.id
		end
	end
	return current
end

function Contract.ForRuntimeSpecies(speciesId: string, level: number, legacyScaleFloor: number?): Variant?
	local stage = Contract.Stage(level, legacyScaleFloor)
	for _, variant in variants do
		if variant.runtimeSpeciesId == speciesId and variant.stage == stage then
			return variant
		end
	end
	return nil -- the three unmapped originals remain available as catalog entries only
end

-- Measure the imported REST VISUAL geometry in studs, excluding helpers.
-- This is an ABSOLUTE multiplier from an unscaled imported template, not a
-- second multiplier on an already-scaled Baby/Juvenile model.
function Contract.Scale(
	variant: Variant,
	importedVisualHeightStuds: number,
	level: number,
	size: number,
	legacyScaleFloor: number?
): (number?, string?)
	local adultHeight = variant.adultHeightStuds
	if not adultHeight then
		return nil, "Adult height not configured for this species"
	end
	if
		not positive(importedVisualHeightStuds)
		or not positive(adultHeight)
		or not positive(size)
		or not positive(level)
	then
		return nil, "Invalid visual measurement, size or level"
	end
	if
		legacyScaleFloor ~= nil
		and (
			legacyScaleFloor ~= legacyScaleFloor
			or legacyScaleFloor < 0
			or legacyScaleFloor > Stages[#Stages].scale
		)
	then
		return nil, "Invalid legacy appearance floor"
	end
	local target = adultHeight * AnimalMath.ScaleFor(level, legacyScaleFloor) * size
	return target / importedVisualHeightStuds, nil
end

function Contract.VisualOffset(variant: Variant): CFrame
	return CFrame.Angles(0, math.rad(variant.visualYawDegrees), 0)
end

function Contract.ValidateBinding(variant: Variant, binding: Binding): (boolean, string?)
	if
		binding.variantKey ~= variant.key
		or binding.sourceSha256 ~= variant.sourceSha256
		or binding.modelAssetId ~= variant.modelAssetId
	then
		return false, "Clip binding belongs to a different original/phase"
	end
	if not binding.clips.Idle or not binding.clips.Walk then
		return false, "Verified Idle/Walk AnimationIds are missing"
	end
	local seen: { [string]: boolean } = {}
	for name, clip in binding.clips do
		if not variant.clips[name] or clip.clipName ~= name or clip.sourceSha256 ~= variant.sourceSha256 then
			return false, "Clip name/source mismatch"
		end
		if
			not clip.assetId:match("^[1-9]%d*$")
			or catalog.modelAssetIds[clip.assetId]
			or clip.verifiedAssetType ~= "Animation"
		then
			return false, "A verified AnimationId is required; a model ID is not a clip"
		end
		if seen[clip.assetId] then
			return false, "Different original clips share an unverified binding"
		end
		seen[clip.assetId] = true
	end
	return true, nil
end

-- Read only. No synthetic Motor6Ds, welds, Bone.Transform edits or reparenting.
function Contract.Inspect(model: Model, variant: Variant): (Animator?, string?)
	if
		model:GetAttribute("PetVariantKey") ~= variant.key
		or model:GetAttribute("ArtSourceSha256") ~= variant.sourceSha256
	then
		return nil, "Original provenance attributes are missing or mismatched"
	end
	local bones: { [string]: Bone } = {}
	local animator: Animator? = nil
	local count = 0
	for _, item in model:GetDescendants() do
		if item:IsA("LuaSourceContainer") or item:IsA("PackageLink") then
			return nil, "Imported executable/package content must be inspected and isolated first"
		end
		if item:IsA("Bone") then
			if bones[item.Name] then
				return nil, "Duplicate bone names: individual phase required"
			end
			bones[item.Name], count = item, count + 1
		elseif item:IsA("Animator") then
			if animator then
				return nil, "Multiple Animators; select a single rig first"
			end
			animator = item
		end
	end
	if count ~= #variant.bones then
		return nil, "Bone count differs or rig replication is incomplete"
	end
	for _, name in variant.bones do
		if not bones[name] then
			return nil, `Missing original bone {name}`
		end
	end
	for name, expectedParent in variant.boneParents do
		local parent: Instance? = bones[name].Parent
		while parent and parent ~= model and not parent:IsA("Bone") do
			parent = parent.Parent
		end
		if not parent or not parent:IsA("Bone") or parent.Name ~= expectedParent then
			return nil, `Unexpected bone parent for {name}`
		end
	end
	local host = animator and animator.Parent
	if not animator or not host or not (host:IsA("Humanoid") or host:IsA("AnimationController")) then
		return nil, "Imported rig needs one Animator under a Humanoid/AnimationController"
	end
	return animator, nil
end

return Contract
