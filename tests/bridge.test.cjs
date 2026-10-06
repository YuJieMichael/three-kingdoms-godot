const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {spawn} = require('node:child_process');
const modules = Promise.all([import('../bridge/server.mjs'), import('../vendor/legacy/online/runtime.mjs')]);
const NOW = 1800000000000;

async function fixture(t, options = {}) {
  const [bridgeModule, runtime] = await modules;
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'three-kingdoms-godot-'));
  let now = NOW, counter = 0;
  const configuration = {dataDir: path.join(directory, 'save'), port: 0, token: 'fixture-private-token', clock: () => now, ...options};
  let bridge = await bridgeModule.startBridge(configuration);
  const api = {
    runtime, directory, configuration, get bridge() { return bridge; },
    advance(ms) { now += ms; }, get now() { return now; },
    async request(route, body, extra = {}) {
      const response = await fetch(`http://127.0.0.1:${bridge.port}${route}`, {
        method: body === undefined ? 'GET' : 'POST',
        headers: {'Authorization': `Bearer ${configuration.token}`, 'Content-Type': 'application/json', ...(extra.headers || {})},
        ...(body === undefined ? {} : {body: JSON.stringify(body)}), ...extra,
      });
      const text = await response.text(); let value;
      try { value = JSON.parse(text); } catch { value = text; }
      return {status: response.status, body: value, headers: response.headers};
    },
    async read() { const result = await api.request('/state'); assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body; },
    async command(type, args = [], extra = {}) {
      const before = await api.read(); const result = await api.request('/command', {
        expectedRevision: before.revision, commandId: `fixture_${String(++counter).padStart(5, '0')}`, type, args, ...extra,
      });
      assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body;
    },
    async restart() { await bridge.close(); bridge = await bridgeModule.startBridge(configuration); },
  };
  t.after(async () => { await bridge.close(); await fs.rm(directory, {recursive: true, force: true}); });
  return api;
}

test('bridge DTOs retain canonical costs and hide future task landmarks', async t => {
  const f = await fixture(t), state = await f.read();
  const native = f.runtime.createGameRuntime({snapshot: state.state, now: f.now}).Game;
  assert.equal(state.revision, 0); assert.equal(native.validSave(state.state), true);
  assert.equal(state.view.buildingSlots.length, 36); assert.equal(state.view.units.length, 12);
  assert.equal(Object.values(state.view.queues).every(queue=>Array.isArray(queue)),true);
  assert.deepEqual(state.view.units.find(u => u.id === 'archer').cost, native.trainCost('archer', 1));
  assert.equal(state.view.buildings.find(b => b.id === 'hall').seconds, native.buildSeconds('hall', 2));
  const world = await f.request('/api/world'); assert.equal(world.status, 200);
  assert.equal(world.body.tiles.length, 4096);
  assert.equal(world.body.tiles.find(tile => tile.id === 'field').name, '河畔荒田');
  assert.equal(world.body.tiles.some(tile => tile.id === 'wood'), false);
  assert.equal(world.body.tiles.find(tile => tile.x === 29 && tile.y === 29).name, '未发现据点');
  const hidden = await f.request('/node?id=wood'); assert.equal(hidden.status, 403); assert.equal(hidden.body.error.code, 'NODE_HIDDEN');
});

test('real building completes with canonical timers and survives process-style restart', async t => {
  const f = await fixture(t);
  await f.command('onboarding.claimAvailable');
  const built = await f.command('queueBuilding', [0, 'house']);
  const queue = built.state.buildQueue[0]; assert.equal(queue.site, 0); assert.equal(queue.id, 'house');
  f.advance(Math.ceil(queue.end - f.now) + 1);
  const projected = await f.read(); assert.equal(projected.state.buildings.house, 1);
  assert.equal(projected.revision, built.revision);
  const claimed = await f.command('claimMission', ['house']); assert.equal(claimed.state.missionClaims.includes('house'), true);
  await f.restart(); const resumed = await f.read();
  assert.equal(resumed.revision, claimed.revision); assert.equal(resumed.state.buildings.house, 1);
  assert.equal(resumed.state.missionClaims.includes('house'), true);
  assert.deepEqual(resumed.state.buildQueue, []);
});

test('simultaneous commands commit once with CAS and retry receipts survive restart', async t => {
  const f = await fixture(t), base = await f.read();
  const shared = {commandId: 'same_tax_00001', expectedRevision: base.revision, type: 'setTax', args: [25]};
  const results = await Promise.all(Array.from({length: 12}, () => f.request('/command', shared)));
  assert.equal(results.every(result => result.status === 200), true);
  assert.equal(results.filter(result => result.body.replayed).length, 11);
  assert.equal((await f.read()).revision, 1);
  const conflict = await f.request('/command', {...shared, commandId: 'stale_tax_0001', args: [30]});
  assert.equal(conflict.status, 409); assert.equal(conflict.body.error.code, 'REVISION_CONFLICT');
  const reused = await f.request('/command', {...shared, args: [30]});
  assert.equal(reused.status, 409); assert.equal(reused.body.error.code, 'ID_REUSED');
  await f.restart(); const replay = await f.request('/command', {type: shared.type, args: shared.args, commandId: shared.commandId, expectedRevision: shared.expectedRevision});
  assert.equal(replay.status, 200); assert.equal(replay.body.replayed, true); assert.equal(replay.body.state.tax, 25);
  assert.equal((await f.read()).revision, 1);
});

test('read projections never rewrite persisted revision, receipts or resource balances', async t => {
  const f = await fixture(t); await f.command('onboarding.claimAvailable');
  const filename = path.join(f.configuration.dataDir, 'save.json'), before = await fs.readFile(filename, 'utf8');
  f.advance(600000); const read = await f.read(); assert.ok(read.state.last > NOW);
  await f.request('/world'); await f.request('/export');
  assert.equal(await fs.readFile(filename, 'utf8'), before);
});

test('read then command then restart settles construction, income and hourly wages exactly once', async t => {
  const f=await fixture(t);
  await f.command('onboarding.claimAvailable'); await f.command('queueBuilding',[0,'house']);
  f.advance(3600001);
  const projected=await f.read(),again=await f.read();
  assert.equal(projected.state.buildings.house,1);
  assert.deepEqual(again.state.res,projected.state.res);
  assert.equal(projected.state.res.gold<15000,true);
  const xp=projected.state.generalXp.su;
  const committed=await f.command('setTax',[25]);
  assert.deepEqual(committed.state.res,projected.state.res);assert.equal(committed.state.generalXp.su,xp);
  await f.restart();const resumed=await f.read();
  assert.deepEqual(resumed.state.res,committed.state.res);assert.equal(resumed.state.generalXp.su,xp);
  const savedAgain=await f.command('setTax',[30]);
  assert.deepEqual(savedAgain.state.res,committed.state.res);assert.equal(savedAgain.state.generalXp.su,xp);
  assert.equal(savedAgain.state.heroService.lastPay,committed.state.heroService.lastPay);
});

test('real research and inventory DTOs quote native rules; random speedup retry never rolls twice', async t => {
  const f=await fixture(t);await f.command('onboarding.claimAvailable');
  const native=f.runtime.createGameRuntime({snapshot:(await f.read()).state,now:f.now}).Game;
  const tech=(await f.read()).view.techs.find(tech=>tech.id==='plant');
  assert.deepEqual(tech.cost,native.researchCost('plant'));assert.equal(tech.seconds,native.researchSeconds('plant'));
  assert.equal((await f.read()).view.generals[0].loyalty,80);
  const bought=await f.command('buyItem',['speed_build_15_30h',1]);assert.equal(bought.state.gems,820);
  const built=await f.command('queueBuilding',[0,'house']);
  const item=built.view.inventory.find(item=>item.id==='speed_build_15_30h');
  assert.equal(item.effect,'speedup');assert.equal(item.queueKind,'build');assert.equal(item.targets.length,1);
  const target=item.targets[0];assert.equal(target.key,native.speedupKey('build',built.state.buildQueue[0]));
  const input={commandId:'random_speedup_001',expectedRevision:built.revision,type:'useSpeedup',args:[item.id,target.key]};
  const first=await f.request('/command',input);assert.equal(first.status,200);
  assert.ok(first.body.result.requestedMs>=15*3600000&&first.body.result.requestedMs<=30*3600000);
  assert.equal(first.body.state.inventory[item.id],0);assert.equal(first.body.state.buildings.house,1);
  const retry=await f.request('/command',input);assert.equal(retry.status,200);assert.equal(retry.body.replayed,true);
  assert.deepEqual(retry.body.result,first.body.result);assert.deepEqual(retry.body.state,first.body.state);
  await f.restart();const resumed=await f.read();assert.equal(resumed.state.inventory[item.id],0);
  assert.equal(resumed.state.generalXp.su,first.body.state.generalXp.su);
  const lateRetry=await f.request('/command',input);assert.deepEqual(lateRetry.body.result,first.body.result);
});

test('invalid imports leave save and revision intact; original browser export round trips', async t => {
  const f = await fixture(t); await f.command('onboarding.claimAvailable');
  const exported = await f.request('/export'), before = await f.read();
  const bad = structuredClone(exported.body); bad.res.gold = -1;
  const invalid = await f.request('/import', {commandId: 'bad_import_001', expectedRevision: before.revision, state: bad});
  assert.equal(invalid.status, 400); assert.equal(invalid.body.error.code, 'BAD_SAVE');
  assert.equal((await f.read()).revision, before.revision);
  const imported = await f.request('/import', {commandId: 'good_import_001', expectedRevision: before.revision, state: exported.body});
  assert.equal(imported.status, 200); assert.equal(imported.body.revision, before.revision + 1);
  assert.equal(imported.body.authorityId,before.authorityId);
  assert.deepEqual(imported.body.state.res, exported.body.res);
  const backup = JSON.parse(await fs.readFile(path.join(f.configuration.dataDir, 'before-import.json'), 'utf8'));
  assert.equal(backup.revision, before.revision); assert.equal(backup.state.res.gold, before.state.res.gold);
});

test('authority identity persists across commands, import and restart; older bridge headers migrate once', async t => {
  const f=await fixture(t),first=await f.read(),health=(await f.request('/health')).body;
  assert.match(first.authorityId,/^[a-f0-9-]{36}$/);assert.equal(health.authorityId,first.authorityId);
  const changed=await f.command('setTax',[25]);assert.equal(changed.authorityId,first.authorityId);
  await f.restart();assert.equal((await f.read()).authorityId,first.authorityId);
  await f.bridge.close();
  const filename=path.join(f.configuration.dataDir,'save.json'),old=JSON.parse(await fs.readFile(filename,'utf8'));
  delete old.authorityId;await fs.writeFile(filename,JSON.stringify(old));
  await f.restart();const migrated=await f.read();assert.notEqual(migrated.authorityId,first.authorityId);
  assert.equal(migrated.revision,changed.revision);assert.equal(migrated.state.tax,25);
  await f.restart();assert.equal((await f.read()).authorityId,migrated.authorityId);
  assert.equal(JSON.parse(await fs.readFile(filename,'utf8')).authorityId,migrated.authorityId);
});

test('real training, mixed-army march duration and recall are governed by the original engine', async t => {
  const f = await fixture(t);
  // This prepared save is a valid test city, imported through the same public boundary as browser saves.
  const game = f.runtime.createGameRuntime({now: f.now}).Game, s = game.state;
  for (const [site, id] of ['house','barracks','drill'].entries()) { s.cityLayout[site] = id; s.cityLevels[site] = 2; s.buildings[id] = 2; }
  s.population = 200; s.res = {food: 100000, wood: 100000, stone: 100000, iron: 100000, gold: 100000};
  s.army.cavalry = 10; s.army.archer = 10; game.save(); assert.equal(game.validSave(s), true);
  assert.equal((await f.request('/import', {commandId:'army_import_001', expectedRevision:0, state:s})).status, 200);
  const trained = await f.command('train', ['militia', 10]), q = trained.state.trainQueue[0];
  assert.equal(q.count, 10); f.advance(Math.ceil(q.end - f.now) + 1);
  assert.equal((await f.read()).state.army.militia, 10);
  const sent = await f.command('dispatch', ['field', 'lin', {cavalry: 5, archer: 5}, 'raid']);
  const quote = f.runtime.createGameRuntime({snapshot: sent.state, now:f.now}).Game.marchQuote('field', {cavalry:5,archer:5}, 'lin');
  assert.equal(sent.state.expedition.end - sent.state.expedition.start, quote.seconds * 1000);
  assert.equal(sent.state.army.cavalry, 5); assert.equal(sent.state.army.archer, 5);
  const world = (await f.request('/world')).body, march = world.marches[0];
  assert.deepEqual(march.from, {x:32,y:32}); assert.deepEqual(march.to, {x:29,y:35});
  assert.equal(march.status, 'march'); assert.equal(march.count, 10);
  f.advance(1000); const recalled = await f.command('recall'); assert.equal(recalled.state.expedition.phase, 'return');
  f.advance(Math.ceil(recalled.state.expedition.end - f.now) + 1);
  const returned = await f.command('setTax', [25]);
  assert.equal(returned.state.expedition, null); assert.equal(returned.state.army.cavalry, 10); assert.equal(returned.state.army.archer, 10);
});

test('canonical battle commands expose actual positions, events, orders and one settlement', async t => {
  const f=await fixture(t),game=f.runtime.createGameRuntime({now:f.now}).Game,s=game.state;
  s.cityLayout[0]='drill';s.cityLevels[0]=2;s.buildings.drill=2;
  s.res={food:100000,wood:100000,stone:100000,iron:100000,gold:100000};s.army.archer=1000;game.save();
  assert.equal(game.validSave(s),true);
  assert.equal((await f.request('/import',{commandId:'battle_import_001',expectedRevision:0,state:s})).status,200);
  const sent=await f.command('dispatch',['field','lin',{archer:1000},'raid']);
  f.advance(sent.state.expedition.end-f.now+1);
  const begun=await f.command('startBattle');const battle=begun.view.battle;
  assert.equal(Array.isArray(battle.player),true);assert.equal(Array.isArray(battle.enemy),true);
  assert.equal(Number.isFinite(battle.player[0].pos),true);assert.equal(battle.player[0].stats.range>0,true);
  const order=await f.command('setBattleOrders',['hold']);
  assert.equal(order.view.battle.orders.archer.command,'hold');
  await f.command('setBattleOrders',['advance']);
  let result;
  for(let i=0;i<30;i++){result=await f.command('battleRound');if(result.view.battle.finished)break;}
  assert.equal(result.view.battle.finished,true);assert.equal(result.view.battle.result.won,true);
  assert.equal(result.view.battle.currentRoundSummary.events.some(event=>event.type==='strike'&&event.killed>0),true);
  assert.equal(result.view.reports.length,1);
  const awarded=structuredClone(result.state.res),xp=result.state.generalXp.lin;
  await f.read();await f.restart();const resumed=await f.read();
  assert.deepEqual(resumed.state.res,awarded);assert.equal(resumed.state.generalXp.lin,xp);assert.equal(resumed.view.reports.length,1);
});

test('arbitrary methods and snapshot injection cannot cross the command whitelist', async t => {
  const f = await fixture(t), before = await f.read();
  for (const type of ['grantTestSupplies', 'reset', 'save', 'setSpeed', '__proto__', 'Game.state']) {
    const result = await f.request('/command', {commandId:`blocked_${type.replace(/[^a-z]/gi,'')}_001`, expectedRevision:0, type, args:[]});
    assert.equal(result.status, 400); assert.equal(result.body.error.code, 'COMMAND_NOT_ALLOWED');
  }
  const injection = await f.request('/command', {commandId:'inject_state_001', expectedRevision:0, type:'setTax', args:[25], state:before.state});
  assert.equal(injection.body.error.code, 'CLIENT_SNAPSHOT_FORBIDDEN');
  const hidden = await f.request('/command', {commandId:'hidden_task_001', expectedRevision:0, type:'dispatch', args:['wood','lin',{},'raid']});
  assert.equal(hidden.body.error.code, 'NODE_HIDDEN'); assert.equal((await f.read()).revision, 0);
});

test('private token and origin boundaries protect save data and process shutdown', async t => {
  const f = await fixture(t);
  const unauthenticated = await f.request('/state', undefined, {headers:{'Content-Type':'application/json'}});
  assert.equal(unauthenticated.status, 401);
  const foreign = await f.request('/health', undefined, {headers:{Origin:'https://evil.example'}});
  assert.equal(foreign.status, 403);
  const options = await f.request('/api/command', undefined, {method:'OPTIONS', headers:{Origin:'http://127.0.0.1:9999'}});
  assert.equal(options.status, 204); assert.equal(options.headers.get('access-control-allow-origin'), 'http://127.0.0.1:9999');
  const local = await f.request('/api/state', undefined, {headers:{Authorization:'Bearer fixture-private-token',Origin:'http://localhost:8137'}});
  assert.equal(local.status, 200);
  const badShutdown = await f.request('/shutdown', {}, {headers:{'Content-Type':'application/json'}}); assert.equal(badShutdown.status, 401);
  assert.equal((await f.request('/health')).status, 200);
});

test('directory lock prevents two authorities and corrupt existing files are preserved', async t => {
  const f = await fixture(t), [module] = await modules;
  await assert.rejects(module.startBridge(f.configuration), error => error.code === 'SAVE_LOCKED');
  await f.bridge.close(); await fs.writeFile(path.join(f.configuration.dataDir, 'save.json'), '{broken');
  await assert.rejects(module.startBridge(f.configuration), error => error.code === 'SAVE_CORRUPT');
  assert.equal(await fs.readFile(path.join(f.configuration.dataDir, 'save.json'), 'utf8'), '{broken');
});

test('same-origin web assets are isolated from saves, ready metadata and symlink escapes', async t => {
  const [module] = await modules, directory = await fs.mkdtemp(path.join(os.tmpdir(),'godot-web-'));
  const webDir = path.join(directory,'web'), dataDir = path.join(directory,'private'), readyFile = path.join(directory,'ready.json');
  await fs.mkdir(webDir); await fs.writeFile(path.join(webDir,'index.html'), '<html>Godot web</html>');
  await fs.writeFile(path.join(directory,'secret.html'), 'private-secret');
  await fs.symlink(path.join(directory,'secret.html'), path.join(webDir,'escape.html'));
  const bridge = await module.startBridge({dataDir,webDir,readyFile,port:0,token:'web-secret',clock:()=>NOW});
  t.after(async()=>{await bridge.close();await fs.rm(directory,{recursive:true,force:true});});
  const ready=JSON.parse(await fs.readFile(readyFile,'utf8')); assert.equal(ready.url,`http://127.0.0.1:${bridge.port}`); assert.equal(ready.token,undefined);
  const index = await fetch(ready.url+'/'); assert.equal(index.status,200); assert.equal(await index.text(),'<html>Godot web</html>');
  assert.equal(index.headers.get('cross-origin-opener-policy'),'same-origin');
  assert.equal((await fetch(ready.url+'/escape.html')).status,404);
  assert.equal((await fetch(ready.url+'/../secret.html')).status,404);
  assert.equal((await fetch(ready.url+'/%2e%2e%2fsecret.html')).status,404);
  assert.equal((await fetch(ready.url+'/save.json')).status,404);
  assert.equal((await fetch(ready.url+'/api/state')).status,401);
  const state=await fetch(ready.url+'/api/state',{headers:{Authorization:'Bearer web-secret',Origin:ready.url}}); assert.equal(state.status,200);
  await fs.mkdir(path.join(webDir,'private'));
  await fs.symlink(path.join(webDir,'private'),path.join(directory,'private-alias'));
  await assert.rejects(module.startBridge({dataDir:path.join(directory,'private-alias'),webDir,port:0}),/separate from private/);
  const tokenFile=path.join(webDir,'token.txt');await fs.writeFile(tokenFile,'private-token');
  await assert.rejects(module.startBridge({dataDir:path.join(directory,'other-save'),webDir,tokenFile,port:0}),/separate from private/);
  await bridge.close(); await assert.rejects(fs.access(readyFile), error=>error.code==='ENOENT');
});

test('desktop CLI emits a ready file with assigned port and authenticated shutdown removes it', async t => {
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'godot-cli-')),readyFile=path.join(directory,'ready.json');
  const child=spawn(process.execPath,[path.resolve(__dirname,'../bridge/server.mjs'),'--port','0','--data-dir',path.join(directory,'save'),'--ready-file',readyFile,'--token','cli-private']);
  let output='';child.stderr.on('data',chunk=>output+=chunk); const ended=new Promise(resolve=>child.once('exit',code=>resolve(code)));
  t.after(async()=>{if(child.exitCode===null)child.kill();await ended;await fs.rm(directory,{recursive:true,force:true});});
  let ready;
  for(let i=0;i<100;i++){try{ready=JSON.parse(await fs.readFile(readyFile,'utf8'));break;}catch{await new Promise(resolve=>setTimeout(resolve,20));}}
  assert.ok(ready,output);assert.equal(ready.pid,child.pid);
  const response=await fetch(ready.url+'/api/shutdown',{method:'POST',headers:{Authorization:'Bearer cli-private'}});assert.equal(response.status,200);
  assert.equal(await ended,0);await assert.rejects(fs.access(readyFile),error=>error.code==='ENOENT');
});
