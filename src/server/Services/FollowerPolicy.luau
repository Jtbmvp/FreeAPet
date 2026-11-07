--!strict
-- The current battle leader is the first equipped pet (BattleService uses
-- the first living member). There is no approved cross-species strength
-- score or tie rule. Keep that decision here; never sort/mutate the roster.

local FollowerPolicy = {}

function FollowerPolicy.Select<T>(team: { T }): T?
	return team[1]
end

return FollowerPolicy
