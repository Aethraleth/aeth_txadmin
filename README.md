<div align="center">

# AETHRALETH · aeth_txadmin

**txAdmin-Logs, Discord-Webhooks und automatische Discord-Rollen für FiveM**

**Version 1.4.0** · **Sprache: Deutsch** · **Serverseitige FiveM-Resource**

</div>

> [!IMPORTANT]
> **`aeth_txadmin` ist eine eigenständige Erweiterung für txAdmin – kein Ersatz für txAdmin und kein offizielles txAdmin-Produkt.** Die Integration protokolliert verfügbare txAdmin-Ereignisse, spiegelt optional txAdmin-Logdateien nach Discord und synchronisiert Discord-Rollen. Sie verändert keine txAdmin-Berechtigungen.
>
> **Entwicklungsstand:** Die vorliegende Version wurde offline mit Mocktests geprüft, aber noch **nicht auf einem echten FiveM-/txAdmin-/Discord-Server vollständig getestet**. Bitte zunächst auf einem Testserver einsetzen.

## Inhaltsverzeichnis

- [Über das Projekt](#über-das-projekt)
- [Funktionsumfang](#funktionsumfang)
- [Voraussetzungen](#voraussetzungen)
- [Installation](#installation)
- [Discord-Bot einrichten](#discord-bot-einrichten)
- [Discord-Webhooks konfigurieren](#discord-webhooks-konfigurieren)
- [Konfiguration erklärt](#konfiguration-erklärt)
- [Alle txAdmin-Berechtigungen erklärt](#alle-txadmin-berechtigungen-erklärt)
- [Vollständigeres txAdmin-Dateilogging](#vollständigeres-txadmin-dateilogging)
- [Automatischer Bannrollen-Sync](#automatischer-bannrollen-sync)
- [Automatischer Admin-Rangsync](#automatischer-admin-rangsync)
- [Unterstützte txAdmin-Ereignisse](#unterstützte-txadmin-ereignisse)
- [Statusbefehle und Funktionstest](#statusbefehle-und-funktionstest)
- [Fehlerbehebung](#fehlerbehebung)
- [Sicherheit und Datenschutz](#sicherheit-und-datenschutz)
- [Bekannte Einschränkungen](#bekannte-einschränkungen)
- [Updates und Datensicherung](#updates-und-datensicherung)
- [Projektstruktur](#projektstruktur)
- [Lizenz und Quellen](#lizenz-und-quellen)

---

## Über das Projekt

**AETHRALETH `aeth_txadmin`** bündelt die Verbindung zwischen dem FiveM-Administrationssystem **txAdmin** und **Discord** in einer Resource. Die Einrichtung erfolgt über eine zentrale, ausführlich kommentierte **`config.lua`**. Es sind keine getrennten `set`-/`setr`-Einträge für jeden Token oder jede ID in der `server.cfg` erforderlich.

Das Projekt verfolgt drei Ziele:

1. **Administrationsvorgänge nachvollziehen:** Von txAdmin bereitgestellte Ereignisse und optional dessen gespeicherte Logdateien in private Discord-Kanäle weiterleiten.
2. **Gesperrte Spieler sichtbar machen:** Nach einem erkannten txAdmin-Bann automatisch eine Discord-Rolle vergeben und diese bei Aufhebung oder Ablauf unter den dokumentierten Voraussetzungen entfernen.
3. **txAdmin-Zugangsrechte anzeigen:** Berechtigungen aus `txData/admins.json` nach frei einstellbaren Regeln in Discord-Ränge übersetzen – **ohne** die txAdmin-Rechte zu verändern.

Das Skript benötigt **weder ESX noch ox_lib oder ox_target** und enthält kein Client-Script, keine eigene NUI und keine SQL-Datenbank.

## Funktionsumfang

| Funktion | Status | Technische Voraussetzung |
|---|---|---|
| 17 dokumentierte txAdmin-Live-Ereignisse protokollieren | Enthalten | Laufende FiveM-Resource, Discord-Webhooks |
| Webhooks je Log-Kategorie | Enthalten | Gültige Webhook-URLs |
| txAdmin-Bann → Discord-Rolle | Enthalten | Bot, Discord-Zuordnung, txAdmin-Live-Ereignis |
| Bann widerrufen / erkannter Zeitbann abgelaufen → Rolle abgleichen | Enthalten | Zuvor von dieser Resource erfasster Bann |
| `admin.log` nach Discord spiegeln | Optional enthalten | Separater Node.js-Host-Helfer |
| `fxserver.log` und `server.log` spiegeln | Optional, standardmäßig aus | Separater Node.js-Host-Helfer |
| Adminrechte → Discord-Ränge | Optional, standardmäßig aus | Separater Host-Helfer + `admins.json` |
| Eigene Rangnamen, Regeln und Rollen-IDs | Enthalten | `Config.AdminRoleSync.Ranks` |
| Gemeinsame Discord-Teamrolle | Optional enthalten | `TeamRoleId` |
| Live-Webhook-Warteschlange bei Neustart fortsetzen | Enthalten | Persistenz aktiviert |
| Offline-Banns vollständig aus txAdmins Bann-Datenbank rekonstruieren | **Nicht enthalten** | Noch keine vollständige Datenbanksynchronisierung |
| Discord-Rollen vergeben txAdmin-Rechte | **Nicht vorgesehen** | txAdmin bleibt allein maßgeblich |

> [!NOTE]
> „Vollständigeres Logging“ bedeutet die Kombination aus **dokumentierten Live-Ereignissen** und den **von txAdmin tatsächlich geschriebenen Dateien**. Es bedeutet nicht, dass jede denkbare Aktion eine eigene Echtzeit-API besitzt oder dass eine lückenlose Zustellung garantiert werden kann.

## Voraussetzungen

- Ein FiveM-/FXServer mit **txAdmin**.
- Ein Discord-Server mit Administratorzugriff zum Einrichten von Bot und Webhooks.
- Ein Discord-Bot mit **Rollen verwalten**, falls Bannrollen oder Admin-Ränge synchronisiert werden sollen.
- Für **`admin.log` / `fxserver.log` / `server.log`** und den **Admin-Rangsync**: **Node.js 18 oder neuer** auf demselben Host sowie Lesezugriff auf die betreffenden `txData`-Dateien.
- Schreibberechtigung für die serverseitigen Zustandsdateien im Resource-Ordner `data/`.

**Hosting-Hinweis:** Bei Shared-Hosting ohne Zugriff auf eigene Node-Prozesse funktionieren die FiveM-Live-Ereignisse und der Bannrollen-Sync, aber **nicht automatisch** der externe Dateirelay oder der Admin-Rangsync.

## Installation

### 1. Resource kopieren

Den Ordner **`aeth_txadmin`** aus dem Release-ZIP beispielsweise hierhin kopieren:

```text
resources/[standalone]/aeth_txadmin/
```

Bei einer älteren Installation **`aeth_txadmin_discord`** oder **`aeth_txban_sync`** nicht parallel starten. Sonst können sich Rollen-Synchronisierungen und Logs überschneiden.

### 2. `config.lua` bearbeiten

In `aeth_txadmin/config.lua` den Discord-Bot, die Server-/Rollen-IDs, Webhooks und gegebenenfalls die Host-Dateipfade eintragen. **Die Konfiguration liegt zentral in dieser Datei.**

> [!CAUTION]
> Die **echte `config.lua` ist in `.gitignore` ausgeschlossen**, da sie Tokens und Webhook-URLs enthalten kann. Wer das Projekt nur mit `git clone` bezieht, muss eine **unbefüllte `config.lua` aus dem Release-Paket** lokal ergänzen. Eine Konfiguration mit echten Zugangsdaten gehört **niemals** in ein öffentliches Repository.

### 3. In der `server.cfg` starten

```cfg
ensure aeth_txadmin
```

Mehr Einträge sind für die Resource selbst nicht nötig.

### 4. Server starten und prüfen

In der **FXServer-Serverkonsole**:

```text
aeth_txadmin_logs_status
aeth_txadmin_bans_status
```

Die Befehle geben den Zustand der Live-Logs bzw. des Bann-Syncs aus. Sie sind **keine Spielerbefehle**.

### 5. Optional den Host-Helfer starten

Nur erforderlich für txAdmin-Dateilogs und/oder den Admin-Rangsync. Die Schritte dazu stehen unter [Vollständigeres txAdmin-Dateilogging](#vollständigeres-txadmin-dateilogging).

## Discord-Bot einrichten

1. Im [Discord Developer Portal](https://discord.com/developers/applications) eine Anwendung und darin einen Bot erstellen.
2. Den **Bot-Token vertraulich** in `Config.Discord.BotToken` eintragen.
3. Den Bot auf den gewünschten Discord-Server einladen und ihm **Rollen verwalten** erlauben.
4. Unter Discord **Entwicklermodus** die **Server-ID** und **Zielrollen-IDs** kopieren.
5. Die **höchste Bot-Rolle oberhalb sämtlicher verwalteter Rollen** anordnen.
6. Sicherstellen, dass die betroffenen Spieler/Administratoren Mitglied im Discord-Server sind.

Der Bot wird **nur für Discord-Rollen** benötigt. Zum Versenden der normalen Protokolle verwendet das Skript **Discord-Webhooks**.

Ein txAdmin-Bann verursacht **keinen Discord-Serverbann**: Es wird ausschließlich die eingestellte Discord-Rolle vergeben.

## Discord-Webhooks konfigurieren

Im gewünschten, **privaten** Discord-Kanal: **Kanal bearbeiten → Integrationen → Webhooks → Neuer Webhook**. Die URL in `Config.Logs.Webhooks` eintragen.

| Webhook-Feld | Inhalt |
|---|---|
| `Allgemein` | Ersatzkanal, wenn für eine Kategorie kein eigener Webhook gesetzt ist |
| `Moderation` | Banns, Entbannungen, Verwarnungen, Kicks, Heilungen |
| `Admin` | Authentifizierung, Adminlisten-Änderungen, txAdmin-Konsole, Konfigurationssignale |
| `AdminRoleSync` | Ergebnisse der txAdmin-Adminrollen-Synchronisierung |
| `BanSync` | Ergebnisse und Fehler der Discord-Bannrollen-Synchronisierung |
| `Whitelist` | Whitelist-Anträge, Freigaben, Ablehnungen |
| `Nachrichten` | txAdmin-Ankündigungen und Direktnachrichten |
| `Server` | Neustarts, übersprungene Neustarts und Shutdown-Ereignisse |
| `AdminDatei` | Neu geschriebene Zeilen aus `admin.log` |
| `KonsoleDatei` | Neu geschriebene Zeilen aus `fxserver.log` |
| `ServerDatei` | Neu geschriebene Zeilen aus `server.log` |

Für den Einstieg genügt ein gültiger Webhook unter `Allgemein`. Für eine saubere Administration empfehlen sich **getrennte Kanäle für Moderation, Admin, Admin-Dateilog und Rollensync**.

**Alle Webhook-URLs sind vertrauliche Zugangsdaten.** Eine bekannt gewordene URL sofort auf Discord zurücksetzen bzw. neu erstellen.

## Konfiguration erklärt

In `config.lua` stehen alle Optionen bereits mit Kommentaren. Die wichtigsten Bereiche:

| Bereich | Zweck | Wichtige Felder |
|---|---|---|
| `Config.Discord` | Bot und Discord-Zielserver | `BotToken`, `GuildId`, `BannedRoleId` |
| `Config.BanSync` | Discord-Rolle für txAdmin-Banns | `Enabled`, `CacheLicenseDiscordLinks`, `VerifyMinutes` |
| `Config.Logs` | txAdmin-Live-Logs über Webhooks | `Enabled`, `Webhooks`, `Events` |
| `Config.Logs.LogConsoleCommandArguments` | Konsolenargumente in Live-Logs zulassen | Standard: `false` |
| `Config.Logs.LogDirectMessageContent` | Inhalte der txAdmin-Direktnachrichten loggen | Standard: `false` |
| `Config.Logs.PersistQueue` | Live-Webhook-Nachrichten auf Datenträger zwischenspeichern | Standard: `true` |
| `Config.FileRelay` | Echte txAdmin-Logdateien auslesen | `Enabled`, `LogsDirectory`, `Admin`, `Fxserver`, `Server` |
| `Config.AdminRoleSync` | txAdmin-Rechte als Discord-Ränge anzeigen | `Enabled`, `AdminsPath`, `PollSeconds`, `TeamRoleId`, `OnlyHighestRank`, `Ranks` |

**Standardmäßig** sind die Live-Logs und der Bann-Sync aktiviert. Der Dateirelay ist in der Konfiguration vorbereitet, benötigt aber seinen **eigenen Prozess**. Die Admin-Rangsynchronisierung ist aus Sicherheitsgründen zunächst **deaktiviert**.

### Beispiel: Admin-Ränge frei zuordnen

Ein gekürzter Ausschnitt der `Config.AdminRoleSync`-Regeln:

```lua
Config.AdminRoleSync = {
    Enabled = false,           -- Erst nach Einrichtung aktivieren
    AdminsPath = 'C:/FXServer/txData/admins.json',
    PollSeconds = 60,
    TeamRoleId = '',           -- Optional: alle txAdmin-Admins
    OnlyHighestRank = true,   -- Nur den höchsten passenden Rang
    DiscordLinks = {},

    Ranks = {
        {
            name = 'Master / Owner',
            roleId = '100000000000000000',
            master = true,
        },
        {
            name = 'Vollzugriff',
            roleId = '200000000000000000',
            mode = 'any',
            permissions = {'all_permissions'},
        },
        {
            name = 'Leitung',
            roleId = '300000000000000000',
            mode = 'any',
            permissions = {'manage.admins', 'control.server', 'console.write'},
        },
        {
            name = 'Administrator',
            roleId = '400000000000000000',
            mode = 'any',
            permissions = {'players.ban', 'players.whitelist'},
        },
        {
            name = 'Supporter',
            roleId = '500000000000000000',
            mode = 'any',
            permissions = {'players.warn', 'players.kick'},
        },
    }
}
```

> **Beispiel, nicht eine zweite Konfiguration:** Die tatsächlichen Regeln werden **nur innerhalb der bereits vorhandenen `Config.AdminRoleSync` in der `config.lua`** angepasst. Rollen-IDs und Hostpfade oben sind Platzhalter. Die ausgelieferte `config.lua` enthält zusätzliche kommentierte Rechte und Einstellungen.

**Regellogik:**

- `mode = 'any'`: Mindestens eines der genannten txAdmin-Rechte reicht.
- `mode = 'all'`: Alle genannten txAdmin-Rechte sind erforderlich.
- `master = true`: Ausschließlich das tatsächliche txAdmin-Masterkonto.
- `OnlyHighestRank = true`: Die **erste passende** Regel in der Liste gewinnt.
- `OnlyHighestRank = false`: Mehrere passende Discord-Ränge sind möglich.
- `TeamRoleId`: Zusätzliche gemeinsame Discord-Rolle für verknüpfte txAdmin-Konten.
- `DiscordLinks`: Manuelle Zuordnung von txAdmin-Benutzername zu Discord-ID, wenn keine eindeutige Discord-Verknüpfung vorhanden ist.

**Rangnamen sind AETHRALETH-Beispiele, keine offiziellen txAdmin-Ränge.** txAdmin arbeitet mit einzelnen Berechtigungen. Alle **27 dokumentierten Permission-Keys** sind weiter unten im Abschnitt [Alle txAdmin-Berechtigungen erklärt](#alle-txadmin-berechtigungen-erklärt) aufgeführt.

## Alle txAdmin-Berechtigungen erklärt

Die folgende Übersicht beschreibt die 27 in der betrachteten txAdmin-Version dokumentierten Permission-Keys. Der txAdmin Admin Manager bestimmt, welche Rechte eine Person tatsächlich erhält. Die Discord-Ränge in `Config.AdminRoleSync.Ranks` sind **frei definierte Anzeigerollen**, keine offiziellen txAdmin-Ränge.

| Permission | Bedeutung |
|---|---|
| `all_permissions` | Alle verfügbaren txAdmin-Rechte, aber **nicht** automatisch das echte Masterkonto. |
| `manage.admins` | txAdmin-Adminkonten anlegen, ändern und entfernen. |
| `settings.view` | Einstellungen ansehen (nicht die geschützten Token). |
| `settings.write` | txAdmin-Einstellungen ändern. |
| `console.view` | Live-Konsole lesen. |
| `console.write` | Befehle in der Live-Konsole ausführen; sehr weitreichend. |
| `control.server` | Gameserver starten, anhalten und neu starten. |
| `announcement` | Ankündigungen senden. |
| `commands.resources` | FiveM-Resources starten oder stoppen. |
| `server.cfg.editor` | `server.cfg` lesen und verändern; besonders mächtig. |
| `txadmin.log.view` | txAdmin-Aktionslog ansehen. |
| `server.log.view` | Serverprotokolle ansehen. |
| `menu.vehicle` | Fahrzeuge über das Admin-Menü spawnen/reparieren. |
| `menu.clear_area` | Bereich von Objekten/Fahrzeugen bereinigen. |
| `menu.viewids` | Spieler-IDs im Spiel anzeigen. |
| `players.direct_message` | Spielern private txAdmin-Nachrichten senden. |
| `players.whitelist` | Whitelist/Allowlist verwalten. |
| `players.warn` | Spieler verwarnen. |
| `players.kick` | Spieler vom Server kicken. |
| `players.ban` | Spieler bannen und entbannen. |
| `players.freeze` | Spieler einfrieren. |
| `players.heal` | Sich oder andere heilen. |
| `players.playermode` | NoClip, Godmode und Superjump. |
| `players.spectate` | Spieler beobachten. |
| `players.teleport` | Sich selbst oder andere teleportieren. |
| `players.troll` | Troll-Funktionen aus dem Admin-Menü. |
| `players.remove_ids` | Gespeicherte Spieler-IDs/HWIDs aus der Datenbank entfernen. |

*Die verfügbaren Berechtigungen können sich mit txAdmin-Versionen ändern. Neue/umbenannte Permission-Keys müssen bei Bedarf in `config.lua` berücksichtigt werden.*

### Beispiel-Zuordnung der Discord-Ränge

| Discord-Rang | Beispiel-Auslöser aus txAdmin | Bedeutung |
|---|---|---|
| Master / Owner | `master=true` | Nur das tatsächliche txAdmin-Masterkonto |
| Vollzugriff | `all_permissions` | Umfassende Berechtigung, nicht automatisch Master |
| Leitung | `manage.admins`, `control.server`, `console.write`, `server.cfg.editor` oder `settings.write` | Verwaltung von Server/Administratoren |
| Administrator | `players.ban` oder `players.whitelist` | Moderation mit Bann- bzw. Whitelist-Rechten |
| Supporter | `players.warn`, `players.kick` oder `players.direct_message` | Unterstützung und niedrigschwellige Moderation |
| txAdmin-Team | `TeamRoleId` gesetzt und Discord-Konto zugeordnet | Gemeinsame Rolle für alle erkannten txAdmin-Admins |

Bei `OnlyHighestRank=true` erhält der Admin nur die erste zutreffende Rangrolle in der konfigurierten Reihenfolge. `TeamRoleId` kann zusätzlich vergeben werden. Ein reines Lese-Recht wie `console.view` reicht für keine der voreingestellten Rangstufen, kann aber trotzdem zur Teamrolle führen. Bei `OnlyHighestRank=false` sind mehrere Rangrollen möglich. **Bestehende manuell vergebene Discord-Rollen werden beim Rechteentzug nicht automatisch gelöscht.**

## Vollständigeres txAdmin-Dateilogging

Neben den Live-Ereignissen besitzt txAdmin persistente Protokolle unter `txData/<profil>/logs/`:

| Datei | Typische Inhalte | Standard in `aeth_txadmin` |
|---|---|---|
| `admin.log` | Adminaktionen, Bann-/Warnaktionen, Administrationsänderungen und Konsolenbefehle | Aktiviert |
| `fxserver.log` | FXServer-Konsolenein- und -ausgabe | Deaktiviert |
| `server.log` | Serveraktionen, Spielerverbindungen, Chat-/Spielereignisse | Deaktiviert |

**Warum ein zusätzlicher Host-Prozess?** FiveM-Resources dürfen aufgrund der Sandbox externe Dateien im `txData`-Ordner nicht ohne Weiteres direkt öffnen. Daher liest `tools/log_relay.js` die Logdateien als **separater Node.js-Prozess**, während die FiveM-Resource seine Konfiguration bereitstellt.

### Einrichtung des Dateirelays

1. In `config.lua` einen **absoluten Pfad** zu deinem echten txAdmin-Logordner eintragen:

   ```lua
   Config.FileRelay.LogsDirectory = 'C:/FXServer/txData/default/logs'
   ```

   Linux-Beispiel: `/home/fivem/txData/default/logs`. Beide Pfade sind nur Beispiele.

2. In `Config.FileRelay` die zu lesenden Logarten bestimmen: `Admin`, `Fxserver`, `Server`. Für Konsolen- und Serverdateien die Datenschutzrisiken beachten.
3. Einen gültigen Webhook `AdminDatei` oder ersatzweise `Admin`/`Allgemein` konfigurieren.
4. Die FiveM-Resource starten oder neu starten. Dabei wird `data/relay_settings.json` geschrieben.
5. **Auf dem Server-Host** im Resource-Ordner ausführen:

   ```bash
   node tools/log_relay.js
   ```

   Alternativ `tools/start_relay_windows.bat` oder `tools/start_relay_linux.sh` nutzen. Der Prozess sollte über einen Host-Prozessmanager dauerhaft laufen.

**Wichtig:** `ensure aeth_txadmin` startet den Node-Helfer **nicht**. Ohne Node-Prozess werden keine txAdmin-Dateilogs oder Admin-Ränge abgeglichen.

### Dateirelay-Einstellungen

| Feld | Erklärung |
|---|---|
| `Enabled` | Datei-Weiterleitung zulassen |
| `LogsDirectory` | Absoluter Pfad zum `txData/<profil>/logs/`-Ordner |
| `Admin` | `admin.log` lesen |
| `Fxserver` | `fxserver.log` lesen; zunächst aus Datenschutzgründen aus |
| `Server` | `server.log` lesen; zunächst aus Datenschutzgründen aus |
| `PollMilliseconds` | Prüfintervall für neue Zeilen; Standard: 2000 ms |
| `MaxPending` | Maximale Anzahl zwischengespeicherter Dateilog-Nachrichten |
| `StartAtEnd` | Bei erstmaliger Einrichtung ab dem **aktuellen Dateiende** beginnen, statt alle alten Zeilen zu senden |

Neue Dateizeilen werden in Discord-Nachrichten zusammengefasst und bei temporären Versandfehlern erneut versucht. Dateipositionen und noch nicht gesendete Meldungen werden lokal gespeichert. Durch Dateirotation, Abstürze, Limits oder einen dauerhaft vollen Puffer **können dennoch Lücken oder Doppelmeldungen entstehen**.

## Automatischer Bannrollen-Sync

Die FiveM-Resource verarbeitet `txAdmin:events:playerBanned` und `txAdmin:events:actionRevoked`.

**Ablauf:**

1. txAdmin bannt einen Spieler, während das Live-Ereignis bei der Resource ankommt.
2. `aeth_txadmin` versucht, aus dem Bann einen Discord-Identifier oder eine bereits gespeicherte Lizenz-/Discord-Zuordnung zu bestimmen.
3. Wenn das Discord-Mitglied gefunden wird, vergibt der Bot die konfigurierte `BannedRoleId`.
4. Wird der **erfasste Bann** aufgehoben oder läuft ein erfasster Zeitbann ab, gleicht das Skript die Rolle erneut ab.
5. Bei mehreren bekannten aktiven Banns bleibt die Rolle bestehen, solange noch ein relevanter Bann aktiv ist.

**Sicherheitsregel:** Eine **vorher manuell vergebene Rolle** wird von der Resource nicht als ihre eigene Rolle beansprucht und beim Entbannen nicht automatisch entfernt.

**Grenzen:** Ein Bann ohne eindeutige Discord-Zuordnung erhält keine Discord-Rolle. Während der FXServer gestoppt ist, gehen txAdmin-Live-Ereignisse an die Resource verloren. Die aktuelle Version führt **keinen vollständigen nachträglichen Abgleich mit txAdmins Bann-Datenbank** durch.

## Automatischer Admin-Rangsync

Die optionale Funktion liest die **globale** Datei `txData/admins.json` mit dem separaten Node-Helfer. Diese Datei wird **niemals vom Skript verändert**.

**Einrichtung:**

1. Die gewünschte Discord-Teamrolle und alle Rangrollen erstellen.
2. Bot-Rolle in Discord **über** diese Rollen stellen.
3. `Config.AdminRoleSync.AdminsPath` auf die **globale** `txData/admins.json` setzen – **nicht** auf `txData/<profil>/logs/`.
4. `Config.AdminRoleSync.Ranks` und optional `DiscordLinks` anpassen.
5. `Config.AdminRoleSync.Enabled = true` setzen.
6. Die FiveM-Resource neu starten, damit die private Relay-Konfiguration neu erstellt wird.
7. `node tools/log_relay.js` starten bzw. den laufenden Host-Helfer neu starten.
8. Mit einem **Test-Admin** Rechte erteilen, verändern und entfernen; Discord-Rollen und Webhook `AdminRoleSync` kontrollieren.

Der Abgleich läuft nach `PollSeconds` (mindestens 30 Sekunden). Sind Berechtigungen, `admins.json` oder ein gespeicherter Zustand ungültig, wird **keine Rangzuordnung geraten**. Ist eine Discord-Rolle bereits manuell vorhanden, bleibt sie außerhalb der Eigentumsverwaltung dieses Skripts.

**txAdmin bleibt die einzige Quelle für echte Adminrechte.** Das Hinzufügen oder Entfernen einer Discord-Rolle vergibt bzw. entzieht **keine** txAdmin-Berechtigung.

## Unterstützte txAdmin-Ereignisse

Die Resource registriert die folgenden **17 dokumentierten Live-Ereignisse**, die einzeln unter `Config.Logs.Events` deaktiviert werden können:

| Kategorie | Ereignisse |
|---|---|
| Server | `announcement`, `serverShuttingDown`, `scheduledRestart`, `scheduledRestartSkipped` |
| Spieler / Moderation | `playerBanned`, `playerDirectMessage`, `playerHealed`, `playerKicked`, `playerWarned` |
| Whitelist | `whitelistPlayer`, `whitelistPreApproval`, `whitelistRequest` |
| Administration | `actionRevoked`, `adminAuth`, `adminsUpdated`, `configChanged`, `consoleCommand` |

Nicht jedes Ereignis enthält ausführliche Daten; beispielsweise signalisiert `adminsUpdated` primär, **dass** sich die Adminliste geändert hat. Detailliertere Adminaktionen sind gegebenenfalls im `admin.log` zu finden. Die Event-Namen und Payloads sind in der [offiziellen txAdmin-Ereignisdokumentation](https://github.com/citizenfx/txAdmin/blob/master/docs/events.md) beschrieben.

## Statusbefehle und Funktionstest

**Nur in der Serverkonsole:**

```text
aeth_txadmin_logs_status
aeth_txadmin_bans_status
```

Empfohlene Abnahme vor dem Produktivbetrieb:

1. Einen harmlosen txAdmin-Live-Konsolenbefehl ausführen und den `Admin`-Webhook prüfen.
2. Eine Testverwarnung und einen Testbann mit einem eigenen Testkonto auslösen.
3. Kontrollieren, ob die Bannrolle vergeben und bei Bannaufhebung entfernt wird.
4. Den Test mit einem **zeitlich begrenzten Bann** wiederholen.
5. Den Host-Helfer starten; eine neue Adminaktion ausführen und `admin.log` mit `AdminDatei` vergleichen.
6. Einem txAdmin-Testadmin eine Berechtigung geben und entziehen; die entsprechende Discord-Rolle kontrollieren.
7. Resource-/Host-Neustarts prüfen und sicherstellen, dass Zustandsdateien erhalten bleiben.

**Tests im Repository** (Node.js):

```bash
node --check tools/admin_roles.js
node --check tools/log_relay.js
node tests/test_admin_roles.js
node tests/test_file_relay.js
```

Zusätzliche Lua-Mocktests liegen unter `tests/`, erfordern jedoch eine geeignete Lua-Umgebung. **Offline-Tests ersetzen keinen echten Integrationstest.**

## Fehlerbehebung

| Problem | Häufige Ursache / Prüfung |
|---|---|
| Keine Webhook-Meldungen | `Config.Logs.Enabled`, gültige URL, Discord-Kanalrechte, Logs-Status prüfen |
| Banns werden geloggt, aber keine Discord-Rolle | Bot-Berechtigung/-Hierarchie, Discord-Identifier, Guild-/Rollen-ID prüfen |
| Rolle bleibt nach Entbannung | Weiterer bekannter Bann, manuell vorhandene Rolle oder fehlendes Revocation-Event |
| Admin-Ränge erscheinen nicht | `AdminRoleSync.Enabled=false`, falscher `AdminsPath`, kein Node-Helfer, fehlende Discord-Zuordnung |
| Keine `admin.log`-Nachrichten | `FileRelay` nicht aktiv, Node-Prozess nicht gestartet, Logordner/Dateiname/Dateirechte prüfen |
| Nach Erststart fehlen ältere Dateilog-Zeilen | `StartAtEnd=true` beginnt bewusst am aktuellen Dateiende |
| Dieselbe Aktion zweimal in Discord | Live-Event **und** Admin-Dateilog spiegeln denselben Vorfall |
| Webhook meldet HTTP 429 | Discord-Rate-Limit; Nachrichten werden verzögert oder je nach Warteschlange verworfen |
| Nach Update fehlen Zuordnungen | `data/state.json` bzw. `data/admin_roles_state.json` wurde nicht übernommen |
| Konfiguration fehlt nach `git clone` | Die private `config.lua` ist absichtlich nicht im Git-Repository enthalten; lokale Vorlage aus dem Release-ZIP übernehmen |

## Sicherheit und Datenschutz

> [!CAUTION]
> **Niemals den echten Bot-Token, Webhook-URLs, `txData/admins.json`, private txAdmin-Logs oder Zustandsdateien veröffentlichen.** Wer Zugang zu einem Webhook hat, kann in dessen Discord-Kanal Nachrichten versenden. Ein kompromittierter Bot-Token muss zurückgesetzt werden.

- Die Dateien `config.lua`, `data/relay_settings.json`, `data/state.json`, `data/admin_roles_state.json`, `data/live_queue.json` und `data/relay_offsets.json` privat halten und beim Git-Upload überprüfen.
- **`relay_settings.json` kann sowohl Webhook-URLs als auch den Bot-Token enthalten.** Dateirechte entsprechend einschränken.
- `txData/admins.json` kann sensible Kontoinformationen enthalten; der Host-Helfer liest sie nur lesend und sendet sie nicht vollständig an Discord.
- Admin-, Server- und Konsolenlogs können Identifiers, IP-Adressen, Chat-Inhalte oder Geheimnisse enthalten. Ausschließlich **private Discord-Logkanäle mit minimalen Zugriffsrechten** verwenden.
- Die Optionen `LogConsoleCommandArguments` und `LogDirectMessageContent` stehen standardmäßig auf `false`; rohe `fxserver.log`- und `server.log`-Weiterleitung ebenfalls. Maskierung ersetzt **keine** vollständige Prüfung auf personenbezogene oder geheime Daten.
- Verzeichniszugriff und Aufbewahrung der Logs nach deinen geltenden Datenschutzregeln einschränken.
- Den Node-Helfer nur einmal starten. Seine Lock-Datei soll doppelte parallele Prozesse verhindern.

## Bekannte Einschränkungen

- **Keine vollständige Offline-Bann-Synchronisierung:** Offline durchgeführte txAdmin-Banns können nicht anhand von Logzeilen zuverlässig als Discord-Rollen rekonstruiert werden.
- **Keine 100-%-Loggarantie:** Live-Ereignisse treffen nur ein, wenn die Resource ausgeführt wird. Bei Dateirotation, Abstürzen, API-/Rate-Limits und Netzwerkfehlern können Einträge fehlen oder mehrfach zugestellt werden.
- **Quellen-Doppelungen:** Die gleiche Adminaktion kann sowohl als Live-Event als auch als `admin.log`-Eintrag erscheinen.
- **Discord-Zuordnung nötig:** Ohne passende Discord-ID oder gespeicherte, eindeutige Verknüpfung ist keine Rollenvergabe möglich.
- **Manuelle Discord-Rollen bleiben erhalten:** Fremdvergebene Rollen werden auch bei entfallenen txAdmin-Rechten nicht automatisch entfernt.
- **Eigenständiger Host-Helfer nötig:** Für Dateilogs und Admin-Rangsync ist Node.js außerhalb von FXServer nötig.
- **Schemaabhängigkeit:** Ändern sich die txAdmin-Struktur von `admins.json`, Ereignisse oder Berechtigungsnamen, kann ein Update der Integration erforderlich werden.
- **Kein Live-Teststatus:** Stand 1.4.0 wurde offline geprüft; der volle Livebetrieb auf einem FiveM-Server ist noch nicht nachgewiesen.

## Updates und Datensicherung

**Vor jedem Update:** FXServer-Resource und Host-Helfer kontrolliert anhalten, die vorhandene `config.lua` und die Inhalte von `data/` sichern.

Besonders wichtig:

```text
data/state.json
data/admin_roles_state.json
data/relay_offsets.json
data/live_queue.json
```

`data/state.json` enthält erfasste Bann- und Discord-Zuordnungen, `data/admin_roles_state.json` die verwalteten Adminrollen, die übrigen Dateien Logpositionen und Warteschlangen. **Diese Daten nicht mit leeren Dateien überschreiben.** Nach einem Update neue Konfigurationsfelder aus der neuen Version übernehmen, bevor die alte Konfiguration weiterverwendet wird.

Beim Umstieg von der früheren Resource `aeth_txadmin_discord` nur **eine** Synchronisierung betreiben; die alte `data/state.json` gegebenenfalls nach Sicherung übernehmen. Frühere Kanal-ID-Konfigurationen sind nicht mit den jetzigen **Webhook-URLs** gleichzusetzen.

Änderungen der Version 1.4.0: konfigurierbarer Admin-Rangsync, automatische Rollenanpassung bei Rechteänderungen und zusätzlicher Adminrollen-Webhook. Frühere Funktionen wie BanSync, Live-Event-Logging und Dateirelay bleiben enthalten.

## Projektstruktur

```text
aeth_txadmin/
├── fxmanifest.lua
├── config.lua                    # Lokal/privat, im Git-Repository ignoriert
├── server/
│   ├── logger.lua                # txAdmin-Live-Ereignisse + Discord-Webhooks
│   ├── ban_sync.lua              # Bannrollen-Synchronisierung
│   └── relay_settings.lua        # Konfiguration für den externen Host-Helfer
├── tools/
│   ├── log_relay.js              # Dateilog-Relay und Host-Einstieg
│   ├── admin_roles.js            # txAdmin-Adminrechte → Discord-Rollen
│   ├── start_relay_windows.bat
│   └── start_relay_linux.sh
├── tests/                        # Offline-/Mocktests (ausführbare Skripte)
├── data/                         # Private Zustands- und Warteschlangendateien
├── .gitignore                    # Schutz privater Laufzeit-Dateien
└── README.md                     # Einzige Dokumentationsdatei inkl. Lizenz
```

## Lizenz und Quellen

### AETHRALETH – Nichtkommerzielle Nutzungslizenz

Copyright (c) 2026 AETHRALETH.

Die Nutzung, Installation, Prüfung, Modifikation und Weitergabe dieses Skripts ist nur für nichtkommerzielle Projekte gestattet. Der Hinweis auf AETHRALETH als Urheber/Projektmarke muss in weitergegebenen Kopien des Skripts sichtbar erhalten bleiben. Anpassungen müssen als Anpassungen gekennzeichnet werden und dürfen nicht als ausschließlich eigene Originalarbeit ausgegeben werden.

Der Verkauf, Weiterverkauf, die Vermietung oder sonstige entgeltliche Lizenzierung dieses Skripts oder abgeleiteter Versionen ist ohne gesonderte schriftliche Erlaubnis des Rechteinhabers untersagt. Das Skript darf nicht zur Bestandteil eines kostenpflichtigen Skriptpakets gemacht werden.

Die Software wird ohne Zusicherung bestimmter Eigenschaften und, soweit gesetzlich zulässig, ohne Gewährleistung bereitgestellt.

Dies ist eine individuelle, **nicht Open-Source-konforme** (nicht-OSI) Nutzungslizenz. Sie kann vor einer öffentlichen Veröffentlichung juristisch überprüft werden.

**Hinweis:** Diese Bedingungen stehen absichtlich direkt in dieser `README.md`, damit es **nur eine zentrale Dokumentationsdatei** gibt. Die Lizenz ist eine individuelle, nicht OSI-anerkannte Lizenz. Eine rechtliche Prüfung vor Veröffentlichung ist empfehlenswert.

**Offizielle technische Dokumentation:**

- [txAdmin – Events](https://github.com/citizenfx/txAdmin/blob/master/docs/events.md)
- [txAdmin – Berechtigungen](https://github.com/citizenfx/txAdmin/blob/master/docs/permissions.md)
- [txAdmin – Logging](https://github.com/citizenfx/txAdmin/blob/master/docs/logs.md)
- [FiveM – Dateisystem-Sandbox](https://docs.fivem.net/docs/developers/sandbox/)
- [Discord – Developer Portal](https://discord.com/developers/applications)

---

<div align="center">

**AETHRALETH** · *Kontrolle, Nachvollziehbarkeit und klare Rechteverwaltung*

</div>
