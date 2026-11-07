--!strict
-- All rectangles use actual safe-container pixels; no whole-desktop shrink on phones.
local Layout = {}
export type Rect = { x: number, y: number, w: number, h: number }
local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h) }
end
function Layout.Compute(width: number, height: number, touch: boolean, jumpTop: number?)
	local compact = height < 700 or width < 1150
	local s = math.clamp(math.min(width / 1920, height / 1000), 0.65, 1.4)
	local navigation = {}
	if compact then
		for i = 1, 4 do
			navigation[i] = rect(8 + (i - 1) * 64, 64, 56, 56)
		end
		navigation[5] = rect(264, 64, 104, 56)
		local bottom = if touch then math.min(height - 112, (jumpTop or height) - 8) else height - 8
		local cashY = math.max(128, bottom - 58)
		return {
			compact = true,
			scale = 1,
			nav = navigation,
			progress = rect(8, 8, math.min(192, width / 2 - 82), 48),
			base = rect(width / 2 - 62, 8, 124, 48),
			settings = rect(width - 56, 8, 48, 48),
			showPets = rect(376, 64, math.max(48, width - 384), 56),
			cash = rect(8, cashY, 212, 58),
			boosts = rect(width - 188, cashY, 180, 56),
			window = rect(8, 8, width - 16, height - 16),
			board = rect(width - 288, 64, 280, math.min(240, height - 80)),
		}
	end
	for i = 1, 4 do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		navigation[i] = rect(36 * s + col * 145 * s, 340 * s + row * 146 * s, 128 * s, 128 * s)
	end
	navigation[5] = rect(36 * s, 632 * s, 272 * s, 104 * s)
	local ww, wh = math.min(width - 360 * s, 1320 * s), math.min(height - 112, 836 * s)
	return {
		compact = false,
		scale = s,
		nav = navigation,
		progress = rect(
			36 * s,
			math.min(232 * s, 340 * s - math.max(76, 76 * s) - 12),
			272 * s,
			math.max(76, 76 * s)
		),
		base = rect(width / 2 - 160 * s, 8, 320 * s, 84 * s),
		settings = rect(width - math.max(48, 52 * s) - 8, 8, math.max(48, 52 * s), math.max(48, 52 * s)),
		showPets = rect(36 * s, 746 * s, 272 * s, 48),
		cash = rect(36 * s, height - 188 * s, 460 * s, 164 * s),
		boosts = rect(width - 350 * s, height - 142 * s, 320 * s, 112 * s),
		window = rect((width - ww) / 2, (height - wh) / 2, ww, wh),
		board = rect(width - 436 * s, 80 * s, 420 * s, math.min(340 * s, height / 2)),
	}
end
-- Sale confirmation fills the visible content area, with its actions outside the scroll.
function Layout.Confirmation(width: number, height: number)
	local half = math.floor((width - 24) / 2)
	local questionHeight = math.clamp(height - 116, 36, 56)
	return {
		question = rect(8, 0, width - 16, questionHeight),
		details = rect(8, questionHeight + 8, width - 16, height - questionHeight - 72),
		cancel = rect(8, height - 56, half, 48),
		commit = rect(half + 16, height - 56, width - half - 24, 48),
	}
end
function Layout.Overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end
return Layout
