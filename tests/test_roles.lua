-- Rollensync: mehrere Banns, manueller Discord-Rollenbesitz, Unban.
local root=assert(arg[1])
local handlers, threads, requests = {}, {}, {}
local roles = {['345678901234567890']=false, ['456789012345678901']=true}
local puts, deletes=0,0
local clock=1730000000
os.time=function() return clock end
GetCurrentResourceName=function() return 'aeth_txadmin' end
AddEventHandler=function(n,f) handlers[n]=f end
RegisterCommand=function() end
CreateThread=function(f) threads[#threads+1]=f end
Wait=function() error('__TICK_DONE__') end
GetPlayers=function() return {} end
GetPlayerIdentifiers=function() return {} end
LoadResourceFile=function() return nil end
SaveResourceFile=function() return true end
SetTimeout=function(_,fn) fn() end
json={encode=function(_) return '{}' end,decode=function(body)
    local member=body:match('^MEMBER:(.+)$')
    if member then return {roles=roles[member] and {'234567890123456789'} or {}} end
    return {}
end}
PerformHttpRequest=function(url, callback, method)
    local d=url:match('/members/(%d+)')
    if method=='GET' then callback(200, 'MEMBER:'..d)
    elseif method=='PUT' then roles[d]=true; puts=puts+1;callback(204,'')
    elseif method=='DELETE' then roles[d]=false; deletes=deletes+1;callback(204,'')
    else error(method) end
end
Config={Discord={BotToken='SAMPLE_SECRET',GuildId='123456789012345678',BannedRoleId='234567890123456789'}, BanSync={Enabled=true,CacheLicenseDiscordLinks=true,VerifyMinutes=30}}
dofile(root..'/server/ban_sync.lua')
assert(#threads==1)
local function tick()
  clock=clock+2
  local ok,e=pcall(threads[1]); assert(not ok and tostring(e):find('__TICK_DONE__'),tostring(e))
end
local ban=handlers['txAdmin:events:playerBanned']
local revoke=handlers['txAdmin:events:actionRevoked']
assert(ban and revoke)
ban({actionId='B1', targetIds={'discord:345678901234567890'},expiration=false})
ban({actionId='B2', targetIds={'discord:345678901234567890'},expiration=false})
tick(); assert(roles['345678901234567890'] and puts==1)
revoke({actionId='B1'}); tick(); assert(roles['345678901234567890'] and deletes==0, 'Rolle darf bei weiteren aktiven Banns nicht entfernt werden')
revoke({actionId='B2'}); tick(); assert(not roles['345678901234567890'] and deletes==1, 'Rolle nach letztem Unban entfernen')
ban({actionId='C1', targetIds={'discord:456789012345678901'}, expiration=false})
tick(); assert(roles['456789012345678901'] and puts==1, 'Manuell vergebene Rolle nicht erneut setzen')
revoke({actionId='C1'}); tick(); assert(roles['456789012345678901'] and deletes==1, 'Fremde Rolle nicht entfernen')
print('PASS: Mehrfachbanns, zwei Entbannungen, vorher vorhandene Rolle behalten')
