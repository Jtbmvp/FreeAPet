--!nonstrict
-- Presentation adapter only: BattleScreen retains queue, combat intents, camera and VFX.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Shared.Config)
local Progression = require(RS.Shared.ProgressionMath)
local Client = script.Parent.Parent
local Layout = require(Client.DesignUI.Core.Layout)
local BattleHUD = require(Client.DesignUI.Screens.BattleHUD)
local BattleSummary = require(Client.DesignUI.Screens.BattleSummary)
local DesignBattle = {}

local function total(lv, xp, curve)
	local value = xp or 0
	for level = 1, lv - 1 do
		value += curve(level)
	end
	return value
end

function DesignBattle.new()
	local self = {}
	local env = Layout.mount({ Name = "BattleDesign", Order = 11 })
	env.BackdropGui.Enabled = false
	self.HUD = BattleHUD.new(env.Stage)
	self.Summary = BattleSummary.new(env.Stage)
	self.HUD:SetBusy(true)
	self.Summary.Continue:Connect(function()
		self.Summary:Hide()
	end)
	local first, initialPlayer, participants = {}, nil, {}
	local current
	function self:Begin(view)
		first, participants = {}, {}
		for _, pet in view.team or { view.mine } do
			first[pet.id] = table.clone(pet)
		end
		local p = Players.LocalPlayer
		initialPlayer = { level = p:GetAttribute("PlayerLevel"), xp = p:GetAttribute("PlayerXp") }
		self.Summary:Hide()
		self:Refresh(view)
	end
	function self:Refresh(view)
		current = view
		participants[view.mine.id] = true
		local foe = Config.Species[view.wild.speciesId]
		local mine = Config.Species[view.mine.speciesId]
		self.HUD:SetFoe({
			name = view.foeName or foe.displayName,
			lv = view.wild.level,
			hp = view.wild.hp,
			max = math.max(1, view.wild.maxHp),
			tag = view.kind == "wild" and "WILD" or "FOE",
		})
		local pips, team, moves = {}, {}, {}
		for _, pet in view.team or {} do
			table.insert(pips, { alive = pet.hp > 0, active = pet.id == view.mine.id })
			table.insert(team, {
				name = Config.Species[pet.speciesId].displayName,
				lv = pet.level,
				hp = pet.hp,
				max = math.max(1, pet.maxHp),
				active = pet.id == view.mine.id,
			})
		end
		self.HUD:SetMe({
			name = mine.displayName,
			lv = view.mine.level,
			hp = view.mine.hp,
			max = math.max(1, view.mine.maxHp),
			xpPct = view.mine.xpToNext > 0 and view.mine.xp / view.mine.xpToNext or 1,
			pips = pips,
		})
		for _, move in view.mine.moves or {} do
			table.insert(
				moves,
				{ name = move.name, power = move.power, uses = move.usesLeft, max = move.maxUses }
			)
		end
		self.HUD:SetMoves(moves)
		self.HUD:SetTeam(team)
		self.HUD:SetBagCount(view.capsules)
		self.HUD:SetBag(view.capsules, Players.LocalPlayer:GetAttribute("Cash") or 0, view.capsulePrice)
		self.HUD:SetPermissions(view.role ~= "defender", view.kind == "wild")
	end
	function self:SetHp(side, hp, maxHp, instant)
		local foe = side == "wild"
		local bar = foe and self.HUD.FoeHp or self.HUD.MeHp
		bar:SetPct(math.clamp(hp / math.max(1, maxHp), 0, 1), instant and 0 or 0.45, "Out")
		local g = require(Client.DesignUI.Core.Theme).Grad
		local ratio = hp / math.max(1, maxHp)
		bar:SetGrad(ratio > 0.5 and g.HpGood or ratio > 0.2 and g.HpMid or g.HpLow)
		local label = foe and self.HUD.FoeHpText or self.HUD.MeHpText
		label.Text = math.max(0, math.ceil(hp)) .. " / " .. maxHp .. " HP"
	end
	function self:Actions(enabled)
		self.HUD:SetBusy(not enabled)
		if enabled then
			self.HUD:ShowView("menu")
		end
	end
	function self:Show()
		self.HUD:Show()
	end
	function self:Hide()
		self.HUD:Hide()
	end
	function self:Result(view, text)
		local rows = {}
		for _, pet in view.team or { view.mine } do
			local before = first[pet.id] or pet
			local gain = math.max(
				0,
				total(pet.level, pet.xp, Progression.PetXpToNext)
					- total(before.level, before.xp, Progression.PetXpToNext)
			)
			table.insert(rows, {
				speciesId = pet.speciesId,
				stage = Progression.Stage(pet.level).id,
				name = Config.Species[pet.speciesId].displayName,
				lv = before.level,
				xp = before.xp,
				need = before.xpToNext,
				nextNeed = pet.xpToNext,
				finalLv = pet.level,
				finalXp = pet.xp,
				finalNeed = pet.xpToNext,
				gain = gain,
				part = participants[pet.id] == true or gain > 0,
				fainted = pet.hp <= 0,
			})
		end
		local p = Players.LocalPlayer
		local lv, xp = p:GetAttribute("PlayerLevel"), p:GetAttribute("PlayerXp")
		local playerRow
		if initialPlayer and initialPlayer.level and initialPlayer.xp and lv and xp then
			playerRow = {
				lv = initialPlayer.level,
				xp = initialPlayer.xp,
				need = Progression.PlayerXpToNext(initialPlayer.level),
				finalLv = lv,
				finalXp = xp,
				finalNeed = p:GetAttribute("PlayerXpToNext") or 0,
				gain = math.max(
					0,
					total(lv, xp, Progression.PlayerXpToNext)
						- total(initialPlayer.level, initialPlayer.xp, Progression.PlayerXpToNext)
				),
			}
		end
		local outcomes = { won = "win", captured = "caught", ran = "fled", lost = "lose" }
		self.Summary:Show({
			result = outcomes[view.result],
			sub = text,
			rows = rows,
			player = playerRow,
			rewards = {},
		})
	end
	function self:Destroy()
		env.Gui:Destroy()
		env.BackdropGui:Destroy()
	end
	function self:View()
		return current
	end
	return self
end

return DesignBattle
