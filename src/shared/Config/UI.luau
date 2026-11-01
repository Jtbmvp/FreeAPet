--!strict
-- UI icon asset ids, by key. The art is the licensed "Stylized Game
-- Essentials" pack (assets/ui-icons, not in git) plus a few icons drawn in
-- the same style (assets/ui-icons-custom). assets/ui-upload holds exactly
-- these icons, named by key: upload them (Studio Asset Manager → Bulk
-- Import, or the MCP with an Open Cloud key) and paste each
-- "rbxassetid://..." here. An empty id falls back to no icon.

local UI = {
	icons = {
		cash = "rbxassetid://137704355384922", -- cash bundle
		day = "rbxassetid://101322053419347", -- hourglass
		heat = "rbxassetid://82884644006221", -- custom sun
		darkness = "rbxassetid://104929494208182", -- custom lantern
		warning = "rbxassetid://101755703783479", -- custom warning triangle
		info = "rbxassetid://96193638472950", -- information symbol
		success = "rbxassetid://97566201775042", -- claim checkmark
		theft = "rbxassetid://117968575128173", -- notification bell
		research = "rbxassetid://114644028443543", -- skill book
		timer = "rbxassetid://132511253051604", -- countdown timer
		carry = "rbxassetid://89803965572404", -- pet carrier
		speed = "rbxassetid://106127776752978", -- speed boot
		shield = "rbxassetid://117509866241689", -- defense shield
		offline = "rbxassetid://129936174843533", -- money bag
		upgrade = "rbxassetid://81719865669308", -- upgrade arrow
		locked = "rbxassetid://123493892530605", -- locked gate
		close = "rbxassetid://124293186294132", -- close button
		bringhome = "rbxassetid://106629659472542", -- teleport crystal
		release = "rbxassetid://132614877370081", -- open lock
		common = "rbxassetid://123133270725918", -- common badge
		uncommon = "rbxassetid://87698902848804", -- uncommon badge
		rare = "rbxassetid://119613877587427", -- rare badge
		-- Stud-style menu (from the same pack; not uploaded yet: Studio preview only)
		settings = "", -- settings gear
		trade = "", -- trade arrows
		leaderboard = "", -- leaderboard podium
		paw = "", -- pet paw
		sword = "", -- battle Attack
		bag = "", -- battle Bag (Pet Capsule)
		-- Research tree tiles (scripts/make-hex-tiles.py). Not uploaded yet:
		-- Studio shows the local preview, players get plain tiles.
		hex_fill = "", -- white hexagon, tinted per category
		hex_frame = "", -- white border + outline, drawn over the fill
		-- Stud texture tiled over panels and buttons (scripts/make-ui-textures.py).
		stud_tile = "",
	} :: { [string]: string },
}

return UI
