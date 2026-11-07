--!strict
-- Policy-driven preparation only. There are deliberately no default
-- reward, per-friend value, cap or stacking choices. Callers must supply
-- approved values before integrating this with any reward service.

local FriendBoostMath = {}

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

function FriendBoostMath.BonusPercent(
	friendCount: number,
	perFriendPercent: number,
	capPercent: number
): number?
	if
		not finite(friendCount)
		or friendCount < 0
		or friendCount % 1 ~= 0
		or not finite(perFriendPercent)
		or perFriendPercent < 0
		or not finite(capPercent)
		or capPercent < 0
	then
		return nil
	end
	return math.min(friendCount * perFriendPercent, capPercent)
end

-- otherMultiplier comes from the reward's existing authoritative bonuses.
function FriendBoostMath.Apply(
	base: number,
	otherMultiplier: number,
	friendPercent: number,
	stacking: "additive" | "multiplicative"
): number?
	if
		not finite(base)
		or base < 0
		or not finite(otherMultiplier)
		or otherMultiplier < 0
		or not finite(friendPercent)
		or friendPercent < 0
	then
		return nil
	end
	local result: number
	if stacking == "additive" then
		result = base * (otherMultiplier + friendPercent / 100)
	elseif stacking == "multiplicative" then
		result = base * otherMultiplier * (1 + friendPercent / 100)
	else
		return nil
	end
	return if finite(result) then result else nil
end

return FriendBoostMath
