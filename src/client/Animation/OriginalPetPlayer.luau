--!strict
-- STAGED, not required by PetAnimator/Main. A render-only native-track adapter
-- for an inspected individual original. It never builds/changes the skeleton,
-- moves the gameplay root, chooses stats, or interprets a model ID as a clip.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Contract = require(ReplicatedStorage.Shared.OriginalPets.Contract)

type Variant = Contract.Variant
type Binding = Contract.Binding
export type Player = {
	Ready: (self: Player) -> (boolean, string?),
	SetMotion: (self: Player, moving: boolean, rate: number?) -> boolean,
	PlayOnce: (self: Player, name: string) -> number?,
	Freeze: (self: Player, seconds: number) -> (),
	SetSuspended: (self: Player, value: boolean) -> (),
	Step: (self: Player) -> (),
	Destroy: (self: Player) -> (),
}

local OriginalPetPlayer = {}
local owned: { [Model]: boolean } = setmetatable({}, { __mode = "k" })
local FADE = 0.2
local LOAD_TIMEOUT = 10

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

function OriginalPetPlayer.Attach(model: Model, binding: Binding): (Player?, string?)
	if owned[model] then
		return nil, "Model already has an original-pet player"
	end
	if not model:IsDescendantOf(Workspace) then
		return nil, "Wait until the visual model is in Workspace"
	end
	local variant: Variant? = Contract.Get(binding.variantKey)
	if not variant then
		return nil, "Unknown individual original phase"
	end
	local valid, bindingError = Contract.ValidateBinding(variant, binding)
	if not valid then
		return nil, bindingError
	end
	local animator, rigError = Contract.Inspect(model, variant)
	if not animator then
		return nil, rigError
	end
	if #animator:GetPlayingAnimationTracks() > 0 then
		return nil, "Animator already has another presentation owner"
	end
	owned[model] = true
	local tracks: { [string]: AnimationTrack } = {}
	local animations: { Animation } = {}
	local connections: { RBXScriptConnection } = {}
	local destroyed = false
	local failed: string? = nil
	local motion = "Idle"
	local motionRate = 1
	local once: string? = nil
	local frozenUntil = 0
	local suspended = false
	local startedAt = os.clock()
	local api: Player = {} :: any

	function api:Destroy()
		if destroyed then
			return
		end
		destroyed = true
		once = nil
		owned[model] = nil
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		for _, track in tracks do
			pcall(function()
				track:Stop(0)
				track:Destroy()
			end)
		end
		table.clear(tracks)
		for _, animation in animations do
			animation:Destroy()
		end
		table.clear(animations)
	end

	local function loaded(name: string): boolean
		local track = tracks[name]
		return track ~= nil and track.Length > 0
	end
	function api:Ready(): (boolean, string?)
		if destroyed then
			return false, failed or "Detached"
		end
		if not loaded("Idle") or not loaded("Walk") then
			return false, "Loading native Idle/Walk"
		end
		return true, nil
	end
	local function speedFor(name: string): number
		if suspended or os.clock() < frozenUntil then
			return 0
		end
		return if name == "Walk" then motionRate else 1
	end
	local function applyMotion()
		local ready = api:Ready()
		if not ready or once then
			return
		end
		local other = tracks[if motion == "Idle" then "Walk" else "Idle"]
		if other.IsPlaying then
			other:Stop(FADE)
		end
		local track = tracks[motion]
		if track.IsPlaying then
			track:AdjustSpeed(speedFor(motion))
		else
			track:Play(FADE, 1, speedFor(motion))
		end
	end

	-- Bounded to this ONE model's bound clips; never load/preload the catalog.
	local ok, loadError = pcall(function()
		for name, clipBinding in binding.clips do
			local animation = Instance.new("Animation")
			animation.Name = name
			animation.AnimationId = `rbxassetid://{clipBinding.assetId}`
			table.insert(animations, animation)
			local track = animator:LoadAnimation(animation)
			tracks[name] = track
			track.Looped = name == "Idle" or name == "Walk"
			track.Priority = if name == "Idle"
				then Enum.AnimationPriority.Idle
				elseif name == "Walk" then Enum.AnimationPriority.Movement
				else Enum.AnimationPriority.Action
			table.insert(
				connections,
				track.Ended:Connect(function()
					if not destroyed and once == name then
						once = nil
						applyMotion()
					end
				end)
			)
		end
	end)
	if not ok then
		api:Destroy()
		return nil, `Native animation load failed: {loadError}`
	end

	function api:SetMotion(moving: boolean, rate: number?): boolean
		if destroyed or (rate ~= nil and not finite(rate)) then
			return false
		end
		motion = if moving then "Walk" else "Idle"
		motionRate = math.clamp(rate or 1, 0.5, 3)
		applyMotion()
		local ready = api:Ready()
		return ready
	end
	function api:PlayOnce(name: string): number?
		if destroyed or name == "Idle" or name == "Walk" or not loaded(name) then
			return nil
		end
		local track = tracks[name]
		if once == name and track.IsPlaying then
			return track.Length
		end -- do not restart the same action
		local previous = once
		once = name -- queued Ended from the previous action cannot clear this one
		if previous and tracks[previous] then
			tracks[previous]:Stop(0)
		end
		for _, motionName in { "Idle", "Walk" } do
			if tracks[motionName].IsPlaying then
				tracks[motionName]:Stop(FADE)
			end
		end
		track:Play(FADE, 1, speedFor(name))
		return track.Length
	end
	function api:Freeze(seconds: number)
		if destroyed or not finite(seconds) or seconds < 0 then
			return
		end
		frozenUntil = math.max(frozenUntil, os.clock() + seconds)
		for _, track in tracks do
			if track.IsPlaying then
				track:AdjustSpeed(0)
			end
		end
	end
	function api:SetSuspended(value: boolean)
		if destroyed then
			return
		end
		suspended = value
		for name, track in tracks do
			if track.IsPlaying then
				track:AdjustSpeed(speedFor(name))
			end
		end
	end
	function api:Step()
		if destroyed then
			return
		end
		local ready = api:Ready()
		if not ready and os.clock() - startedAt >= LOAD_TIMEOUT then
			failed = "Native Idle/Walk unavailable after bounded load timeout"
			api:Destroy()
			return
		end
		for name, track in tracks do
			if track.IsPlaying then
				track:AdjustSpeed(speedFor(name))
			end
		end
		applyMotion()
	end

	table.insert(
		connections,
		model.Destroying:Connect(function()
			api:Destroy()
		end)
	)
	table.insert(
		connections,
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(Workspace) then
				api:Destroy()
			end
		end)
	)
	applyMotion()
	return api, nil
end

return OriginalPetPlayer
