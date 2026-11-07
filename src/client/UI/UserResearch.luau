--!strict
-- Desktop retains the functional hex tree; phones reflow to readable node cards, not a tiny canvas.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(RS.Shared.Config)
local Remotes = require(RS.Shared.Remotes)
local Math = require(RS.Shared.ResearchMath)
local Progression = require(RS.Shared.ProgressionMath)
local Format = require(RS.Shared.Format)
local P = require(script.Parent.HudPrimitives)
local Legacy = require(script.Parent.ResearchTab)
local Research = {}
function Research.Mount(container: Frame, _api: any)
	local player = Players.LocalPlayer
	local visible = false
	local selected = "IncomeBoost"
	local compact = false
	local desktop = P.Frame(container, "DesktopTree", nil, 1)
	desktop.Size = UDim2.fromScale(1, 1)
	local legacy = Legacy.Mount(desktop)
	local phone = P.Frame(container, "CompactTree", nil, 1)
	phone.Size = UDim2.fromScale(1, 1)
	phone.Visible = false
	local hint = P.Text(phone, "Hint", "Choose an upgrade", 16)
	hint.Size = UDim2.new(1, 0, 0, 24)
	local nodes = P.Frame(phone, "Nodes", nil, 1)
	nodes.Position = UDim2.fromOffset(0, 32)
	nodes.Size = UDim2.new(1, 0, 0, 188)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -6, 0, 56)
	grid.CellPadding = UDim2.fromOffset(12, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = nodes
	local detail = P.Frame(phone, "Details", nil, 0.15)
	detail.Position = UDim2.fromOffset(0, 232)
	detail.Size = UDim2.new(1, 0, 0, 252)
	P.Round(detail)
	P.Stroke(detail)
	local title = P.Text(detail, "Title", "", 20)
	title.Position = UDim2.fromOffset(12, 8)
	title.Size = UDim2.new(1, -24, 0, 30)
	local description = P.Text(detail, "Description", "", 16)
	description.Position = UDim2.fromOffset(12, 42)
	description.Size = UDim2.new(1, -24, 0, 64)
	description.TextWrapped = true
	description.TextTruncate = Enum.TextTruncate.None
	local reason = P.Text(detail, "Requirement", "", 16)
	reason.Position = UDim2.fromOffset(12, 112)
	reason.Size = UDim2.new(1, -24, 0, 64)
	reason.TextWrapped = true
	reason.TextTruncate = Enum.TextTruncate.None
	local action, label = P.Button(detail, "StartResearch", "Research", P.colors.Research)
	action.Position = UDim2.fromOffset(12, 190)
	action.Size = UDim2.new(1, -24, 0, 48)
	local buttons = {}
	local eligible = false
	local pendingAt: number? = nil
	local function snapshot()
		local progress = {}
		local active = player:GetAttribute("ResearchActive")
		local finish = player:GetAttribute("ResearchFinishesAt")
		for id in Config.Research do
			local rank = player:GetAttribute(`Research_{id}`)
			local entry: any = { level = if typeof(rank) == "number" then rank else 0 }
			if active == id and typeof(finish) == "number" then
				entry.activeLevel = entry.level + 1
				entry.finishesAt = finish
			end
			progress[id] = entry
		end
		return progress, math.floor(Workspace:GetServerTimeNow())
	end
	local function refresh()
		if not visible or not compact then
			return
		end
		local progress, now = snapshot()
		local node = Config.Research[selected]
		if not node then
			return
		end
		local rank = Math.LevelOf(progress, selected, now)
		local nextRank = node.levels[rank + 1]
		local active = Math.Active(progress, now)
		local pl = player:GetAttribute("PlayerLevel")
		local required = Progression.ResearchLevel(selected, rank + 1)
		local money = player:GetAttribute("Cash")
		local ready = player:GetAttribute("DataLoaded") == true and typeof(pl) == "number"
		for id, b in buttons do
			local current = Math.LevelOf(progress, id, now)
			b.Label.Text = `{Config.Research[id].displayName} · {current}/{#Config.Research[id].levels}`
		end
		title.Text = `{node.displayName} · {rank}/{#node.levels}`
		description.Text = Math.Describe(selected, rank)
		eligible = false
		if pendingAt and (active or os.clock() - pendingAt > 4) then
			pendingAt = nil
		end
		if not ready then
			label.Text = "Loading…"
			reason.Text = "Waiting for your progress."
		elseif not nextRank then
			label.Text = "MAX"
			reason.Text = "Fully researched."
		elseif pl < required then
			label.Text = `Player Lv {required}`
			reason.Text = `Reach player level {required} for this rank.`
		elseif not Math.IsUnlocked(progress, selected, now) then
			label.Text = "Locked"
			reason.Text = "Research a neighbouring upgrade first."
		elseif active then
			label.Text = "Researching…"
			reason.Text = `Active: {Config.Research[active].displayName}`
		elseif pendingAt then
			label.Text = "Waiting for server…"
			reason.Text = "Checking your research request."
		elseif typeof(money) ~= "number" or money < nextRank.cost then
			label.Text = `Research ${Format.Short(nextRank.cost)}`
			reason.Text = "Not enough Cash."
		else
			eligible = true
			label.Text = `Research ${Format.Short(nextRank.cost)}`
			reason.Text = `Player Lv {required} · {Format.Duration(
				Math.Duration(progress, selected, rank + 1, now)
			)} · continues offline`
		end
		P.Recolor(action, if eligible then P.colors.Research else P.colors.Settings)
	end
	local ids = {}
	for id in Config.Research do
		table.insert(ids, id)
	end
	table.sort(ids)
	for i, id in ids do
		local b = P.Button(nodes, id, Config.Research[id].displayName, P.colors.Research)
		b.LayoutOrder = i
		buttons[id] = b
		b.Label.TextSize = 14
		b.Activated:Connect(function()
			selected = id
			refresh()
		end)
	end
	action.Activated:Connect(function()
		refresh()
		if eligible then
			pendingAt = os.clock()
			Remotes.Get("StartResearch"):FireServer(selected)
			refresh()
		end
	end)
	local function reflow()
		local small = container.AbsoluteSize.X < 800
		local changed = compact ~= small
		compact = small
		desktop.Visible = not compact
		phone.Visible = compact
		if changed and visible then
			if compact then
				legacy.Hide()
				refresh()
			else
				legacy.Show()
			end
		end
	end
	local connection = container:GetPropertyChangedSignal("AbsoluteSize"):Connect(reflow)
	return {
		Show = function()
			visible = true
			reflow()
			if compact then
				refresh()
			else
				legacy.Show()
			end
		end,
		Refresh = refresh,
		Hide = function()
			visible = false
			legacy.Hide()
		end,
		Destroy = function()
			visible = false
			connection:Disconnect()
			if legacy.Destroy then
				legacy.Destroy()
			end
		end,
	}
end
return Research
