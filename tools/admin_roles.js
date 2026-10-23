'use strict';
/**
 * AETHRALETH txAdmin -> Discord role mirror (READ ONLY txData/admins.json).
 * Only reads the txAdmin admin list. Never writes permissions or txAdmin files.
 * Does not import passwords, hashes, or private provider details into state.
 */
const fs = require('node:fs');
const path = require('node:path');

const VALID_ID = /^\d{17,22}$/;
const API = 'https://discord.com/api/v10';
const STATE_PATH = path.join(__dirname, '..', 'data', 'admin_roles_state.json');
const validId = value => typeof value === 'string' && VALID_ID.test(value);
const validHook = value => typeof value === 'string' && /^https:\/\/discord(?:app)?\.com\/api\/webhooks\/\d+\/[\w-]+$/.test(value);

function extractDiscord(admin, manualLinks={}) {
  const direct = admin.discordID || admin.discordId;
  if (validId(direct)) return direct;
  const provider = admin.providers && admin.providers.discord;
  const ids = [provider, provider && provider.id, provider && provider.userId, provider && provider.user_id, provider && provider.discordId];
  for (const id of ids) if (validId(id)) return id;
  if (Array.isArray(admin.identifiers)) {
    for (const id of admin.identifiers) {
      if (typeof id === 'string' && /^discord:\d{17,22}$/.test(id)) return id.slice(8);
    }
  }
  const linked = manualLinks[admin.name];
  return validId(linked) ? linked : null;
}

function validRanks(config) {
  if (!Array.isArray(config.ranks) || !config.ranks.length) throw new Error('Keine Rangregeln konfiguriert.');
  const seen = new Set();
  for (const rank of config.ranks) {
    if (!rank || typeof rank.name !== 'string' || !rank.name || !validId(rank.roleId)) throw new Error('Ungueltiger Rangname oder Rollen-ID.');
    if (seen.has(rank.roleId)) throw new Error('Discord-Rollen-ID bei mehreren Raengen verwendet.');
    seen.add(rank.roleId);
    if (rank.master !== true && (rank.mode !== 'any' && rank.mode !== 'all')) throw new Error('Rang braucht mode=any/all oder master=true.');
    if (rank.master !== true && (!Array.isArray(rank.permissions) || !rank.permissions.length || rank.permissions.some(p=>typeof p!=='string'))) {
      throw new Error('Rang hat keine gueltige Permission-Liste.');
    }
  }
  if (validId(config.teamRoleId) && seen.has(config.teamRoleId)) throw new Error('Teamrolle muss eine eigene Rolle sein.');
}
function desiredRoles(admin, cfg) {
  const perms = new Set(admin.permissions || []);
  const desired = validId(cfg.teamRoleId) ? [cfg.teamRoleId] : [];
  const all = perms.has('all_permissions') || admin.master === true;
  for (const rank of cfg.ranks) {
    const matches = rank.master === true ? admin.master === true : (
      all || (rank.mode==='all' ? rank.permissions.every(p=>perms.has(p)) : rank.permissions.some(p=>perms.has(p)))
    );
    if (!matches) continue;
    desired.push(rank.roleId);
    if (cfg.onlyHighestRank !== false) break;
  }
  return desired;
}
function loadAdmins(file, cfg) {
  if (!path.isAbsolute(file)) throw new Error('AdminsPath muss ein ABSOLUTER Hostpfad sein.');
  const stat=fs.statSync(file);
  if (!stat.isFile() || stat.size>2*1024*1024) throw new Error('admins.json keine gueltige Datei oder zu gross.');
  const raw=JSON.parse(fs.readFileSync(file, 'utf8'));
  // Official txAdmin vault has a top-level array; don't guess on changed schemas.
  if (!Array.isArray(raw) || raw.length === 0 || !raw.some(x=>x && x.master===true)) {
    throw new Error('admins.json: nicht erkanntes Schema oder kein Masterkonto. Keine Rollen aendern.');
  }
  const target={};
  const ownership=new Set();
  for (const a of raw) {
    if (!a || typeof a.name!=='string' || !Array.isArray(a.permissions) || (a.master !== undefined && typeof a.master!=='boolean')) {
      throw new Error('admins.json: Adminstruktur unerwartet. Keine Rollen aendern.');
    }
    if (a.permissions.some(x=>typeof x!=='string')) throw new Error('admins.json: unbekanntes Berechtigungsformat.');
    const discord=extractDiscord(a,cfg.discordLinks||{});
    if (!discord) continue;
    if (ownership.has(discord)) throw new Error('Mehrere txAdmin-Konten zeigen auf dieselbe Discord-ID; Zuordnung klaeren.');
    ownership.add(discord);
    target[discord]={ name:a.name, roles:desiredRoles(a,cfg)};
  }
  return target;
}
function loadState() {
  if (!fs.existsSync(STATE_PATH)) return {version:1, users:{}};
  const raw=JSON.parse(fs.readFileSync(STATE_PATH,'utf8'));
  if (raw.version!==1 || !raw.users || typeof raw.users!=='object' || Array.isArray(raw.users)) {
    throw new Error('admin_roles_state.json inkompatibel; Backup pruefen.');
  }
  for (const [id, user] of Object.entries(raw.users)) {
    if (!validId(id) || !user || !Array.isArray(user.owned) || user.owned.some(r=>!validId(r))) throw new Error('admin_roles_state.json beschaedigt; keine Rollen aendern.');
  }
  return raw;
}
function saveState(state) {
  const tmp=STATE_PATH+'.tmp';
  fs.writeFileSync(tmp, JSON.stringify(state), {mode:0o600});
  fs.renameSync(tmp, STATE_PATH);
}
class AdminRoleSync {
  constructor(settings, fetcher=fetch) {
    this.config=settings;
    this.fetch=fetcher;
    this.nextRun=0;
    this.busy=false;
    this.lastError='';
    validRanks(settings);
    if (!validId(settings.guildId) || typeof settings.botToken!=='string' || settings.botToken.length<20) {
      throw new Error('Discord BotToken/GuildId fuer AdminRoleSync fehlen.');
    }
    if (!path.isAbsolute(settings.adminsPath||'')) throw new Error('AdminsPath muss absolut sein.');
    this.state=loadState();
    this.interval=Math.max(30,Math.min(3600,Number(settings.pollSeconds)||60))*1000;
  }
  async discord(method, discord, roleId) {
    const endpoint=`${API}/guilds/${this.config.guildId}/members/${discord}${roleId ? '/roles/'+roleId:''}`;
    const result=await this.fetch(endpoint, {method, headers:{'Authorization':'Bot '+this.config.botToken}});
    if (result.status === 429) {
      let seconds=10;
      try {seconds=Math.max(5,Math.ceil(Number((await result.json()).retry_after)||10));} catch {}
      throw new Error(`Discord Rate-Limit (${seconds}s) - spaeter erneut pruefen.`);
    }
    if (result.status >= 500) throw new Error(`Discord API temporaer nicht erreichbar (${result.status}).`);
    return result;
  }
  async emit(message) {
    if (!validHook(this.config.webhook)) return;
    try {
      const res=await this.fetch(this.config.webhook,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:'AETHRALETH txAdmin',content:message,allowed_mentions:{parse:[]}})});
      if (res.status!==204 && res.status!==200) console.warn('[aeth_txadmin:roles] Log-Webhook HTTP '+res.status);
    } catch (e) { console.warn('[aeth_txadmin:roles] Webhook-Fehler: '+e.message); }
  }
  async sync() {
    // A new, valid snapshot is required BEFORE considering removal.
    const target=loadAdmins(this.config.adminsPath,this.config);
    const ids=new Set([...Object.keys(target),...Object.keys(this.state.users)]);
    const managed=new Set(this.config.ranks.map(r=>r.roleId));
    if (validId(this.config.teamRoleId)) managed.add(this.config.teamRoleId);
    for (const userId of ids) {
      const planned=target[userId]?.roles || [];
      const desired=new Set(planned);
      const owned=new Set(this.state.users[userId]?.owned || []);
      const response=await this.discord('GET',userId);
      if (response.status===404) {
        // Not a member yet. Keep previously owned roles recorded so they can be reconciled when rejoining.
        continue;
      }
      if (response.status!==200) throw new Error(`Mitglied ${userId}: GET HTTP ${response.status}`);
      const member=await response.json();
      if (!member || !Array.isArray(member.roles)) throw new Error('Discord-Mitglied-Antwort ungueltig.');
      const actual=new Set(member.roles);
      // Permission changes: remove ONLY roles that this integration previously granted.
      for (const roleId of [...owned]) {
        if (desired.has(roleId)) continue;
        if (actual.has(roleId)) {
          const removed=await this.discord('DELETE',userId,roleId);
          if (removed.status!==204 && removed.status!==404) throw new Error(`Rolle entfernen: HTTP ${removed.status}`);
          await this.emit(`txAdmin Rangsync: Rolle ${roleId} von Discord ${userId} entfernt.`);
        }
        owned.delete(roleId);
        this.state.users[userId]={owned:[...owned]}; saveState(this.state);
      }
      for (const roleId of desired) {
        if (!managed.has(roleId)) continue;
        if (actual.has(roleId)) continue; // Pre-existing/manual role: DO NOT claim ownership.
        const result=await this.discord('PUT',userId,roleId);
        if (result.status!==204) throw new Error(`Rolle zuweisen: HTTP ${result.status}`);
        owned.add(roleId);
        this.state.users[userId]={owned:[...owned]}; saveState(this.state);
        await this.emit(`txAdmin Rangsync: Rolle ${roleId} an Discord ${userId} vergeben (${target[userId]?.name||'ehemaliger Admin'}).`);
      }
      if (owned.size) this.state.users[userId]={owned:[...owned]};
      else delete this.state.users[userId];
      saveState(this.state);
    }
    return {admins:Object.keys(target).length};
  }
  async poll() {
    if (this.busy || Date.now()<this.nextRun) return;
    this.busy=true;
    this.nextRun=Date.now()+this.interval;
    try {
      const result=await this.sync();
      this.lastError='';
      console.log(`[aeth_txadmin:roles] Admin-Sync geprüft (${result.admins} Discord-verknuepfte Admin-Konten).`);
    } catch(e) {
      if(this.lastError!==e.message) console.error('[aeth_txadmin:roles] '+e.message);
      this.lastError=e.message;
    } finally {this.busy=false;}
  }
}
module.exports={extractDiscord,desiredRoles,loadAdmins,validRanks,AdminRoleSync};
