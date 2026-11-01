--!strict
-- Cinematic battle start (docs/BATTLE-POLISH-PLAN.md §5.1), about 5 s:
-- a wide shot as the ring draws itself, a hero shot of our pet, one of the
-- foe, 3-2-1, FIGHT! and the camera settles over the player's shoulder.
-- A click, tap or gamepad A skips to the end. The short version (Settings,
-- and owners joining to defend, whose turn timer is already running) only
-- does the countdown. Yields until the battle view is ready.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local BattleCamera = require(script.Parent.BattleCamera)
local Common = require(script.Parent.Fx.Common)

local BattleIntro = {}

export type Info = {
	centre: CFrame,
	arena: Instance?,
	mine: Model?,
	foe: Model?,
	mineCard: Common.CardInfo,
	foeCard: Common.CardInfo,
	short: boolean,
}

local SKIP_INPUTS = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

function BattleIntro.Play(info: Info)
	local skipped = false
	local skipConnection = UserInputService.InputBegan:Connect(function(input)
		if SKIP_INPUTS[input.UserInputType] or input.KeyCode == Enum.KeyCode.ButtonA then
			skipped = true
		end
	end)
	-- Waits, unless the player skips: then returns true at once.
	local function sleep(seconds: number): boolean
		local untilTime = os.clock() + seconds
		while os.clock() < untilTime do
			if skipped then
				return true
			end
			task.wait()
		end
		return skipped
	end

	local closeBars = Common.Letterbox()
	Common.Desaturate(0.45, 0.7)
	local showRing = Common.RingReveal(info.arena, 0.55)
	repeat
		if not info.short then
			BattleCamera.Move(BattleCamera.Wide(), 0.6)
			if sleep(0.65) then
				break
			end
			BattleCamera.Move(BattleCamera.Hero(info.mine, 1), 0.35, Enum.EasingStyle.Quad)
			Common.Reveal(info.mine, info.mineCard, "left")
			if sleep(1.3) then
				break
			end
			BattleCamera.Move(BattleCamera.Hero(info.foe, -1), 0.35, Enum.EasingStyle.Quad)
			Common.Reveal(info.foe, info.foeCard, "right")
			if sleep(1.3) then
				break
			end
		end
		BattleCamera.Move(BattleCamera.Approach(1.6), 0.45)
		if Common.Countdown(sleep, function()
			BattleCamera.Punch(-5, 0.2)
		end) then
			break
		end
		Common.FightSlam(info.centre.Position, Config.Battle.arenaRadius)
		task.delay(0.14, BattleCamera.Shake, "medium")
		BattleCamera.Move(BattleCamera.Gameplay(), 0.5)
		sleep(0.45)
	until true
	skipConnection:Disconnect()
	showRing()
	if skipped then
		BattleCamera.Move(BattleCamera.Gameplay(), 0.35)
		task.wait(0.2)
	end
	closeBars()
end

return BattleIntro
