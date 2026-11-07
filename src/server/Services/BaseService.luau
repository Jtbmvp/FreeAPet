--!strict
-- Assigns one base plot per player, spawns them there and frees it on leave.
-- Plots are read from Workspace.Map.Bases (built in Studio), never hardcoded.

local Players = game:GetService("Players")

local BaseService = {}

local plotsFolder: Instance? = nil
local ownerByPlot: { [Model]: Player } = {}
local plotByPlayer: { [Player]: Model } = {}

local function sortedPlots(): { Model }
	local plots = {}
	if not plotsFolder then
		return plots
	end
	for _, child in plotsFolder:GetChildren() do
		if child:IsA("Model") then
			table.insert(plots, child)
		end
	end
	table.sort(plots, function(a, b)
		return (a:GetAttribute("PlotIndex") :: number) < (b:GetAttribute("PlotIndex") :: number)
	end)
	return plots
end

-- The sign at the plot entrance (Plot.Sign, a SurfaceGui on the map's sign
-- board) shows "<DisplayName>'s Base", or "Free Base" while nobody owns it.
local function setOwnerLabel(plot: Model, player: Player?)
	local sign = plot:FindFirstChild("Sign")
	local label = sign and sign:FindFirstChild("Label", true)
	if not label or not label:IsA("TextLabel") then
		warn(`[BaseService] {plot.Name} has no Sign with a Label`)
		return
	end
	label.Text = if player then `{player.DisplayName}'s Base` else "Free Base"
end

local function spawnAtPlot(player: Player, character: Model)
	local plot = plotByPlayer[player]
	if not plot then
		return
	end
	local spawn = plot:FindFirstChild("Spawn") :: BasePart
	-- Wait one frame so the default spawn does not override our position.
	task.defer(function()
		if character.Parent then
			character:PivotTo(spawn.CFrame * CFrame.new(0, 4, 0))
		end
	end)
end

local function onPlayerAdded(player: Player)
	for _, plot in sortedPlots() do
		if not ownerByPlot[plot] then
			ownerByPlot[plot] = player
			plotByPlayer[player] = plot
			plot:SetAttribute("OwnerUserId", player.UserId)
			player:SetAttribute("PlotIndex", plot:GetAttribute("PlotIndex"))
			setOwnerLabel(plot, player)
			break
		end
	end
	if not plotByPlayer[player] then
		warn(`[BaseService] No free plot for {player.Name}; set Max Players to the number of plots.`)
	end

	player.CharacterAdded:Connect(function(character)
		spawnAtPlot(player, character)
	end)
	if player.Character then
		spawnAtPlot(player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local plot = plotByPlayer[player]
	if plot then
		ownerByPlot[plot] = nil
		plotByPlayer[player] = nil
		plot:SetAttribute("OwnerUserId", nil)
		setOwnerLabel(plot, nil)
	end
end

function BaseService.GetPlot(player: Player): Model?
	return plotByPlayer[player]
end

-- Slot pads of a plot, ordered by SlotIndex, limited to the player's slot count.
function BaseService.GetSlots(plot: Model, slotCount: number): { BasePart }
	local slots = {}
	local folder = plot:FindFirstChild("Slots")
	if folder then
		for _, pad in folder:GetChildren() do
			if pad:IsA("BasePart") and (pad:GetAttribute("SlotIndex") :: number) <= slotCount then
				table.insert(slots, pad)
			end
		end
	end
	table.sort(slots, function(a, b)
		return (a:GetAttribute("SlotIndex") :: number) < (b:GetAttribute("SlotIndex") :: number)
	end)
	return slots
end

-- The area inside a plot where its animals wander.
function BaseService.GetPetArea(plot: Model): BasePart?
	local area = plot:FindFirstChild("PetArea")
	return if area and area:IsA("BasePart") then area else nil
end

function BaseService.GetPlotOwner(plot: Model): Player?
	return ownerByPlot[plot]
end

function BaseService.Start()
	-- Timeouts so a missing map piece warns instead of stalling every later service.
	local map = workspace:WaitForChild("Map", 10)
	plotsFolder = map and map:WaitForChild("Bases", 5)
	if not plotsFolder then
		warn("[BaseService] Workspace.Map.Bases not found: players get no base")
	end
	for _, plot in sortedPlots() do
		setOwnerLabel(plot, nil)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return BaseService
