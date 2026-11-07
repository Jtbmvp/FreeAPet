--!strict
-- Single owner for unresolved profile operations. No yielding inside mutations.
local Guard = {}
local owners: { [Player]: string } = {}
function Guard.IsBusy(player: Player): boolean
	return owners[player] ~= nil
end
function Guard.Acquire(player: Player, owner: string): boolean
	if owners[player] then
		return false
	end
	owners[player] = owner
	return true
end
function Guard.Release(player: Player, owner: string)
	if owners[player] == owner then
		owners[player] = nil
	end
end
function Guard.Forget(player: Player)
	owners[player] = nil
end
return Guard
