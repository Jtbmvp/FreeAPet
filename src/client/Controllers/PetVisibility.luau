--!strict
-- "Show pets" (HUD toggle): when off, other players' pets that sit in their
-- bases or follow them are hidden on this client only (parts, labels and
-- prompts). Wild and loose pets always show, because those are the ones you
-- play with. Reads the "OwnerUserId" and "State" attributes the server sets.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PetVisibility = {}

local HIDDEN_STATES = { InBase = true, Following = true }

local shown = true
local started = false
local switches: { [Instance]: boolean } = {} -- labels and prompts: Enabled before hiding
local watched: { [Model]: RBXScriptConnection } = {}

local function shouldHide(model: Model): boolean
	local owner = model:GetAttribute("OwnerUserId")
	local state = model:GetAttribute("State")
	return not shown
		and typeof(owner) == "number"
		and owner ~= Players.LocalPlayer.UserId
		and typeof(state) == "string"
		and HIDDEN_STATES[state] == true
end

local function apply(model: Model)
	local hide = shouldHide(model)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.LocalTransparencyModifier = if hide then 1 else 0
		elseif item:IsA("BillboardGui") or item:IsA("ProximityPrompt") then
			if hide and switches[item] == nil then
				switches[item] = item.Enabled
				item.Enabled = false
			elseif not hide and switches[item] ~= nil then
				item.Enabled = switches[item]
				switches[item] = nil
			end
		end
	end
end

local function watch(child: Instance)
	if not child:IsA("Model") or watched[child] then
		return
	end
	watched[child] = child.AttributeChanged:Connect(function(name)
		if name == "State" or name == "OwnerUserId" then
			apply(child)
		end
	end)
	task.defer(apply, child) -- after its parts stream in
end

local function start()
	if started then
		return
	end
	started = true
	local animals = Workspace:WaitForChild("Animals")
	animals.ChildAdded:Connect(watch)
	animals.ChildRemoved:Connect(function(child)
		local connection = watched[child :: Model]
		if connection then
			connection:Disconnect()
			watched[child :: Model] = nil
		end
	end)
	for _, child in animals:GetChildren() do
		watch(child)
	end
end

function PetVisibility.SetShown(value: boolean)
	shown = value
	start()
	for model in watched do
		apply(model)
	end
end

function PetVisibility.IsShown(): boolean
	return shown
end

return PetVisibility
