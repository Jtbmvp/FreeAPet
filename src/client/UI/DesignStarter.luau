--!nonstrict
-- Supplied StarterPick visuals; the existing starter service owns all grants/saves.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local Input = game:GetService("UserInputService")
local Config = require(RS.Shared.Config)
local Remotes = require(RS.Shared.Remotes)
local Client = script.Parent.Parent
local Layout = require(Client.DesignUI.Core.Layout)
local StarterPick = require(Client.DesignUI.Screens.StarterPick)
local DesignStarter = {}

function DesignStarter.Start()
	local player = Players.LocalPlayer
	local env = Layout.mount({ Name = "StarterChoiceDesign", Order = 60 })
	local picker = StarterPick.new(env.Stage)
	local snapshot, selected, previousFocus
	local key, pending, welcome = "", false, false
	env.Gui.Enabled = false
	local function visible(show)
		if show and not env.Gui.Enabled then
			previousFocus = GuiService.SelectedObject
		elseif not show and env.Gui.Enabled then
			GuiService.SelectedObject = previousFocus and previousFocus.Parent and previousFocus or nil
		end
		env.Gui.Enabled = show
		env.Dim.Visible = show
		env.Dim.BackgroundTransparency = 0.45
		if show then
			picker:Open()
		else
			picker:Close()
		end
	end
	local function render(state)
		if not state then
			return
		end
		snapshot = state
		if welcome then
			return
		end
		local newKey = tostring(state.nextIndex) .. ":" .. table.concat(state.choices, ",")
		if key ~= newKey then
			key = newKey
			local names = {}
			for _, id in state.choices do
				table.insert(names, Config.Species[id] and Config.Species[id].displayName or id)
			end
			picker:SetStarters(names, state.choices)
		end
		pending = state.pending == true
		picker:SetPending(pending)
		visible(state.available == true or (pending and selected ~= nil))
		if env.Gui.Enabled and Input.PreferredInput == Enum.PreferredInput.Gamepad then
			if not GuiService.SelectedObject then
				GuiService.SelectedObject = picker:FirstButton()
			end
		end
	end
	picker.Chosen:Connect(function(index)
		if pending or not snapshot or not snapshot.available then
			return
		end
		local speciesId = snapshot.choices[index]
		if not speciesId then
			return
		end
		selected = speciesId
		pending = true
		picker:SetPending(true)
		Remotes.Get("ChooseStarter"):FireServer(snapshot.nextIndex, speciesId)
	end)
	picker.Played:Connect(function()
		welcome = false
		selected = nil
		visible(false)
		if snapshot then
			render(snapshot)
		end
	end)
	Remotes.Get("StarterResult").OnClientEvent:Connect(function(result)
		if result.phase == "Pending" then
			pending = true
			picker:SetPending(true)
		elseif result.phase == "Committed" then
			local chosen = selected
			pending = false
			if chosen then
				welcome = true
				snapshot = result.snapshot or snapshot
				picker:SetPending(false)
				visible(true)
				picker:Welcome(Config.Species[chosen].displayName)
			else
				render(result.snapshot)
			end
		end
	end)
	while env.Gui.Parent do
		local ok, state = pcall(function()
			return Remotes.GetFunction("GetStarters"):InvokeServer()
		end)
		if ok then
			render(state)
		end
		task.wait(3)
	end
end

return DesignStarter
