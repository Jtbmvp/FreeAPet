-- InteriorDoorsClient (StarterPlayerScripts, outside the Client folder): gives the interior door
-- prompts (Workspace.Map.Interiors, parts with the InteriorDoor attribute) the game's own prompt
-- look by mounting Client.Controllers.ProximityPromptRenderer on them (read-only use of the module).
-- If the renderer is missing or fails, the prompt keeps the default Roblox style.
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local scripts = player:WaitForChild("PlayerScripts")

local renderer
task.spawn(function()
	local client = scripts:WaitForChild("Client", 30)
	local controllers = client and client:WaitForChild("Controllers", 30)
	local mod = controllers and controllers:WaitForChild("ProximityPromptRenderer", 30)
	if mod and mod:IsA("ModuleScript") then
		local ok, res = pcall(require, mod)
		if ok then
			renderer = res
		end
	end
end)

local mounted: { [ProximityPrompt]: boolean } = {}

local function isDoorPrompt(inst: Instance): boolean
	return inst:IsA("ProximityPrompt")
		and inst.Parent ~= nil
		and inst.Parent:IsA("BasePart")
		and inst.Parent:GetAttribute("InteriorDoor") ~= nil
end

local function mount(prompt: ProximityPrompt)
	if mounted[prompt] or not renderer then
		return
	end
	local ok, ready = pcall(renderer.Mount, prompt)
	if ok and ready == true then
		mounted[prompt] = true
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Destroying:Connect(function()
			mounted[prompt] = nil
			pcall(renderer.Unmount, prompt)
		end)
	else
		pcall(renderer.Unmount, prompt)
		prompt.Style = Enum.ProximityPromptStyle.Default
	end
end

-- Prompts stream in and out (StreamingEnabled), so mount whenever one is about to be shown.
local ProximityPromptService = game:GetService("ProximityPromptService")
ProximityPromptService.PromptShown:Connect(function(prompt)
	if isDoorPrompt(prompt) and not mounted[prompt] and renderer then
		mount(prompt)
		-- The first Shown fired before the renderer was installed: re-show it once.
		if mounted[prompt] then
			prompt.Enabled = false
			prompt.Enabled = true
		end
	end
end)

-- Mount the ones already present / streamed in, so the very first Shown is ours.
task.spawn(function()
	while not renderer do
		task.wait(0.5)
	end
	local map = workspace:WaitForChild("Map", 60)
	local root = map and map:WaitForChild("Interiors", 60)
	if not root then
		return
	end
	for _, d in root:GetDescendants() do
		if isDoorPrompt(d) then
			mount(d)
		end
	end
	root.DescendantAdded:Connect(function(d)
		task.defer(function()
			if isDoorPrompt(d) then
				mount(d)
			end
		end)
	end)
end)
