--!strict
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Format = require(RS.Shared.Format)
local P = require(script.Parent.HudPrimitives)
local Leaderboard = {}
function Leaderboard.Mount(container: Frame, _api: any)
	local visible = false
	local rows = {}
	local list = Instance.new("ScrollingFrame")
	list.Name = "Players"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.Selectable = true
	list.Parent = container
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local function refresh()
		if not visible then
			return
		end
		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			return (a:GetAttribute("IncomePerSecond") or 0) > (b:GetAttribute("IncomePerSecond") or 0)
		end)
		for i, p in players do
			local row = rows[p]
			if not row then
				row = P.Text(list, "Player", "", 18)
				row.Size = UDim2.new(1, -8, 0, 48)
				rows[p] = row
			end
			local level = p:GetAttribute("PlayerLevel")
			local income = p:GetAttribute("IncomePerSecond")
			row.LayoutOrder = i
			row.Text =
				`{p.DisplayName} · Lv {if typeof(level) == "number" then tostring(level) else "—"} · ${if typeof(
						income
					) == "number"
					then Format.Short(income)
					else "—"}/s`
		end
		for p, row in rows do
			if not p.Parent then
				row:Destroy()
				rows[p] = nil
			end
		end
	end
	return {
		Show = function()
			visible = true
			refresh()
		end,
		Refresh = refresh,
		Hide = function()
			visible = false
		end,
	}
end
return Leaderboard
