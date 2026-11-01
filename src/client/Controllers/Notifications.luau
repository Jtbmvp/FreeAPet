--!strict
-- Toasts at the top centre, stud style; each pops in with a bounce. Each toast shows
-- its icon (notification.icon, else one per kind). Warnings (theft) stay
-- longer and can carry a button, e.g. "Bring home", which sends the request
-- to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local UITheme = require(ReplicatedStorage.Shared.UITheme)

local Notifications = {}

local MAX_VISIBLE = 4
local DURATION = { info = 4, warning = 8, success = 5 }
local KIND_ICON = { info = "info", warning = "warning", success = "success" }
local ICON_SIZE = 48

local list: Frame
local order = 0

local function show(notification: Remotes.Notification)
	local toast = UITheme.Panel(notification.kind)
	toast.Name = "Toast"
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.Size = UDim2.fromScale(1, 0)
	order -= 1
	toast.LayoutOrder = order -- newest on top
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = toast
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = toast

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.Size = UDim2.fromScale(1, 0)
	row.LayoutOrder = 1
	row.ZIndex = 3
	row.Parent = toast

	local icon = UITheme.Icon(notification.icon or KIND_ICON[notification.kind] or "info", ICON_SIZE)
	local textOffset = 0
	if icon then
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.fromScale(0, 0.5)
		icon.ZIndex = 3
		icon.Parent = row
		textOffset = ICON_SIZE + 8
	end

	local text = UITheme.Label(notification.text, 20)
	text.Name = "Text"
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.Position = UDim2.fromOffset(textOffset, 0)
	text.Size = UDim2.new(1, -textOffset, 0, if icon then ICON_SIZE else 0)
	text.TextWrapped = true
	text.ZIndex = 3
	text.Parent = row

	local action = notification.action
	if action then
		local button, buttonText = UITheme.Button("orange", UDim2.fromOffset(270, 46)) -- big enough for a thumb
		button.Name = "Action"
		button.LayoutOrder = 2
		button.ZIndex = 3
		buttonText.Visible = false
		local buttonIcon = UITheme.Icon(
			if action.kind == "defend"
				then "shield"
				elseif action.kind == "trade" then "success"
				else "bringhome",
			34
		)
		if buttonIcon then
			buttonIcon.AnchorPoint = Vector2.new(0, 0.5)
			buttonIcon.Position = UDim2.new(0, 6, 0.5, 0)
			buttonIcon.ZIndex = 4
			buttonIcon.Parent = button
		end
		local buttonLabel = UITheme.Label(action.label, 20)
		buttonLabel.Position = UDim2.fromOffset(if buttonIcon then 20 else 0, 0)
		buttonLabel.Size = UDim2.new(1, if buttonIcon then -20 else 0, 1, 0)
		buttonLabel.ZIndex = 4
		buttonLabel.Parent = button
		button.Parent = toast
		button.Activated:Connect(function()
			if action.kind == "defend" then
				Remotes.Get("DefendBattle"):FireServer(action.animalId)
			elseif action.kind == "trade" then
				Remotes.Get("TradeRespond"):FireServer(action.animalId)
			else
				Remotes.Get("TeleportHome"):FireServer(action.animalId)
			end
			toast:Destroy()
		end)
	end

	toast.Parent = list
	Sfx.Play("notify")
	-- Pop in with a little bounce.
	local enter = Instance.new("UIScale")
	enter.Scale = 0.4
	enter.Parent = toast
	TweenService
		:Create(enter, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()

	-- Keep only the newest few.
	local toasts = {}
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = MAX_VISIBLE + 1, #toasts do
		toasts[index]:Destroy()
	end

	task.delay(DURATION[notification.kind] or 4, function()
		if toast.Parent then
			local shrink =
				TweenService:Create(enter, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Scale = 0 })
			shrink:Play()
			shrink.Completed:Wait()
			toast:Destroy()
		end
	end)
end

function Notifications.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Notifications"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Name = "List"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 56) -- below the exposure bar
	frame.Size = UDim2.fromScale(0.9, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(480, math.huge)
	constraint.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	frame.Parent = gui
	list = frame

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	Remotes.Get("Notify").OnClientEvent:Connect(show)
	Remotes.Get("ClientReady"):FireServer()
end

return Notifications
