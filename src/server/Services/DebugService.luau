--!strict
-- QA chat commands, only in Studio with Config.Debug.enabled (never in the
-- published game: the commands are not even created there).
--   /givepet <speciesId> [level]  a new pet in your base (saved)
--   /reset                        force the day reset
--   /battles on|off               turn battles on or off in this server

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local AnimalService = require(script.Parent.AnimalService)
local BattleService = require(script.Parent.BattleService)
local DayCycleService = require(script.Parent.DayCycleService)
local HomeService = require(script.Parent.HomeService)
local NotifyService = require(script.Parent.NotifyService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local DebugService = {}

local function reply(player: Player, text: string)
	NotifyService.Send(player, { text = text, kind = "info", icon = "info" })
end

local function givePet(player: Player, args: { string })
	local speciesId = args[1]
	local species = speciesId and Config.Species[speciesId]
	if not species then
		reply(player, `Unknown species. Try: /givepet <speciesId> [level]`)
		return
	end
	if not PlayerDataService.IsReady(player) or not HomeService.CanAcquire(player) then
		reply(player, "Your save is loading or your reserve is full.")
		return
	end
	local record = if species.starter
		then AnimalService.Restore(
			game:GetService("HttpService"):GenerateGUID(false),
			{ speciesId = speciesId, size = 1, slot = 0, level = 1, xp = 0, location = "Inventory" },
			player.UserId
		)
		else AnimalService.SpawnWild(species.biome :: string, speciesId)
	if not record then
		reply(player, `Could not spawn {speciesId} (no spawn area).`)
		return
	end
	local level = tonumber(args[2])
	if level then
		record.level = math.clamp(math.floor(level), 1, Config.Battle.maxLevel)
	end
	record.origin = {
		ownerUserId = player.UserId,
		ownerName = player.DisplayName,
		capturedAt = os.time(),
		place = "Debug",
	}
	AnimalService.Rescale(record)
	if HomeService.Receive(player, record) then
		HomeService.SaveCaught(player, record)
		reply(player, `Gave you a {species.displayName} (Lv {record.level}).`)
	else
		AnimalService.Remove(record)
		reply(player, "Your base is full.")
	end
end

local COMMANDS: { [string]: (Player, { string }) -> () } = {
	givepet = givePet,
	reset = function(player)
		DayCycleService.ForceReset()
		reply(player, "Day reset forced.")
	end,
	battles = function(player, args)
		local value = args[1] == "on"
		if args[1] ~= "on" and args[1] ~= "off" then
			reply(player, "Use /battles on or /battles off.")
			return
		end
		BattleService.SetEnabled(value)
		reply(player, `Battles {if value then "on" else "off"} in this server.`)
	end,
}

function DebugService.Start()
	if not (RunService:IsStudio() and Config.Debug.enabled) then
		return
	end
	for name, handler in COMMANDS do
		local command = Instance.new("TextChatCommand")
		command.Name = `Debug_{name}`
		command.PrimaryAlias = `/{name}`
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if not player then
				return
			end
			local args = {}
			for word in string.gmatch(text, "%S+") do
				table.insert(args, word)
			end
			table.remove(args, 1) -- the command itself
			local ok, err = pcall(handler, player, args)
			if not ok then
				warn(`[DebugService] /{name} failed: {err}`)
			end
		end)
		command.Parent = TextChatService
	end
	print("[DebugService] QA commands: /givepet <speciesId> [level], /reset, /battles on|off")
end

return DebugService
