--!strict
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GS = game:GetService("GuiService")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Config = require(RS.Shared.Config)
local Remotes = require(RS.Shared.Remotes)
local Format = require(RS.Shared.Format)
local Portrait = require(script.Parent.PetPortrait)
local Data = require(script.Parent.TabletData)
local P = require(script.Parent.HudPrimitives)
local State = require(script.Parent.HudState)
local ActionState = require(script.Parent.HudActionState)
local Layout = require(script.Parent.HudLayout)
local Pets = {}
local function enable(button: GuiButton, value: boolean, color: Color3)
	button.Interactable = value
	button.Active = value
	button.Selectable = value
	button.AutoButtonColor = value
	P.Recolor(button, if value then color else P.colors.Settings)
end
function Pets.Mount(container: Frame, api: any)
	local visible = false
	local selected: string? = nil
	local pets = {}
	local cards = {}
	local pending: any = nil -- existing individual SetEquipped path
	local portraitKey = ""
	local alive = true
	local actions = api.Actions -- shared across Shop/Pets, including after a panel closes
	local sale: any = nil
	local saleVersion = 0
	local feedback = ""
	local refreshing = false
	local refresh: () -> ()
	local updateControls: () -> ()
	local summary = P.Text(container, "Summary", "Loading…", 18)
	summary.Size = UDim2.new(1, -208, 0, 48)
	summary.TextXAlignment = Enum.TextXAlignment.Left
	local best, bestText = P.Button(container, "EquipBest", "Equip Best", P.colors.Trade)
	best.Position = UDim2.new(1, -200, 0, 0)
	best.Size = UDim2.fromOffset(200, 48)
	local statusText = P.Text(container, "ActionStatus", "Loading actions…", 14)
	statusText.Position = UDim2.fromOffset(0, 54)
	statusText.Size = UDim2.new(1, 0, 0, 44)
	statusText.TextWrapped = true
	statusText.TextTruncate = Enum.TextTruncate.None
	statusText.TextXAlignment = Enum.TextXAlignment.Left
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Collection"
	grid.BorderSizePixel = 0
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(0, 104)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ScrollBarThickness = 6
	grid.Parent = container
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(128, 156)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local sheet = P.Frame(container, "Detail", nil, 0.3)
	P.Round(sheet)
	P.Stroke(sheet)
	sheet.Visible = false
	local back = P.Button(sheet, "Back", "Back", P.colors.Settings)
	back.Position = UDim2.fromOffset(8, 8)
	back.Size = UDim2.fromOffset(64, 48)
	local picture = P.Frame(sheet, "Portrait", nil, 1)
	picture.Position = UDim2.fromOffset(8, 62)
	picture.Size = UDim2.fromOffset(80, 80)
	local name = P.Text(sheet, "Name", "", 18)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Position = UDim2.fromOffset(96, 8)
	name.Size = UDim2.new(1, -104, 0, 28)
	local rarity = P.Text(sheet, "Rarity", "", 14)
	rarity.TextXAlignment = Enum.TextXAlignment.Left
	rarity.Position = UDim2.fromOffset(96, 38)
	rarity.Size = UDim2.new(1, -104, 0, 22)
	local xp, fill = P.Bar(sheet, "EXP")
	xp.Position = UDim2.fromOffset(96, 68)
	xp.Size = UDim2.new(1, -112, 0, 12)
	local xpText = P.Text(sheet, "XPText", "", 14)
	xpText.Position = UDim2.fromOffset(96, 84)
	xpText.Size = UDim2.new(1, -104, 0, 22)
	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Stats"
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.Position = UDim2.fromOffset(96, 112)
	rows.Size = UDim2.new(1, -104, 1, -176)
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.CanvasSize = UDim2.new()
	rows.ScrollBarThickness = 6
	rows.Parent = sheet
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = rows
	local fields = {}
	for i, title in { "Strength", "HP", "Stage", "State", "Cash/s", "Original owner", "Caught", "Moves" } do
		local l = P.Text(rows, title, "", 14)
		l.Size = UDim2.new(1, -8, 0, 30)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.LayoutOrder = i
		fields[title] = l
		if title == "Moves" then
			l.TextTruncate = Enum.TextTruncate.None
			l.TextWrapped = true
			l.Size = UDim2.new(1, -8, 0, 110)
		end
	end
	local action, actionText = P.Button(sheet, "TeamAction", "Add to team", P.colors.Trade)
	action.Position = UDim2.new(0, 8, 1, -56)
	action.Size = UDim2.new(0.5, -12, 0, 48)
	local sell, sellText = P.Button(sheet, "Sell", "Sell…", P.colors.Shop)
	sell.Position = UDim2.new(0.5, 4, 1, -56)
	sell.Size = UDim2.new(0.5, -12, 0, 48)
	local confirm = P.Frame(container, "SaleConfirmation", P.colors.panel)
	confirm.Size = UDim2.fromScale(1, 1)
	confirm.Visible = false
	confirm.SelectionGroup = true
	for _, direction in { "Up", "Down", "Left", "Right" } do
		(confirm :: any)[`SelectionBehavior{direction}`] = Enum.SelectionBehavior.Stop
	end
	local question = P.Text(confirm, "Question", "", 18)
	question.TextWrapped = true
	question.TextTruncate = Enum.TextTruncate.None
	local details = Instance.new("ScrollingFrame")
	details.Name = "SaleDetails"
	details.BorderSizePixel = 0
	details.BackgroundTransparency = 1
	details.AutomaticCanvasSize = Enum.AutomaticSize.Y
	details.CanvasSize = UDim2.new()
	details.ScrollBarThickness = 6
	details.ScrollingDirection = Enum.ScrollingDirection.Y
	details.Selectable = true
	details.SelectionOrder = 3
	details.Parent = confirm
	local detailList = Instance.new("UIListLayout")
	detailList.Padding = UDim.new(0, 8)
	detailList.SortOrder = Enum.SortOrder.LayoutOrder
	detailList.Parent = details
	local breakdown = P.Text(details, "Breakdown", "", 16)
	breakdown.TextWrapped = true
	breakdown.TextTruncate = Enum.TextTruncate.None
	breakdown.Size = UDim2.new(1, -8, 0, 44)
	breakdown.AutomaticSize = Enum.AutomaticSize.Y
	breakdown.LayoutOrder = 1
	local caution = P.Text(details, "Consequence", "This removes the pet from your collection.", 16)
	caution.TextWrapped = true
	caution.TextTruncate = Enum.TextTruncate.None
	caution.Size = UDim2.new(1, -8, 0, 44)
	caution.AutomaticSize = Enum.AutomaticSize.Y
	caution.LayoutOrder = 2
	local confirmStatus = P.Text(details, "Status", "", 14)
	confirmStatus.TextWrapped = true
	confirmStatus.TextTruncate = Enum.TextTruncate.None
	confirmStatus.Size = UDim2.new(1, -8, 0, 56)
	confirmStatus.AutomaticSize = Enum.AutomaticSize.Y
	confirmStatus.LayoutOrder = 3
	local cancel, cancelText = P.Button(confirm, "Cancel", "Cancel", P.colors.Settings)
	cancel.Position = UDim2.new(0, 8, 1, -56)
	cancel.Size = UDim2.new(0.5, -12, 0, 48)
	cancel.SelectionOrder = 1
	local commit, commitText = P.Button(confirm, "ConfirmSale", "Check price", P.colors.Shop)
	commit.Position = UDim2.new(0.5, 4, 1, -56)
	commit.Size = UDim2.new(0.5, -12, 0, 48)
	commit.SelectionOrder = 2
	cancel.NextSelectionRight = commit
	commit.NextSelectionLeft = cancel
	cancel.NextSelectionUp = details
	commit.NextSelectionUp = details
	details.NextSelectionDown = cancel
	local function narrow(): boolean
		return container.AbsoluteSize.X < 800
	end
	local function reflow()
		local small = narrow()
		local w = container.AbsoluteSize.X
		local side = if small then w else math.min(440, math.floor(w * 0.43))
		sheet.Position = if small then UDim2.fromOffset(0, 104) else UDim2.new(1, -side, 0, 104)
		sheet.Size = UDim2.new(0, side, 1, -104)
		confirm.Visible = sale ~= nil
		sheet.Visible = selected ~= nil and sale == nil
		back.Visible = small
		grid.Visible = sale == nil and not (small and selected ~= nil)
		best.Visible = sale == nil
		summary.Visible = sale == nil
		statusText.Visible = sale == nil
		grid.Size = UDim2.new(1, if not small and selected then -side - 16 else 0, 1, -104)
		local gridWidth = w - (if not small and selected then side + 16 else 0)
		local available = math.max(112, gridWidth - 8)
		local columns = math.max(1, math.floor((available + 12) / 140))
		local cell = math.floor((available - 12 * (columns - 1)) / columns)
		layout.CellSize = UDim2.fromOffset(cell, 156)
		local dialog = Layout.Confirmation(w, container.AbsoluteSize.Y)
		question.TextSize = if dialog.question.h < 48 then 16 else 18
		P.Place(question, dialog.question)
		P.Place(details, dialog.details)
		P.Place(cancel, dialog.cancel)
		P.Place(commit, dialog.commit)
	end
	local function dismissSale(restoreFocus: boolean)
		if not sale then
			return
		end
		saleVersion += 1
		sale = nil
		reflow()
		if api.PinContent then
			api.PinContent(false)
		end
		if api.Resize then
			api.Resize()
		end
		updateControls()
		if restoreFocus and visible and UIS.PreferredInput == Enum.PreferredInput.Gamepad then
			if sell.Interactable and sheet.Visible then
				GS.SelectedObject = sell
			else
				GS:Select(grid)
			end
		end
	end
	local function pick(id: string?)
		local previous = selected
		selected = id
		portraitKey = ""
		reflow()
		refresh()
		if UIS.PreferredInput == Enum.PreferredInput.Gamepad then
			task.defer(function()
				if not visible or not alive then
					return
				end
				if id then
					GS:Select(sheet)
				elseif previous and cards[previous] then
					GS.SelectedObject = cards[previous]
				else
					GS:Select(grid)
				end
			end)
		end
	end
	local function showPet(pet: any)
		local species = Config.Species[pet.speciesId]
		name.Text = species.displayName
		rarity.Text = `{species.rarity} · Lv {pet.level}`
		local ratio, text = State.Progress(pet.level, pet.xp, pet.xpToNext)
		fill.Size = UDim2.fromScale(ratio, 1)
		xpText.Text = text
		fields.Strength.Text = `Strength: {pet.attack}`
		fields.HP.Text = `HP: {pet.hp} / {pet.maxHp}`
		fields.Stage.Text =
			`Stage: {pet.stage}{if pet.legacyAppearance then " · preserved appearance" else ""}`
		fields.State.Text = `State: {pet.state}`
		fields["Cash/s"].Text = `Cash/s: ${Format.Short(pet.cashPerSecond)}`
		fields["Original owner"].Text =
			`Original owner: {if pet.origin then pet.origin.ownerName else "Unknown"}`
		fields.Caught.Text = if pet.origin
			then `Caught: {pet.origin.place} · {os.date("%d %b %Y", pet.origin.capturedAt)}`
			else "Caught: before records"
		fields.Moves.Text = `Moves:\n{table.concat(pet.moves, "\n")}`
		local key = `{pet.id}:{pet.speciesId}:{pet.stage}`
		if portraitKey ~= key then
			picture:ClearAllChildren()
			local art = Portrait.New(pet.speciesId, nil, pet.stage)
			art.Size = UDim2.fromScale(1, 1)
			art.Parent = picture
			portraitKey = key
		end
	end
	updateControls = function()
		if not alive or not visible then
			return
		end
		local snapshot, busy, status = actions.Read()
		local inBattle = Players.LocalPlayer:GetAttribute("InBattle") == true
		local team = snapshot and snapshot.equipBest
		local canBest = actions.Ready("equipBest")
			and team
			and team.canEquip == true
			and not pending
			and not inBattle
		enable(best, canBest == true, P.colors.Trade)
		bestText.Text = if busy and busy.kind == "equipBest" then "Equipping…" else "Equip Best"
		statusText.Text = if busy
			then (if busy.phase == "Unknown"
				then ActionState.Message("TIMEOUT")
				else "Waiting for server confirmation…")
			elseif pending then "Waiting for team update…"
			elseif status ~= "Ready" then actions.ErrorText()
			elseif feedback ~= "" then feedback
			elseif not snapshot or snapshot.capabilities.equipBest ~= true then ActionState.Message(
				"UNAVAILABLE"
			)
			elseif team and team.canEquip ~= true then ActionState.Message(
				team.reasonCode or "UNAVAILABLE"
			)
			else "Equip Best selects the highest combat power."
		local pet = selected and pets[selected]
		local eligible = pet
			and (pet.state == "InBase" or pet.state == "Following" or pet.state == "Inventory")
		local canTeam = eligible and not pending and not busy and not inBattle and sale == nil
		enable(action, canTeam == true, P.colors.Trade)
		actionText.Text = if pending
			then "Waiting…"
			elseif pet and pet.state == "Following" then "Send home"
			elseif eligible then "Add to team"
			else "Unavailable"
		enable(
			sell,
			pet ~= nil and not pending and not inBattle and sale == nil and actions.Ready("quoteSell"),
			P.colors.Shop
		)
		sellText.Text = "Sell…"
		if not sale then
			return
		end
		local quote = sale.quote
		local valid = ActionState.ValidQuote(quote, sale.id, Workspace:GetServerTimeNow())
		question.Text = if busy and busy.kind == "sellPet"
			then `Checking the sale of {sale.name} (Lv {sale.level}) with the server…`
			elseif
				quote and not valid
			then `Offer expired for {sale.name} (Lv {sale.level}). Check the price again.`
			elseif
				sale.message
				and sale.message ~= ""
				and not busy
			then `{sale.name} (Lv {sale.level}): {sale.message}`
			elseif valid then `Sell {sale.name} (Lv {sale.level}) for ${quote.totalCash} Cash?`
			else `Checking the Cash offer for {sale.name} (Lv {sale.level})…`
		breakdown.Text = if quote
			then `Rarity: ${quote.rarityBase} + level bonus: ${quote.levelBonus}`
			else "The server calculates rarity value and level bonus."
		commitText.Text = if busy
			then "Waiting…"
			elseif valid then `Sell · ${quote.totalCash}`
			else "Check price"
		confirmStatus.Text = if busy
			then (if busy.phase == "Unknown"
				then ActionState.Message("TIMEOUT")
				else "Waiting for server confirmation…")
			elseif status ~= "Ready" then actions.ErrorText()
			elseif quote and not valid then ActionState.Message("QUOTE_EXPIRED")
			elseif sale.message and sale.message ~= "" then sale.message
			elseif not actions.Ready(if valid then "sellPet" else "quoteSell") then ActionState.Message(
				"UNAVAILABLE"
			)
			else ""
		enable(
			commit,
			not pending and not inBattle and actions.Ready(if valid then "sellPet" else "quoteSell"),
			P.colors.Shop
		)
		cancelText.Text = if busy and busy.kind == "sellPet" then "Close" else "Cancel"
		caution.Text = if busy and busy.kind == "sellPet"
			then "Closing this panel does not cancel the sale already sent."
			else "This removes the pet from your collection."
	end
	local function requestQuote()
		if not sale or pending then
			return
		end
		local context = sale
		local version = saleVersion
		context.quote = nil
		context.message = ""
		actions.Request("quoteSell", { petId = context.id }, function(result)
			if not alive or not visible or sale ~= context or saleVersion ~= version then
				return
			end
			if result.phase == "Quoted" then
				context.quote = result.quote
				context.level = result.quote.petLevel
			else
				context.message = ActionState.Message(result.reasonCode)
			end
		end)
	end
	refresh = function()
		if not visible or not alive then
			return
		end
		updateControls()
		if refreshing then
			return
		end
		refreshing = true
		local data = Data.Get()
		refreshing = false
		if not alive or not visible or not container.Parent then
			return
		end
		if not data then
			summary.Text = "Loading pets…"
			return
		end
		local ids = {}
		pets = {}
		for _, pet in data.pets do
			pets[pet.id] = pet
			table.insert(ids, pet.id)
		end
		table.sort(ids)
		for id, card in cards do
			if not pets[id] then
				card:Destroy()
				cards[id] = nil
			end
		end
		if selected and not pets[selected] then
			selected = nil
			portraitKey = ""
		end
		summary.Text = if #ids == 0 then "No pets yet." else `Pets: {#ids}`
		for i, id in ids do
			local pet = pets[id]
			local species = Config.Species[pet.speciesId]
			local card = cards[id]
			if not card then
				card = P.Button(grid, id, "", Config.Rarities[species.rarity].color)
				local chosen = P.Frame(card, "Chosen", nil, 1)
				chosen.Size = UDim2.new(1, -4, 1, -4)
				chosen.Position = UDim2.fromOffset(2, 2)
				P.Round(chosen)
				P.Stroke(chosen, 2, Color3.new(1, 1, 1))
				chosen.Visible = false
				local art = Portrait.New(pet.speciesId, nil, pet.stage)
				art.Position = UDim2.fromOffset(4, 4)
				art.Size = UDim2.new(1, -8, 0, 92)
				art.Parent = card
				local l = card.Label
				l.Position = UDim2.fromOffset(4, 98)
				l.Size = UDim2.new(1, -8, 0, 52)
				l.TextSize = 14
				l.TextWrapped = true
				card.Activated:Connect(function()
					pick(id)
				end)
				cards[id] = card
			end
			local art = card:FindFirstChild("PetPortrait")
			if art and art:IsA("ImageLabel") then
				Portrait.Update(art, pet.speciesId, nil, pet.stage)
			end
			card.LayoutOrder = i
			card.Label.Text = `{species.displayName}\nLv {pet.level} · {pet.state}`
			card.Chosen.Visible = selected == id
		end
		if pending then
			local pet = pets[pending.id]
			if not pet or pet.state ~= pending.state then
				pending = nil
			elseif os.clock() - pending.at > 5 then
				pending = nil
				api.Notify("Could not confirm team change. Refresh before trying again.")
			end
		end
		if selected and pets[selected] then
			showPet(pets[selected])
		end
		reflow()
		updateControls()
	end
	best.Activated:Connect(function()
		local snapshot = actions.Read()
		if
			not visible
			or pending
			or not snapshot
			or not snapshot.equipBest
			or snapshot.equipBest.canEquip ~= true
		then
			return
		end
		feedback = ""
		actions.Request("equipBest", {}, function(result)
			if not alive then
				return
			end
			feedback = if result.phase == "Committed"
				then "Best combat team equipped."
				else ActionState.Message(result.reasonCode)
			if result.phase == "Committed" then
				Data.Invalidate()
				api.Notify(feedback)
			end
			task.spawn(refresh)
		end)
	end)
	sell.Activated:Connect(function()
		local pet = selected and pets[selected]
		if not visible or not pet or pending or not actions.Ready("quoteSell") then
			return
		end
		saleVersion += 1
		sale = { id = pet.id, name = Config.Species[pet.speciesId].displayName, level = pet.level }
		details.CanvasPosition = Vector2.zero
		if api.PinContent then
			api.PinContent(true)
		end
		if api.Resize then
			api.Resize()
		end
		reflow()
		requestQuote()
		updateControls()
		if UIS.PreferredInput == Enum.PreferredInput.Gamepad then
			GS.SelectedObject = cancel
		end
	end)
	commit.Activated:Connect(function()
		if not sale or pending then
			return
		end
		local context = sale
		if not ActionState.ValidQuote(context.quote, context.id, Workspace:GetServerTimeNow()) then
			requestQuote()
			return
		end
		local version = saleVersion
		local quote = context.quote
		actions.Request("sellPet", { petId = context.id, quoteId = quote.quoteId }, function(result)
			if not alive then
				return
			end
			local stillOpen = visible and sale == context and saleVersion == version
			if result.phase == "Committed" then
				feedback = `Sold {context.name} for ${quote.totalCash} Cash.`
				Data.Invalidate()
				api.Notify(feedback)
				if stillOpen then
					dismissSale(false)
				end
			elseif stillOpen then
				context.message = ActionState.Message(result.reasonCode)
				-- Every refusal requires a fresh quote and a new explicit confirmation.
				context.quote = nil
			end
			task.spawn(refresh)
		end)
	end)
	cancel.Activated:Connect(function()
		dismissSale(true)
		updateControls()
	end)
	action.Activated:Connect(function()
		local pet = selected and pets[selected]
		local _, busy = actions.Read()
		if not pet or pending or busy or sale or Players.LocalPlayer:GetAttribute("InBattle") == true then
			return
		end
		if pet.state ~= "InBase" and pet.state ~= "Following" and pet.state ~= "Inventory" then
			return
		end
		pending = { id = pet.id, state = pet.state, at = os.clock() }
		Remotes.Get("SetEquipped"):FireServer(pet.id, pet.state ~= "Following")
		Data.Invalidate()
		updateControls()
	end)
	back.Activated:Connect(function()
		pick(nil)
	end)
	local unsubscribe = actions.Subscribe(updateControls)
	local resize = container:GetPropertyChangedSignal("AbsoluteSize"):Connect(reflow)
	local gridResize = grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(reflow)
	return {
		Show = function()
			visible = true
			Data.Invalidate()
			actions.Refresh(true)
			reflow()
			task.spawn(refresh)
		end,
		Refresh = refresh,
		ContentHeight = function()
			return if sale then 0 else 360
		end,
		RequestClose = function()
			dismissSale(false)
			return true
		end,
		Back = function()
			if sale then
				dismissSale(true)
				updateControls()
				return true
			end
			if selected and narrow() then
				pick(nil)
				return true
			end
			return false
		end,
		Hide = function()
			visible = false
			dismissSale(false)
		end,
		Destroy = function()
			alive = false
			visible = false
			saleVersion += 1
			unsubscribe()
			resize:Disconnect()
			gridResize:Disconnect()
		end,
	}
end
return Pets
