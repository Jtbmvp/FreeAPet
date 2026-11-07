--!nocheck
-- Exercise actual private handlers through registered server remote callbacks.
-- Home/PlayerData adapters isolate orchestration, not graphics or real storage.
local failures = 0
local function result(name, ok, evidence)
	print((if ok then "PASS " else "FAIL ") .. name .. " | " .. evidence)
	if not ok then failures += 1 end
end
local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = copy(v) end
	return out
end
local function setup()
	clock, timestamp = 10, 10000
	delayed, scheduled, remotes = {}, {}, {}
	cache["ServerScriptService.Server.Services.TradeService"] = nil
	local a, b = player(101), player(202)
	Players.list = { a, b }
	local ap = { id="pet-A", ownerUserId=a.UserId, state="InBase", speciesId="AcornSquirrel", level=1, size=1 }
	local bp = { id="pet-B", ownerUserId=b.UserId, state="InBase", speciesId="AcornSquirrel", level=1, size=1 }
	local records = { [ap.id]=ap, [bp.id]=bp }
	local function data(pet)
		return { playerTotalXp=840, animals={ [pet.id]={speciesId=pet.speciesId,level=1,xp=0} }, trades={day=timestamp//86400,count=0} }
	end
	local live = { [a]=data(ap), [b]=data(bp) }
	local durable = { [a]=copy(live[a]), [b]=copy(live[b]) }
	local saves, notices = {}, {}
	mocks["ServerScriptService.Server.Services.PlayerDataService"] = {
		Get=function(p) return live[p] end,
		IsReady=function(p) return live[p] ~= nil end,
		SaveNow=function(p) table.insert(saves,{player=p,snapshot=copy(live[p])}) end,
	}
	mocks["ServerScriptService.Server.Services.AnimalService"] = { Get=function(id) return records[id] end }
	mocks["ServerScriptService.Server.Services.HomeService"] = {
		CanAcquire=function() return true end,
		GiveAway=function(p,r) live[p].animals[r.id]=nil; return true end,
		Receive=function(p,r)
			r.ownerUserId=p.UserId
			live[p].animals[r.id]={speciesId=r.speciesId,level=r.level,xp=0}
			return true
		end,
	}
	mocks["ServerScriptService.Server.Services.NotifyService"] = {
		Send=function(p,n) table.insert(notices,{player=p,notice=n}) end,
	}
	local trade=load("ServerScriptService.Server.Services.TradeService")
	trade.Start()
	local function fire(p,action)
		clock+=0.2
		RemoteAdapter.Get("TradeAction").OnServerEvent:Fire(p,action)
	end
	local function begin()
		RemoteAdapter.Get("TradeRequest").OnServerEvent:Fire(a,b.UserId)
		RemoteAdapter.Get("TradeRespond").OnServerEvent:Fire(b,tostring(a.UserId))
		fire(a,{kind="add",id=ap.id}); fire(b,{kind="add",id=bp.id})
		fire(a,{kind="ready"}); fire(b,{kind="ready"})
		fire(a,{kind="confirm"}); fire(b,{kind="confirm"})
	end
	return {a=a,b=b,live=live,durable=durable,saves=saves,notices=notices,begin=begin,fire=fire,ap=ap,bp=bp}
end

local t=setup()
t.begin()
local finish=delayed[#delayed]
clock+=finish.seconds
finish.fn(table.unpack(finish.args))
local successes=0
for _,v in t.notices do if v.notice.kind=="success" then successes+=1 end end
result("TRADE-SUCCESS-DURABILITY",successes==0,
	`success notifications={successes}; completed durable saves=0; enqueued={#t.saves}`)

local function owners(state,id)
	local n=0
	for _,d in state do if d.animals[id] then n+=1 end end
	return n
end
-- One side writes successfully, the other remains at its pre-trade snapshot.
for _,which in {t.a,t.b} do
	local cut=copy(t.durable) -- player keys must retain identity, so build explicitly
	cut={ [t.a]=copy(t.durable[t.a]), [t.b]=copy(t.durable[t.b]) }
	for _,save in t.saves do if save.player==which then cut[which]=copy(save.snapshot) end end
	local na,nb=owners(cut,t.ap.id),owners(cut,t.bp.id)
	result(`TRADE-CRASH-CUT-{which.UserId}`,na==1 and nb==1,
		`durable owners pet-A={na}, pet-B={nb}; expected exactly one each`)
end
local both={}
for _,save in t.saves do both[save.player]=copy(save.snapshot) end
result("TRADE-BOTH-WRITES-CONTROL",owners(both,t.ap.id)==1 and owners(both,t.bp.id)==1,
	"both profile writes committed in adapter")

-- A repeated confirm changes the visible deadline but not callback version.
t=setup(); t.begin()
local first=delayed[#delayed]
local firstDue=clock+first.seconds
clock+=0.8
t.fire(t.b,{kind="confirm"})
local updates=RemoteAdapter.Get("TradeUpdate").messages
local displayedDue=clock+updates[#updates].value.countdown
clock=firstDue
first.fn(table.unpack(first.args))
result("TRADE-COUNTDOWN-RECONFIRM",#t.saves==0 or clock>=displayedDue,
	`save requests={#t.saves}; first callback={clock}; latest advertised deadline={displayedDue}`)

t=setup()
for _=1,25 do RemoteAdapter.Get("TradeRespond").OnServerEvent:Fire(t.a,"999999") end
result("TRADE-RESPOND-BURST-BOUND",#t.notices<=1,
	`25 same-clock invalid responses emitted {#t.notices} notifications; synthetic abuse guard expectation, no game timing policy inferred`)

print(`Findings failing regression expectations: {failures}`)
assert(failures==0,"Security trade regression expectations failed; see evidence above")
