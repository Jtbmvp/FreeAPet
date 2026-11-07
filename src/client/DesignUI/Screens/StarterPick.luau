-- StarterPick: escolha do primeiro pet (3 cartas), confirmação e boas-vindas.
-- SetStarters({ "Starter A", "Starter B", "Starter C" }) — sem stats/raridade (nenhum confirmado).
-- Sinais: Chosen(index, name), Played
local Core = script.Parent.Parent.Core
local Theme = require(Core.Theme)
local Kit = require(Core.Kit)
local Motion = require(Core.Motion)
local Signal = require(Core.Signal)
local Portrait = require(script.Parent.Parent.Parent.UI.PetPortrait)

local C, G, hex = Theme.Colors, Theme.Grad, Theme.hex
local V2 = Vector2.new

local StarterPick = {}

function StarterPick.new(stage)
	local self = { Chosen = Signal.new(), Played = Signal.new(), CloseRequested = Signal.new(), BlockClose = true }
	local root = Kit.make("Frame", stage, { Name = "StarterPick", Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = Theme.Z.Starter })
	self.Root = root
	Kit.label(root, { Text = "Choose your first pet", TS = 34, Stroke = 4.5, Pos = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 40) })
	Kit.label(root, { Text = "Your starter is Neutral and has no biome. Forest is the first biome you'll explore.", TS = 13, Font = "Body", Color = hex("E4E8EE"), Wrap = true, Pos = UDim2.new(0.5, 0, 0, 50), Anchor = V2(0.5, 0), Size = UDim2.fromOffset(520, 34) })
	local row = Kit.make("Frame", root, { Position = UDim2.new(0.5, 0, 0, 92), AnchorPoint = V2(0.5, 0), Size = UDim2.fromOffset(620, 212) })
	Kit.list(row, "H", 20, "Center", "Top")
	local sel, names, cards = nil, {}, {}
	local pending = false
	local bobs = {}

	local choose = Kit.button(root, { Name = "Choose", Size = UDim2.fromOffset(300, 48), Anchor = V2(0.5, 1), Pos = UDim2.new(0.5, 0, 1, -14), Grad = G.Grey, Text = "Pick a pet", TS = 24, Stroke = 3, HitPad = 0 })
	choose:SetOpacity(0.7)

	local function select(i)
		if pending then return end
		sel = i
		for j, c in pairs(cards) do
			local on = j == i
			c.Glow.Visible = on
			c.Ring.Color = on and C.White or C.Outline
			c.Check.Visible = on
			Motion.tween(c.Holder, 0.2, { Position = UDim2.fromOffset(0, on and -8 or 0) })
		end
		choose:SetText("Choose " .. names[i])
		choose:SetGrad(G.GreenB)
		choose:SetOpacity(1)
	end

	function self:SetStarters(list, speciesIds)
		for _, bob in bobs do if bob then bob:Cancel() end end
		table.clear(bobs)
		table.clear(cards)
		sel = nil
		choose:SetText("Pick a pet")
		choose:SetGrad(G.Grey)
		names = list
		for _, c in ipairs(row:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		for i, name in ipairs(list) do
			local slot = Kit.make("Frame", row, { Size = UDim2.fromOffset(190, 212), LayoutOrder = i })
			local holder = Kit.make("Frame", slot, { Size = UDim2.fromScale(1, 1) })
			local glow = Kit.make("Frame", holder, { Position = UDim2.fromOffset(-6, -6), Size = UDim2.new(1, 12, 1, 12), BackgroundColor3 = C.Gold, BackgroundTransparency = 0.45, Visible = false })
			Kit.corner(glow, 14)
			local card = Kit.make("CanvasGroup", holder, { Size = UDim2.new(1, 0, 0, 200), BackgroundColor3 = C.White, BackgroundTransparency = 0 })
			Kit.corner(card, 8)
			Kit.grad(card, { hex("F2EEE6"), hex("D9C9A6") })
			local ring = Kit.stroke(card, C.Outline, 4)
			local strip = Kit.make("Frame", card, { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = C.White, BackgroundTransparency = 0 })
			Kit.grad(strip, G.Neutral)
			Kit.studs(strip, 24)
			Kit.make("Frame", strip, { Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 1, -4), BackgroundColor3 = C.Outline, BackgroundTransparency = 0 })
			Kit.label(strip, { Text = name, TS = 22, Stroke = 2.6, Size = UDim2.new(1, 0, 1, -3) })
			local art = Kit.make("Frame", card, { Position = UDim2.new(0.5, 0, 0, 52), AnchorPoint = V2(0.5, 0), Size = UDim2.fromOffset(104, 100), BackgroundColor3 = C.White, BackgroundTransparency = 0.6 })
			Kit.corner(art, UDim.new(0.46, 0))
			local image = Portrait.New(speciesIds[i], false, "Baby")
			image.Size = UDim2.fromScale(1, 1)
			image.Parent = art
			table.insert(bobs, Motion.loop(art, { Position = UDim2.new(0.5, 0, 0, 44) }, 1.5))
			local tag = Kit.chip(card, "Neutral Starter", { H = 20, TS = 12, PadX = 8, Grad = { C.Sand, C.Sand }, Radius = 6 })
			tag.AnchorPoint, tag.Position = V2(0.5, 1), UDim2.new(0.5, 0, 1, -28)
			Kit.label(card, { Text = "Type: Neutral", TS = 14, Stroke = 2, Pos = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 18) })
			local check = Kit.make("Frame", card, { Position = UDim2.new(1, -8, 0, 44), AnchorPoint = V2(1, 0), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = C.White, BackgroundTransparency = 0, Visible = false })
			Kit.corner(check, UDim.new(0.5, 0))
			Kit.grad(check, G.GreenB)
			Kit.stroke(check, C.Outline, 3)
			Kit.label(check, { Text = "✓", TS = 18, Stroke = 2 })
			local hit = Kit.make("TextButton", card, { Size = UDim2.fromScale(1, 1), ZIndex = 6 })
			hit.Activated:Connect(function() select(i) end)
			hit.Name = "Pick" .. i
			cards[i] = { Holder = holder, Glow = glow, Ring = ring, Check = check, Hit = hit }
			Motion.cardIn(card, (i - 1) * 0.1)
		end
	end

	-- Confirmação
	local dlg = Kit.dialog(root, { Name = "ConfirmStarter", Title = "Choose?", Grad = G.GreenB, Width = 360 })
	Kit.label(dlg.Body, { Text = "You can't change your starter later.", TS = 14, Font = "Body", Color = hex("E4E8EE"), Wrap = true, Size = UDim2.new(1, 0, 0, 36), Order = 1 })
	local br = Kit.make("Frame", dlg.Body, { Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 2 })
	Kit.list(br, "H", 10, "Center", "Center")
	local back = Kit.button(br, { Size = UDim2.new(0.5, -5, 0, 46), Grad = G.Grey, Text = "Back", TS = 20, Order = 1, HitPad = 0 })
	local ok = Kit.button(br, { Name = "Confirm", Size = UDim2.new(0.5, -5, 0, 46), Grad = G.GreenB, Text = "Confirm", TS = 20, Order = 2, HitPad = 0 })
	back.Activated:Connect(function() dlg:Close() end)
	choose.Activated:Connect(function()
		if not sel or pending then return end
		dlg.Title.Text = "Choose " .. names[sel] .. "?"
		dlg:Open()
	end)

	-- Boas-vindas
	local wel = Kit.make("Frame", root, { Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 10 })
	Kit.make("Frame", wel, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = hex("05080E"), BackgroundTransparency = 0.4 })
	local wbox = Kit.make("Frame", wel, { AnchorPoint = V2(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(560, 190) })
	local wsc = Instance.new("UIScale")
	wsc.Parent = wbox
	Kit.label(wbox, { Text = "Welcome to FreeAPet!", TS = 42, Color = C.Gold, Stroke = 5.5, Pos = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 52) })
	local wsub = Kit.label(wbox, { Text = "", TS = 16, Stroke = 2.4, Pos = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 22) })
	local play = Kit.button(wbox, { Name = "Play", Size = UDim2.fromOffset(190, 52), Anchor = V2(0.5, 0), Pos = UDim2.new(0.5, 0, 0, 108), Grad = G.GreenB, Text = "Play", TS = 28, Stroke = 3.4, HitPad = 0 })
	play.Activated:Connect(function() wel.Visible = false self.Played:Fire() end)
	ok.Activated:Connect(function()
		if pending or not sel then return end
		dlg:Close()
		self.Chosen:Fire(sel, names[sel])
	end)
	function self:Welcome(name)
		wsub.Text = name .. " joined your team"
		wel.Visible = true
		wsc.Scale = 0.6
		Motion.tween(wsc, 0.4, { Scale = 1 }, "Back")
	end
	function self:SetPending(value)
		pending = value
		choose:SetEnabled(not value)
		choose:SetText(value and "Saving your starter…" or (sel and ("Choose " .. names[sel]) or "Pick a pet"))
		for _, c in cards do c.Hit.Interactable = not value end
	end
	function self:FirstButton() return cards[1] and cards[1].Hit end

	function self:Open() root.Visible = true end
	function self:Close() root.Visible = false wel.Visible = false end
	return self
end

return StarterPick
