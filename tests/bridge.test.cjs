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

test('empty-land choices quote each actual resource type and match committed fees and construction time', async t => {
  const f = await fixture(t), initial = await f.read();
  assert.deepEqual(initial.view.plotOptions.map(option => option.id), ['farm', 'lumber', 'quarry', 'mine']);
  assert.equal(new Set(initial.view.plotOptions.map(option => JSON.stringify(option.cost))).size, 4);
  for (const [index, id] of ['farm', 'lumber', 'quarry', 'mine'].entries()) {
    const before = await f.read(), option = before.view.plotOptions.find(row => row.id === id);
    assert.equal(before.state.plots[index].type, null);
    assert.equal(option.requirement, ''); assert.equal(option.affordable, true);
    const queued = await f.command('developPlot', [index, id]);
    const job = queued.state.buildQueue.find(row => row.plot === index);
    assert.deepEqual(job.paid, option.cost);
    assert.ok(Math.abs((job.end - job.start) / 1000 - option.seconds) < 0.001);
    for (const [resource, fee] of Object.entries(option.cost))
      assert.equal(before.state.res[resource] - queued.state.res[resource], fee);
    f.advance(Math.ceil(job.end - f.now) + 1);
  }
  const {gameView} = await import('../bridge/dto.mjs');
  const runtime = f.runtime.createGameRuntime({snapshot: initial.state, now: f.now}), game = runtime.Game;
  const unboosted = gameView(game, f.now, runtime).plotOptions;
  game.state.tech.construction = 5;
  for (const resource of Object.keys(game.state.res)) game.state.res[resource] = 0;
  const poor = gameView(game, f.now, runtime).plotOptions;
  assert.ok(poor.every(option => !option.affordable));
  assert.ok(poor.every((option, index) => option.seconds < unboosted[index].seconds));
  assert.deepEqual(poor.map(option => option.cost), unboosted.map(option => option.cost));
  assert.equal((await f.read()).revision, 4, 'presentation quotations submit no extra commands');
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

test('management unlock requirements reject transactions without changing save or revision', async t => {
  const f=await fixture(t),before=await f.read();
  assert.equal(before.view.market.level,0);assert.equal(before.view.inn.level,0);
  assert.equal(before.view.market.resources[0].buy.reason,'请先建造市场');
  assert.equal(before.view.inn.refreshReason,'请先建造客栈');
  for(const [type,args,message] of [['trade',['food',1,true],'请先建造市场'],['refreshInn',[],'请先建造客栈'],['recruit',['missing'],'候选已离开']]){
    const result=await f.request('/command',{commandId:`management_block_${type}`,expectedRevision:before.revision,type,args});
    assert.equal(result.status,400);assert.equal(result.body.error.code,'GAME_RULE');assert.equal(result.body.error.message,message);
  }
  const after=await f.read();assert.equal(after.revision,before.revision);assert.deepEqual(after.state,before.state);
});

test('real market quotes allow full-resource purchases, reject oversize, and replay one persisted settlement', async t => {
  const f=await fixture(t),game=f.runtime.createGameRuntime({now:f.now}).Game,s=game.state;
  s.cityLayout[0]='market';s.cityLevels[0]=1;s.buildings.market=1;
  s.res.food=game.capacity('food');s.res.gold=200000;game.save();assert.equal(game.validSave(s),true);
  const imported=await f.request('/import',{commandId:'market_import_001',expectedRevision:0,state:s});assert.equal(imported.status,200);
  const before=await f.read(),native=f.runtime.createGameRuntime({snapshot:before.state,now:f.now}).Game;
  const resource=before.view.market.resources.find(row=>row.id==='food');
  assert.deepEqual(resource.buy,native.tradeQuote('food',true));assert.deepEqual(resource.sell,native.tradeQuote('food',false));
  assert.equal(resource.name,'粮食');assert.equal(resource.buy.room,0);assert.equal(resource.buy.limit,100000);
  assert.match(resource.buy.warning,/仍可购买/);
  const tooMany=await f.request('/command',{commandId:'market_toomany_001',expectedRevision:before.revision,type:'trade',args:['food',resource.buy.limit+1,true]});
  assert.equal(tooMany.status,400);assert.equal(tooMany.body.error.message,'当前最多可买入 100000');
  assert.equal((await f.read()).revision,before.revision);
  const input={commandId:'market_buy_once_001',expectedRevision:before.revision,type:'trade',args:['food',resource.buy.limit,true]};
  const bought=await f.request('/command',input);assert.equal(bought.status,200);
  assert.equal(bought.body.state.res.food,before.state.res.food+100000);assert.equal(bought.body.state.res.gold,before.state.res.gold-100000);
  assert.ok(bought.body.state.res.food>bought.body.view.caps.food);
  const retry=await f.request('/command',input);assert.equal(retry.body.replayed,true);assert.deepEqual(retry.body.state.res,bought.body.state.res);
  await f.restart();assert.deepEqual((await f.read()).state.res,bought.body.state.res);
  const lateRetry=await f.request('/command',input);assert.equal(lateRetry.body.replayed,true);
  const sold=await f.command('trade',['food',1234,false]);
  assert.equal(sold.state.res.food,bought.body.state.res.food-1234);assert.equal(sold.state.res.gold,bought.body.state.res.gold+1234);
});

test('market sale capacity and cash shortage remain authoritative rules', async t => {
  const f=await fixture(t),game=f.runtime.createGameRuntime({now:f.now}).Game,s=game.state;
  s.cityLayout[0]='market';s.cityLevels[0]=1;s.buildings.market=1;
  s.res.gold=game.capacity('gold')-3;game.save();assert.equal(game.validSave(s),true);
  assert.equal((await f.request('/import',{commandId:'market_gold_import',expectedRevision:0,state:s})).status,200);
  const before=await f.read(),quote=before.view.market.resources.find(row=>row.id==='wood').sell;
  assert.equal(quote.limit,3);assert.equal(quote.room,3);
  const excess=await f.request('/command',{commandId:'market_sell_excess',expectedRevision:before.revision,type:'trade',args:['wood',4,false]});
  assert.equal(excess.status,400);assert.equal(excess.body.error.message,'当前最多可卖出 3');
  const sold=await f.command('trade',['wood',3,false]);assert.equal(sold.state.res.gold,sold.view.caps.gold);
  assert.equal(sold.view.market.resources.find(row=>row.id==='wood').sell.reason,'黄金已满仓，当前不能卖出');
  // A separate valid imported treasury exercises the buy quote's zero-cash branch.
  const emptyGame=f.runtime.createGameRuntime({snapshot:sold.state,now:f.now}).Game;
  emptyGame.state.res.gold=0;emptyGame.save();const empty=emptyGame.state;
  assert.equal((await f.request('/import',{commandId:'market_cash_import',expectedRevision:sold.revision,state:empty})).status,200);
  const cashless=await f.read();assert.equal(cashless.view.market.resources.find(row=>row.id==='iron').buy.reason,'黄金不足');
  const denied=await f.request('/command',{commandId:'market_cash_denied',expectedRevision:cashless.revision,type:'trade',args:['iron',1,true]});
  assert.equal(denied.status,400);assert.equal(denied.body.error.message,'黄金不足');
});

test('governor and tax commands change canonical production, construction and morale; marching governors are rejected', async t => {
  const f=await fixture(t),game=f.runtime.createGameRuntime({now:f.now}).Game,s=game.state;
  for(const [site,id] of ['house','drill'].entries()){s.cityLayout[site]=id;s.cityLevels[site]=3;s.buildings[id]=3;}
  s.plots[0]={type:'farm',level:1};s.population=200;s.unrest=5;s.army.cavalry=10;s.res.food=100000;
  game.save();assert.equal(game.validSave(s),true);
  assert.equal((await f.request('/import',{commandId:'governor_import_001',expectedRevision:0,state:s})).status,200);
  const initial=await f.read(),native=f.runtime.createGameRuntime({snapshot:initial.state,now:f.now}).Game;
  assert.equal(initial.view.governance.targetMorale,native.governanceStatus().moraleTarget);
  assert.equal(initial.view.governance.goldPerMinute,native.rates().gold);
  const suBuild=initial.view.buildings.find(row=>row.id==='hall').seconds;
  const appointed=await f.command('setGovernor',['lin']);
  assert.equal(appointed.state.governor,'lin');assert.equal(appointed.view.governance.governorId,'lin');
  assert.ok(appointed.view.rates.food<initial.view.rates.food);assert.ok(appointed.view.governance.productionBoost<initial.view.governance.productionBoost);
  assert.ok(appointed.view.buildings.find(row=>row.id==='hall').seconds>suBuild);
  await f.command('setGovernor',['su']);
  const taxed=await f.command('setTax',[35]);assert.equal(taxed.state.tax,35);assert.equal(taxed.view.governance.targetMorale,60);
  assert.equal(taxed.view.governance.goldPerMinute,initial.view.governance.goldPerMinute*35/20);
  const capped=await f.command('setTax',[200]);assert.equal(capped.state.tax,100);assert.equal(capped.view.governance.targetMorale,0);
  const sent=await f.command('dispatch',['field','lin',{cavalry:5},'raid']);
  const candidate=sent.view.governance.candidates.find(hero=>hero.id==='lin');assert.equal(candidate.busy,true);assert.equal(candidate.reason,'该武将正在出征或驻守');
  const denied=await f.request('/command',{commandId:'governor_busy_001',expectedRevision:sent.revision,type:'setGovernor',args:['lin']});
  assert.equal(denied.status,400);assert.equal(denied.body.error.message,candidate.reason);
  assert.equal((await f.read()).revision,sent.revision);assert.equal((await f.read()).state.governor,'su');
  await f.restart();const resumed=await f.read();assert.equal(resumed.state.governor,'su');assert.equal(resumed.state.tax,100);
});

test('inn inquiry is free; recruitment charges once, consumes a room and persists real hero statistics', async t => {
  const f=await fixture(t),game=f.runtime.createGameRuntime({now:f.now}).Game,s=game.state;
  for(const [site,id,level] of [[0,'inn',2],[1,'tavern',3]]){s.cityLayout[site]=id;s.cityLevels[site]=level;s.buildings[id]=level;}
  s.res.gold=20000;game.save();assert.equal(game.validSave(s),true);
  assert.equal((await f.request('/import',{commandId:'inn_import_001',expectedRevision:0,state:s})).status,200);
  const before=await f.read(),inquired=await f.command('refreshInn');
  assert.equal(inquired.state.res.gold,before.state.res.gold);assert.equal(inquired.view.inn.candidates.length,2);
  assert.equal(inquired.view.inn.capacity,3);assert.equal(inquired.view.inn.used,2);assert.equal(inquired.view.inn.remaining,1);
  const candidate=inquired.view.inn.candidates[0];assert.equal(candidate.affordable,true);assert.equal(candidate.reason,'');
  assert.equal(candidate.price,candidate.level*1000);
  const input={commandId:'recruit_once_001',expectedRevision:inquired.revision,type:'recruit',args:[candidate.id]};
  const hired=await f.request('/command',input);assert.equal(hired.status,200);
  assert.equal(hired.body.state.res.gold,inquired.state.res.gold-candidate.price);assert.equal(hired.body.state.generals.includes(candidate.id),true);
  assert.equal(hired.body.view.inn.used,3);assert.equal(hired.body.view.inn.remaining,0);
  assert.equal(hired.body.view.inn.candidates[0].reason,'招贤馆没有空闲房间（包含被俘将领）');
  const owned=hired.body.view.generals.find(hero=>hero.id===candidate.id);
  const native=f.runtime.createGameRuntime({snapshot:hired.body.state,now:f.now}).Game;
  for(const attr of ['atk','def','pol','wis','lead','level'])assert.equal(owned[attr],native.general(candidate.id)[attr]);
  const duplicate=await f.request('/command',input);assert.equal(duplicate.body.replayed,true);assert.deepEqual(duplicate.body.state,hired.body.state);
  const denied=await f.request('/command',{commandId:'recruit_no_room_001',expectedRevision:hired.body.revision,type:'recruit',args:[hired.body.view.inn.candidates[0].id]});
  assert.equal(denied.status,400);assert.equal(denied.body.error.message,hired.body.view.inn.candidates[0].reason);
  await f.restart();const resumed=await f.read();assert.deepEqual(resumed.state.generals,hired.body.state.generals);assert.equal(resumed.state.res.gold,hired.body.state.res.gold);
  const lateRetry=await f.request('/command',input);assert.equal(lateRetry.body.replayed,true);assert.equal((await f.read()).revision,hired.body.revision);
});

test('inn rooms include both captive pools, and recruit quotes expose cash shortage only when space exists', async t => {
  const f=await fixture(t),runtime=f.runtime.createGameRuntime({now:f.now}),game=runtime.Game,s=game.state;
  for(const [site,id,level] of [[0,'inn',1],[1,'tavern',4]]){s.cityLayout[site]=id;s.cityLevels[site]=level;s.buildings[id]=level;}
  game.save();assert.equal(runtime.HeroSystem.wild.discover(),null);
  const line=s.wildGenerals.rumors.find(row=>row.line==='wanderer'),portrait=runtime.HeroSystem.wild.portraitQuote(s,'wanderer');
  assert.equal(runtime.HeroSystem.wild.buyPortrait('wanderer',portrait.key),null);
  // Canonical settlement helpers prepare a strict-valid fictional captive save; no player data is touched.
  const captured=runtime.HeroSystem.wild.settle(s,game.getNode(line.node),{finished:false,mode:'raid',enemy:[{hp:0}]},true,f.now);
  assert.equal(captured.status,'captured');
  const loser=f.runtime.createGameRuntime({now:f.now});loser.Game.state.generals.push('yan');loser.Game.state.generalLevels.yan=1;loser.Game.state.generalXp.yan=0;
  loser.HeroSystem.init(loser.Game.state);loser.Game.state.heroLoyalty.yan=40;loser.Game.save();
  assert.equal(runtime.GovernanceSystem.captureDefeated(loser.Game.state,s,'yan',f.now).status,'captured');
  game.refreshInn();game.save();assert.equal(game.validSave(s),true);
  const imported=await f.request('/import',{commandId:'captive_rooms_import',expectedRevision:0,state:s});assert.equal(imported.status,200,JSON.stringify(imported.body));
  const full=await f.read();assert.equal(full.view.inn.used,4);assert.equal(full.view.inn.remaining,0);
  assert.equal(full.view.inn.candidates[0].reason,'招贤馆没有空闲房间（包含被俘将领）');
  const roomyGame=f.runtime.createGameRuntime({snapshot:full.state,now:f.now}).Game,roomy=roomyGame.state;
  roomy.cityLevels[1]=5;roomy.buildings.tavern=5;roomy.res.gold=0;roomyGame.save();
  assert.equal((await f.request('/import',{commandId:'captive_cash_import',expectedRevision:full.revision,state:roomy})).status,200);
  const cashless=await f.read();assert.equal(cashless.view.inn.remaining,1);assert.equal(cashless.view.inn.candidates[0].affordable,false);
  assert.equal(cashless.view.inn.candidates[0].reason,'黄金不足');
  const denied=await f.request('/command',{commandId:'captive_cash_denied',expectedRevision:cashless.revision,type:'recruit',args:[cashless.view.inn.candidates[0].id]});
  assert.equal(denied.status,400);assert.equal(denied.body.error.message,'黄金不足');
});

test('multi-city management uses the requested city treasury, tax and inn while rooms remain realm-wide', async t => {
  const f=await fixture(t),game=f.runtime.createGameRuntime({now:f.now}).Game,s=game.state;
  const plain=Array.from({length:4096},(_,i)=>game.getWorldTile(i%64,Math.floor(i/64))).find(node=>node.wild&&node.type==='plain');
  s.honors.noble=1;s.conquered[plain.id]=true;s.landClaims[plain.id]={at:f.now,level:plain.level};s.realm.wildOwners[plain.id]='capital';
  for(const key of Object.keys(s.res))s.res[key]=100000;
  for(const [site,id,level] of [[0,'market',1],[1,'inn',1],[2,'tavern',2]]){s.cityLayout[site]=id;s.cityLevels[site]=level;s.buildings[id]=level;}
  game.save();const quote=game.foundCityQuote(plain.id,'试验分城');assert.equal(quote.reason,'');
  assert.equal(game.foundCity(plain.id,quote.name,quote.key),null);const city=`city_${plain.id}`;
  assert.equal(game.switchCity(city),null);
  for(const [site,id,level] of [[0,'market',2],[1,'inn',2],[2,'tavern',3]]){s.cityLayout[site]=id;s.cityLevels[site]=level;s.buildings[id]=level;}
  for(const key of Object.keys(s.res))s.res[key]=40000;s.realm.heroLocations.lin=city;
  assert.equal(game.setGovernor('lin'),null);assert.equal(game.switchCity('capital'),null);game.save();assert.equal(game.validSave(s),true);
  assert.equal((await f.request('/import',{commandId:'realm_manage_import',expectedRevision:0,state:s})).status,200);
  const before=await f.read(),capitalTreasury=structuredClone(before.state.res);
  const traded=await f.command('trade',['wood',50,true],{sourceCity:city});
  assert.equal(traded.view.city.id,city);assert.equal(traded.view.market.level,2);
  assert.equal(traded.state.res.wood,40050);assert.equal(traded.state.res.gold,39950);
  assert.deepEqual(traded.state.realm.cities.capital.data.res,capitalTreasury);
  const taxed=await f.command('setTax',[30],{sourceCity:city});assert.equal(taxed.state.tax,30);assert.equal(taxed.state.realm.cities.capital.data.tax,20);
  const inquired=await f.command('refreshInn',[],{sourceCity:city});assert.equal(inquired.view.inn.candidates.length,2);
  assert.equal(inquired.state.realm.cities.capital.data.innCandidates.length,0);assert.equal(inquired.view.inn.capacity,5);
  const nonlocal=inquired.view.governance.candidates.find(hero=>hero.id==='su');assert.equal(nonlocal.city,'capital');assert.equal(nonlocal.busy,true);
  const blocked=await f.request('/command',{commandId:'realm_governor_denied',expectedRevision:inquired.revision,type:'setGovernor',args:['su'],sourceCity:city});
  assert.equal(blocked.status,400);assert.equal(blocked.body.error.message,nonlocal.reason);
  const hired=await f.command('recruit',[inquired.view.inn.candidates[0].id],{sourceCity:city});
  assert.equal(hired.state.res.gold,inquired.state.res.gold-inquired.view.inn.candidates[0].price);
  assert.deepEqual(hired.state.realm.cities.capital.data.res,capitalTreasury);
  assert.equal(hired.view.inn.used,3);assert.equal(hired.view.inn.remaining,2);
  assert.equal(hired.state.realm.heroLocations[inquired.view.inn.candidates[0].id],city);
  const capitalTax=await f.command('setTax',[15],{sourceCity:'capital'});assert.equal(capitalTax.state.tax,15);
  assert.equal(capitalTax.state.realm.cities[city].data.tax,30);assert.equal(capitalTax.view.inn.capacity,5);
  await f.restart();const resumed=await f.read();assert.equal(resumed.state.realm.cities[city].data.res.gold,hired.state.res.gold);
  assert.equal(resumed.state.realm.cities[city].data.innCandidates.length,1);assert.equal(resumed.state.realm.cities.capital.data.tax,15);
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
  let fileSymlink = true;
  try { await fs.symlink(path.join(directory,'secret.html'), path.join(webDir,'escape.html')); }
  catch (error) {
    if (process.platform !== 'win32' || error.code !== 'EPERM') throw error;
    fileSymlink = false;
  }
  const bridge = await module.startBridge({dataDir,webDir,readyFile,port:0,token:'web-secret',clock:()=>NOW});
  t.after(async()=>{await bridge.close();await fs.rm(directory,{recursive:true,force:true});});
  const ready=JSON.parse(await fs.readFile(readyFile,'utf8')); assert.equal(ready.url,`http://127.0.0.1:${bridge.port}`); assert.equal(ready.token,undefined);
  const index = await fetch(ready.url+'/'); assert.equal(index.status,200); assert.equal(await index.text(),'<html>Godot web</html>');
  assert.equal(index.headers.get('cross-origin-opener-policy'),'same-origin');
  await t.test('file symlink escape', {skip: !fileSymlink && 'Windows account cannot create file symlinks'}, async () => {
    assert.equal((await fetch(ready.url+'/escape.html')).status,404);
  });
  assert.equal((await fetch(ready.url+'/../secret.html')).status,404);
  assert.equal((await fetch(ready.url+'/%2e%2e%2fsecret.html')).status,404);
  assert.equal((await fetch(ready.url+'/save.json')).status,404);
  assert.equal((await fetch(ready.url+'/api/state')).status,401);
  const state=await fetch(ready.url+'/api/state',{headers:{Authorization:'Bearer web-secret',Origin:ready.url}}); assert.equal(state.status,200);
  await fs.mkdir(path.join(webDir,'private'));
  await fs.symlink(path.join(webDir,'private'),path.join(directory,'private-alias'), process.platform === 'win32' ? 'junction' : 'dir');
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
  assert.equal(await ended,0,output);await assert.rejects(fs.access(readyFile),error=>error.code==='ENOENT');
});
