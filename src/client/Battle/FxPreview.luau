--!strict
-- Studio test bench for attack effects (docs/VFX-CATALOGUE.md §0): copies
-- two live pets, stands them like in a battle in front of the player, films
-- them with the battle camera and plays one move, without a real battle.
-- From the client command bar in a playtest:
--   require(game.Players.LocalPlayer.PlayerScripts.Client.Battle.FxPreview)
--     .Play("AcornSquirrel", "Acorn Toss", "HoppingMushroom", "super")
-- Works only in Studio. The copies are local and removed afterwards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local BattleCamera = require(script.Parent.BattleCamera)
local Fx = require(script.Parent.Fx)

local FxPreview = {}

local LAYOUT = Config.Battle.layout

-- A local copy of a live pet of this species, cleaned of prompts and labels.
local function copyOf(speciesId: string): Model?
	local animals = Workspace:FindFirstChild("Animals")
	for _, model in (animals and animals:GetChildren() or {}) do
		if model:IsA("Model") and model:GetAttribute("SpeciesId") == speciesId and model.PrimaryPart then
			model.Archivable = true
			local copy = model:Clone()
			for _, item in copy:GetDescendants() do
				if item:IsA("ProximityPrompt") or item:IsA("BillboardGui") then
					item:Destroy()
				end
			end
			return copy
		end
	end
	return nil
end

local function place(model: Model, at: Vector3, lookAt: Vector3)
	local height = model:GetExtentsSize().Y
	local root = model.PrimaryPart :: BasePart
	root.Anchored = true
	model:PivotTo(
		CFrame.lookAt(at + Vector3.new(0, height / 2, 0), Vector3.new(lookAt.X, at.Y + height / 2, lookAt.Z))
	)
	model.Parent = Workspace:FindFirstChild("Animals") or Workspace -- PetAnimator animates pets in Animals
end

local previewEpoch = 0
function FxPreview.Cancel()
	previewEpoch += 1
	Fx.CancelAll()
end
function FxPreview.Play(attackerSpecies: string, move: string, targetSpecies: string?, effect: string?)
	assert(RunService:IsStudio(), "FxPreview only runs in Studio")
	assert(
		not Players.LocalPlayer:GetAttribute("InBattle"),
		"Do not take a participant's active battle camera"
	)
	previewEpoch += 1
	local token = previewEpoch
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	assert(root, "no character")
	local attacker, target = copyOf(attackerSpecies), copyOf(targetSpecies or attackerSpecies)
	local ticket: number? = nil
	local function cancelled(): boolean
		return token ~= previewEpoch
			or Players.LocalPlayer.Character ~= character
			or Players.LocalPlayer:GetAttribute("InBattle") == true
	end
	local ok, problem = xpcall(function()
		assert(attacker and target, "no live pet of that species to copy")
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local ground = root.Position - Vector3.new(0, 3, 0) + look * 14
		local centre = CFrame.lookAt(ground, ground + look)
		local mineAt, foeAt =
			(centre * CFrame.new(LAYOUT.mine)).Position, (centre * CFrame.new(LAYOUT.foe)).Position
		place(attacker, mineAt, foeAt)
		place(target, foeAt, mineAt)
		task.wait(0.3)
		if cancelled() then
			return
		end
		ticket = BattleCamera.Begin(centre, attacker, target)
		BattleCamera.Move(BattleCamera.Gameplay(), 0.4)
		task.wait(0.6)
		Fx.Play({
			attacker = attacker,
			target = target,
			species = attackerSpecies,
			move = move,
			moveType = (Config.Battle.species[attackerSpecies] or { type = "Neutral" }).type,
			effect = effect,
			damage = 23,
			impact = function() end,
			clip = function()
				return nil, nil
			end,
			cancelled = cancelled,
			onBeat = BattleCamera.OnBeat,
		})
	end, debug.traceback)
	if token == previewEpoch then
		Fx.Destroy()
	end
	if attacker then
		attacker:Destroy()
	end
	if target then
		target:Destroy()
	end
	if ticket then
		BattleCamera.Release(0.4, ticket)
	end
	if not ok then
		error(problem, 0)
	end
end
return FxPreview
