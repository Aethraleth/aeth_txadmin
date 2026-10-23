'use strict';
/**
 * AETHRALETH | txAdmin private file-log relay.
 * Run as SEPARATE Node 18+ process ON THE SERVER HOST, never within browser/client.
 * This process reads txData's real log files which the FXServer resource sandbox
 * does not permit resources to access. No txAdmin APIs are scraped or modified.
 */
const fs = require('node:fs');
const path = require('node:path');
const settingsPath = path.join(__dirname, '..', 'data', 'relay_settings.json');
const statePath = path.join(__dirname, '..', 'data', 'relay_offsets.json');
const lockPath = path.join(__dirname, '..', 'data', 'relay_instance.lock');
const {AdminRoleSync}=require('./admin_roles');
const FILES = {admin: 'admin.log', fxserver: 'fxserver.log', server: 'server.log'};

function maskSecrets(line) {
    // File logs may hold arbitrary output. Do not attempt to forward lines
    // containing clearly sensitive credentials even if formatting is unfamiliar.
    if (/\b(?:sv_licensekey|rcon_password|mysql_connection_string|bot[_-]?token|api[_-]?key|password|secret|authorization|webhook)\b/i.test(String(line))) {
        return '[VERTRAULICHE LOGZEILE AUSGEBLENDET]';
    }
    return String(line)
        .replace(/https?:\/\/(?:discord(?:app)?\.com)\/api\/webhooks\/\d+\/[^\s]+/gi, '[DISCORD-WEBHOOK-ENTFERNT]')
        .replace(/(\b(?:Bot|Bearer)\s+)[A-Za-z0-9._-]{15,}/gi, '$1[GEHEIM]')
        .replace(/(\b(?:set|setr)\s+\S*(?:token|password|secret|licensekey|mysql_connection_string|webhook)\S*\s+)("[^"]*"|'[^']*'|\S+)/gi, '$1[GEHEIM]')
        .replace(/\bmysql:\/\/[^\s]+/gi, 'mysql://[GEHEIM]')
        .replace(/(["']?(?:token|password|secret|licensekey)["']?\s*[:=]\s*)["']?[^\s,}]+/gi, '$1[GEHEIM]');
}
function validWebhook(v) { return typeof v === 'string' && /^https:\/\/discord(?:app)?\.com\/api\/webhooks\/\d+\/[A-Za-z0-9_-]+$/.test(v); }
function safeLine(line) {
    return maskSecrets(line.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, ' '))
        .replace(/```/g, 'ˋˋˋ').replace(/@everyone/g, '@ everyone').replace(/@here/g, '@ here');
}
function loadJSON(file, fallback) { try {return JSON.parse(fs.readFileSync(file, 'utf8'));} catch { return fallback; } }
function saveAtomic(file, data) {
    const tmp = file + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(data), {mode:0o600});
    fs.renameSync(tmp, file);
}
function log(msg) { console.log(`[aeth_txadmin:file] ${msg}`); }

class Relay {
    constructor(config) {
        this.config = config;
        // Corrupt offset files must not silently reset or skip backlog.
        if (fs.existsSync(statePath)) {
            try { this.state=JSON.parse(fs.readFileSync(statePath,'utf8')); }
            catch(e) {throw new Error('relay_offsets.json beschaedigt; manuell aus Backup wiederherstellen: '+e.message);}
        } else this.state={offsets:{}, pending:[]};
        if (!this.state.offsets || typeof this.state.offsets !== 'object') this.state.offsets={};
        if (!Array.isArray(this.state.pending)) this.state.pending=[];
        this.sending = false;
        this.active = true;
        this.nextAttempt = 0;
        this.lastError = '';
        this.pollDelay = Math.max(1000, Math.min(60000, Number(config.pollMilliseconds) || 2000));
        this.maxPending = Math.max(100, Math.min(10000, Number(config.maxPending) || 3000));
    }
    store() { saveAtomic(statePath, this.state); }
    queueLineBatches(kind, lines) {
        let message = '';
        let pushed = 0;
        const flush = () => {
            if (!message) return;
            this.state.pending.push({kind, content:`**txAdmin ${FILES[kind]}**\n\`\`\`text\n${message}\n\`\`\``, tries:0});
            message = '';
            pushed++;
        };
        for (const raw of lines) {
            const line = safeLine(raw.replace(/\r$/, ''));
            if (message && message.length + line.length + 1 > 1400) flush();
            if (line.length > 1400) {
                // Unusually long lines: split rather than silently dropping data.
                for (let i=0; i<line.length; i+=1400) {
                    if (message) flush();
                    message=line.slice(i,i+1400); flush();
                }
            } else {
                message += (message ? '\n' : '') + line;
            }
        }
        flush();
        return pushed;
    }
    pollOne(kind) {
        if (!this.config.enabledKinds[kind] || !validWebhook(this.config.webhooks[kind])) return;
        if (this.state.pending.length + 40 > this.maxPending) return; // Queue full: never advance file cursor.
        const file = path.join(this.config.logDirectory, FILES[kind]);
        let fd;
        try { fd=fs.openSync(file,'r'); } catch(err) {
            if (err.code !== 'ENOENT') log(`${kind}: Kann ${file} nicht lesen (${err.code || err.message})`);
            return;
        }
        try {
            const stats = fs.fstatSync(fd);
            const identity = `${stats.dev}:${stats.ino}`;
            let point=this.state.offsets[kind];
            if (!point) {
                point={identity, pos:this.config.startAtEnd ? stats.size : 0};
                this.state.offsets[kind]=point;
                this.store();
                log(`${kind}: neuer Dateizustand ab Byte ${point.pos}`);
            }
            if (point.identity !== identity || stats.size < point.pos) {
                point.identity = identity;
                point.pos = 0; // new file after rotation/truncation
            }
            const bytes = Math.min(48*1024, stats.size - point.pos);
            if (bytes <= 0) return;
            const buff=Buffer.allocUnsafe(bytes);
            const n=fs.readSync(fd,buff,0,bytes,point.pos);
            const chunk=buff.subarray(0,n);
            const lastNewline=chunk.lastIndexOf(10);
            if (lastNewline < 0) {
                if (n >= 48*1024) {
                    // Safety valve for log streams without newlines.
                    const line=safeLine(chunk.toString('utf8'));
                    this.queueLineBatches(kind, [line]);
                    point.pos+=n;
                    this.store();
                }
                return;
            }
            const complete=chunk.subarray(0,lastNewline+1);
            const lines=complete.toString('utf8').split('\n');
            lines.pop();
            // Queue messages before committing file cursor for crash recovery.
            this.queueLineBatches(kind, lines);
            point.pos += complete.length;
            this.store();
        } finally {fs.closeSync(fd);}
    }
    poll() {
        // Fresh URLs/categories after resource restart, without restarting the helper.
        const updated=loadJSON(settingsPath, null);
        if (updated) {
            this.active=updated.enabled === true;
            if (this.active && updated.webhooks && updated.enabledKinds && path.isAbsolute(updated.logDirectory || '')) {
                this.config.webhooks=updated.webhooks;
                this.config.enabledKinds=updated.enabledKinds;
                this.config.logDirectory=updated.logDirectory;
            } else this.active=false;
        }
        if (!this.active) return;
        for (const kind of Object.keys(FILES)) this.pollOne(kind);
    }
    async sendOne() {
        if (!this.active || this.sending || Date.now()<this.nextAttempt || !this.state.pending.length) return;
        this.sending = true;
        const item=this.state.pending[0];
        try {
            // Resolve via current config rather than persisting secret webhook URLs
            // in the queue. This also allows reconfiguration without losing data.
            const webhook=this.config.webhooks[item.kind];
            if (!validWebhook(webhook)) throw new Error('Kein gueltiger Webhook fuer '+item.kind);
            const reply=await fetch(webhook, {
                method:'POST',headers:{'Content-Type':'application/json'},
                body:JSON.stringify({username:'AETHRALETH txAdmin Files',content:item.content,allowed_mentions:{parse:[]}})
            });
            if (reply.status === 200 || reply.status === 204) {
                this.state.pending.shift();
                this.store();
                this.lastError='';
                this.nextAttempt=Date.now()+1750;
            } else {
                let cooldown=reply.status === 429 ? 8000 : 20000;
                if (reply.status === 429) {
                    try {const o=await reply.json(); cooldown = Math.max(3000,Math.ceil((Number(o.retry_after)||5)*1000)+1000);} catch {}
                } else if (reply.status===401 || reply.status===403 || reply.status===404) cooldown=300000;
                this.nextAttempt=Date.now()+cooldown;
                const err=`Discord HTTP ${reply.status}, erneuter Versuch in ${Math.ceil(cooldown/1000)}s`;
                if (this.lastError!==err) {log(err); this.lastError=err;}
            }
        } catch(e) {
            this.nextAttempt=Date.now()+20000;
            log(`Netzwerkfehler: ${e.message}`);
        } finally { this.sending=false; }
    }
    start() {
        log('Dateirelay gestartet (admin.log, fxserver.log, server.log je nach config.lua).');
        const loop=async()=>{try {this.poll(); await this.sendOne();} catch(e) {log('FEHLER: '+e.message);} };
        loop(); setInterval(loop,this.pollDelay);
    }
}

function acquireLock() {
    const create=() => {
        const fd=fs.openSync(lockPath,'wx',0o600);
        try {fs.writeFileSync(fd,String(process.pid));} finally {fs.closeSync(fd);}
    };
    try {create();} catch(e) {
        if (e.code !== 'EEXIST') throw e;
        const pid=Number(loadText(lockPath));
        if (Number.isSafeInteger(pid) && pid>0 && pid !== process.pid) {
            try {process.kill(pid,0); throw new Error('Ein anderer Relay-Prozess laeuft bereits (PID '+pid+').');}
            catch(err) {if (err.code !== 'ESRCH') throw err;}
        }
        fs.unlinkSync(lockPath); create();
    }
    process.on('exit', () => {try {if (loadText(lockPath)===String(process.pid)) fs.unlinkSync(lockPath);} catch {}});
    for(const signal of ['SIGTERM','SIGINT']) process.once(signal,()=>process.exit(0));
}
function loadText(file) {try{return fs.readFileSync(file,'utf8').trim();}catch{return '';}}
function main() {
    const config=loadJSON(settingsPath, null);
    if (!config) throw new Error('Relay-Einstellungen fehlen. Resource einmal starten.');
    const fileEnabled=config.enabled===true;
    const roleEnabled=config.adminRoles?.enabled===true;
    if (!fileEnabled && !roleEnabled) throw new Error('FileRelay und AdminRoleSync sind deaktiviert.');
    if (typeof fetch !== 'function') throw new Error('Node.js 18+ erforderlich (global fetch).');
    let relay;
    if (fileEnabled) {
        if (!path.isAbsolute(config.logDirectory)) throw new Error('LogsDirectory muss ein ABSOLUTER Host-Dateipfad sein.');
        if (!config.webhooks || !config.enabledKinds) throw new Error('Webhook-Konfiguration fehlt.');
        const active=Object.keys(FILES).filter(x=>config.enabledKinds[x] && validWebhook(config.webhooks[x]));
        if (active.length) {
            relay=new Relay(config);
            log(`Aktive Dateien: ${active.map(x=>FILES[x]).join(', ')}`);
        } else log('Dateirelay ohne aktive Webhook-Kategorien, ausgesetzt.');
    }
    const adminSync=roleEnabled ? new AdminRoleSync(config.adminRoles) : null;
    if (!relay && !adminSync) throw new Error('Keine aktive Host-Funktion.');
    acquireLock();
    if (relay) relay.start();
    if (adminSync) {
        console.log('[aeth_txadmin:roles] AdminRoleSync gestartet (nur Lesezugriff auf txAdmin).');
        adminSync.poll();
        setInterval(()=>adminSync.poll(), 5000);
    }
}

if (require.main === module) {try {main();} catch(e) {console.error('[aeth_txadmin:file] '+e.message); process.exitCode=1;}}
module.exports={maskSecrets,safeLine,validWebhook,Relay};
