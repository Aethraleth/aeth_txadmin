'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'aeth-adminroles-'));
fs.mkdirSync(path.join(tmp,'tools'));fs.mkdirSync(path.join(tmp,'data'));
fs.copyFileSync(path.join(__dirname,'..','tools','admin_roles.js'),path.join(tmp,'tools','admin_roles.js'));
const {extractDiscord,desiredRoles,loadAdmins,AdminRoleSync}=require(path.join(tmp,'tools','admin_roles.js'));
const id='123456789012345678';
const id2='223456789012345678';
const guild='323456789012345678';
const roleTeam='423456789012345678';
const roleSupport='523456789012345678';
const roleMod='623456789012345678';
const roleFull='723456789012345678';
const roleOwner='823456789012345678';
const admins=path.join(tmp,'admins.json');
const cfg={enabled:true,adminsPath:admins,botToken:'x'.repeat(30),guildId:guild,pollSeconds:30,teamRoleId:roleTeam,onlyHighestRank:true,
  ranks:[{name:'Owner',roleId:roleOwner,master:true},{name:'Full',roleId:roleFull,mode:'any',permissions:['all_permissions']},
    {name:'Admin',roleId:roleMod,mode:'any',permissions:['players.ban']},{name:'Support',roleId:roleSupport,mode:'any',permissions:['players.warn']}],discordLinks:{}};
function admin(name,dis,permissions,master=false) {return {name,master,providers:dis?{discord:dis}:{},permissions,password_hash:'TOP_SECRET_SHOULD_NEVER_WRITE'};}
function write(users) {fs.writeFileSync(admins,JSON.stringify(users));}
async function main() {
  assert.equal(extractDiscord({name:'alpha',providers:{discord:{id}}}),id);
  assert.equal(extractDiscord({name:'alpha',identifiers:['discord:'+id]}),id);
  assert.equal(extractDiscord({name:'alpha'}, {alpha:id}),id);
  assert.deepEqual(desiredRoles(admin('test',id,['players.warn']),cfg),[roleTeam,roleSupport]);
  assert.deepEqual(desiredRoles(admin('test',id,['all_permissions']),cfg),[roleTeam,roleFull]);
  assert.deepEqual(desiredRoles(admin('test',id,[],true),cfg),[roleTeam,roleOwner]);
  write([admin('root',null,[],true),admin('case',id,['players.warn'])]);
  assert.deepEqual(loadAdmins(admins,cfg)[id].roles,[roleTeam,roleSupport]);
  const memberRoles={[id]:new Set(),[id2]:new Set([roleSupport])};
  const ops=[];
  const fetcher=async (url,opt)=>{
    const method=opt.method;
    if(url.includes('webhooks')) return {status:204};
    const parts=url.split('/');
    const discord=parts[parts.indexOf('members')+1];
    const role=parts[parts.indexOf('roles')+1];
    ops.push([method,discord,role||null]);
    if (!memberRoles[discord]) return {status:404};
    if (method==='GET') return {status:200,json:async()=>({roles:[...memberRoles[discord]]})};
    if(method==='PUT') {memberRoles[discord].add(role);return {status:204};}
    if(method==='DELETE') {memberRoles[discord].delete(role);return {status:204};}
    throw Error('unknown method');
  };
  const sync=new AdminRoleSync(cfg,fetcher);
  await sync.sync();
  assert.deepEqual([...memberRoles[id]].sort(),[roleTeam,roleSupport].sort());
  assert.deepEqual(sync.state.users[id].owned.sort(),[roleTeam,roleSupport].sort());
  assert(!JSON.stringify(sync.state).includes('TOP_SECRET_SHOULD_NEVER_WRITE'));
  write([admin('root',null,[],true),admin('case',id,['players.ban'])]);
  await sync.sync();
  assert.deepEqual([...memberRoles[id]].sort(),[roleTeam,roleMod].sort());
  assert(ops.some(o=>o[0]==='DELETE' && o[2]===roleSupport));
  // Removed admin: only owned roles are removed.
  write([admin('root',null,[],true)]);
  await sync.sync();
  assert.equal(memberRoles[id].size,0);
  // Pre-existing manual role stays when txAdmin rights disappear.
  write([admin('root',null,[],true),admin('manual',id2,['players.warn'])]);
  await sync.sync();
  assert(memberRoles[id2].has(roleSupport));
  assert.deepEqual(sync.state.users[id2]?.owned,[roleTeam]);
  write([admin('root',null,[],true)]);
  await sync.sync();
  assert(memberRoles[id2].has(roleSupport));
  assert(!memberRoles[id2].has(roleTeam));
  // Missing/corrupt admin file must NOT revoke any roles.
  write([admin('root',null,[],true),admin('case',id,['players.ban'])]);
  await sync.sync();
  const before=[...memberRoles[id]];
  fs.writeFileSync(admins,'{broken');
  await assert.rejects(()=>sync.sync());
  assert.deepEqual([...memberRoles[id]],before);
  // Corrupt state should fail closed.
  fs.writeFileSync(path.join(tmp,'data','admin_roles_state.json'),'corrupt');
  assert.throws(()=>new AdminRoleSync(cfg,fetcher));
  console.log('AdminRoleSync: 12/12 Mock-Tests OK');
}
main().catch(err=>{console.error(err);process.exitCode=1;}).finally(()=>fs.rmSync(tmp,{recursive:true,force:true}));
