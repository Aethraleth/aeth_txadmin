'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'aeth-txadmin-v14-test-'));
(async()=>{
try {
    fs.mkdirSync(path.join(tmp, 'data'));
    fs.mkdirSync(path.join(tmp, 'tools'));
    fs.copyFileSync(path.join(__dirname, '..', 'tools', 'log_relay.js'), path.join(tmp, 'tools', 'log_relay.js'));
    fs.copyFileSync(path.join(__dirname, '..', 'tools', 'admin_roles.js'), path.join(tmp, 'tools', 'admin_roles.js'));
    const mod = require(path.join(tmp, 'tools', 'log_relay.js'));
    assert.equal(mod.maskSecrets('set sv_licenseKey secret123'), '[VERTRAULICHE LOGZEILE AUSGEBLENDET]');
    assert.equal(mod.maskSecrets('mysql://john:pw@host/db'), 'mysql://[GEHEIM]');
    assert.equal(mod.maskSecrets('normal text'), 'normal text');
    const hook='https://discord.com/api/webhooks/123456789012345678/abcdefghijklmnopqrstuvwxyz_A';
    assert.equal(mod.validWebhook(hook), true);
    assert.equal(mod.validWebhook('https://evil.example/api/webhooks/123/abc'), false);
    assert.equal(mod.validWebhook('https://discord.com/api/webhooks/1/abc?bad=1'), false);
    assert.ok(mod.maskSecrets(hook).includes('[DISCORD-WEBHOOK-ENTFERNT]'));
    const logs=path.join(tmp, 'txData');
    fs.mkdirSync(logs);
    fs.writeFileSync(path.join(logs, 'admin.log'), 'eins\nzwei\n');
    fs.writeFileSync(path.join(logs, 'fxserver.log'), 'konsole\n');
    fs.writeFileSync(path.join(logs, 'server.log'), 'join\n');
    const config={logDirectory:logs,enabledKinds:{admin:true,fxserver:true,server:true},
      webhooks:{admin:hook,fxserver:hook,server:hook},startAtEnd:false,pollMilliseconds:1000};
    const r=new mod.Relay(config);
    r.poll();
    assert.equal(r.state.pending.length,3, '3 file streams queued');
    assert.ok(r.state.pending[0].content.includes('zwei'));
    assert.equal(r.state.pending[0].webhook, undefined, 'No webhook secrets in persisted queue');
    r.poll();
    assert.equal(r.state.pending.length,3, 'same lines not repeated');
    fs.appendFileSync(path.join(logs,'admin.log'), 'set sv_licenseKey SECRET\n');
    r.poll();
    assert.equal(r.state.pending.length,4);
    assert.ok(r.state.pending[3].content.includes('[VERTRAULICHE LOGZEILE AUSGEBLENDET]'));
    assert.ok(!r.state.pending[3].content.includes('SECRET'));
    const rRestart=new mod.Relay(config);
    rRestart.poll();
    assert.equal(rRestart.state.pending.length,4, 'durable queue restored');
    fs.writeFileSync(path.join(logs,'admin.log'), 'rotated\n');
    rRestart.poll();
    assert.equal(rRestart.state.pending.length,5, 'truncation handled');
    const oldFetch=global.fetch;
    const sent=[];
    global.fetch=async (url,opts) => {
        sent.push({url,opts});
        return {status:204};
    };
    try {
        await rRestart.sendOne();
        assert.equal(sent.length,1);
        assert.equal(sent[0].url,hook);
        assert.ok(!sent[0].opts.headers.Authorization);
        assert.equal(rRestart.state.pending.length,4);
        assert.equal(JSON.parse(sent[0].opts.body).allowed_mentions.parse.length,0);
    } finally {global.fetch=oldFetch;}
    console.log('FileRelay Webhook- und Logdatei-Tests bestanden.');
} finally {fs.rmSync(tmp,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exitCode=1});
