-- Beschaedigte state.json darf nicht ueberschrieben / zur Rolle verwendet werden.
local root=assert(arg[1]); local handlers, writes, http, threads = {},0,0,{}
GetCurrentResourceName=function()return'aeth_txadmin'end
LoadResourceFile=function()return '{broken json' end
SaveResourceFile=function()writes=writes+1;return true end
AddEventHandler=function(n,f)handlers[n]=f end
RegisterCommand=function()end
CreateThread=function(f)threads[#threads+1]=f end
GetPlayers=function()return {}end
GetPlayerIdentifiers=function()return {}end
PerformHttpRequest=function()http=http+1 end
json={encode=function()return '{}'end,decode=function()error('bad json')end}
Config={Discord={BotToken='test',GuildId='123456789012345678',BannedRoleId='234567890123456789'},BanSync={Enabled=true,CacheLicenseDiscordLinks=true}}
dofile(root..'/server/ban_sync.lua')
handlers['txAdmin:events:playerBanned']({actionId='B1',targetIds={'discord:345678901234567890'},expiration=false})
for _,fn in ipairs(threads)do fn()end
assert(writes==0 and http==0, 'Korruptes Original muss unangetastet bleiben')
print('PASS: Bei kaputtem Persistenzzustand kein Ueberschreiben, kein Discord-Request')
