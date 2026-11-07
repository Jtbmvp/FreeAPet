-- BattleSummary: VICTORY / CAUGHT / ESCAPED / DEFEATED com barras de XP animadas e LEVEL UP.
-- Show(data): { result = "win"|"caught"|"fled"|"lose", sub = "texto",
--   rows = { { name, lv, xp, need, nextNeed, gain, part (bool), fainted (bool) }, ... },
--   player = { lv, xp, need, nextNeed, gain } | nil, rewards = { { icon = "cash", text = "+$75", color = Color3 } } }
-- Sinal: Continue
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Kit = require(Core.Kit)
local Motion = require(Core.Motion)
local Signal = require(Core.Signal)
local Portrait = require(script.Parent.Parent.Parent.UI.PetPortrait)

local C, G, hex = Theme.Colors, Theme.Grad, Theme.hex
local V2 = Vector2.new

local HEAD = {
	win = { "VICTORY!", G.Victory }, caught = { "CAUGHT!", G.Caught }, fled = { "ESCAPED", G.Escaped }, lose = { "DEFEATED", G.Defeat },
}

local BattleSummary = {}

function BattleSummary.new(stage)
	local self = { Continue = Signal.new(), _run = 0 }
	local root = Kit.make("Frame", stage, { Name = "BattleSummary", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = Theme.Z.Summary })
	local dim = Kit.make("TextButton", root, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = hex("05080E"), BackgroundTransparency = 0.45 })
	local holder = Kit.make("Frame", root, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(580, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local popSc = Instance.new("UIScale")
	popSc.Parent = holder
	local card = Kit.make("CanvasGroup", holder, { Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.Black, BackgroundTransparency = 0.4 })
	Kit.corner(card, 10)
	Kit.stroke(card, C.Outline, 4)
	Kit.list(card, "V", 0)
	local head = Kit.make("Frame", card, { Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = C.White, BackgroundTransparency = 0, LayoutOrder = 1 })
	Kit.studs(head, 24)
	Kit.make("Frame", head, { Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 1, -4), BackgroundColor3 = C.Outline, BackgroundTransparency = 0 })
	local title = Kit.label(head, { TS = 38, Stroke = 4.5, Pos = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 38) })
	local titleSc = Instance.new("UIScale")
	titleSc.Parent = title
	local subL = Kit.label(head, { TS = 13, Stroke = 1.8, Pos = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 14) })
	local rows = Kit.make("Frame", card, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	Kit.pad(rows, 12, 8, 12, 2)
	Kit.list(rows, "V", 5)
	local foot = Kit.make("Frame", card, { Size = UDim2.new(1, 0, 0, 58), LayoutOrder = 3 })
	Kit.pad(foot, 12, 4, 12, 4)
	local rewards = Kit.make("Frame", foot, { AnchorPoint = V2(0, 0.5), Position = UDim2.fromScale(0, 0.5), AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new() })
	Kit.list(rewards, "H", 8, "Left", "Center")
	local cont = Kit.button(foot, { Name = "Continue", Size = UDim2.fromOffset(170, 46), Anchor = V2(1, 0.5), Pos = UDim2.fromScale(1, 0.5), Grad = G.GreenB, Text = "Continue", TS = 24, Stroke = 3, Shine = 3, ShineDelay = 1, HitPad = 0 })
	cont.Activated:Connect(function() self.Continue:Fire() end)

	local function buildRow(parent, d, order, isPlayer)
		local f = Kit.make("Frame", parent, { Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = isPlayer and C.Gold or C.White, BackgroundTransparency = isPlayer and 0.88 or 0.94, LayoutOrder = order })
		Kit.corner(f, 8)
		Kit.stroke(f, C.Outline, 3)
		local av = Kit.make("Frame", f, { Position = UDim2.new(0, 7, 0.5, 0), AnchorPoint = V2(0, 0.5), Size = UDim2.fromOffset(38, 38), BackgroundColor3 = C.White, BackgroundTransparency = 0 })
		Kit.corner(av, UDim.new(0.5, 0))
		Kit.stroke(av, C.Outline, 3)
		if isPlayer then Kit.grad(av, G.Gold) Kit.studs(av, 16, 19) else Kit.grad(av, { hex("FFFFFF"), hex("C9D2DC") }) end
		local lvNum = Kit.label(av, { Text = isPlayer and tostring(d.lv) or "arte", TS = isPlayer and 20 or 12, Stroke = isPlayer and 2.4 or nil, Font = isPlayer and "Title" or "Body", Color = isPlayer and C.White or C.Outline })
		if not isPlayer then
			lvNum.Visible = false
			local image = Portrait.New(d.speciesId, false, d.stage)
			image.Size = UDim2.fromScale(1, 1)
			image.Parent = av
		end
		local nm = Kit.make("Frame", f, { Position = UDim2.fromOffset(52, 4), AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.new() })
		Kit.list(nm, "H", 6, "Left", "Center")
		Kit.label(nm, { Text = isPlayer and "Player EXP" or d.name, TS = 16, Stroke = 2.2, Auto = "XY", Size = UDim2.fromOffset(0, 18), Order = 1 })
		local lvChip, lvText
		if not isPlayer then lvChip, lvText = Kit.chip(nm, "Lv " .. d.lv, { H = 16, TS = 12, PadX = 5, Order = 2 }) end
		local up = Kit.chip(nm, "LEVEL UP!", { H = 16, TS = 12, PadX = 5, Order = 3, Grad = isPlayer and G.Gold or G.GreenB, Color = C.White, Stroke = 1.4 })
		up.Visible = false
		local bar = Kit.bar(f, { Size = UDim2.new(1, -170, 0, 10), Pos = UDim2.fromOffset(52, 25), Grad = isPlayer and G.Yellow or G.Xp, Radius = 5, Border = 2 })
		local note = Kit.label(f, { TS = 12, Font = "Body", Color = hex("B8C2CF"), X = "Left", Pos = UDim2.fromOffset(52, 36), Size = UDim2.new(1, -170, 0, 14) })
		local gain = Kit.label(f, { Text = d.gain > 0 and ("+" .. d.gain .. " XP") or "—", TS = 20, Stroke = 2.4, Color = d.gain > 0 and (isPlayer and C.Gold or C.Xp) or hex("8C8D91"), X = "Right", Anchor = V2(1, 0.5), Pos = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 24) })
		if not isPlayer and not d.part then f.BackgroundTransparency = 0.97 end

		local tot = d.finalXp
		local leveled = d.finalLv > d.lv
		local endPct = d.finalNeed <= 0 and 1 or math.clamp(d.finalXp / d.finalNeed, 0, 1)
		bar:SetPct(d.need <= 0 and 1 or d.xp / d.need)
		note.Text = isPlayer and (d.finalXp .. " / " .. d.finalNeed .. " XP") or (d.part and ((d.fainted and "Fainted · " or "") .. (d.gain > 0 and (tot .. " / " .. d.finalNeed .. " XP") or "No EXP")) or "Didn't battle")
		return {
			step1 = function() bar:SetPct(leveled and 1 or endPct, Theme.T.BarSlow, "Out") end,
			step2 = function()
				if not leveled then return end
				bar:SetPct(0)
				up.Visible = true
				local us = Instance.new("UIScale")
				us.Scale = 0.3
				us.Parent = up
				Motion.tween(us, 0.45, { Scale = 1 }, "Back")
				if lvText then lvText.Text = "Lv " .. d.finalLv end
				if isPlayer then lvNum.Text = tostring(d.finalLv) end
				note.Text = (isPlayer and "Player Lv " or "Lv ") .. d.lv .. " → " .. d.finalLv
			end,
			step3 = function() if leveled then bar:SetPct(endPct, Theme.T.BarSlow, "Out") end end,
			frame = f,
		}
	end

	function self:Show(data)
		self._run += 1
		local run = self._run
		for _, c in ipairs(rows:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		for _, c in ipairs(rewards:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		local h = HEAD[data.result] or HEAD.win
		title.Text, subL.Text = h[1], data.sub or ""
		Kit.grad(head, h[2])
		local built = {}
		for i, r in ipairs(data.rows or {}) do
			if data.result == "win" or data.result == "caught" then r.gain = r.part and (r.gain or 0) or 0 else r.gain = 0 end
			table.insert(built, buildRow(rows, r, i, false))
		end
		if data.player and (data.result == "win" or data.result == "caught") then table.insert(built, buildRow(rows, data.player, 50, true)) end
		for i, w in ipairs(data.rewards or {}) do
			local chip = Kit.make("Frame", rewards, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40), BackgroundColor3 = C.White, BackgroundTransparency = 0.94, LayoutOrder = i })
			Kit.corner(chip, 8)
			Kit.stroke(chip, C.Outline, 3)
			Kit.pad(chip, 5, 0, 10, 0)
			Kit.list(chip, "H", 4, "Left", "Center")
			Kit.icon(chip, w.icon, { Size = UDim2.fromOffset(28, 28), Order = 1 })
			Kit.label(chip, { Text = w.text, TS = 18, Color = w.color or C.White, Stroke = 2.2, Auto = "XY", Size = UDim2.new(), Order = 2 })
		end
		root.Visible = true
		dim.BackgroundTransparency = 1
		Motion.tween(dim, 0.3, { BackgroundTransparency = 0.45 })
		Motion.popIn(popSc, card, 0.45)
		titleSc.Scale = 0.3
		Motion.tween(titleSc, 0.5, { Scale = 1 }, "Back", 0.15)
		local function at(t, key) task.delay(t, function() if run == self._run then for _, b in ipairs(built) do b[key]() end end end) end
		at(0.45, "step1") at(1.45, "step2") at(1.52, "step3")
	end
	function self:Hide() self._run += 1 root.Visible = false end
	self.Root = root
	return self
end

return BattleSummary
