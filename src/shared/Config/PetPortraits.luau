--!strict
-- Image URIs resolved in Studio from each uploaded Decal.Texture; no numeric-ID assumptions.
local assets: { [string]: { [string]: string } } = {
	AcornSquirrel = {
		Baby = "rbxassetid://134086354252760",
		Juvenile = "rbxassetid://77844542567343",
		Adult = "rbxassetid://81754546557925",
	},
	BallScorpion = {
		Baby = "rbxassetid://138450603807413",
		Juvenile = "rbxassetid://80695345864640",
		Adult = "rbxassetid://97162454654045",
	},
	BranchDeer = {
		Baby = "rbxassetid://129887467177816",
		Juvenile = "rbxassetid://128344795359038",
		Adult = "rbxassetid://96960273775173",
	},
	Glimmouse = {
		Baby = "rbxassetid://131935215403924",
		Juvenile = "rbxassetid://114152934565942",
		Adult = "rbxassetid://99702611102129",
	},
	HoppingMushroom = {
		Baby = "rbxassetid://107797605726887",
		Juvenile = "rbxassetid://100797335768585",
		Adult = "rbxassetid://104751382387514",
	},
	Plazadillo = {
		Baby = "rbxassetid://100336943488289",
		Juvenile = "rbxassetid://114777371102395",
		Adult = "rbxassetid://100302957861055",
	},
	RunningCactus = {
		Baby = "rbxassetid://134792479040112",
		Juvenile = "rbxassetid://98696757094054",
		Adult = "rbxassetid://139576705459280",
	},
	Spoutle = {
		Baby = "rbxassetid://73117323628197",
		Juvenile = "rbxassetid://74800106121892",
		Adult = "rbxassetid://129625023867526",
	},
	SunCamel = {
		Baby = "rbxassetid://120094555387076",
		Juvenile = "rbxassetid://96366119666093",
		Adult = "rbxassetid://139089678845120",
	},
}
local Portraits = { AssetType = "Image", BySpecies = assets }
function Portraits.Get(speciesId: string, stage: string?): string
	local phases = assets[speciesId]
	return if phases then phases[stage or "Adult"] or "" else ""
end
return Portraits
