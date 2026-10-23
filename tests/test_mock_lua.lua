-- Offline-FiveM-Lua-Mock: bestaetigt Eventregistrierung, Webhookversand und Bannrolle.
local root = assert(arg[1], 'Resourcepfad fehlt')
local handlers, commands, threads, requests, writes = {}, {}, {}, {}, {}
GetCurrentResourceName = function() return 'aeth_txadmin' end
AddEventHandler = function(name, fn) handlers[name]=handlers[name] or {}; table.insert(handlers[name],fn) end
RegisterCommand = function(name, fn) commands[name]=fn end
CreateThread = function(fn) threads[#threads+1] = fn end
Wait = function() error('__TEST_STOP__') end
LoadResourceFile = function() return nil end
SaveResourceFile = function(resource, file, content) writes[file]=content; return true end
GetPlayers = function() return {} end
GetPlayerIdentifiers = function() return {} end
SetTimeout = function(delay, fn) fn() end
json = {
    encode = function(data)
        if data.embeds and data.embeds[1] then
            return data.embeds[1].title
        end
        return 'MOCK_JSON'
    end,
    decode = function(text) return {roles={}} end
}
PerformHttpRequest = function(url, callback, method, body, hdrs)
    requests[#requests+1] = {url=url,method=method,body=body,headers=hdrs}
    if url:match('/api/webhooks/') then
        callback(204, '')
    elseif method=='GET' then callback(200,'{"roles":[]}')
    else callback(204,'') end
end

dofile(root..'/config.lua')
Config.Discord.BotToken='SAMPLE_BOT_SECRET'
Config.Logs.Webhooks.Allgemein='https://discord.com/api/webhooks/123456789012345678/abcdefghijklmnopqrstuvwxyz_TEST'
dofile(root..'/server/logger.lua')
dofile(root..'/server/ban_sync.lua')
dofile(root..'/server/relay_settings.lua')
local expected = {
 'announcement','serverShuttingDown','scheduledRestart','scheduledRestartSkipped','playerBanned',
 'playerDirectMessage','playerHealed','playerKicked','playerWarned','whitelistPlayer',
 'whitelistPreApproval','whitelistRequest','actionRevoked','adminAuth','adminsUpdated',
 'configChanged','consoleCommand'
}
for _,event in ipairs(expected) do
    assert(type(handlers['txAdmin:events:'..event])=='table', event)
end
assert(#expected==17)
assert(type(commands.aeth_txadmin_logs_status)=='function')
assert(type(commands.aeth_txadmin_bans_status)=='function')
assert(writes['data/relay_settings.json']=='MOCK_JSON')
for _,fn in ipairs(handlers['txAdmin:events:adminAuth']) do fn({username='admin1', netid=12, isAdmin=true}) end
for _,fn in ipairs(handlers['txAdmin:events:playerBanned']) do fn({author='admin1',targetName='p', actionId=42,
 targetIds={'discord:345678901234567890'},expiration=false,reason='Test'}) end
assert(writes['data/state.json']=='MOCK_JSON')
for _,fn in ipairs(threads) do
   local ok,err=pcall(fn)
   assert(not ok and tostring(err):find('__TEST_STOP__'), tostring(err))
end
local webhook, role, usedAuth=false,false,false
for _,r in ipairs(requests) do
    if r.url:find('/api/webhooks/', 1, true) then
        webhook=true
        assert(r.headers.Authorization==nil, 'Webhook darf keinen Bot-Token senden')
    end
    if r.url:find('/guilds/', 1, true) then
        usedAuth=true
        assert(r.headers.Authorization=='Bot SAMPLE_BOT_SECRET')
        if r.method=='PUT' then role=true end
    end
end
assert(webhook, 'Keine Webhook-Anfrage')
assert(usedAuth and role, 'Bannrolle nicht vergeben')
print('PASS: 17 txAdmin-Events, server.cfg-freie Config, Webhook und Bannrollen-Bot')
