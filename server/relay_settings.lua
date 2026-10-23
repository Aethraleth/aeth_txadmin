-- Die echte txData-Datei wird nur vom separaten, optionalen Host-Relay gelesen.
-- Einstellungen in data/relay_settings.json sind GEHEIM (Webhook URLs enthalten Token).
local fileConfig = Config.FileRelay or {}
local hooks = (Config.Logs or {}).Webhooks or {}
local function validHook(url)
    return type(url)=='string' and (
        url:match('^https://discord%.com/api/webhooks/%d+/[%w_%-]+$')
        or url:match('^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+$')) ~= nil
end
local function choose(main, secondary)
    if validHook(hooks[main]) then return hooks[main] end
    if secondary and validHook(hooks[secondary]) then return hooks[secondary] end
    if validHook(hooks.Allgemein) then return hooks.Allgemein end
    return ''
end
local settings = {enabled = fileConfig.Enabled == true and (Config.Logs or {}).Enabled == true}
if settings.enabled then
    settings.logDirectory = tostring(fileConfig.LogsDirectory or '')
    settings.pollMilliseconds = tonumber(fileConfig.PollMilliseconds) or 2000
    settings.maxPending = tonumber(fileConfig.MaxPending) or 3000
    settings.startAtEnd = fileConfig.StartAtEnd ~= false
    settings.webhooks = {
        admin = choose('AdminDatei','Admin'),
        fxserver = choose('KonsoleDatei','Server'),
        server = choose('ServerDatei','Server'),
    }
    settings.enabledKinds = {admin=fileConfig.Admin == true,
        fxserver=fileConfig.Fxserver == true, server=fileConfig.Server == true}
end
-- Admin-Rangsync nutzt denselben SEPARATEN Host-Prozess wie der Datei-Relay.
-- Nie die gesamte admins.json nach Discord uebertragen (sie enthaelt Passwort-Hashes).
local adminRoles = Config.AdminRoleSync or {}
settings.adminRoles = {
    enabled = adminRoles.Enabled == true,
    adminsPath = tostring(adminRoles.AdminsPath or ''),
    pollSeconds = tonumber(adminRoles.PollSeconds) or 60,
    botToken = tostring((Config.Discord or {}).BotToken or ''),
    guildId = tostring((Config.Discord or {}).GuildId or ''),
    teamRoleId = tostring(adminRoles.TeamRoleId or ''),
    onlyHighestRank = adminRoles.OnlyHighestRank ~= false,
    ranks = adminRoles.Ranks or {},
    discordLinks = adminRoles.DiscordLinks or {},
    webhook = choose('AdminRoleSync', 'Admin'),
}
local ok = SaveResourceFile(GetCurrentResourceName(),'data/relay_settings.json',json.encode(settings),-1)
if not ok then
    print('^1[aeth_txadmin:file]^7 Konnte Relay-Einstellungen nicht speichern!')
elseif settings.enabled then
    print('^3[aeth_txadmin:file]^7 Dateirelay vorbereitet; auf dem Host separat node tools/log_relay.js starten.')
end
