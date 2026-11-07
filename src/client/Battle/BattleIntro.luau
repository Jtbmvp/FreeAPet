--!strict
-- Cancellable fitted shots; BattleCamera owns every camera write.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local Config = require(ReplicatedStorage.Shared.Config)
local Camera = require(script.Parent.BattleCamera)
local Settings = require(script.Parent.BattleSettings)
local Common = require(script.Parent.Fx.Common)
local Intro = {}
export type Info = {
	centre: CFrame,
	arena: Instance?,
	mine: Model?,
	foe: Model?,
	mineCard: Common.CardInfo,
	foeCard: Common.CardInfo,
	short: boolean,
	cancelled: (() -> boolean)?,
}
function Intro.Play(info: Info): boolean
	local skipped = false
	local initialReduced = Settings.reducedMotion
	local function aborted(): boolean
		return info.cancelled ~= nil and info.cancelled()
	end
	local input = Input.InputBegan:Connect(function(key)
		if
			key.UserInputType == Enum.UserInputType.MouseButton1
			or key.UserInputType == Enum.UserInputType.Touch
			or key.KeyCode == Enum.KeyCode.ButtonA
		then
			skipped = true
		end
	end)
	local function sleep(seconds: number): boolean
		local deadline = os.clock() + seconds
		while os.clock() < deadline do
			if not initialReduced and Settings.reducedMotion then
				skipped = true
			end
			if skipped or aborted() then
				return true
			end
			task.wait()
		end
		return skipped or aborted()
	end
	local closeBars: () -> () = function() end
	local showRing: () -> () = function() end
	local ok, problem = xpcall(function()
		if aborted() then
			return
		end
		if not Settings.reducedMotion then
			closeBars = Common.Letterbox()
			Common.Desaturate(0.45, 0.7)
			showRing = Common.RingReveal(info.arena, 0.55)
		end
		repeat
			if not info.short and not Settings.reducedMotion then
				Camera.Move(Camera.Wide(), 0.6)
				if sleep(0.65) then
					break
				end
				Camera.Move(Camera.Hero(info.mine, 1), 0.35, Enum.EasingStyle.Quad)
				Common.Reveal(info.mine, info.mineCard, "left")
				if sleep(1.3) then
					break
				end
				Camera.Move(Camera.Hero(info.foe, -1), 0.35, Enum.EasingStyle.Quad)
				Common.Reveal(info.foe, info.foeCard, "right")
				if sleep(1.3) then
					break
				end
			end
			if aborted() then
				break
			end
			Camera.Move(Camera.Approach(1.6), 0.45)
			if
				Common.Countdown(sleep, function()
					if not Settings.reducedMotion then
						Camera.Punch(-5, 0.2)
					end
				end, Settings.reducedMotion)
			then
				break
			end
			if not Settings.reducedMotion then
				Common.FightSlam(info.centre.Position, Config.Battle.arenaRadius, aborted)
				Camera.Shake("medium")
			end
			Camera.Move(Camera.Gameplay(), 0.5)
			sleep(0.45)
		until true
	end, debug.traceback)
	input:Disconnect()
	pcall(showRing)
	pcall(closeBars)
	if not ok then
		warn("[BattleIntro] " .. tostring(problem))
	end
	if aborted() then
		return false
	end
	Camera.Move(Camera.Gameplay(), if skipped then 0.2 else 0.35)
	return true
end
return Intro
