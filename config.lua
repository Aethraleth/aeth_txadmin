-- AETHRALETH | aeth_txadmin v1.4.0
-- ZENTRALE SERVER-KONFIGURATION. Nicht in ein oeffentliches Git-Repo hochladen!
-- Einziger Eintrag in der server.cfg: ensure aeth_txadmin
Config = {}

-- Discord-Bot nur fuer die txAdmin Bann <-> Discord-Rolle.
-- KEIN Discord-Serverbann! Ein Spieler bekommt ausschliesslich die konfigurierte Rolle.
Config.Discord = {
    BotToken = 'HIER_BOT_TOKEN',
    GuildId = '123456789012345678',
    BannedRoleId = '234567890123456789',
}

Config.BanSync = {
    Enabled = true,
    CacheLicenseDiscordLinks = true,
    VerifyMinutes = 30,     -- Abgleich fuer bereits von dieser Resource ERFASSTE Banns.
}

Config.Logs = {
    Enabled = true,

    -- Discord: Kanal bearbeiten > Integrationen > Webhooks > Neuer Webhook > URL kopieren.
    -- Fuer jede Kategorie eine eigene URL, oder nur Allgemein als Fallback angeben.
    -- Fuer AdminDatei kann stattdessen auf Admin zurueckgefallen werden.
    -- GILT AUCH FUER DIE ECHTEN txData-LOGDATEIEN (siehe FileRelay weiter unten).
    Webhooks = {
        Allgemein    = 'HIER_WEBHOOK_ALLGEMEIN',
        Moderation   = '', -- Bann, Unbann, Warnung, Kick, Heal
        Admin        = '', -- Admin-Auth, Rechteaenderung, Live-Konsole, Config
        AdminRoleSync = '', -- Automatische Rollenvergabe bei txAdmin-Rechteaenderungen
        BanSync      = '', -- Discord-Bannrolle vergeben/entfernt oder Fehler
        Whitelist    = '', -- Antraege, Freigaben, Ablehnungen
        Nachrichten  = '', -- txAdmin Ankuendigungen und Direktnachrichten
        Server       = '', -- txAdmin Restart, Shutdown
        AdminDatei   = '', -- ECHTE txData/admin.log: alle protokollierten Admin-Aktionen
        KonsoleDatei = '', -- ECHTE txData/fxserver.log: Konsole
        ServerDatei  = '', -- ECHTE txData/server.log: Serveraktivitaet
    },

    -- Saemtliche 17 derzeit offiziell dokumentierten txAdmin-Live-Ereignisse.
    Events = {
        announcement = true,
        serverShuttingDown = true,
        scheduledRestart = true,
        scheduledRestartSkipped = true,
        playerBanned = true,
        playerDirectMessage = true,
        playerHealed = true,
        playerKicked = true,
        playerWarned = true,
        whitelistPlayer = true,
        whitelistPreApproval = true,
        whitelistRequest = true,
        actionRevoked = true,
        adminAuth = true,
        adminsUpdated = true,
        configChanged = true,
        consoleCommand = true,
    },
    -- Achtung: Konsoleingaben koennen personenbezogene Daten/Geheimnisse enthalten.
    -- Bei false wird nur der Befehlsname und nicht dessen Argumente geloggt.
    LogConsoleCommandArguments = false,
    LogDirectMessageContent = false,
    LogRoleSyncEvents = true,
    MaxQueue = 500,
    PersistQueue = true, -- Live-Webhook-Nachrichten auch nach Resource-/Server-Neustart erneut senden.
    -- Bei Abstuerzen kann eine bereits zugestellte Nachricht erneut gesendet werden.

}


-- ================================================================
-- ADMIN-RANGSYNC: txAdmin-Rechte als Discord-Rollen ANZEIGEN
-- ================================================================
-- Was er macht:
-- 1. Der Host-Helfer liest txData/admins.json (NUR LESEN).
-- 2. Er vergleicht deine txAdmin-Rechte mit den Regeln unten.
-- 3. Er vergibt/entfernt passende Discord-Rollen.
-- WICHTIG: Discord-Rollen geben NIEMALS txAdmin-Rechte!
--
-- Solange du die echten IDs nicht eingetragen hast, Enabled=false lassen.
-- Auch hier gilt: nur config.lua bearbeiten; KEINE set/setr in server.cfg.
Config.AdminRoleSync = {
    Enabled = false, -- zuerst IDs/Pfad setzen, danach auf true stellen.

    -- Absoluter Pfad zur GLOBALEN txData/admins.json (NICHT profile/logs!).
    -- Beispiel Windows: C:/FXServer/txData/admins.json
    -- Beispiel Linux:   /home/fivem/txData/admins.json
    -- Die Datei ist privat und kann Passwort-Hashes enthalten: NICHT teilen!
    AdminsPath = 'C:/FXServer/txData/admins.json',

    PollSeconds = 60, -- Alle 60 Sekunden Konten/Rechte kontrollieren (mindestens 30).
    TeamRoleId = '', -- Optionale gemeinsame Discord-Rolle fuer ALLE verknuepften txAdmin-Admins.
    OnlyHighestRank = true, -- true: nur hoechster zutreffender Rang; false: mehrere Rangsrollen.

    -- Wenn einem txAdmin-Konto keine Discord-ID zugeordnet ist, kann
    -- man es hier ausnahmsweise MANUELL mit Discord verbinden.
    -- Schluessel = txAdmin-Benutzername, Wert = Discord-Nutzer-ID.
    DiscordLinks = {
        -- ['MeinAdminAccount'] = '123456789012345678',
    },

    -- RANGLISTE: OBEN = hoechste Prioritaet.
    -- roleId = Discord-ROLLEN-ID (keine Kanal-ID, keine Nutzer-ID).
    -- permissions = offizielle txAdmin-Permission-Keys.
    -- mode='any' -> EINE aufgefuehrte Berechtigung reicht.
    -- mode='all' -> ALLE aufgefuehrten Berechtigungen sind erforderlich.
    -- master=true -> NUR das echte txAdmin-Masterkonto.
    -- all_permissions erfuellt die normalen permission-basierten Regeln.
    Ranks = {
        {
            name = 'Master / Owner', -- nur txAdmin-Master; nicht durch all_permissions erreichbar.
            roleId = '100000000000000000',
            master = true,
        },
        {
            name = 'Vollzugriff', -- txAdmin-Wurzelrecht (nicht automatisch Master).
            roleId = '200000000000000000',
            mode = 'any',
            permissions = {'all_permissions'},
        },
        {
            name = 'Leitung', -- sehr weitreichende Server-/Adminverwaltung.
            roleId = '300000000000000000',
            mode = 'any',
            permissions = {'manage.admins', 'control.server', 'console.write', 'server.cfg.editor', 'settings.write'},
        },
        {
            name = 'Administrator', -- Bannbefugnis, ohne zwingenden Vollzugriff.
            roleId = '400000000000000000',
            mode = 'any',
            permissions = {'players.ban', 'players.whitelist'},
        },
        {
            name = 'Supporter', -- Verwarnen/Kicken/Nachrichten, ohne Bannrecht.
            roleId = '500000000000000000',
            mode = 'any',
            permissions = {'players.warn', 'players.kick', 'players.direct_message'},
        },
    },
}

-- Zusaetzlich die vollstaendiger protokollierten txAdmin-Dateilogs an Discord spiegeln.
-- OHNE Host-Helfer ist nur das Live-Event-Logging moeglich!
-- Helper: node tools/log_relay.js (auf demselben Server/Host, Node 18+)
Config.FileRelay = {
    Enabled = true,
    LogsDirectory = 'C:/FXServer/txData/default/logs', -- Hier echten ABSOLUTEN Hostpfad angeben.
    Admin = true, -- Alle zusaetzlich in admin.log protokollierten Adminaktionen.
    Fxserver = false, -- VORSICHT: rohe Konsole kann Passwoerter/IPs und Secrets enthalten.
                          -- Nur fuer private Log-Kanaele bewusst auf true stellen.
    Server = false, -- Enthält evtl. Chatnachrichten/Spieler-Identifiers/IPs; bewusst aktivieren.
    PollMilliseconds = 2000,
    MaxPending = 3000, -- Schutz vor unbegrenztem Anwachsen des FileRelay-Puffers.

    StartAtEnd = true, -- nur NEUE Zeilen ab Erststart; keine alte Flut an Discord.
    -- AdminDatei und Live-Moderation koennen denselben Vorfall doppelt melden.
}
