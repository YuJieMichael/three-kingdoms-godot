const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const NOW = 1800000000000;
const modules = Promise.all([import('../bridge/server.mjs'), import('../vendor/legacy/online/runtime.mjs'),
  import('../bridge/shared-server.mjs')]);

async function fixture(t) {
  const [server, canonical] = await modules;
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'shanhece-scout-http-'));
  let now = NOW, serial = 0, bridge;
  const config = {port: 0, dataDir: directory, token: 'isolated-scout-http-token', clock: () => now};
  bridge = await server.startBridge(config);
  const f = {canonical, directory, get now() { return now; },
    at(value) { assert.ok(value >= now); now = value; },
    async request(route, input, token = config.token) {
      const response = await fetch(`http://127.0.0.1:${bridge.port}${route}`, {
        method: input === undefined ? 'GET' : 'POST', headers: {'Content-Type': 'application/json',
          ...(token ? {Authorization: 'Bearer ' + token} : {})},
        ...(input === undefined ? {} : {body: JSON.stringify(input)})});
      return {status: response.status, body: await response.json()};
    },
    async read() { const result = await this.request('/state'); assert.equal(result.status, 200); return result.body; },
    async quote(node = 'field', count = 1, sourceCity) {
      const result = await this.request('/quote', {kind: 'scout', args: [node, count], requestId: 'scout_http_quote_' + ++serial,
        ...(sourceCity ? {sourceCity} : {})});
      assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body;
    },
    async input(command) {
      const current = await this.read(); return {commandId: 'scout_http_command_' + ++serial,
        expectedRevision: current.revision, ...command};
    },
    async send(command) { const input = await this.input(command); return {...await this.request('/command', input), input}; },
    async command(type, args = [], sourceCity) {
      const result = await this.send({type, args, ...(sourceCity ? {sourceCity} : {})});
      assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body;
    },
    async import(game) {
      game.save(); assert.equal(game.validSave(game.state), true);
      const current = await this.read(), result = await this.request('/import', {commandId: 'scout_http_import_' + ++serial,
        expectedRevision: current.revision, state: game.state});
      assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body;
    },
    async saved() { return fs.readFile(path.join(directory, 'save.json'), 'utf8'); },
    async restart() { await bridge.close(); bridge = await server.startBridge(config); },
  };
  t.after(async () => { await bridge.close(); await fs.rm(directory, {recursive: true, force: true}); });
  return f;
}
function prepared(canonical, tech = 5) {
  const runtime = canonical.createGameRuntime({now: NOW}), game = runtime.Game;
  prepareCity(game, tech); game.state.honors.noble = 10; game.save();
  assert.equal(game.validSave(game.state), true); return game;
}
function prepareCity(game, tech = 5) {
  game.state.cityLayout[0] = 'drill'; game.state.cityLevels[0] = 2; game.state.buildings.drill = 2;
  game.state.tech.scouting = tech; game.state.army.scout = 50;
  game.state.res = {food: 1000000, wood: 1000000, stone: 1000000, iron: 1000000, gold: 1000000};
}
function foundCity(game) {
  const node = Array.from({length: 4096}, (_, i) => game.getWorldTile(i % 64, Math.floor(i / 64)))
    .filter(n => n.wild && n.type === 'plain').sort((a, b) =>
      Math.hypot(a.x - 32, a.y - 32) - Math.hypot(b.x - 32, b.y - 32))[0];
  game.state.conquered[node.id] = true; game.state.landClaims[node.id] = {at: NOW, level: node.level};
  game.state.realm.wildOwners[node.id] = 'capital';
  const quote = game.foundCityQuote(node.id, '情报分城'); assert.equal(quote.reason, '');
  assert.equal(game.foundCity(node.id, quote.name, quote.key), null); return 'city_' + node.id;
}

test('HTTP scout previews authenticate, validate, hide unreached targets and never persist a fee or receipt', async t => {
  const f = await fixture(t), game = prepared(f.canonical); await f.import(game);
  const stored = await f.saved(), current = await f.read(), result = await f.quote();
  const expected = game.scoutQuote('field', 1);
  for (const key of ['cost', 'seconds', 'returnSeconds', 'precision', 'expectedLost', 'ttlMs', 'key'])
    assert.deepEqual(result.quote[key], expected[key]);
  assert.equal(result.authorityId, current.authorityId); assert.equal(result.revision, current.revision);
  assert.equal(result.requestId.startsWith('scout_http_quote_'), true); assert.equal(result.quote.sourceCity, 'capital');
  const base = {kind: 'scout', args: ['field', 1], requestId: 'scout_http_bad_preview'};
  assert.equal((await f.request('/quote', base, null)).status, 401);
  for (const input of [{...base, actor: 'other'}, {...base, sourceCity: {}}, {...base, args: ['field', '1']},
    {...base, args: ['field', 0]}, {...base, args: ['field', 1001]}, {...base, args: ['field', 1, 'key']}, {...base, requestId: ''}])
    assert.equal((await f.request('/quote', input)).status, 400);
  assert.equal((await f.request('/quote?sourceCity=capital', base)).status, 400);
  assert.equal((await f.request('/quote', {...base, args: ['wood', 1]})).status, 403);
  assert.equal((await f.request('/quote', {...base, args: ['missing_node', 1]})).status, 404);
  assert.equal((await f.request('/quote', {...base, sourceCity: 'city_foreign'})).body.error.code, 'CITY_NOT_OWNED');
  assert.equal(await f.saved(), stored); assert.equal((await f.read()).revision, current.revision);
});

test('HTTP scouting charges once with CAS/replay, persists arrival intel, returns survivors and expires at exact TTL', async t => {
  const f = await fixture(t); await f.import(prepared(f.canonical));
  const current = await f.read(), preview = await f.quote(), input = await f.input(preview.quote.command);
  const competing = {...input, commandId: input.commandId + '_competing'};
  const responses = await Promise.all([f.request('/command', input), f.request('/command', competing)]);
  assert.deepEqual(responses.map(row => row.status).sort(), [200, 409]);
  const accepted = responses.find(row => row.status === 200), sentInput = accepted === responses[0] ? input : competing;
  const sent = accepted.body, march = sent.state.scoutQueue[0];
  assert.equal(sent.state.res.food, current.state.res.food - preview.quote.cost.food);
  assert.equal(sent.state.army.scout, current.state.army.scout - 1);
  assert.equal(sent.view.marches.find(row => row.type === 'scout').lost, null);
  assert.equal(sent.view.marches.find(row => row.type === 'scout').status, 'march');
  assert.equal(JSON.stringify(sent.view).includes('enemySnapshot'), false);
  assert.ok(march.enemySnapshot, 'canonical private save retains its required frozen enemy snapshot');
  let replay = await f.request('/command', sentInput);
  assert.equal(replay.status, 200); assert.equal(replay.body.replayed, true); assert.equal(replay.body.revision, sent.revision);
  await f.restart(); replay = await f.request('/command', sentInput);
  assert.equal(replay.body.replayed, true); assert.equal((await f.read()).state.scoutQueue.length, 1);
  f.at(march.arriveAt); const arrived = await f.command('setTax', [20]);
  const report = arrived.state.scoutIntel.field, intel = arrived.view.scouting.intelByNode.field;
  assert.equal(intel.precision, 'exact'); assert.deepEqual(intel.army, report.army);
  assert.equal(arrived.state.army.scout, current.state.army.scout - 1);
  const returnRow = arrived.view.marches.find(row => row.type === 'scout');
  assert.equal(returnRow.status, 'return'); assert.equal(returnRow.lost, 0); assert.equal(returnRow.count, 1);
  assert.equal(returnRow.recallCommand, undefined); assert.equal(returnRow.selectCommand, undefined);
  f.at(arrived.state.scoutQueue[0].end); const returned = await f.command('setTax', [20]);
  assert.equal(returned.state.army.scout, current.state.army.scout); assert.deepEqual(returned.state.scoutQueue, []);
  assert.equal(returned.view.marches.some(row => row.type === 'scout'), false);
  await f.restart(); assert.deepEqual((await f.read()).view.scouting.intelByNode.field, intel);
  f.at(report.expiresAt - 1); assert.equal((await f.read()).view.scouting.intelByNode.field.precision, 'exact');
  f.at(report.expiresAt); const expired = await f.read(), old = expired.view.scouting.intelByNode.field;
  assert.equal(old.precision, 'expired'); assert.deepEqual(old.army, {}); assert.deepEqual(old.bands, {}); assert.deepEqual(old.types, []);
  assert.equal(old.at, report.at); assert.equal(old.expiresAt, report.expiresAt);
  assert.deepEqual(expired.view.nodes.find(row => row.id === 'field').army, {});
  const detail = await f.request('/node?id=field'); assert.equal(detail.status, 200);
  assert.equal(detail.body.node.intel.precision, 'expired'); assert.deepEqual(detail.body.node.army, {});
  assert.deepEqual(expired.state.scoutIntel.field.army, report.army, 'projection must not destroy canonical history');
});

test('HTTP failure settles own losses and rejects count/target/source-city stale quote keys without charging', async t => {
  const f = await fixture(t), game = prepared(f.canonical, 0), city = foundCity(game);
  game.switchCity(city); prepareCity(game, 0); game.switchCity('capital'); await f.import(game);
  const q = await f.quote(), before = await f.read(), stored = await f.saved();
  const wild = game.getWorldTile(31, 31).id;
  for (const command of [{...q.quote.command, args: ['field', 2, q.quote.key]},
    {...q.quote.command, args: [wild, 1, q.quote.key]}, {...q.quote.command, sourceCity: city}]) {
    const denied = await f.send(command); assert.equal(denied.status, 400); assert.match(denied.body.error.message, /侦察条件已变化/);
  }
  assert.equal(await f.saved(), stored); assert.equal((await f.read()).state.res.food, before.state.res.food);
  const sent = await f.send(q.quote.command); assert.equal(sent.status, 200); assert.equal(q.quote.precision, 'failed');
  assert.equal(q.quote.expectedLost, 1);
  f.at(sent.body.state.scoutQueue[0].arriveAt); const arrived = await f.command('setTax', [20]);
  const intel = arrived.view.scouting.intelByNode.field;
  assert.equal(intel.precision, 'failed'); assert.equal(intel.success, false); assert.equal(intel.lost, 1); assert.equal(intel.survivors, 0);
  assert.deepEqual(intel.army, {}); assert.deepEqual(intel.bands, {}); assert.deepEqual(intel.types, []);
  assert.equal(arrived.view.marches.find(row => row.type === 'scout').count, 0);
  f.at(arrived.state.scoutQueue[0].end); const returned = await f.command('setTax', [20]);
  assert.equal(returned.state.army.scout, before.state.army.scout - 1); assert.deepEqual(returned.state.scoutQueue, []);
});

test('HTTP quotes and dispatch scope a second city while all-city queues stay visible and intel never crosses cities', async t => {
  const f = await fixture(t), game = prepared(f.canonical, 5), city = foundCity(game);
  game.switchCity(city); prepareCity(game, 3); game.switchCity('capital'); await f.import(game);
  const first = await f.quote('field', 1), second = await f.quote('field', 1, city);
  assert.equal(first.quote.precision, 'exact'); assert.equal(second.quote.precision, 'bands');
  assert.equal((await f.read()).state.realm.activeCity, 'capital');
  assert.equal((await f.send(first.quote.command)).status, 200);
  const sentSecond = await f.send(second.quote.command); assert.equal(sentSecond.status, 200);
  const current = await f.read(), rows = current.view.marches.filter(row => row.type === 'scout');
  assert.equal(rows.length, 2); assert.deepEqual(new Set(rows.map(row => row.sourceCity)), new Set(['capital', city]));
  const ends = Object.values(current.state.realm.cities).flatMap(c => c.data.scoutQueue.map(row => row.arriveAt));
  f.at(Math.max(...ends)); const settled = await f.command('setTax', [20], 'capital');
  assert.equal(settled.view.scouting.intelByNode.field.precision, 'exact');
  const selected = await f.command('switchCity', [city]);
  assert.equal(selected.view.scouting.intelByNode.field.precision, 'bands');
  assert.deepEqual(selected.view.nodes.find(row => row.id === 'field').army, {});
  assert.equal(JSON.stringify(selected.view).includes('enemySnapshot'), false);
  assert.equal(selected.state.realm.cities.capital.data.scoutIntel.field.quality, 3);
  assert.equal(selected.state.scoutIntel.field.quality, 2);
});

test('authenticated shared HTTP disables local scouting previews and commands without a receipt or fee', async t => {
  const [,, shared] = await modules;
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'shanhece-scout-shared-'));
  const bridge = await shared.startSharedBridge({port: 0, dataDir: directory, clock: () => NOW, settlementIntervalMs: 0});
  t.after(async () => { await bridge.close(); await fs.rm(directory, {recursive: true, force: true}); });
  const actor = bridge.credentials[0];
  async function request(route, input) {
    const response = await fetch(bridge.url + route, {method: input === undefined ? 'GET' : 'POST',
      headers: {Authorization: 'Bearer ' + actor.token, 'Content-Type': 'application/json'},
      ...(input === undefined ? {} : {body: JSON.stringify(input)})});
    return {status: response.status, body: await response.json()};
  }
  const before = (await request('/state')).body, stored = await fs.readFile(path.join(directory, 'shared-world.json'), 'utf8');
  assert.equal(before.view.scouting.supported, false); assert.deepEqual(before.view.scouting.intelByNode, {});
  const quote = await request('/quote', {kind: 'scout', args: ['field', 1], requestId: 'scout_shared_preview'});
  assert.equal(quote.status, 400); assert.equal(quote.body.error.code, 'COMMAND_NOT_ALLOWED');
  for (const type of ['dispatchScout', 'scout']) {
    const denied = await request('/command', {commandId: 'scout_shared_denied_' + type, expectedRevision: before.revision,
      type, args: ['field', 1, 'never_a_quote']});
    assert.equal(denied.status, 400); assert.equal(denied.body.error.code, 'COMMAND_NOT_ALLOWED');
  }
  const after = (await request('/state')).body;
  assert.equal(after.revision, before.revision); assert.deepEqual(after.state.res, before.state.res);
  assert.equal(await fs.readFile(path.join(directory, 'shared-world.json'), 'utf8'), stored);
});
