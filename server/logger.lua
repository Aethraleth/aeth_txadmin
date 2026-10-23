-- AETHRALETH aeth_txadmin | 17 txAdmin events -> Discord WEBHOOKS (not bot messages).
-- Server-only handlers, keine vom Client aufrufbaren NetEvents.
local RESOURCE = GetCurrentResourceName()
local LOGCFG = (Config and Config.Logs) or {}
local enabled = LOGCFG.Enabled == true
local webhooks = LOGCFG.Webhooks or {}
local MAX_QUEUE = math.max(20, math.min(3000, tonumber(LOGCFG.MaxQueue) or 500))
local queue, busy, nextPostAt = {}, false, 0
local handled, sent, dropped = 0, 0, 0
local warnedNoWebhook = false
local LIVE_QUEUE_FILE = 'data/live_queue.json'
local persistEnabled = enabled and LOGCFG.PersistQueue == true
local persistentHealthy = true
local function persistQueue()
    if not persistEnabled or not persistentHealthy then return end
    local ok, encoded = pcall(json.encode, {version=1, queue=queue})
    if not ok or type(encoded) ~= 'string'
       or not SaveResourceFile(RESOURCE, LIVE_QUEUE_FILE, encoded, -1) then
        print('^1[aeth_txadmin:logs]^7 WARNUNG: Live-Webhook-Warteschlange konnte nicht gespeichert werden.')
    end
end
local function restoreQueue()
    if not persistEnabled then return end
    local raw = LoadResourceFile(RESOURCE, LIVE_QUEUE_FILE)
    if not raw or raw == '' then return end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' or type(decoded.queue) ~= 'table' then
        persistentHealthy = false
        print('^1[aeth_txadmin:logs]^7 WARNUNG: Live-Webhook-Warteschlange beschädigt. Datei wird NICHT ueberschrieben; Backup pruefen.')
        return
    end
    for _, item in ipairs(decoded.queue) do
        if #queue >= MAX_QUEUE then break end
        if type(item) == 'table' and type(item.group) == 'string'
            and type(item.payload) == 'string' and #item.payload < 12000 then
            queue[#queue+1] = {group=item.group, payload=item.payload,
                attempts=math.max(0, math.min(5, tonumber(item.attempts) or 0)),
                readyAt=tonumber(item.readyAt) or 0}
        end
    end
end
restoreQueue()

local function log(text)
    print(('^5[%s:logs]^7 %s'):format(RESOURCE, text))
end

-- Keine beliebigen Requests ueber konfigurierbare Webhook-URLs (Whitelist Discord-Domain).
local function validWebhook(url)
    if type(url) ~= 'string' then return false end
    return url:match('^https://discord%.com/api/webhooks/%d+/[%w_%-]+$') ~= nil
        or url:match('^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+$') ~= nil
end
local function webhookFor(group)
    if validWebhook(webhooks[group]) then return webhooks[group] end
    if group == 'AdminDatei' and validWebhook(webhooks.Admin) then return webhooks.Admin end
    if (group == 'KonsoleDatei' or group == 'ServerDatei') and validWebhook(webhooks.Server) then return webhooks.Server end
    if validWebhook(webhooks.Allgemein) then return webhooks.Allgemein end
    return nil
end

local function redact(text)
    if not text then return nil end
    text = tostring(text)
    if text:lower():match('mysql_connection_string') or text:lower():match('sv_licensekey')
       or text:lower():match('rcon_password') or text:lower():match('webhook')
       or text:lower():match('bot_token') or text:lower():match('password')
       or text:lower():match('set%s+') or text:lower():match('setr%s+')
       or text:lower():match('secret') or text:lower():match('token') then
        return '[Aus Sicherheitsgruenden teilweise maskiert]'
    end
    return text
end
local function clean(v, limit)
    if v == nil or v == false or type(v) == 'table' then return nil end
    local text = tostring(v):gsub('[%z\1-\8\11\12\14-\31]', ' ')
    text = text:gsub('@everyone', '@ everyone'):gsub('@here', '@ here')
    text = text:gsub('https://discord%.com/api/webhooks/%d+/[%w_%-]+', '[Webhook entfernt]')
    return text:sub(1, limit or 850)
end
local function safeValue(v, key, event)
    if key == 'license' or key == 'identifier' then return '[Identifier verborgen]' end
    if key == 'command' then
        if LOGCFG.LogConsoleCommandArguments ~= true then
            return type(v) == 'string' and v:match('^%s*(%S+)') or nil
        end
        return redact(clean(v, 650))
    end
    if key == 'message' and event == 'playerDirectMessage' and LOGCFG.LogDirectMessageContent ~= true then
        return '[Nachrichteninhalt deaktiviert]'
    end
    return clean(v, 850)
end

local GROUP = {
    announcement='Nachrichten', serverShuttingDown='Server', scheduledRestart='Server',
    scheduledRestartSkipped='Server', playerBanned='Moderation', playerDirectMessage='Nachrichten',
    playerHealed='Moderation', playerKicked='Moderation', playerWarned='Moderation',
    whitelistPlayer='Whitelist', whitelistPreApproval='Whitelist', whitelistRequest='Whitelist',
    actionRevoked='Moderation', adminAuth='Admin', adminsUpdated='Admin',
    configChanged='Admin', consoleCommand='Admin',
}
local TITLE = {
    announcement='Ankuendigung', serverShuttingDown='Server wird heruntergefahren',
    scheduledRestart='Geplanter Neustart', scheduledRestartSkipped='Neustart uebersprungen',
    playerBanned='Spieler gebannt', playerDirectMessage='Admin-Nachricht an Spieler',
    playerHealed='Heilung durch txAdmin', playerKicked='Spieler gekickt',
    playerWarned='Spieler verwarnt', whitelistPlayer='Whitelist-Status geaendert',
    whitelistPreApproval='Whitelist-Vorabfreigabe', whitelistRequest='Whitelist-Anfrage',
    actionRevoked='Admin-Aktion widerrufen', adminAuth='Admin-Authentifizierung',
    adminsUpdated='Adminrechte/Accounts aktualisiert', configChanged='txAdmin-Einstellungen geaendert',
    consoleCommand='txAdmin Live-Console-Befehl'
}
local KEYS = {
    announcement={'author','message'},
    serverShuttingDown={'author','message','delay'},
    scheduledRestart={'secondsRemaining','translatedMessage'},
    scheduledRestartSkipped={'author','secondsRemaining','temporary'},
    playerBanned={'author','targetName','reason','actionId','durationTranslated','expiration','targetNetId'},
    playerDirectMessage={'author','target','message'},
    playerHealed={'author','target'},
    playerKicked={'author','target','reason','dropMessage'},
    playerWarned={'author','targetName','targetNetId','reason','actionId'},
    whitelistPlayer={'adminName','action','playerName','license'},
    whitelistPreApproval={'adminName','action','playerName','identifier'},
    whitelistRequest={'adminName','action','playerName','requestId','license'},
    actionRevoked={'revokedBy','actionAuthor','actionType','actionId','actionReason','playerName'},
    adminAuth={'username','netid','isAdmin'},
    adminsUpdated={}, configChanged={}, consoleCommand={'author','channel','command'}
}
local LABEL = {
    author='Administrator', adminName='Administrator', targetName='Spieler',
    reason='Grund', actionId='Aktions-ID', targetNetId='Server-ID', target='Spieler-ID',
    durationTranslated='Banndauer', expiration='Ablauf (Unix)', delay='Shutdown-Verzoegerung (ms)',
    secondsRemaining='Sekunden bis Neustart', translatedMessage='Hinweis', temporary='Temporar',
    message='Nachricht', action='Aktion', playerName='Spieler', license='Lizenz',
    identifier='Identifier', requestId='Anfrage-ID', revokedBy='Widerrufen von',
    actionAuthor='Urspruenglicher Admin', actionType='Aktionstyp', actionReason='Grund',
    username='txAdmin-Account', netid='Server-ID', isAdmin='Ist Admin',
    channel='Kanal', command='Befehl', dropMessage='Kick-Text'
}
local COLORS = {Moderation=0xDE4040, Admin=0xE8B451, BanSync=0xD8AC55,
                Server=0x498CCD, Whitelist=0x59B386, Nachrichten=0xA58FDC}

local function enqueue(group, title, fields, event)
    if not enabled then return end
    local url = webhookFor(group)
    if not url then
        if not warnedNoWebhook then
            log('Kein gueltiger Webhook konfiguriert (Config.Logs.Webhooks); Logs derzeit nicht versendbar.')
            warnedNoWebhook = true
        end
        return
    end
    if #queue >= MAX_QUEUE then
        dropped = dropped + 1
        if dropped == 1 or dropped % 50 == 0 then log(('Warteschlange voll (%d verworfen)'):format(dropped)) end
        return
    end
    local embed = { title='txAdmin | '..title, color=COLORS[group] or 0xD8AC55,
                    fields=fields, footer={text='AETHRALETH | aeth_txadmin | '..event},
                    timestamp=os.date('!%Y-%m-%dT%H:%M:%SZ') }
    queue[#queue+1] = {group=group, payload=json.encode({username='AETHRALETH txAdmin',
        allowed_mentions={parse={}}, embeds={embed}}), attempts=0, readyAt=0}
    persistQueue()
end

local function onEvent(eventName, payload)
    if LOGCFG.Events and LOGCFG.Events[eventName] == false then return end
    handled = handled + 1
    local fields = {}
    if eventName == 'adminsUpdated' then
        fields[1] = {name='Betroffene eingeloggte Admins', value=tostring(type(payload)=='table' and #payload or 0), inline=true}
    else
        local data = type(payload)=='table' and payload or {}
        for _, key in ipairs(KEYS[eventName]) do
            local value = safeValue(data[key], key, eventName)
            if value and value ~= '' then
                value = clean(value, 850)
                fields[#fields+1] = {name=LABEL[key] or key,value=value,inline=(#value < 80)}
            end
        end
    end
    if #fields == 0 then fields[1] = {name='Info', value='txAdmin hat die Aktion signalisiert (keine Details im Event).'} end
    enqueue(GROUP[eventName], TITLE[eventName], fields, eventName)
end

for name in pairs(GROUP) do
    local captured = name
    AddEventHandler('txAdmin:events:'..captured, function(payload) onEvent(captured, payload) end)
end

-- Andere Dateien innerhalb DIESER rein serverseitigen Resource koennen interne
-- BanSync-Erfolge ebenfalls ueber die konfigurierten Webhooks melden.
AethTxAdminInternalLog = function(title, fields)
    if LOGCFG.LogRoleSyncEvents ~= true then return end
    local out = {}
    for _, row in ipairs(fields or {}) do
        local value = clean(row.value, 850)
        if value then out[#out+1] = {name=clean(row.name,100) or 'Info',value=value,inline=#value<80} end
    end
    if #out == 0 then out[1] = {name='Status',value='Aktion ausgefuehrt.'} end
    enqueue('BanSync',clean(title,150) or 'Bannrollen-Sync',out,'banRoleSync')
end

CreateThread(function()
    while true do
        local now = os.time()
        if not busy and #queue>0 and now>=nextPostAt and now >= (queue[1].readyAt or 0) then
            local item = queue[1]
            busy = true
            local url = webhookFor(item.group)
            if not url then
                -- Keine URL mehr konfiguriert: Nachricht behalten und auf Konfigurationsfix warten.
                busy = false
                item.readyAt = os.time() + 60
            else
            PerformHttpRequest(url, function(status, response)
                local code = tonumber(status) or 0
                busy = false
                if code == 204 or code == 200 then
                    table.remove(queue,1); sent = sent + 1
                    persistQueue()
                    nextPostAt = os.time() + 1
                else
                    item.attempts = item.attempts + 1
                    if item.attempts >= 6 then
                        log(('Webhook HTTP %d: nach sechs Versuchen verworfen. Rechte/URL pruefen.'):format(code))
                        table.remove(queue,1); dropped = dropped + 1
                    else
                        local delay = 20
                        if code == 429 then
                            local ok, body = pcall(json.decode,response or '')
                            local retry = ok and type(body)=='table' and tonumber(body.retry_after) or 5
                            delay = math.max(3, math.ceil(retry)+2)
                        elseif code == 401 or code == 403 or code == 404 then delay = 300 end
                        item.readyAt = os.time()+delay
                    end
                    persistQueue()
                    nextPostAt = os.time()+1
                end
            end, 'POST', item.payload, {['Content-Type']='application/json'})
            end
        end
        Wait(500)
    end
end)
RegisterCommand('aeth_txadmin_logs_status', function(source)
    if source ~= 0 then return end
    log(('Live-Events=%d, Webhook-Nachrichten=%d, Puffer=%d, verworfen=%d')
        :format(handled,sent,#queue,dropped))
end,false)
log('17 txAdmin-Events ueber Discord-Webhooks registriert. Logs '..(enabled and 'aktiv' or 'deaktiviert')..'.')
