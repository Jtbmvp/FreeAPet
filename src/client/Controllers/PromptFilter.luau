--!strict
-- Client-side prompt tweaks, purely cosmetic (the server checks everything):
--   * Owner-only prompts (Pick up, Equip, Send home) are shown only to the owner.
--   * Catch prompts on someone else's loose animal read "Steal".

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PromptFilter = {}

local function ownerOf(prompt: ProximityPrompt): number?
	local model = prompt:FindFirstAncestorOfClass("Model")
	local owner = model and model:GetAttribute("OwnerUserId")
	return if typeof(owner) == "number" then owner else nil
end

local function filter(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local me = Players.LocalPlayer.UserId
	if prompt:GetAttribute("OwnerUserId") ~= nil then
		-- Owner-only prompts: Pick up, Equip, Send home.
		prompt.Enabled = prompt:GetAttribute("OwnerUserId") == me
	elseif prompt.Name == "CatchPrompt" then
		local owner = ownerOf(prompt)
		prompt.ActionText = if owner and owner ~= me
			then "Steal"
			elseif not owner and Workspace:GetAttribute("BattlesEnabled") then "Battle"
			else "Catch"
	end
end

function PromptFilter.Start()
	local animals = Workspace:WaitForChild("Animals")
	animals.DescendantAdded:Connect(filter)
	for _, descendant in animals:GetDescendants() do
		filter(descendant)
	end
	-- Ownership changes when a thief deposits an animal: refresh its prompts.
	animals.ChildAdded:Connect(function(model)
		model:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			for _, descendant in model:GetDescendants() do
				filter(descendant)
			end
		end)
	end)
end

return PromptFilter
