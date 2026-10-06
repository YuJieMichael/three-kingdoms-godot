const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');

const NOW = 1800000000000;
const modules = () => Promise.all([
  import('../bridge/shared-server.mjs'),
  import('../vendor/legacy/online/runtime.mjs'),
]);

async function fixture(t, options = {}) {
  const [module, runtime] = await modules();
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'three-kingdoms-shared-'));
  let now = NOW, counter = 0, bridge;
  const configuration = {dataDir: path.join(directory, 'private'), port: 0,
    clock: () => now, settlementIntervalMs: 0, ...options};
  bridge = await module.startSharedBridge(configuration);
  const actors = bridge.credentials;
  assert.equal(actors.length, 4);
  const api = {
    module, runtime, directory, configuration, actors,
    get bridge() { return bridge; }, get now() { return now; },
    at(value) { assert.ok(value >= now); now = value; }, advance(ms) { now += ms; },
    async request(actor, route, body, extra = {}) {
      const headers = {'Content-Type': 'application/json'};
      if (actor) headers.Authorization = `Bearer ${actor.token}`;
      Object.assign(headers, extra.headers || {});
      const response = await fetch(bridge.url + route, {
        method: body === undefined ? 'GET' : 'POST', ...extra, headers,
        ...(body === undefined ? {} : {body: JSON.stringify(body)}),
      });
      const text = await response.text(); let value;
      try { value = JSON.parse(text); } catch { value = text; }
      return {status: response.status, body: value, headers: response.headers};
    },
    async read(actor = actors[0]) {
      const result = await api.request(actor, '/state');
      assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body;
    },
    async command(actor, type, args = [], extra = {}) {
      const before = await api.read(actor);
      const result = await api.request(actor, '/command', {expectedRevision: before.revision,
        commandId: `shared_fixture_${String(++counter).padStart(6, '0')}`, type, args, ...extra});
      assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body;
    },
    async saved() { return JSON.parse(await fs.readFile(path.join(configuration.dataDir, 'shared-world.json'), 'utf8')); },
    async restart() { await bridge.close(); bridge = await module.startSharedBridge(configuration); },
    async settle() { return bridge.settle(); },
  };
  t.after(async () => { await bridge?.close(); await fs.rm(directory, {recursive: true, force: true}); });
  return api;
}

const worldOf = envelope => envelope.shared || envelope.publicWorld || envelope.world;
const privateFields = ['state', 'army', 'res', 'inventory', 'equipment', 'token', 'credentials', 'receipts'];
function assertPublicPlayer(row) {
  for (const key of privateFields) assert.equal(row[key], undefined, `public player leaked ${key}`);
}
function sameBattleReport(a, b) {
  for (const key of ['id', 'source', 'target', 'sourceCity', 'targetCity', 'at', 'won', 'attacker', 'defender',
    'wounded', 'defenderWounded', 'lost', 'defenderLost', 'loot', 'log', 'reason', 'captive', 'occupation']) {
    assert.deepEqual(a?.[key], b?.[key], `battle report ${key}`);
  }
}

test('four authenticated accounts have independent stable authorities and one public shared map', async t => {
  const f = await fixture(t), authorities = new Set(), homes = new Set();
  const credentials = JSON.parse(await fs.readFile(path.join(f.configuration.dataDir, 'credentials.json'), 'utf8'));
  assert.equal(credentials.schema, 1); assert.equal(credentials.actors.length, 4);
  if (process.platform !== 'win32') {
    assert.equal((await fs.stat(f.configuration.dataDir)).mode & 0o777, 0o700);
    assert.equal((await fs.stat(path.join(f.configuration.dataDir, 'credentials.json'))).mode & 0o777, 0o600);
    assert.equal((await fs.stat(path.join(f.configuration.dataDir, 'shared-world.json'))).mode & 0o777, 0o600);
  }
  assert.equal(new Set(f.actors.map(actor => actor.token)).size, 4);
  for (const actor of f.actors) {
    const health = await f.request(actor, '/health'), own = await f.read(actor), world = worldOf(own);
    assert.equal(health.status, 200); assert.equal(health.body.mode, 'shared');
    assert.equal(own.actor.id, actor.id); assert.equal(health.body.actor.id, actor.id);
    assert.equal(own.authorityId, health.body.authorityId); assert.match(own.authorityId, /^[a-f0-9-]{36}$/);
    assert.equal(own.state.ruler, actor.name);
    assert.equal(f.runtime.createGameRuntime({snapshot: own.state, now: f.now}).Game.validSave(own.state), true);
    assert.equal(world.players.length, 4);
    world.players.forEach(assertPublicPlayer);
    assert.equal(world.players.find(row => row.id === actor.id).alliance,
      world.players.find(row => row.id === f.actors[actor.slot <= 2 ? 0 : 2].id).alliance);
    authorities.add(own.authorityId);
    const home = world.players.find(row => row.id === actor.id).home;
    homes.add(`${home.x},${home.y}`);
    const map = await f.request(actor, '/world'); assert.equal(map.status, 200);
    assert.equal(map.body.tiles.length, 4096);
    for (const player of f.actors) {
      const tile = map.body.tiles.find(row => row.id === `player_city:${player.id}:capital`);
      assert.ok(tile, `missing shared city ${player.id}`); assert.equal(tile.playerId, player.id);
      assert.deepEqual(tile.army, {}); assert.equal(tile.res, undefined); assert.equal(tile.state, undefined);
    }
    for (const other of f.actors) assert.equal(JSON.stringify(own).includes(other.token), false);
  }
  assert.equal(authorities.size, 4); assert.equal(homes.size, 4);
  const ids = await Promise.all(f.actors.map(async actor => (await f.read(actor)).authorityId));
  await f.restart();
  assert.deepEqual(await Promise.all(f.actors.map(async actor => (await f.read(actor)).authorityId)), ids);
  assert.deepEqual(f.bridge.credentials, f.actors);
});

test('anonymous, invalid credentials and foreign origin cannot read private state or mutate the world', async t => {
  const f = await fixture(t), saved = JSON.stringify(await f.saved());
  for (const route of ['/health', '/state', '/world', '/api/state', '/api/world']) {
    assert.equal((await f.request(null, route)).status, 401, route);
    assert.equal((await f.request({token: 'not-an-account'}, route)).status, 401, route);
  }
  const input = {commandId: 'unauthorized_spend_01', expectedRevision: 1, type: 'trade', args: ['food', 100, true]};
  assert.equal((await f.request(null, '/command', input)).status, 401);
  assert.equal((await f.request(f.actors[0], '/state', undefined, {headers: {Origin: 'https://evil.example'}})).status, 403);
  assert.equal(JSON.stringify(await f.saved()), saved);
});

test('shared mode rejects import, export, client state injection, actor overrides and client settlement', async t => {
  const f = await fixture(t), actor = f.actors[0], before = await f.read(actor), saved = JSON.stringify(await f.saved());
  const common = {commandId: 'boundary_state_00001', expectedRevision: before.revision, type: 'setTax', args: [30]};
  const attempts = [
    ['/import', {commandId: 'boundary_import_001', expectedRevision: before.revision, state: before.state}],
    ['/command', {...common, state: {...before.state, res: {gold: 999999999}}}],
    ['/command', {...common, actor: f.actors[2].id}],
    ['/command', {...common, actorId: f.actors[2].id}],
    ['/command', {...common, userId: f.actors[2].id}],
    ['/command', {...common, type: 'shared.settle'}],
    ['/command', {...common, type: 'grantTestSupplies'}],
    ['/command', {...common, type: 'setSpeed', args: [100]}],
  ];
  for (const [route, body] of attempts) {
    const result = await f.request(actor, route, body);
    assert.ok(result.status >= 400 && result.status < 500, JSON.stringify({route, body, result}));
  }
  assert.ok((await f.request(actor, '/export')).status >= 400);
  assert.equal(JSON.stringify(await f.saved()), saved);
  assert.equal((await f.read(actor)).revision, before.revision);
});

test('malformed commands and inherited namespace names fail as client errors without writing receipts', async t => {
  const f = await fixture(t), actor = f.actors[0], before = await f.read(actor), saved = JSON.stringify(await f.saved());
  const input = {commandId: 'malformed_command_01', expectedRevision: before.revision, type: 'setTax', args: [30]};
  for (const body of [[], null, {...input, commandId: 'short'}, {...input, expectedRevision: -1},
    {...input, expectedRevision: 1.5}, {...input, args: {}}, {...input, args: ['x'.repeat(50001)]},
    {...input, type: 'constructor'}, {...input, type: '__proto__.evil'}, {...input, type: 'constructor.evil'},
    {...input, type: 'shared.__proto__'}]) {
    const denied = await f.request(actor, '/command', body);
    assert.ok(denied.status >= 400 && denied.status < 500, JSON.stringify(denied));
  }
  const badContentType = await f.request(actor, '/command', input, {headers: {'Content-Type': 'text/plain'}});
  assert.equal(badContentType.status, 415);
  assert.equal(JSON.stringify(await f.saved()), saved);
});

test('same-revision simultaneous spends commit one real payment; exact retry and receipts survive restart', async t => {
  const f = await fixture(t), actor = f.actors[0], base = await f.read(actor);
  const input = {commandId: 'shared_spend_replay_01', expectedRevision: base.revision, type: 'trade', args: ['food', 100, true]};
  const firstWave = await Promise.all(Array.from({length: 12}, () => f.request(actor, '/command', input)));
  firstWave.forEach(reply => assert.equal(reply.status, 200, JSON.stringify(reply.body)));
  assert.equal(firstWave.filter(reply => reply.body.replayed).length, 11);
  const committed = await f.read(actor);
  assert.equal(committed.revision, base.revision + 1);
  assert.equal(committed.state.res.food, base.state.res.food + 100);
  assert.equal(committed.state.res.gold, base.state.res.gold - 100);
  const reused = await f.request(actor, '/command', {...input, args: ['food', 101, true]});
  assert.equal(reused.status, 409); assert.equal(reused.body.error.code, 'ID_REUSED');
  const concurrency = await Promise.all(Array.from({length: 10}, (_, index) => f.request(actor, '/command', {
    commandId: `shared_parallel_spend_${index}`, expectedRevision: committed.revision, type: 'trade', args: ['food', 7, true],
  })));
  assert.equal(concurrency.filter(reply => reply.status === 200).length, 1);
  assert.equal(concurrency.filter(reply => reply.status === 409 && reply.body.error.code === 'REVISION_CONFLICT').length, 9);
  const after = await f.read(actor);
  assert.equal(after.state.res.gold, committed.state.res.gold - 7);
  assert.equal(after.state.res.food, committed.state.res.food + 7);
  assert.equal(after.revision, committed.revision + 1);
  await f.restart(); const replay = await f.request(actor, '/command', input);
  assert.equal(replay.status, 200); assert.equal(replay.body.replayed, true);
  assert.deepEqual(replay.body.state.res, firstWave[0].body.state.res);
  assert.deepEqual(replay.body, {...firstWave.find(reply => !reply.body.replayed).body, replayed: true});
  const resumed = await f.read(actor);
  assert.equal(resumed.authorityId, base.authorityId); assert.deepEqual(resumed.state.res, after.state.res);
  assert.equal(resumed.revision, after.revision);
});

test('different actors can use the same command id without affecting each other', async t => {
  const f = await fixture(t), [a, b] = f.actors, beforeA = await f.read(a), beforeB = await f.read(b);
  const replies = await Promise.all([f.request(a, '/command', {commandId: 'same_id_two_accounts', expectedRevision: beforeA.revision, type: 'setTax', args: [25]}),
    f.request(b, '/command', {commandId: 'same_id_two_accounts', expectedRevision: beforeB.revision, type: 'setTax', args: [35]})]);
  replies.forEach(reply => assert.equal(reply.status, 200, JSON.stringify(reply.body)));
  assert.equal((await f.read(a)).state.tax, 25); assert.equal((await f.read(b)).state.tax, 35);
  await f.restart(); assert.equal((await f.read(a)).state.tax, 25); assert.equal((await f.read(b)).state.tax, 35);
});

for (const type of ['shared.attackPlayer', 'shared.aid']) test(`${type} rejects cross-account entity id collisions before troop escrow and retains exact retries`, async t => {
  const f = await fixture(t), [a, b, c, d] = f.actors;
  const firstActor = a, secondActor = type === 'shared.aid' ? c : b;
  const firstTarget = type === 'shared.aid' ? b : c, secondTarget = d;
  const firstBefore = await f.read(firstActor), secondBefore = await f.read(secondActor);
  const input = {commandId: 'cross_account_march_id', expectedRevision: firstBefore.revision, type,
    args: [{targetId: firstTarget.id, general: 'lin', army: {cavalry: 10}}]};
  const first = await f.request(firstActor, '/command', input);
  assert.equal(first.status, 200, JSON.stringify(first.body));
  const colliding = {...input, expectedRevision: secondBefore.revision,
    args: [{targetId: secondTarget.id, general: 'lin', army: {cavalry: 10}}]};
  const durable = await f.saved(), denied = await f.request(secondActor, '/command', colliding);
  assert.equal(denied.status, 409); assert.equal(denied.body.error.code, 'ENTITY_ID_REUSED');
  assert.deepEqual(await f.saved(), durable, 'collision cannot debit either player, replace escrow or record success');
  assert.deepEqual((await f.read(secondActor)).state.army, secondBefore.state.army);
  assert.equal(worldOf(await f.read(secondActor)).marches.some(march => march.source === secondActor.id), false);
  await f.restart();
  const replay = await f.request(firstActor, '/command', input);
  assert.equal(replay.status, 200); assert.deepEqual(replay.body, {...first.body, replayed: true});
  const deniedAgain = await f.request(secondActor, '/command', colliding);
  assert.equal(deniedAgain.status, 409); assert.deepEqual(await f.saved(), durable);
  const fresh = await f.request(secondActor, '/command', {...colliding, commandId: 'second_account_fresh_march'});
  assert.equal(fresh.status, 200, JSON.stringify(fresh.body));
  assert.equal(fresh.body.state.army.cavalry, secondBefore.state.army.cavalry - 10);
  assert.equal(f.bridge.snapshot().marches.filter(march => march.source === secondActor.id).length, 1);
});

test('market order and delivery id collisions preserve seller stock, buyer gold and original receipts', async t => {
  const f = await fixture(t), [a, b, c, d] = f.actors;
  const orderInput = {commandId: 'cross_account_order_id', expectedRevision: (await f.read(a)).revision,
    type: 'shared.marketCreate', args: [{resource: 'wood', quantity: 100, price: 2}]};
  const order = await f.request(a, '/command', orderInput); assert.equal(order.status, 200, JSON.stringify(order.body));
  const beforeSeller = await f.read(c), collision = {...orderInput, expectedRevision: beforeSeller.revision};
  let durable = await f.saved(), denied = await f.request(c, '/command', collision);
  assert.equal(denied.status, 409); assert.equal(denied.body.error.code, 'ENTITY_ID_REUSED');
  assert.deepEqual(await f.saved(), durable); assert.deepEqual((await f.read(c)).state.res, beforeSeller.state.res);
  const otherOrder = await f.command(c, 'shared.marketCreate', [{resource: 'wood', quantity: 100, price: 2}]);
  const deliveryInput = {commandId: 'cross_account_delivery_id', expectedRevision: (await f.read(b)).revision,
    type: 'shared.marketBuy', args: [{id: order.body.result.order.id, targetId: a.id, quantity: 10}]};
  const delivery = await f.request(b, '/command', deliveryInput); assert.equal(delivery.status, 200, JSON.stringify(delivery.body));
  const buyerBefore = await f.read(d), deliveryCollision = {...deliveryInput, expectedRevision: buyerBefore.revision,
    args: [{id: otherOrder.result.order.id, targetId: c.id, quantity: 10}]};
  durable = await f.saved(); denied = await f.request(d, '/command', deliveryCollision);
  assert.equal(denied.status, 409); assert.equal(denied.body.error.code, 'ENTITY_ID_REUSED');
  assert.deepEqual(await f.saved(), durable); assert.deepEqual((await f.read(d)).state.res, buyerBefore.state.res);
  await f.restart();
  assert.deepEqual((await f.request(a, '/command', orderInput)).body, {...order.body, replayed: true});
  assert.deepEqual((await f.request(b, '/command', deliveryInput)).body, {...delivery.body, replayed: true});
  assert.equal((await f.request(d, '/command', deliveryCollision)).status, 409);
  assert.deepEqual(await f.saved(), durable);
});

test('alliance and operation marker ids cannot alias another account entity', async t => {
  const f = await fixture(t), [a, b, c, d] = f.actors;
  const markInput = {commandId: 'cross_account_marker_id', expectedRevision: (await f.read(a)).revision,
    type: 'shared.markOperation', args: [{kind: 'defend', x: 26, y: 28, note: 'first alliance'}]};
  const mark = await f.request(a, '/command', markInput); assert.equal(mark.status, 200, JSON.stringify(mark.body));
  let durable = await f.saved(), denied = await f.request(c, '/command', {...markInput, expectedRevision: (await f.read(c)).revision});
  assert.equal(denied.status, 409); assert.equal(denied.body.error.code, 'ENTITY_ID_REUSED'); assert.deepEqual(await f.saved(), durable);
  for (const actor of [b, a, d, c]) await f.command(actor, 'shared.leaveAlliance');
  const allianceInput = {commandId: 'cross_account_alliance_id', expectedRevision: (await f.read(a)).revision,
    type: 'shared.createAlliance', args: [{name: 'Review First'}]};
  const alliance = await f.request(a, '/command', allianceInput); assert.equal(alliance.status, 200, JSON.stringify(alliance.body));
  durable = await f.saved();
  const collision = {...allianceInput, expectedRevision: (await f.read(c)).revision, args: [{name: 'Review Second'}]};
  denied = await f.request(c, '/command', collision);
  assert.equal(denied.status, 409); assert.equal(denied.body.error.code, 'ENTITY_ID_REUSED'); assert.deepEqual(await f.saved(), durable);
  await f.restart();
  assert.deepEqual((await f.request(a, '/command', allianceInput)).body, {...alliance.body, replayed: true});
  assert.equal((await f.request(c, '/command', collision)).status, 409); assert.deepEqual(await f.saved(), durable);
  assert.equal(f.bridge.snapshot().memberships.some(member => member.user === c.id), false);
});

test('reads project elapsed time without rewriting authoritative resources, revisions or receipts', async t => {
  const f = await fixture(t), filename = path.join(f.configuration.dataDir, 'shared-world.json');
  const before = await fs.readFile(filename, 'utf8'); f.advance(600001);
  for (const actor of f.actors) { await f.read(actor); await f.request(actor, '/world'); await f.request(actor, '/health'); }
  assert.equal(await fs.readFile(filename, 'utf8'), before);
});

test('friendly fire, unowned source city and busy general are rejected without duplicate escrow', async t => {
  const f = await fixture(t), [a, ally, enemy] = f.actors, before = await f.read(a);
  const friendly = await f.request(a, '/command', {commandId: 'friendly_fire_denied', expectedRevision: before.revision,
    type: 'shared.attackPlayer', args: [{targetId: ally.id, general: 'lin', army: {cavalry: 10}}]});
  assert.equal(friendly.status, 400); assert.equal(friendly.body.error.code, 'WAR_NOT_OPEN');
  const wrongCity = await f.request(a, '/command', {commandId: 'wrong_source_denied', expectedRevision: before.revision,
    sourceCity: 'city_enemy_private', type: 'shared.attackPlayer', args: [{targetId: enemy.id, general: 'lin', army: {cavalry: 10}}]});
  assert.ok(wrongCity.status >= 400); assert.equal((await f.read(a)).revision, before.revision);
  const sent = await f.command(a, 'shared.attackPlayer', [{targetId: enemy.id, general: 'lin', army: {cavalry: 10}}]);
  assert.equal(sent.state.army.cavalry, before.state.army.cavalry - 10);
  const busy = await f.request(a, '/command', {commandId: 'busy_general_denied', expectedRevision: sent.revision,
    type: 'shared.attackPlayer', args: [{targetId: enemy.id, general: 'lin', army: {cavalry: 10}}]});
  assert.ok(busy.status >= 400); assert.equal((await f.read(a)).state.army.cavalry, sent.state.army.cavalry);
  assert.equal(worldOf(await f.read(a)).marches.length, 1);
});

test('server determines arrival and incoming marches hide private army while unrelated accounts see no march', async t => {
  const f = await fixture(t), [a, unrelated, enemy] = f.actors;
  const before = await f.read(a);
  const forged = await f.request(a, '/command', {commandId: 'forged_march_denied', expectedRevision: before.revision,
    type: 'shared.attackPlayer', args: [{targetId: enemy.id, general: 'lin', army: {cavalry: 20},
      start: 0, arrive: 0, returnAt: 0, won: true, loot: {gold: 999999999}}]});
  assert.equal(forged.status, 400); assert.equal(forged.body.error.code, 'CLIENT_AUTHORITY_FORBIDDEN');
  assert.equal((await f.read(a)).revision, before.revision);
  const sent = await f.command(a, 'shared.attackPlayer', [{targetId: enemy.id, general: 'lin', army: {cavalry: 20}}]);
  const march = sent.result.march;
  assert.equal(march.start, f.now); assert.ok(march.arrive > f.now);
  const own = worldOf(await f.read(a)).marches.find(row => row.id === march.id);
  const incoming = worldOf(await f.read(enemy)).marches.find(row => row.id === march.id);
  assert.equal(own.army.cavalry, 20); assert.ok(incoming);
  for (const field of ['army', 'statsSnapshot', 'generalSnapshot', 'orders', 'loot']) assert.equal(incoming[field], undefined);
  assert.equal(worldOf(await f.read(unrelated)).marches.some(row => row.id === march.id), false);
  const map = (await f.request(enemy, '/world')).body, shown = map.marches.find(row => row.id === march.id);
  assert.ok(shown); assert.ok(shown.count === null || shown.count === undefined);
  assert.ok(!shown.army || Object.keys(shown.army).length === 0);
});

test('overdue attack resolves and returns once on reconnect after server restart without battle confirmation', async t => {
  const f = await fixture(t), [a, , enemy] = f.actors, before = await f.read(a), targetBefore = await f.read(enemy);
  const army = {cavalry: Math.min(500, before.state.army.cavalry)};
  assert.ok(army.cavalry > 0);
  const sent = await f.command(a, 'shared.attackPlayer', [{targetId: enemy.id, general: 'lin', army}]);
  f.at(sent.result.march.arrive + Math.max(1000, sent.result.march.arrive - sent.result.march.start) + 1);
  await f.restart();
  const result = await f.read(a), defender = await f.read(enemy), report = worldOf(result).reports.find(row => row.id === sent.result.march.id);
  assert.ok(report, 'reconnect must resolve the overdue attack');
  assert.equal(worldOf(result).marches.some(row => row.id === sent.result.march.id), false);
  sameBattleReport(worldOf(defender).reports.find(row => row.id === sent.result.march.id), report);
  assert.equal(report.attacker.cavalry + report.wounded.cavalry + report.lost.cavalry, army.cavalry);
  assert.equal(result.state.army.cavalry, before.state.army.cavalry - army.cavalry + report.attacker.cavalry);
  assert.equal(result.state.warCare.wounded.cavalry, before.state.warCare.wounded.cavalry + report.wounded.cavalry);
  assert.equal(defender.state.army.cavalry, report.defender.cavalry || 0);
  assert.equal(report.defender.cavalry + report.defenderWounded.cavalry + report.defenderLost.cavalry, targetBefore.state.army.cavalry);
  const balances = JSON.stringify([result.state.res, defender.state.res, result.state.army, defender.state.army,
    result.state.warCare.wounded, defender.state.warCare.wounded]);
  await f.settle(); await f.restart();
  const again = await f.read(a), defenderAgain = await f.read(enemy);
  assert.equal(JSON.stringify([again.state.res, defenderAgain.state.res, again.state.army, defenderAgain.state.army,
    again.state.warCare.wounded, defenderAgain.state.warCare.wounded]), balances);
  assert.equal(worldOf(again).reports.filter(row => row.id === report.id).length, 1);
  assert.equal(again.authorityId, before.authorityId);
});

test('victorious raid deducts real defender stock, carries it home once and survives lost acknowledgement retry', async t => {
  const f = await fixture(t), [attacker, , defender] = f.actors;
  const initial = await f.read(attacker), targetInitial = await f.read(defender);
  const army = {cavalry: initial.state.army.cavalry, archer: initial.state.army.archer};
  const input = {commandId: 'raid_with_actual_loot', expectedRevision: initial.revision,
    type: 'shared.attackPlayer', args: [{targetId: defender.id, general: 'lin', army}]};
  const sentReply = await f.request(attacker, '/command', input);
  assert.equal(sentReply.status, 200, JSON.stringify(sentReply.body));
  const sent = sentReply.body, march = sent.result.march;
  for (const [unit, count] of Object.entries(army)) assert.equal(sent.state.army[unit], initial.state.army[unit] - count);
  assert.equal(sent.state.res.food, initial.state.res.food - sent.result.supply);
  assert.equal((await f.read(defender)).state.res.food, targetInitial.state.res.food);
  f.at(march.arrive);
  const attackerBeforeBattle = await f.read(attacker), defenderBeforeBattle = await f.read(defender);
  assert.equal(worldOf(attackerBeforeBattle).reports.length, 0, 'reads must not resolve shared arrivals');
  await f.settle();
  const fought = await f.read(attacker), targetFought = await f.read(defender);
  const report = worldOf(fought).reports.find(row => row.id === march.id);
  assert.equal(report.won, true, JSON.stringify(report));
  assert.ok(Object.values(report.loot).some(quantity => quantity > 0));
  for (const resource of ['food', 'wood', 'stone', 'iron', 'gold']) {
    assert.equal(targetFought.state.res[resource], defenderBeforeBattle.state.res[resource] - (report.loot[resource] || 0), resource);
    assert.equal(fought.state.res[resource], attackerBeforeBattle.state.res[resource], `loot still in transit: ${resource}`);
  }
  const returning = worldOf(fought).marches.find(row => row.id === march.id);
  assert.equal(returning.status, 'return');
  f.at(returning.returnAt);
  const justBeforeReturn = await f.read(attacker);
  await f.settle();
  const home = await f.read(attacker), targetHome = await f.read(defender);
  for (const resource of ['food', 'wood', 'stone', 'iron', 'gold']) {
    assert.equal(home.state.res[resource], justBeforeReturn.state.res[resource] + (report.loot[resource] || 0), resource);
  }
  for (const [unit, count] of Object.entries(army)) {
    assert.equal(home.state.army[unit], initial.state.army[unit] - count + (report.attacker[unit] || 0));
    assert.equal((report.attacker[unit] || 0) + (report.wounded[unit] || 0) + (report.lost[unit] || 0), count);
  }
  const authoritative = JSON.stringify([home.state.res, home.state.army, targetHome.state.res, targetHome.state.army]);
  const lateRetry = await f.request(attacker, '/command', input);
  assert.equal(lateRetry.status, 200); assert.equal(lateRetry.body.replayed, true);
  assert.equal(lateRetry.body.result.march.id, march.id);
  assert.deepEqual(lateRetry.body, {...sent, replayed: true}, 'late receipt must retain the original state, world and rendering confirmation together');
  await f.settle(); await f.restart();
  const resumed = await f.read(attacker), targetResumed = await f.read(defender);
  assert.equal(JSON.stringify([resumed.state.res, resumed.state.army, targetResumed.state.res, targetResumed.state.army]), authoritative);
  assert.equal(worldOf(resumed).reports.filter(row => row.id === march.id).length, 1);
  assert.equal(worldOf(resumed).marches.some(row => row.id === march.id), false);
});

test('allied aid retains its owner during battle, receives wounds once, and recalls only surviving troops', async t => {
  const f = await fixture(t), [attacker, , defender, ally] = f.actors;
  const originalAlly = await f.read(ally), originalDefender = await f.read(defender), originalAttacker = await f.read(attacker);
  const aidArmy = {spear: Math.min(100, originalAlly.state.army.spear)};
  assert.ok(aidArmy.spear > 0);
  const aid = await f.command(ally, 'shared.aid', [{targetId: defender.id, general: 'lin', army: aidArmy}]);
  assert.equal(aid.state.army.spear, originalAlly.state.army.spear - aidArmy.spear);
  f.at(aid.result.march.arrive); await f.settle();
  const stationed = worldOf(await f.read(ally)).marches.find(row => row.id === aid.result.march.id);
  assert.equal(stationed.status, 'stationed');
  assert.equal((await f.read(defender)).state.army.spear, originalDefender.state.army.spear);
  // Focus a smaller attack on the spear line so reinforcements take losses but survive to recall.
  await f.command(attacker, 'setTactic', ['cavalry', 'advance', 'spear']);
  const attackArmy = {cavalry: Math.min(400, originalAttacker.state.army.cavalry)};
  const attack = await f.command(attacker, 'shared.attackPlayer', [{targetId: defender.id, general: 'lin', army: attackArmy}]);
  f.at(attack.result.march.arrive); await f.settle();
  const attackerNow = await f.read(attacker), defenderNow = await f.read(defender), allyNow = await f.read(ally);
  const report = worldOf(attackerNow).reports.find(row => row.id === attack.result.march.id);
  assert.ok(report); sameBattleReport(worldOf(defenderNow).reports.find(row => row.id === report.id), report);
  const aidNow = worldOf(allyNow).marches.find(row => row.id === aid.result.march.id);
  assert.equal(aidNow.source, ally.id); assert.equal(aidNow.status, 'stationed');
  assert.equal(defenderNow.state.army.spear + aidNow.army.spear, report.defender.spear || 0);
  const allyWounds = allyNow.state.warCare.wounded.spear - originalAlly.state.warCare.wounded.spear;
  const defenderWounds = defenderNow.state.warCare.wounded.spear - originalDefender.state.warCare.wounded.spear;
  assert.equal(allyWounds + defenderWounds, report.defenderWounded.spear || 0);
  assert.ok(allyWounds > 0, 'allied casualties must enter the original owner hospital');
  assert.equal(report.defender.spear + report.defenderLost.spear + report.defenderWounded.spear,
    originalDefender.state.army.spear + aidArmy.spear);
  assert.equal(allyNow.state.army.spear, originalAlly.state.army.spear - aidArmy.spear);
  const recall = await f.command(ally, 'shared.recallAid', [{id: aid.result.march.id}]);
  const recallMarch = worldOf(recall).marches.find(row => row.id === aid.result.march.id);
  assert.equal(recallMarch.start, recall.serverTime);
  assert.equal(recallMarch.arrive, recall.result.returnAt);
  assert.deepEqual(recallMarch.from, worldOf(recall).players.find(row => row.id === defender.id).home);
  assert.deepEqual(recallMarch.to, worldOf(recall).players.find(row => row.id === ally.id).home);
  f.at(Math.max(recall.result.returnAt, attack.result.march.arrive + (attack.result.march.arrive - attack.result.march.start)) + 1);
  await f.settle();
  const returned = await f.read(ally);
  assert.equal(returned.state.army.spear, originalAlly.state.army.spear - aidArmy.spear + aidNow.army.spear);
  assert.equal(returned.state.warCare.wounded.spear, allyNow.state.warCare.wounded.spear);
  await f.settle(); await f.restart();
  assert.equal((await f.read(ally)).state.army.spear, returned.state.army.spear);
  assert.equal((await f.read(ally)).state.warCare.wounded.spear, returned.state.warCare.wounded.spear);
  assert.equal(worldOf(await f.read(ally)).marches.some(row => row.id === aid.result.march.id), false);
});

test('static serving rejects private paths, symlinks, traversal and private web root overlap', async t => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'three-kingdoms-shared-web-'));
  const webDir = path.join(directory, 'web'), dataDir = path.join(directory, 'private');
  await fs.mkdir(webDir); await fs.writeFile(path.join(webDir, 'index.html'), '<html>shared PvP</html>');
  const f = await fixture(t, {dataDir, webDir});
  t.after(() => fs.rm(directory, {recursive: true, force: true}));
  await fs.symlink(path.join(dataDir, 'credentials.json'), path.join(webDir, 'escape.json'));
  await fs.symlink(dataDir, path.join(webDir, 'private-link'));
  const index = await f.request(null, '/'); assert.equal(index.status, 200); assert.equal(index.body, '<html>shared PvP</html>');
  assert.equal(index.headers.get('cross-origin-opener-policy'), 'same-origin');
  for (const route of ['/credentials.json', '/shared-world.json', '/.shared.lock', '/escape.json',
    '/private-link/credentials.json', '/%2e%2e%2fprivate/credentials.json', '/%2e%2e/private/credentials.json', '/%5cprivate%5ccredentials.json']) {
    const denied = await f.request(null, route);
    assert.ok(denied.status >= 400, route); for (const actor of f.actors) assert.equal(String(denied.body).includes(actor.token), false);
  }
  await fs.mkdir(path.join(webDir, 'nested-save'));
  await fs.symlink(path.join(webDir, 'nested-save'), path.join(directory, 'private-alias'));
  await assert.rejects(f.module.startSharedBridge({dataDir: path.join(directory, 'private-alias'), webDir, port: 0,
    settlementIntervalMs: 0, clock: () => NOW}), /separate|private|overlap/i);
});

test('one data directory has one authority and corrupt persisted worlds are preserved', async t => {
  const f = await fixture(t);
  await assert.rejects(f.module.startSharedBridge(f.configuration), /运行|lock|进程/i);
  const filename = path.join(f.configuration.dataDir, 'shared-world.json');
  await f.bridge.close(); await fs.writeFile(filename, '{corrupt');
  await assert.rejects(f.module.startSharedBridge(f.configuration));
  assert.equal(await fs.readFile(filename, 'utf8'), '{corrupt');
});

test('stale lock recovery serializes two contenders through deletion and replacement', async t => {
  const f = await fixture(t), dataDir = f.bridge.dataDir;
  await f.bridge.close();
  const dead = spawnSync(process.execPath, ['-e', '']); assert.equal(dead.status, 0);
  const ownerFile = path.join(dataDir, '.shared-bridge.lock'), guardFile = path.join(dataDir, '.shared-bridge.reclaim.lock');
  await fs.writeFile(ownerFile, JSON.stringify({pid: dead.pid, identity: 'crashed-owner'}));
  const durable = await fs.readFile(path.join(dataDir, 'shared-world.json'), 'utf8'), originalUnlink = fs.unlink;
  let pause, resume, paused = false, winner, first;
  const deletionStarted = new Promise(resolve => { pause = resolve; });
  const continueDeletion = new Promise(resolve => { resume = resolve; });
  fs.unlink = async (...args) => {
    if (args[0] === ownerFile && !paused) { paused = true; pause(); await continueDeletion; }
    return originalUnlink(...args);
  };
  try {
    first = f.module.startSharedBridge(f.configuration).then(service => { winner = service; return service; });
    await deletionStarted;
    assert.ok(await fs.stat(guardFile), 'guard must exist before the stale owner is unlinked');
    await assert.rejects(f.module.startSharedBridge({...f.configuration, port: 0}), error => error.code === 'SAVE_LOCKED' && error.message.includes('reclaim.lock'));
    assert.equal(JSON.parse(await fs.readFile(ownerFile, 'utf8')).identity, 'crashed-owner');
    resume(); await first;
    const identity = JSON.parse(await fs.readFile(ownerFile, 'utf8')).identity;
    await assert.rejects(f.module.startSharedBridge({...f.configuration, port: 0}), error => error.code === 'SAVE_LOCKED');
    assert.equal(JSON.parse(await fs.readFile(ownerFile, 'utf8')).identity, identity);
    await assert.rejects(fs.stat(guardFile), error => error.code === 'ENOENT');
    assert.equal(await fs.readFile(path.join(dataDir, 'shared-world.json'), 'utf8'), durable);
  } finally { resume(); fs.unlink = originalUnlink; await first?.catch(() => {}); await winner?.close(); }
});

test('an interrupted recovery guard fails closed without deleting another lock or private data', async t => {
  const f = await fixture(t), dataDir = f.bridge.dataDir;
  await f.bridge.close();
  const dead = spawnSync(process.execPath, ['-e', '']); assert.equal(dead.status, 0);
  const ownerFile = path.join(dataDir, '.shared-bridge.lock'), guardFile = path.join(dataDir, '.shared-bridge.reclaim.lock');
  const owner = JSON.stringify({pid: dead.pid, identity: 'crashed-owner'}), guard = JSON.stringify({pid: dead.pid, identity: 'crashed-recovery'});
  await fs.writeFile(ownerFile, owner); await fs.writeFile(guardFile, guard);
  const durable = await fs.readFile(path.join(dataDir, 'shared-world.json'), 'utf8');
  await assert.rejects(f.module.startSharedBridge(f.configuration), error => error.code === 'SAVE_LOCKED' && error.message.includes('reclaim.lock'));
  assert.equal(await fs.readFile(ownerFile, 'utf8'), owner); assert.equal(await fs.readFile(guardFile, 'utf8'), guard);
  assert.equal(await fs.readFile(path.join(dataDir, 'shared-world.json'), 'utf8'), durable);
  // Explicit recovery after verifying no process remains can remove only the
  // interrupted guard; the normal guarded path then reclaims the dead owner.
  await fs.unlink(guardFile);
  const recovered = await f.module.startSharedBridge(f.configuration);
  try { assert.equal(recovered.credentials[0].authorityId, f.actors[0].authorityId); }
  finally { await recovered.close(); }
});

test('failed atomic rename leaves balances and receipts unchanged, allowing the same command to retry once', async t => {
  const f = await fixture(t), actor = f.actors[0], before = await f.read(actor);
  const filename = path.join(f.bridge.dataDir, 'shared-world.json'), durable = await fs.readFile(filename, 'utf8');
  const input = {commandId: 'atomic_failed_retry', expectedRevision: before.revision, type: 'trade', args: ['food', 100, true]};
  const originalRename = fs.rename; let injected = false, denied;
  fs.rename = async (...args) => {
    if (!injected && args[1] === filename) { injected = true; const error = new Error('Injected disk write failure'); error.code = 'ENOSPC'; throw error; }
    return originalRename(...args);
  };
  try { denied = await f.request(actor, '/command', input); } finally { fs.rename = originalRename; }
  assert.equal(injected, true); assert.equal(denied.status, 503); assert.equal(denied.body.error.code, 'PERSISTENCE_FAILED');
  assert.equal(await fs.readFile(filename, 'utf8'), durable);
  assert.deepEqual(f.bridge.snapshot().receipts, JSON.parse(durable).data.receipts);
  const unchanged = await f.read(actor);
  assert.equal(unchanged.revision, before.revision); assert.deepEqual(unchanged.state.res, before.state.res);
  const retried = await f.request(actor, '/command', input);
  assert.equal(retried.status, 200); assert.equal(retried.body.replayed, false);
  assert.equal(retried.body.state.res.gold, before.state.res.gold - 100);
  assert.equal(retried.body.state.res.food, before.state.res.food + 100);
  await f.restart(); const replay = await f.request(actor, '/command', input);
  assert.equal(replay.body.replayed, true); assert.equal((await f.read(actor)).state.res.gold, before.state.res.gold - 100);
});

test('post-rename directory fsync failure restores the previous durable world and its receipts', {skip: process.platform === 'win32'}, async t => {
  const f = await fixture(t), actor = f.actors[0], before = await f.read(actor);
  const filename = path.join(f.bridge.dataDir, 'shared-world.json'), durable = await fs.readFile(filename, 'utf8');
  const input = {commandId: 'directory_fsync_retry', expectedRevision: before.revision, type: 'trade', args: ['food', 50, true]};
  const originalOpen = fs.open; let injected = false, denied;
  fs.open = async (...args) => {
    const handle = await originalOpen(...args);
    if (!injected && args[0] === f.bridge.dataDir && args[1] === 'r') {
      injected = true;
      return {async sync() { const error = new Error('Injected directory sync failure'); error.code = 'EIO'; throw error; }, close: () => handle.close()};
    }
    return handle;
  };
  try { denied = await f.request(actor, '/command', input); } finally { fs.open = originalOpen; }
  assert.equal(injected, true); assert.equal(denied.status, 503); assert.equal(denied.body.error.code, 'PERSISTENCE_FAILED');
  assert.equal(await fs.readFile(filename, 'utf8'), durable);
  assert.deepEqual(f.bridge.snapshot().receipts, JSON.parse(durable).data.receipts);
  assert.deepEqual((await f.read(actor)).state.res, before.state.res);
  await f.restart(); assert.equal((await f.read(actor)).revision, before.revision);
  const retried = await f.request(actor, '/command', input);
  assert.equal(retried.status, 200); assert.equal(retried.body.replayed, false);
  assert.equal(retried.body.state.res.gold, before.state.res.gold - 50);
  assert.equal(retried.body.state.res.food, before.state.res.food + 50);
  assert.equal(f.bridge.snapshot().receipts.filter(receipt => receipt.actor === actor.id && receipt.id === input.commandId).length, 1);
});

test('failed battle persistence rolls back attacker, defender, escrow and reports as one transaction', async t => {
  const f = await fixture(t), [attacker, , defender] = f.actors, before = await f.read(attacker);
  const sent = await f.command(attacker, 'shared.attackPlayer', [{targetId: defender.id, general: 'lin',
    army: {cavalry: before.state.army.cavalry, archer: before.state.army.archer}}]);
  f.at(sent.result.march.arrive);
  const attackerProjection = await f.read(attacker), defenderProjection = await f.read(defender);
  const filename = path.join(f.bridge.dataDir, 'shared-world.json'), durable = await fs.readFile(filename, 'utf8');
  const storedBefore = f.bridge.snapshot(), originalRename = fs.rename; let injected = false;
  fs.rename = async (...args) => {
    if (!injected && args[1] === filename) { injected = true; const error = new Error('Injected battle disk failure'); error.code = 'ENOSPC'; throw error; }
    return originalRename(...args);
  };
  try { await assert.rejects(f.settle(), error => error.code === 'PERSISTENCE_FAILED'); } finally { fs.rename = originalRename; }
  assert.equal(injected, true); assert.equal(await fs.readFile(filename, 'utf8'), durable);
  assert.deepEqual(f.bridge.snapshot(), storedBefore);
  assert.deepEqual((await f.read(attacker)).state.res, attackerProjection.state.res);
  assert.deepEqual((await f.read(defender)).state.res, defenderProjection.state.res);
  assert.equal(worldOf(await f.read(attacker)).reports.length, 0);
  assert.equal(worldOf(await f.read(defender)).reports.length, 0);
  await f.settle();
  const fought = await f.read(attacker), targetFought = await f.read(defender);
  const report = worldOf(fought).reports.find(row => row.id === sent.result.march.id);
  assert.equal(report.won, true); sameBattleReport(worldOf(targetFought).reports.find(row => row.id === report.id), report);
  for (const resource of ['food', 'wood', 'stone', 'iron', 'gold']) {
    assert.equal(targetFought.state.res[resource], defenderProjection.state.res[resource] - (report.loot[resource] || 0));
  }
  const committed = f.bridge.snapshot(); await f.settle();
  assert.deepEqual(f.bridge.snapshot(), committed);
});
