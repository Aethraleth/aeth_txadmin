-- AETHRALETH | txAdmin Ban -> Discord Role Sync, Bestandteil aeth_txadmin
-- Keine Clientevents. Discord-Bot-Token bleibt ausschließlich serverseitig.

local RESOURCE = GetCurrentResourceName()
local STATE_FILE = 'data/state.json'
local API_ROOT = 'https://discord.com/api/v10'
local TOKEN = tostring((Config.Discord or {}).BotToken or '')
local GUILD_ID = tostring((Config.Discord or {}).GuildId or '')
local ROLE_ID = tostring((Config.Discord or {}).BannedRoleId or '')
local BANCFG = Config.BanSync or {}
local ENABLED = BANCFG.Enabled == true
local CACHE_LINKS = BANCFG.CacheLicenseDiscordLinks == true
local VERIFY_INTERVAL = math.max(5, tonumber(BANCFG.VerifyMinutes) or 30) * 60
local READY = ENABLED and TOKEN ~= '' and TOKEN ~= 'HIER_BOT_TOKEN'
    and #GUILD_ID >= 17 and #GUILD_ID <= 22 and GUILD_ID:match('^%d+$') ~= nil
    and #ROLE_ID >= 17 and #ROLE_ID <= 22 and ROLE_ID:match('^%d+$') ~= nil

local state = { version = 1, bans = {}, users = {}, links = {} }
local pending, retryAt = {}, {}
local busy, nextRequestAt = false, 0
local eventsHandled = 0
local STATE_HEALTHY = true

local function log(message)
    print(('^3[aeth_txadmin:ban]^7 %s'):format(tostring(message)))
end

local function loadState()
    local content = LoadResourceFile(RESOURCE, STATE_FILE)
    if not content or content == '' then return end
    local ok, data = pcall(json.decode, content)
    if ok and type(data) == 'table' and data.version == 1
        and type(data.bans) == 'table' and type(data.users) == 'table'
        and type(data.links) == 'table' then
        state.bans, state.users, state.links = data.bans, data.users, data.links
    else
        STATE_HEALTHY = false
        log('KRITISCH: state.json beschaedigt oder inkompatibel. Kein Rollensync; Original pruefen/aus Backup wiederherstellen, um Datenverlust zu verhindern.')
    end
end

local function saveState()
    if not STATE_HEALTHY then return false end
    local ok, content = pcall(json.encode, state)
    if not ok or not content then
        log('KRITISCH: JSON-Speicherung nicht moeglich, Bannsync gestoppt.')
        STATE_HEALTHY = false
        return false
    end
    if not SaveResourceFile(RESOURCE, STATE_FILE, content, -1) then
        log('KRITISCH: state.json konnte nicht geschrieben werden. Bannsync gestoppt, Rechte am Datenordner pruefen!')
        STATE_HEALTHY = false
        return false
    end
    return true
end

local function validDiscordId(id)
    return type(id) == 'string' and #id >= 17 and #id <= 22 and id:match('^%d+$') ~= nil
end

local function idsFromSource(src)
    local sourceNumber = tonumber(src)
    if not sourceNumber or sourceNumber <= 0 then return {} end
    local identifiers = GetPlayerIdentifiers(sourceNumber)
    if type(identifiers) ~= 'table' then return {} end
    return identifiers
end

local function combineIdentifiers(ids, netid)
    local combined = {}
    if type(ids) == 'table' then
        for _, identifier in pairs(ids) do
            if type(identifier) == 'string' then
                combined[#combined + 1] = identifier
            end
        end
    end
    if tonumber(netid) and tonumber(netid) > 0 then
        for _, identifier in ipairs(idsFromSource(netid)) do
            combined[#combined + 1] = identifier
        end
    end
    return combined
end

local function findDiscord(ids)
    for _, identifier in ipairs(ids) do
        local candidate = identifier:match('^discord:(%d+)$')
        if validDiscordId(candidate) then return candidate end
    end
    for _, identifier in ipairs(ids) do
        if identifier:match('^license:[%da-fA-F]+$') or identifier:match('^license2:[%da-fA-F]+$') then
            local known = state.links[identifier]
            if validDiscordId(known) then return known end
        end
    end
    return nil
end

local function rememberLink(ids)
    if not CACHE_LINKS or not STATE_HEALTHY then return end
    local discord
    for _, identifier in ipairs(ids) do
        local possible = identifier:match('^discord:(%d+)$')
        if validDiscordId(possible) then discord = possible; break end
    end
    if not discord then return end
    local changed = false
    for _, identifier in ipairs(ids) do
        if identifier:match('^license:[%da-fA-F]+$') or identifier:match('^license2:[%da-fA-F]+$') then
            if state.links[identifier] ~= discord then
                state.links[identifier] = discord
                changed = true
            end
        end
    end
    if changed then saveState() end
end

local function isBanActive(record, now)
    if type(record) ~= 'table' then return false end
    local expiry = tonumber(record.expiration)
    return (expiry == nil or expiry == 0 or expiry > now)
end

local function wantsRole(discord)
    local now = os.time()
    for _, ban in pairs(state.bans) do
        if ban.discord == discord and isBanActive(ban, now) then return true end
    end
    return false
end

local function queueUser(discord, delaySeconds)
    if not validDiscordId(discord) then return end
    pending[discord] = true
    if delaySeconds and delaySeconds > 0 then
        retryAt[discord] = os.time() + delaySeconds
    else
        retryAt[discord] = 0
    end
end

local function expireRecords()
    local now = os.time()
    local changed, affected = false, {}
    for id, ban in pairs(state.bans) do
        if type(ban) ~= 'table' or not validDiscordId(ban.discord) then
            state.bans[id] = nil
            changed = true
        elseif tonumber(ban.expiration) and tonumber(ban.expiration) > 0
            and tonumber(ban.expiration) <= now then
            affected[ban.discord] = true
            state.bans[id] = nil
            changed = true
        end
    end
    if changed then
        saveState()
        for discord in pairs(affected) do queueUser(discord) end
    end
end

local function http(method, discord, callback)
    local url = ('%s/guilds/%s/members/%s'):format(API_ROOT, GUILD_ID, discord)
    if method ~= 'GET' then url = url .. '/roles/' .. ROLE_ID end
    local headers = { ['Authorization'] = 'Bot ' .. TOKEN, ['Content-Type'] = 'application/json' }
    PerformHttpRequest(url, function(status, body, responseHeaders)
        callback(tonumber(status) or 0, body, responseHeaders)
    end, method, '', headers)
end

local function getRetrySeconds(code, body)
    if code == 429 then
        local ok, data = pcall(json.decode, body or '')
        local retryAfter = ok and type(data) == 'table' and tonumber(data.retry_after) or nil
        return math.max(2, math.ceil(retryAfter or 5) + 1)
    end
    if code == 404 then return 1800 end -- Noch kein Mitglied im Discord-Server.
    if code == 401 or code == 403 then return 600 end
    return 90
end

local function syncUser(discord, finished)
    local function fail(code, body, operation)
        local cooldown = getRetrySeconds(code, body)
        if AethTxAdminInternalLog then AethTxAdminInternalLog('Bannrolle Synchronisierung fehlgeschlagen',{{name='Discord-ID',value=discord},{name='Vorgang',value=operation},{name='HTTP',value=tostring(code)}}) end
        log(('%s für Discord %s fehlgeschlagen (HTTP %d), neuer Versuch in %ds.')
            :format(operation, discord, code, cooldown))
        queueUser(discord, cooldown)
        finished()
    end

    if not wantsRole(discord) then
        local status = state.users[discord]
        if not status or status.owned ~= true then
            if status then state.users[discord] = nil; saveState() end
            finished()
            return
        end
        http('DELETE', discord, function(code, body)
            if code == 204 or code == 404 then
                state.users[discord] = nil
                saveState()
                log('Ban-Rolle entfernt für Discord ' .. discord)
                if AethTxAdminInternalLog then AethTxAdminInternalLog('Bannrolle entfernt',{{name='Discord-ID',value=discord},{name='Ergebnis',value='Rolle erfolgreich entfernt'}}) end
                if wantsRole(discord) then queueUser(discord) end
                finished()
            else
                fail(code, body, 'Rolle entfernen')
            end
        end)
        return
    end

    -- Vor der Vergabe prüfen: bereits vorhandene Rollen dürfen bei Unban nicht
    -- fälschlich entfernt werden, wenn unser Skript sie nicht selbst vergab.
    http('GET', discord, function(code, body)
        if code ~= 200 then
            fail(code, body, 'Mitglied prüfen')
            return
        end
        local ok, member = pcall(json.decode, body or '')
        if not ok or type(member) ~= 'table' or type(member.roles) ~= 'table' then
            fail(0, '', 'Antwort auswerten')
            return
        end
        local hasRole = false
        for _, role in ipairs(member.roles) do
            if tostring(role) == ROLE_ID then hasRole = true; break end
        end
        if not wantsRole(discord) then
            queueUser(discord)
            finished()
            return
        end
        if hasRole then
            if not state.users[discord] then
                state.users[discord] = { owned = false }
                saveState()
            end
            finished()
            return
        end
        -- Bewusst getrennte Requests; verhindert zu schnelle API-Aufrufe.
        SetTimeout(500, function()
            if not wantsRole(discord) then
                queueUser(discord)
                finished()
                return
            end
            http('PUT', discord, function(putCode, putBody)
                if putCode == 204 then
                    state.users[discord] = { owned = true }
                    saveState()
                    log('Ban-Rolle vergeben an Discord ' .. discord)
                    if AethTxAdminInternalLog then AethTxAdminInternalLog('Bannrolle vergeben',{{name='Discord-ID',value=discord},{name='Ergebnis',value='Rolle erfolgreich vergeben'}}) end
                    if not wantsRole(discord) then queueUser(discord) end
                    finished()
                else
                    fail(putCode, putBody, 'Rolle vergeben')
                end
            end)
        end)
    end)
end

local function countRecords()
    local count = 0
    for _ in pairs(state.bans) do count = count + 1 end
    return count
end

loadState()
if not STATE_HEALTHY then
    log('Bann-Rollensync gestoppt: state.json defekt oder nicht schreibbar.')
elseif not READY then
    log('Bann-Rollensync inaktiv oder Discord-Konfiguration unvollstaendig (config.lua pruefen).')
else
    log('Gestartet; gespeicherte Bann-Einträge: ' .. countRecords())
end

AddEventHandler('playerJoining', function()
    local src = source
    rememberLink(idsFromSource(src))
end)

AddEventHandler('txAdmin:events:playerBanned', function(event)
    if not ENABLED or not STATE_HEALTHY then return end
    if type(event) ~= 'table' or event.actionId == nil then
        log('Bann-Ereignis ohne actionId ignoriert.')
        return
    end
    eventsHandled = eventsHandled + 1
    local id = tostring(event.actionId)
    local ids = combineIdentifiers(event.targetIds, event.targetNetId)
    rememberLink(ids)
    local discord = findDiscord(ids)
    if not discord then
        log(('Bann %s: Keine Discord-ID gefunden. Ohne ID-Zuordnung kann keine Rolle vergeben werden.')
            :format(id))
        return
    end
    local expiry = event.expiration == false and 0 or tonumber(event.expiration) or 0
    if expiry > 100000000000 then expiry = math.floor(expiry / 1000) end
    local old = state.bans[id]
    state.bans[id] = { discord = discord, expiration = expiry }
    if not saveState() then state.bans[id] = old; return end
    if old and old.discord ~= discord then queueUser(old.discord) end
    queueUser(discord)
    log(('txAdmin-Bann %s für Discord %s übernommen.'):format(id, discord))
end)

AddEventHandler('txAdmin:events:actionRevoked', function(event)
    if not ENABLED or not STATE_HEALTHY then return end
    if type(event) ~= 'table' or event.actionId == nil then return end
    local id = tostring(event.actionId)
    local old = state.bans[id]
    if not old then return end -- Warnungen und nicht erfasste Aktionen ignorieren.
    state.bans[id] = nil
    if not saveState() then state.bans[id] = old; return end
    queueUser(old.discord)
    log(('txAdmin-Bann %s aufgehoben; Rolle wird abgeglichen.'):format(id))
end)

RegisterCommand('aeth_txadmin_bans_status', function(src)
    if src ~= 0 then return end -- Nur Serverkonsole; kein Spieler-Kommando.
    local users, retries = 0, 0
    for _ in pairs(state.users) do users = users + 1 end
    for _ in pairs(pending) do retries = retries + 1 end
    log(('Status: Konfiguration=%s, aktive Bann-Einträge=%d, verfolgte Discord-Nutzer=%d, Warteschlange=%d, verarbeitete Events=%d')
        :format(READY and 'OK' or 'FEHLT', countRecords(), users, retries, eventsHandled))
end, false)

CreateThread(function()
    if not STATE_HEALTHY then return end
    -- Beim Start keine alte Vergabe verlieren. Nur eigene alte Rollen entfernen.
    expireRecords()
    for _, ban in pairs(state.bans) do
        if validDiscordId(ban.discord) then queueUser(ban.discord) end
    end
    for discord in pairs(state.users) do queueUser(discord) end
    -- Spieler, die beim Resource-Start schon online sind.
    if CACHE_LINKS then
        for _, src in ipairs(GetPlayers()) do rememberLink(idsFromSource(src)) end
    end
    local nextExpiry = 0
    local nextVerify = os.time() + VERIFY_INTERVAL
    while true do
        local now = os.time()
        if now >= nextExpiry then
            expireRecords()
            nextExpiry = now + 30
        end
        if now >= nextVerify then
            for _, ban in pairs(state.bans) do queueUser(ban.discord) end
            nextVerify = now + VERIFY_INTERVAL
        end
        if READY and STATE_HEALTHY and not busy and now >= nextRequestAt then
            for discord in pairs(pending) do
                if now >= (retryAt[discord] or 0) then
                    pending[discord] = nil
                    retryAt[discord] = nil
                    busy = true
                    syncUser(discord, function()
                        busy = false
                        nextRequestAt = os.time() + 1
                    end)
                    break
                end
            end
        end
        Wait(1000)
    end
end)
