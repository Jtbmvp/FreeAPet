local Layout = require("../../src/client/UI/HudLayout")
local State = require("../../src/client/UI/HudState")
local count = 0
local function check(value, message)
	assert(value, message)
	count += 1
end
local sizes = {
	{ 480, 260 },
	{ 568, 262 },
	{ 480, 280 },
	{ 549, 317 },
	{ 667, 317 },
	{ 844, 332 },
	{ 932, 372 },
	{ 1024, 542 },
	{ 1024, 710 },
	{ 1150, 700 },
	{ 1366, 710 },
	{ 1920, 1000 },
	{ 2560, 1380 },
	{ 3840, 2100 },
}
for _, v in sizes do
	for _, touch in { false, true } do
		local w, h = v[1], v[2]
		local m = Layout.Compute(w, h, touch, if touch then h - 112 else nil)
		local rects = { m.progress, m.base, m.settings, m.cash, m.boosts }
		for _, r in m.nav do
			table.insert(rects, r)
		end
		if m.compact then
			table.insert(rects, m.showPets)
		end
		for i, a in rects do
			check(a.x >= 0 and a.y >= 0 and a.x + a.w <= w and a.y + a.h <= h, `bounds {w}x{h} item{i}`)
			for j, b in rects do
				if i < j then
					check(not Layout.Overlaps(a, b), `overlap {w}x{h} items {i}/{j}`)
				end
			end
		end
		for _, r in m.nav do
			check(r.w >= 44 and r.h >= 44, "nav hit floor")
		end
		check(m.settings.w >= 44 and m.settings.h >= 44, "settings hit floor")
		check(
			m.window.x >= 0
				and m.window.y >= 0
				and m.window.x + m.window.w <= w
				and m.window.y + m.window.h <= h,
			"window safe bounds"
		)
		-- The modal uses the *visible* body, not the collection's 360px minimum.
		local bodyW, bodyH = m.window.w - 40, m.window.h - 92
		local dialog = Layout.Confirmation(bodyW, bodyH)
		local parts = { dialog.question, dialog.details, dialog.cancel, dialog.commit }
		for i, a in parts do
			check(
				a.x >= 0 and a.y >= 0 and a.w > 0 and a.h > 0 and a.x + a.w <= bodyW and a.y + a.h <= bodyH,
				`confirmation bounds {w}x{h}/{i}`
			)
			for j, b in parts do
				if i < j then
					check(not Layout.Overlaps(a, b), `confirmation overlap {i}/{j}`)
				end
			end
		end
		check(dialog.cancel.h >= 48 and dialog.commit.h >= 48, "confirmation actions remain tappable")
		check(dialog.commit.x - dialog.cancel.x - dialog.cancel.w >= 8, "confirmation target separation")
		check(dialog.details.h >= 44, "smallest phone retains a usable details scroll region")
		for _, cardHeight in { 86, 136 } do
			local cw = math.min(320, w * 0.42)
			local obstacle =
				{ x = (w - cw) / 2, y = h - (if touch then 124 else 24) - cardHeight, w = cw, h = cardHeight }
			-- A coexisting world card collapses only the intersecting HUD widgets.
			local kept = 0
			for _, r in rects do
				if not Layout.Overlaps(r, obstacle) then
					kept += 1
				end
			end
			check(kept > 0, "world action must not remove every menu entry")
		end
	end
end
local ratio, text = State.Progress(2, 0, 150)
check(ratio == 0 and text == "0 / 150 EXP", "zero XP is valid")
ratio, text = State.Progress(30, 100, 0)
check(ratio == 1 and text == "MAX", "cap must not divide by zero")
ratio, text = State.Progress(nil, nil, nil)
check(ratio == 0 and text == "Loading…", "missing data is not level zero")
ratio, text = State.Progress(3, 0 / 0, 10)
check(ratio == 0 and text == "Loading…", "reject NaN progress")
ratio = State.Progress(3, 250, 100)
check(ratio == 1, "clamp overflow")
local c = State.NewConfirmations()
local function event(session, sequence, revision)
	return { sessionId = session, sequence = sequence, committedRevision = revision }
end
check(State.AcceptConfirmation(c, event("A", 1, 2)), "first durable event")
check(not State.AcceptConfirmation(c, event("A", 1, 2)), "duplicate event")
check(not State.AcceptConfirmation(c, event("A", 2, 1)), "late lower revision")
check(not State.AcceptConfirmation(c, event("A", 1, 9)), "out of order sequence")
check(State.AcceptConfirmation(c, event("A", 3, 3)), "new confirmation")
check(not State.AcceptConfirmation(c, event("B", 4, 4)), "stale other session")
check(not State.AcceptConfirmation(c, {}), "bad payload")
print(`PASS {count} UI layout/state assertions; no Roblox runtime claimed`)
