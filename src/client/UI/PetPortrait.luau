--!strict
-- Flat uploaded portraits: no cloned models, cameras, WorldModels or ViewportFrames.
local RS = game:GetService("ReplicatedStorage")
local Assets = require(RS.Shared.Config.PetPortraits)
local PetPortrait = {}
function PetPortrait.Update(image: ImageLabel, speciesId: string, silhouette: boolean?, stage: string?)
	local uri = Assets.Get(speciesId, stage)
	if image.Image ~= uri then
		image.Image = uri
	end
	image.ImageColor3 = if silhouette then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
	image.ImageTransparency = if silhouette then 0.15 else 0
	image:SetAttribute("PortraitSpeciesId", speciesId)
	image:SetAttribute("PortraitStage", stage or "Adult")
	image:SetAttribute("PortraitAssetKind", Assets.AssetType)
end
function PetPortrait.New(speciesId: string, silhouette: boolean?, stage: string?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = "PetPortrait"
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit
	PetPortrait.Update(image, speciesId, silhouette, stage)
	return image
end
return PetPortrait
