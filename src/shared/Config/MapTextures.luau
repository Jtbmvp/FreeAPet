--!strict
-- Denser stud textures for the floor colours of the mesh map (2x2 studs per
-- tile instead of 1, softer greens), made by scripts/make-map-textures.sh from
-- the map's own baked textures. MapPolishService swaps them in at runtime.
-- Upload assets/map-textures/*.png (Studio: Asset Manager > Bulk Import) and
-- paste each "rbxassetid://..." here. Empty = Studio shows a local preview
-- (scripts/studio-icon-preview.sh); players keep the original texture.

return {
	Desert_c_EEA84F = "",
	Desert_c_EFAB52 = "",
	Desert_c_F0AF56 = "",
	Desert_c_F1B65D = "",
	Desert_c_F2BD63 = "",
	Desert_c_F3C369 = "",
	Desert_c_F5C96F = "",
	Desert_hot_dune = "",
	Desert_sun_sand = "",
	Forest_c_379437 = "",
	Forest_c_3DA139 = "",
	Forest_c_43AD3B = "",
	Forest_c_47B83D = "",
	Forest_c_70D04A = "",
	Forest_meadow_green = "",
	SafeZone_boulevard_slate = "",
	SafeZone_plaza_lawn = "",
	SafeZone_plaza_paving = "",
	SafeZone_reserved_lawn = "",
	SafeZone_trim_white = "",
} :: { [string]: string }
