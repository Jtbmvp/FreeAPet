local Portraits = require("../../src/shared/Config/PetPortraits")
local count = 0
for _, phases in Portraits.BySpecies do
	assert(
		phases.Baby ~= phases.Juvenile and phases.Juvenile ~= phases.Adult and phases.Baby ~= phases.Adult,
		"each growth phase needs its own portrait"
	)
	for _, uri in phases do
		assert(uri:match("^rbxassetid://[1-9]%d*$"), "valid uploaded Decal URI")
		count += 1
	end
end
assert(count == 27 and Portraits.AssetType == "Image", "27 bindings use resolved image content")
assert(
	Portraits.Get("Glimmouse", "Baby") == "rbxassetid://131935215403924",
	"Baby uses the supplied Baby upload"
)
assert(
	Portraits.Get("Glimmouse", "Adult") == "rbxassetid://99702611102129",
	"Adult uses the supplied Adult upload"
)
assert(
	Portraits.Get("SunCamel") == Portraits.Get("SunCamel", "Adult"),
	"species-only Index preview defaults to Adult"
)
assert(
	Portraits.Get("Missing", "Baby") == "" and Portraits.Get("Glimmouse", "Unknown") == "",
	"unknown binding must not display another species or phase"
)
print("PASS 27 portrait bindings; phase/default/unknown lookup guards; no engine load claimed")
