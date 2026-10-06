const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const NOW = 1800000000000;
const modules = Promise.all([import('../bridge/server.mjs'), import('../vendor/legacy/online/runtime.mjs'),
  import('../bridge/realm-view.mjs'), import('../bridge/shared-server.mjs'), import('../bridge/room-server.mjs')]);

async function fixture(t) {
  const [server, canonical, projection] = await modules;
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'shanhece-realm-'));
  let now = NOW, serial = 0, bridge;
  const config = {port: 0, dataDir: directory, token: 'realm-isolated-token', clock: () => now};
  bridge = await server.startBridge(config);
  const f = {canonical, projection, directory, get now() { return now; },
    at(value) { assert.ok(value >= now); now = value; },
    async request(route, body, token = config.token) {
      const response = await fetch(`http://127.0.0.1:${bridge.port}${route}`, {method: body === undefined ? 'GET' : 'POST',
        headers: {'Content-Type': 'application/json', ...(token ? {Authorization: 'Bearer ' + token} : {})},
        ...(body === undefined ? {} : {body: JSON.stringify(body)})});
      return {status: response.status, body: await response.json()};
    },
    async read() { const result = await this.request('/state'); assert.equal(result.status, 200); return result.body; },
    async quote(kind, args, sourceCity) {
      const result = await this.request('/quote', {kind, args, requestId: 'realm_quote_' + ++serial, ...(sourceCity ? {sourceCity} : {})});
      assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body;
    },
    async send(command, extra = {}) {
      const before = await this.read(), input = {commandId: 'realm_command_' + ++serial, expectedRevision: before.revision, ...command, ...extra};
      const result = await this.request('/command', input); return {...result, input};
    },
    async command(type, args = [], extra = {}) {
      const result = await this.send({type, args}, extra); assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body;
    },
    async import(game) {
      game.save(); assert.equal(game.validSave(game.state), true);
      const before = await this.read(), result = await this.request('/import', {commandId: 'realm_import_' + ++serial, expectedRevision: before.revision, state: game.state});
      assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body;
    },
    async saved() { return fs.readFile(path.join(directory, 'save.json'), 'utf8'); },
  };
  t.after(async () => { await bridge.close(); await fs.rm(directory, {recursive: true, force: true}); });
  return f;
}

function prepared(canonical) {
  const runtime = canonical.createGameRuntime({now: NOW}), game = runtime.Game, state = game.state;
  for (const [site, id, level] of [[0, 'house', 10], [1, 'drill', 10], [2, 'market', 1], [3, 'barracks', 10], [4, 'academy', 10]]) {
    state.cityLayout[site] = id; state.cityLevels[site] = level; state.buildings[id] = level;
  }
  state.population = 1000; state.res = {food: 1000000, wood: 1000000, stone: 1000000, iron: 1000000, gold: 1000000};
  state.army.archer = 2000; state.army.wagon = 10; state.honors.noble = 10;
  game.save(); assert.equal(game.validSave(state), true); return runtime;
}

function closest(game, predicate) {
  return Array.from({length: 4096}, (_, i) => game.getWorldTile(i % 64, Math.floor(i / 64)))
    .filter(predicate).sort((a, b) => Math.hypot(a.x - 32, a.y - 32) - Math.hypot(b.x - 32, b.y - 32))[0];
}

function ownWild(game, node, city = 'capital') {
  game.state.conquered[node.id] = true; game.state.landClaims[node.id] = {at: NOW, level: node.level};
  game.state.realm.wildOwners[node.id] = city;
}

test('HTTP management previews enforce identity and shape, hide unreached nodes, and never persist fees/queues/receipts', async t => {
  const f = await fixture(t), runtime = prepared(f.canonical); await f.import(runtime.Game);
  const before = await f.saved(), envelope = await f.read();
  const valid = await f.quote('march', ['field', 'lin', {archer: 30}, 'raid', false]);
  assert.equal(valid.authorityId, envelope.authorityId); assert.equal(valid.revision, envelope.revision);
  assert.equal(valid.quote.reason, ''); assert.ok(valid.quote.foodCost > 0);
  assert.equal(valid.quote.carry, runtime.Game.carry({archer: 30}));
  assert.equal(await f.saved(), before);
  const base = {kind: 'march', args: ['field', 'lin', {archer: 30}, 'raid', false], requestId: 'realm_bad_quote'};
  assert.equal((await f.request('/quote', base, null)).status, 401);
  for (const body of [{...base, actor: 'someone'}, {...base, serverTime: NOW + 1}, {...base, kind: 'unknown'},
    {...base, args: ['field', 'lin', {archer: -1}, 'raid', false]}, {...base, args: ['field', 'lin', {archer: 1.5}, 'raid', false]},
    {...base, args: ['field', 'lin', {fakeUnit: 1}, 'raid', false]}, {...base, requestId: ''}])
    assert.equal((await f.request('/quote', body)).status, 400);
  assert.equal((await f.request('/quote?sourceCity=capital', base)).status, 400);
  const foreign = await f.request('/quote', {...base, sourceCity: 'city_foreign'});
  assert.equal(foreign.status, 400); assert.equal(foreign.body.error.code, 'CITY_NOT_OWNED');
  for (const node of ['wood']) {
    const result = await f.request('/quote', {...base, args: [node, 'lin', {archer: 30}, 'raid', false]});
    assert.equal(result.status, 403); assert.equal(result.body.error.code, 'NODE_HIDDEN');
  }
  const unknown = await f.request('/quote', {...base, args: ['not_a_node', 'lin', {archer: 30}, 'raid', false]});
  assert.equal(unknown.status, 404); assert.equal(unknown.body.error.code, 'NODE_NOT_FOUND');
  assert.equal(await f.saved(), before);
});

test('found-city preview/commit and transport/redeploy scope, keys, returns and overflow obey canonical rules', async t => {
  const f = await fixture(t), runtime = prepared(f.canonical), game = runtime.Game;
  const plain = closest(game, node => node.wild && node.type === 'plain'); ownWild(game, plain); await f.import(game);
  const before = await f.read(), found = await f.quote('foundCity', [plain.id, '运输分城']);
  assert.equal(found.quote.reason, ''); assert.deepEqual(found.quote.cost, game.foundCityQuote(plain.id, '运输分城').cost);
  const founded = await f.send(found.quote.command); assert.equal(founded.status, 200, JSON.stringify(founded.body));
  const city = 'city_' + plain.id;
  for (const [id, amount] of Object.entries(found.quote.cost)) assert.equal(founded.body.state.res[id], before.state.res[id] - amount);
  const same = await f.request('/command', founded.input); assert.equal(same.body.replayed, true);
  const again = await f.send(found.quote.command); assert.equal(again.status, 400);
  const second = f.canonical.createGameRuntime({snapshot: founded.body.state, now: f.now}).Game;
  second.switchCity(city); second.state.res.wood = second.capacity('wood'); second.switchCity('capital'); await f.import(second);
  let q = await f.quote('transport', [city, {wagon: 2}, {wood: 5000}, '']); assert.equal(q.quote.reason, '');
  const bad = await f.send({...q.quote.command, args: [...q.quote.command.args.slice(0, -1), 'stale-key']});
  assert.equal(bad.status, 400); assert.match(bad.body.error.message, /重新预览/);
  const original = await f.read(), sent = await f.send(q.quote.command); assert.equal(sent.status, 200);
  assert.equal(sent.body.state.army.wagon, original.state.army.wagon - 2);
  assert.equal(sent.body.state.res.wood, original.state.res.wood - 5000);
  const job = sent.body.state.realm.logistics[0]; assert.equal(job.phase, 'outbound');
  f.at(job.end); const arrived = await f.command('setTax', [20]);
  assert.ok(arrived.state.realm.cities[city].data.res.wood >= 15000);
  assert.equal(arrived.state.realm.logistics[0].phase, 'return');
  assert.equal(arrived.state.army.wagon, original.state.army.wagon - 2);
  f.at(arrived.state.realm.logistics[0].end); const returned = await f.command('setTax', [20]);
  assert.equal(returned.state.army.wagon, original.state.army.wagon); assert.deepEqual(returned.state.realm.logistics, []);
  q = await f.quote('redeploy', [city, {archer: 20}, 'lin']); assert.equal(q.quote.reason, '');
  const moved = await f.send(q.quote.command); assert.equal(moved.status, 200);
  f.at(moved.body.state.realm.logistics[0].end); const stationed = await f.command('setTax', [20]);
  assert.equal(stationed.state.realm.heroLocations.lin, city); assert.equal(stationed.state.realm.cities[city].data.army.archer, 20);
  assert.equal(stationed.state.army.archer, original.state.army.archer - 20);
  const local = f.canonical.createGameRuntime({snapshot: stationed.state, now: f.now});
  assert.equal(f.projection.realmView(local).generals.some(hero => hero.id === 'lin'), false);
});

test('realm presentation retains own-city roles and separates each city wild holdings', async () => {
  const [, canonical, projection] = await modules, runtime = prepared(canonical), game = runtime.Game;
  const plain = closest(game, node => node.wild && node.type === 'plain'); ownWild(game, plain);
  const q = game.foundCityQuote(plain.id, '分城'); assert.equal(game.foundCity(plain.id, q.name, q.key), null);
  const city = 'city_' + plain.id, fields = Array.from({length: 4096}, (_, i) => game.getWorldTile(i % 64, Math.floor(i / 64))).filter(n => n.wild && n.type === 'forest').slice(0, 2);
  ownWild(game, fields[0], 'capital'); ownWild(game, fields[1], city); game.save();
  let view = projection.realmView(runtime); assert.deepEqual(view.holdings.map(h => h.id), [fields[0].id]);
  game.switchCity(city); view = projection.realmView(runtime); assert.deepEqual(view.holdings.map(h => h.id), [fields[1].id]);
  assert.equal(view.generals.length, 0); game.switchCity('capital');
  assert.equal(runtime.HeritageSystem.assign('su', 'lin', ''), null);
  view = projection.realmView(runtime); assert.equal(view.roles.commander.hero, 'lin');
  assert.equal(runtime.HeritageSystem.assign('su', 'su', ''), '一位将领只能担任一个职位');
});

test('fill templates preserve existing high-level fields, replacements retain matches, and reserves pause automation', async () => {
  const [, canonical, projection] = await modules, runtime = prepared(canonical), game = runtime.Game, state = game.state;
  state.plots[0] = {type: 'lumber', level: 8}; state.plots[1] = {type: 'lumber', level: 7};
  state.plots[2] = {type: 'farm', level: 6}; game.save();
  const view = projection.realmView(runtime), template = view.templates.find(t => t.id === 'army');
  const fill = template.quotes.find(q => q.mode === 'fill'), replace = template.quotes.find(q => q.mode === 'replace');
  assert.equal(fill.tasks.some(task => task.index <= 2), false);
  assert.equal(replace.tasks.some(task => task.index === 0 || task.index === 2), false);
  assert.equal(replace.tasks.find(task => task.index === 1).kind, 'replace');
  const reserve = {...state.res};
  assert.equal(game.setAutomationSettings({reserve, researchFocus: 'military', researchPriority: 'shooting', notify: false}), null);
  assert.equal(game.applyPlotTemplate('army', 'fill'), null); assert.deepEqual(state.buildQueue, []);
  assert.match(game.plotTemplateStatus(), /保留额度/);
  assert.equal(game.setAutoResearch(true), null); assert.equal(state.researchQueue, null);
  assert.equal(game.setAutomationSettings({reserve: {food: 0, wood: 0, stone: 0, iron: 0, gold: 0}, researchFocus: 'military', researchPriority: 'shooting', notify: true}), null);
  assert.ok(state.buildQueue.length > 0); assert.equal(state.plots[0].level, 8);
});

test('stationed gathering has a real wait and permits overflow; collection and troop recall settle once', async t => {
  const f = await fixture(t), runtime = prepared(f.canonical), game = runtime.Game;
  const target = closest(game, node => node.wild && node.type === 'forest' && node.level === 1);
  await f.import(game);
  const dispatched = await f.command('dispatch', [target.id, 'lin', {archer: 1000}, 'occupy', false]);
  f.at(dispatched.state.expedition.end); await f.command('startBattle');
  let won;
  for (let i = 0; i < 30; i++) { won = await f.command('battleRound'); if (won.state.battle.finished) break; }
  assert.equal(won.state.battle.result.won, true); assert.equal(won.state.garrisons[target.id].phase, 'stationed');
  const started = await f.command('heritage.startGather', [target.id]);
  assert.equal((await f.send({type: 'heritage.collectGather', args: [target.id]})).status, 400);
  f.at(started.state.gatherings[target.id].start + 3600000);
  const before = await f.read(), reading = f.canonical.createGameRuntime({snapshot: before.state, now: f.now}), q = reading.HeritageSystem.gatherQuote(reading.Game.state, target.id);
  assert.equal(q.ready, true); assert.ok(q.received > 0); assert.ok(q.overCapacity > 0);
  const collected = await f.send({type: 'heritage.collectGather', args: [target.id]}); assert.equal(collected.status, 200);
  assert.equal(collected.body.state.res[q.resource], before.state.res[q.resource] + q.received);
  assert.equal(collected.body.state.gatherings[target.id], undefined);
  const replay = await f.request('/command', collected.input); assert.equal(replay.body.replayed, true); assert.deepEqual(replay.body.state.heritageHistory, collected.body.state.heritageHistory);
  const army = collected.body.state.garrisons[target.id].army.archer;
  const recalled = await f.command('recallGarrison', [target.id]); f.at(recalled.state.garrisons[target.id].end);
  const returned = await f.command('setTax', [20]); assert.equal(returned.state.garrisons[target.id], undefined);
  assert.equal(returned.state.army.archer, won.state.army.archer + army);
});

test('shared and room previews authenticate own source and reject local NPC/auto-defense capabilities without persistence', async t => {
  const [,, , sharedModule, roomModule] = await modules;
  for (const mode of ['shared', 'room']) {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'shanhece-quote-auth-'));
    const config = {port: 0, dataDir: directory, clock: () => NOW, settlementIntervalMs: 0};
    const bridge = mode === 'shared' ? await sharedModule.startSharedBridge(config) : await roomModule.startRoomsServer(config);
    t.after(async () => { await bridge.close(); await fs.rm(directory, {recursive: true, force: true}); });
    async function request(route, body, token) {
      const response = await fetch(bridge.url + route, {method: body ? 'POST' : 'GET', headers: {'Content-Type': 'application/json', ...(token ? {Authorization: 'Bearer ' + token} : {})}, ...(body ? {body: JSON.stringify(body)} : {})});
      return {status: response.status, body: await response.json()};
    }
    let token;
    if (mode === 'shared') token = bridge.credentials[0].token;
    else { const created = await request('/lobby/create', {requestId: crypto.randomBytes(32).toString('hex'), roomName: '预览验证', capacity: 2, playerName: '甲'}); assert.equal(created.status, 200); token = created.body.accessToken; }
    const prefix = mode === 'shared' ? '' : '/api', filename = path.join(directory, mode === 'shared' ? 'shared-world.json' : 'rooms.json');
    const before = await fs.readFile(filename, 'utf8'), state = (await request(prefix + '/state', undefined, token)).body;
    const args = {kind: 'redeploy', args: ['not_owned', {archer: 1}, ''], requestId: 'shared_quote_identity'};
    assert.equal((await request(prefix + '/quote', args)).status, 401);
    const own = await request(prefix + '/quote', args, token); assert.equal(own.status, 200); assert.equal(own.body.actor.id, state.actor.id); assert.equal(own.body.authorityId, state.authorityId);
    assert.ok(own.body.quote.reason);
    assert.equal((await request(prefix + '/quote', {...args, sourceCity: 'city_foreign'}, token)).body.error.code, 'CITY_NOT_OWNED');
    assert.equal((await request(prefix + '/quote', {...args, actor: 'someone'}, token)).status, 400);
    assert.equal((await request(prefix + '/quote', {...args, kind: 'march', args: ['field', 'lin', {archer: 1}, 'raid', false]}, token)).body.error.code, 'COMMAND_NOT_ALLOWED');
    const blocked = await request(prefix + '/command', {commandId: 'shared_auto_defense_denied', expectedRevision: state.revision, type: 'setAutoCityDefense', args: [true]}, token);
    assert.equal(blocked.status, 400); assert.equal(blocked.body.error.code, 'COMMAND_NOT_ALLOWED');
    assert.equal(await fs.readFile(filename, 'utf8'), before);
  }
});

test('fresh-city playable route builds, researches and trains the 30-archer first battle using only normal rewards', async t => {
  const f = await fixture(t);
  async function rewards() {
    let envelope = await f.read(), runtime = f.canonical.createGameRuntime({snapshot: envelope.state, now: f.now});
    if (runtime.OnboardingSystem.available(runtime.Game.state).length) await f.command('onboarding.claimAvailable');
    envelope = await f.read(); runtime = f.canonical.createGameRuntime({snapshot: envelope.state, now: f.now});
    if (runtime.Game.missions.some(mission => runtime.Game.missionReady(mission))) await f.command('claimReadyMissions');
  }
  async function building(id, target) {
    for (;;) {
      const envelope = await f.read(), game = f.canonical.createGameRuntime({snapshot: envelope.state, now: f.now}).Game;
      if (game.requirementLevel(id) >= target) return;
      for (const condition of game.buildingConditions(id, game.requirementLevel(id) + 1))
        if (condition.kind === 'building') await building(condition.id, condition.level);
      const current = (await f.read()).state;
      const plot = Object.hasOwn(game.plotTypes, id);
      const site = plot ? current.plots.findIndex(field => field.type === id) : current.cityLayout.includes(id) ? current.cityLayout.indexOf(id) : current.cityLayout.indexOf(null);
      assert.ok(site >= 0, 'building requires an existing slot for ' + id);
      const queued = await f.command(plot ? 'developPlot' : 'queueBuilding', [site, id]);
      const queue = queued.state.buildQueue.find(job => plot ? job.plot === site : job.site === site);
      f.at(Math.ceil(queue.end)); await f.command('setTax', [20]); await rewards();
    }
  }
  await rewards(); await building('house', 2); await building('hall', 2);
  for (const [index, type] of ['farm', 'lumber', 'quarry', 'mine'].entries()) {
    const queued = await f.command('developPlot', [index, type]), job = queued.state.buildQueue.find(q => q.plot === index);
    f.at(Math.ceil(job.end)); await f.command('setTax', [20]); await rewards();
  }
  // Follow the actual displayed guide instead of reproducing the prerequisite
  // table in this regression. Each next step must be actionable by a new city.
  const visited = new Set();
  for (let step = 0; step < 60; step++) {
    const envelope = await f.read(), next = envelope.view.progression.firstBattle.next;
    if (next.route === 'army') break;
    visited.add(next.route + ':' + next.target);
    if (next.route === 'inner' || next.route === 'outer') {
      const game = f.canonical.createGameRuntime({snapshot: envelope.state, now: f.now}).Game;
      await building(next.target, game.requirementLevel(next.target) + 1);
    } else {
      assert.equal(next.route, 'research');
      const queued = await f.command('research', [next.target]); f.at(Math.ceil(queued.state.researchQueue.end)); await f.command('setTax', [20]); await rewards();
    }
  }
  assert.ok(visited.has('outer:mine')); assert.ok(visited.has('research:training')); assert.ok(visited.has('research:shooting'));
  let city = await f.read(); assert.equal(city.state.buildings.barracks, 4); assert.equal(city.state.tech.shooting, 1);
  let trainingGame = f.canonical.createGameRuntime({snapshot: city.state, now: f.now}).Game;
  const people = 30 * trainingGame.units.archer.people;
  while (trainingGame.freePopulation() < people) {
    assert.ok(trainingGame.state.inventory.population > 0, 'normal onboarding rewards must support the first army population');
    const populated = await f.command('useItem', ['population']);
    trainingGame = f.canonical.createGameRuntime({snapshot: populated.state, now: f.now}).Game;
  }
  const trained = await f.command('train', ['archer', 30]); f.at(Math.ceil(trained.state.trainQueue.at(-1).end)); await f.command('setTax', [20]); await rewards();
  city = await f.read(); assert.equal(city.state.army.archer, 30);
  const sent = await f.command('dispatch', ['field', 'lin', {archer: 30}, 'raid', false]); f.at(Math.ceil(sent.state.expedition.end)); await f.command('startBattle');
  let result;
  for (let i = 0; i < 30; i++) { result = await f.command('battleRound'); if (result.state.battle.finished) break; }
  assert.equal(result.state.battle.result.won, true); assert.equal(result.state.stats.victories, 1);
  assert.ok(result.state.reports[0].resourceReceipt.base.received.food > 0);
  assert.equal((await f.send({type: 'completeFirstBattleGuide', args: []})).status, 400);
  f.at(Math.ceil(result.state.expedition.end)); await f.command('setTax', [20]);
  city = await f.read();
  if (city.state.army.archer < 30) {
    const refill = await f.command('train', ['archer', 30 - city.state.army.archer]); f.at(Math.ceil(refill.state.trainQueue.at(-1).end)); await f.command('setTax', [20]);
  }
  const completed = await f.command('completeFirstBattleGuide'); assert.equal(completed.state.onboarding.firstBattle, 'complete');
  assert.equal(completed.state.army.archer, 30); assert.equal(completed.state.expedition, null);
  assert.deepEqual(completed.state.onboarding.claims, [1, 2]);
  assert.equal(f.canonical.createGameRuntime({snapshot: completed.state, now: f.now}).Game.validSave(completed.state), true);
  t.diagnostic('Fresh save reached first battle and complete return after ' + Math.ceil((f.now - NOW) / 60000) + ' simulated minutes, using earned hall gifts/missions and population items only.');
});

test('prepared late-game route pays epic/rank gates, occupies county and every chapter-two node before revealing chapter three', async t => {
  // A lawful advanced-army stock fixture isolates chapter mechanics from natural
  // multi-day resource accumulation. The fresh-city test above uses no imports.
  const f = await fixture(t), runtime = prepared(f.canonical), game = runtime.Game, state = game.state;
  state.honors.noble = 0; state.prestige = 1000; state.army.archer = 6000; state.army.ram = 300; state.army.catapult = 100;
  state.jewels.pearl = 31; state.jewels.coral = 5; state.epic.kills = 1490; state.epic.killRewards = 2;
  await f.import(game);
  async function battle(node, mode) {
    let before = await f.read();
    if (before.state.cooldowns[node] > f.now) { f.at(before.state.cooldowns[node]); await f.command('setTax', [20]); before = await f.read(); }
    const army = {archer: 3000, ram: 100, catapult: 50};
    const sent = await f.command('dispatch', [node, 'lin', army, mode, true]); f.at(Math.ceil(sent.state.expedition.end)); await f.command('startBattle');
    let finished;
    for (let round = 0; round < 30; round++) { finished = await f.command('battleRound'); if (finished.state.battle.finished) break; }
    assert.equal(finished.state.battle.result.won, true, node + ' must settle as a real canonical victory');
    assert.equal(finished.state.reports.length, Math.min(20, before.state.reports.length + 1));
    const result = finished.state.battle.result;
    if (mode === 'occupy' && result.moraleBefore !== null) assert.equal(result.moraleAfter, Math.max(-100, result.moraleBefore - 35));
    else assert.equal(result.claimed, mode === 'occupy');
    if (finished.state.expedition) { f.at(Math.ceil(finished.state.expedition.end)); await f.command('setTax', [20]); }
    return finished;
  }
  await battle('field', 'raid');
  assert.equal((await f.read()).state.epic.kills, 1500);
  for (const id of ['food', 'wood', 'stone', 'iron', 'gold']) await f.command('donateEpic', ['resource', id]);
  await f.command('donateEpic', ['troop', 'archer']);
  await f.command('donateEpic', ['jewel', 'pearl']); await f.command('donateEpic', ['jewel', 'pearl']);
  await f.command('heritage.promote', ['office']); await f.command('heritage.promote', ['noble']);
  let snapshot = await f.read(), live = f.canonical.createGameRuntime({snapshot: snapshot.state, now: f.now}).Game;
  assert.equal(live.countyUnlocked(), true); assert.equal(live.cityLimit(), 2); assert.equal(snapshot.state.jewels.coral, 0);
  for (const id of ['wood', 'pass', 'camp', 'mine']) await battle(id, id === 'camp' ? 'occupy' : 'raid');
  assert.ok((await f.read()).state.generals.includes('yan'), 'occupying the camp must actually rescue the canonical general');
  let countyAttacks = 0;
  while (!(await f.read()).state.conquered.fort && countyAttacks < 5) { await battle('fort', 'occupy'); countyAttacks++; }
  assert.ok(countyAttacks > 1, 'county control must require the original negative-morale threshold');
  snapshot = await f.read(); assert.equal(snapshot.state.conquered.fort, true);
  assert.equal(snapshot.view.progression.chapters[0].unlocked, true); assert.equal(snapshot.view.progression.chapters[1].unlocked, false);
  const nodes = runtime.ChapterData.chapterNodes(2);
  for (const [index, node] of nodes.entries()) {
    assert.equal((await f.request('/node?id=' + runtime.ChapterData.chapterNodes(3)[0].id)).status, 403);
    await battle(node.id, 'occupy');
    const claimed = await f.command('claimMission', ['chapter2_' + node.id]);
    assert.equal(claimed.state.missionClaims.includes('chapter2_' + node.id), true);
    assert.equal(claimed.view.progression.chapters[0].conquered, index + 1);
    assert.equal(claimed.view.progression.chapters[1].unlocked, index === nodes.length - 1);
  }
  snapshot = await f.read();
  assert.equal(snapshot.view.progression.chapters[0].claimed, 6);
  assert.equal((await f.request('/node?id=' + runtime.ChapterData.chapterNodes(3)[0].id)).status, 200);
  assert.equal((await f.request('/node?id=' + runtime.ChapterData.chapterNodes(3)[1].id)).status, 403);
  t.diagnostic('Prepared late-game stock fixture completed legal epic/rank fees, ' + countyAttacks + ' county attacks, and all ' + nodes.length + ' chapter-two occupations; this isolates rules, not natural long-game pacing.');
});
