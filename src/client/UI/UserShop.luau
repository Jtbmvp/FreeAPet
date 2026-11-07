--!strict
-- Cash-only prototype. Future products and Codes have no purchase/reward path.
local P = require(script.Parent.HudPrimitives)
local ActionState = require(script.Parent.HudActionState)
local Shop = {}
local function enable(button: GuiButton, value: boolean)
	button.Interactable = value
	button.Active = value
	button.Selectable = value
	button.AutoButtonColor = value
	P.Recolor(button, if value then P.colors.Trade else P.colors.Settings)
end
function Shop.Mount(container: Frame, api: any)
	local selected = "Offers"
	local visible = false
	local alive = true
	local feedback = ""
	local actions = api.Actions
	local tabs = P.Frame(container, "Tabs", nil, 1)
	tabs.Size = UDim2.new(1, 0, 0, 48)
	local offers = P.Frame(container, "Offers", nil, 1)
	offers.Position = UDim2.fromOffset(0, 64)
	offers.Size = UDim2.new(1, 0, 0, 596)
	local card = P.Frame(offers, "PetCapsule", Color3.fromRGB(47, 134, 232))
	P.Round(card)
	P.Stroke(card)
	card.Position = UDim2.fromOffset(8, 0)
	card.Size = UDim2.new(1, -16, 0, 300)
	P.Studs(card)
	local icon = P.Image(card, "petCapsuleDefault")
	icon.Position = UDim2.fromOffset(12, 12)
	icon.Size = UDim2.fromOffset(100, 100)
	local title = P.Text(card, "Title", "Pet Capsule", 24)
	title.Position = UDim2.fromOffset(124, 8)
	title.Size = UDim2.new(1, -136, 0, 36)
	local info = P.Text(card, "Description", "Buy one capsule for a future wild battle.", 16)
	info.TextWrapped = true
	info.TextTruncate = Enum.TextTruncate.None
	info.Position = UDim2.fromOffset(124, 48)
	info.Size = UDim2.new(1, -136, 0, 64)
	local cost = P.Text(card, "Cost", "Loading price…", 18)
	cost.Position = UDim2.fromOffset(12, 118)
	cost.Size = UDim2.new(1, -24, 0, 30)
	local stock = P.Text(card, "Stock", "Owned: —", 16)
	stock.Position = UDim2.fromOffset(12, 148)
	stock.Size = UDim2.new(1, -24, 0, 26)
	local buy, buyText = P.Button(card, "BuyCapsule", "Loading…", P.colors.Settings)
	buy.Position = UDim2.fromOffset(12, 182)
	buy.Size = UDim2.new(1, -24, 0, 48)
	enable(buy, false)
	local statusText = P.Text(card, "Status", "Loading your data…", 14)
	statusText.Position = UDim2.fromOffset(12, 240)
	statusText.Size = UDim2.new(1, -24, 0, 48)
	statusText.TextWrapped = true
	statusText.TextTruncate = Enum.TextTruncate.None
	-- Disabled slots preserve the supplied structure; no SKU, price or activation handler.
	for index = 1, 2 do
		local placeholder = P.Frame(offers, `FutureProduct{index}`, P.colors.panel, 0.12)
		P.Round(placeholder)
		P.Stroke(placeholder)
		placeholder.Position = UDim2.fromOffset(8, 316 + (index - 1) * 140)
		placeholder.Size = UDim2.new(1, -16, 0, 124)
		local productTitle = P.Text(placeholder, "Title", "Product", 20)
		productTitle.Position = UDim2.fromOffset(12, 8)
		productTitle.Size = UDim2.new(1, -24, 0, 28)
		local unavailable = P.Button(placeholder, "Unavailable", "Unavailable", P.colors.Settings)
		unavailable.Position = UDim2.fromOffset(12, 56)
		unavailable.Size = UDim2.new(1, -24, 0, 48)
		enable(unavailable, false)
	end
	local note = P.Text(container, "Availability", "No Cash packs available in this prototype.", 18)
	note.TextWrapped = true
	note.TextTruncate = Enum.TextTruncate.None
	note.Position = UDim2.fromOffset(12, 72)
	note.Size = UDim2.new(1, -24, 0, 112)
	local codes = P.Frame(container, "Codes", nil, 1)
	codes.Position = UDim2.fromOffset(12, 64)
	codes.Size = UDim2.new(1, -24, 0, 264)
	local codeTitle = P.Text(codes, "Title", "# CODES", 26)
	codeTitle.Size = UDim2.new(1, 0, 0, 38)
	local input = Instance.new("TextBox")
	input.Name = "Code"
	input.PlaceholderText = "Codes unavailable"
	input.Text = ""
	input.ClearTextOnFocus = false
	input.TextSize = 18
	input.Font = Enum.Font.FredokaOne
	input.TextColor3 = Color3.new(1, 1, 1)
	input.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	input.Size = UDim2.new(1, 0, 0, 52)
	input.Position = UDim2.fromOffset(0, 54)
	P.Round(input)
	P.Stroke(input)
	input.TextEditable = false
	input.Active = false
	input.Selectable = false
	input.Parent = codes
	local redeem = P.Button(codes, "Redeem", "Unavailable", P.colors.Settings)
	redeem.Size = UDim2.new(1, 0, 0, 48)
	enable(redeem, false)
	redeem.Position = UDim2.fromOffset(0, 124)
	local why =
		P.Text(codes, "Reason", "Codes are not active in this prototype. No rewards are available.", 16)
	why.Position = UDim2.fromOffset(0, 186)
	why.Size = UDim2.new(1, 0, 0, 60)
	why.TextWrapped = true
	why.TextTruncate = Enum.TextTruncate.None
	local function refresh()
		if not alive or not visible then
			return
		end
		codes.Visible = selected == "Codes"
		offers.Visible = selected == "Offers"
		note.Visible = selected == "Cash"
		local snapshot, pending, status = actions.Read()
		local capsule = snapshot and snapshot.capsule
		local valid = type(capsule) == "table"
			and ActionState.Integer(capsule.unitPrice)
			and capsule.unitPrice > 0
			and type(capsule.priceVersion) == "string"
			and #capsule.priceVersion > 0
			and #capsule.priceVersion <= 64
		cost.Text = if valid then `Fixed price: ${capsule.unitPrice} Cash / capsule` else "Loading price…"
		stock.Text = if capsule and ActionState.Integer(capsule.stock)
			then `Owned: {capsule.stock}`
			else "Owned: —"
		local canBuy = valid and capsule.canBuy == true and actions.Ready("buyCapsule")
		enable(buy, canBuy)
		buyText.Text = if pending
			then (if pending.kind == "buyCapsule" then "Checking purchase…" else "Action in progress…")
			elseif canBuy then `Buy 1 · ${capsule.unitPrice} Cash`
			elseif status == "Loading" then "Loading…"
			else "Unavailable"
		statusText.Text = if pending
			then (if pending.phase == "Unknown"
				then ActionState.Message("TIMEOUT")
				else "Waiting for server confirmation…")
			elseif status ~= "Ready" then actions.ErrorText()
			elseif not valid then "Price is currently unavailable."
			elseif capsule.canBuy ~= true then ActionState.Message(capsule.reasonCode or "UNAVAILABLE")
			else feedback
	end
	buy.Activated:Connect(function()
		local snapshot = actions.Read()
		if not visible or not snapshot or not snapshot.capsule or snapshot.capsule.canBuy ~= true then
			return
		end
		if not ActionState.Integer(snapshot.capsule.unitPrice) or snapshot.capsule.unitPrice <= 0 then
			return
		end
		if type(snapshot.capsule.priceVersion) ~= "string" then
			return
		end
		feedback = ""
		actions.Request(
			"buyCapsule",
			{ quantity = 1, priceVersion = snapshot.capsule.priceVersion },
			function(result)
				if not alive then
					return
				end
				feedback = if result.phase == "Committed"
					then "Capsule purchased."
					else ActionState.Message(result.reasonCode)
				if result.phase == "Committed" then
					api.Notify(feedback)
				end
				-- Cash and stock always come from the next authoritative snapshot/attributes.
				actions.Refresh(true)
			end
		)
	end)
	for i, name in { "Offers", "Cash", "Codes" } do
		local b = P.Button(tabs, name, name, P.colors.Shop)
		b.Position = UDim2.new((i - 1) / 3, 4, 0, 0)
		b.Size = UDim2.new(1 / 3, -8, 0, 48)
		b.Activated:Connect(function()
			selected = name
			refresh()
			if api.Resize then
				api.Resize()
			end
		end)
	end
	local unsubscribe = actions.Subscribe(refresh)
	return {
		Show = function()
			visible = true
			refresh()
			actions.Refresh(true)
		end,
		Refresh = refresh,
		ContentHeight = function()
			return if selected == "Offers" then 680 elseif selected == "Codes" then 340 else 220
		end,
		Hide = function()
			visible = false
			input:ReleaseFocus()
		end,
		Destroy = function()
			alive = false
			visible = false
			input:ReleaseFocus()
			unsubscribe()
		end,
	}
end
return Shop
