const {test} = require('node:test');
const assert = require('node:assert/strict');
const NOW = 1800000000000;
const modules = Promise.all([import('../vendor/legacy/online/runtime.mjs'), import('../bridge/scouting-view.mjs'),
  import('../bridge/dto.mjs'), import('../bridge/management-quotes.mjs')]);

async function fixture(tech = 5, count = 50) {
  const [canonical, projection, dto, quotes] = await modules;
  const runtime = canonical.createGameRuntime({now: NOW}), game = runtime.Game;
  prepareCity(game, tech, count); game.state.honors.noble = 10; game.save();
  assert.equal(game.validSave(game.state), true);
  return {canonical, projection, dto, quotes, runtime, game};
}
function prepareCity(game, tech, count) {
  game.state.cityLayout[0] = 'drill'; game.state.cityLevels[0] = 2; game.state.buildings.drill = 2;
  game.state.tech.scouting = tech; game.state.army.scout = count;
  game.state.res = {food: 1000000, wood: 1000000, stone: 1000000, iron: 1000000, gold: 1000000};
}
function dispatch(game, node = 'field', count = 1) {
  const quote = game.scoutQuote(node, count); assert.equal(quote.reason, '');
  assert.equal(game.dispatchScout(node, count, quote.key), null);
  return game.state.scoutQueue.at(-1);
}
function foundCity(game) {
  const plain = Array.from({length: 4096}, (_, i) => game.getWorldTile(i % 64, Math.floor(i / 64)))
    .filter(node => node.wild && node.type === 'plain').sort((a, b) =>
      Math.hypot(a.x - 32, a.y - 32) - Math.hypot(b.x - 32, b.y - 32))[0];
  game.state.conquered[plain.id] = true; game.state.landClaims[plain.id] = {at: NOW, level: plain.level};
  game.state.realm.wildOwners[plain.id] = 'capital';
  const quote = game.foundCityQuote(plain.id, '斥候分城'); assert.equal(quote.reason, '');
  assert.equal(game.foundCity(plain.id, quote.name, quote.key), null);
  return 'city_' + plain.id;
}
function noEnemyDetails(intel) {
  assert.deepEqual(intel.army, {}); assert.deepEqual(intel.bands, {}); assert.deepEqual(intel.types, []);
}

test('scout quotation is canonical, read only, strict, and shares one source-city command key', async () => {
  const f = await fixture(), before = JSON.stringify(f.game.state), expected = f.game.scoutQuote('field', 10);
  const result = f.quotes.managementQuote(f.runtime, {kind: 'scout', args: ['field', 10], requestId: 'scout_preview_one'});
  assert.deepEqual({...result.quote, command: undefined, sourceCity: undefined}, {...expected, command: undefined, sourceCity: undefined});
  assert.deepEqual(result.quote.command, {type: 'dispatchScout', args: ['field', 10, expected.key], sourceCity: 'capital'});
  assert.equal(result.sourceCity, 'capital'); assert.equal(result.quote.sourceCity, 'capital');
  assert.equal(JSON.stringify(f.game.state), before);
  for (const args of [['field'], ['field', 0], ['field', 1001], ['field', 1.5], ['field', '1'], ['field', 1, 'extra'], [null, 1]])
    assert.throws(() => f.quotes.managementQuote(f.runtime, {kind: 'scout', args, requestId: 'scout_bad_args'}), error => error.code === 'BAD_QUOTE');
  assert.throws(() => f.quotes.managementQuote(f.runtime, {kind: 'scout', args: ['missing_node', 1], requestId: 'scout_missing'}), error => error.code === 'NODE_NOT_FOUND');
  assert.throws(() => f.quotes.managementQuote(f.runtime, {kind: 'scout', args: ['wood', 1], requestId: 'scout_hidden'}), error => error.code === 'NODE_HIDDEN');
  assert.throws(() => f.quotes.managementQuote(f.runtime, {kind: 'scout', args: ['field', 1], requestId: 'scout_shared'}, {shared: true}), error => error.code === 'COMMAND_NOT_ALLOWED');
  assert.equal(JSON.stringify(f.game.state), before);
  assert.equal(f.projection.scoutQuoteView({...expected, enemySnapshot: {archer: 999}, outcome: {army: {archer: 999}}}).enemySnapshot, undefined);
});

test('original blockers cover training, scouts, food, duplicate targets and the original queue limit', async () => {
  const f = await fixture(), g = f.game;
  g.state.buildings.drill = 0; assert.equal(g.scoutQuote('field', 1).reason, '请先建造校场');
  g.state.buildings.drill = 2; g.state.army.scout = 0; assert.equal(g.scoutQuote('field', 1).reason, '城内斥候不足');
  g.state.army.scout = 50; g.state.res.food = 0; assert.equal(g.scoutQuote('field', 1).reason, '行军粮食不足');
  g.state.res.food = 1000; dispatch(g); assert.equal(g.scoutQuote('field', 1).reason, '已有斥候前往这个目标');
  const wild = g.getWorldTile(31, 31); dispatch(g, wild.id);
  assert.equal(g.scoutQuote('field', 1).reason, '侦察队列已满');
  assert.equal(f.projection.scoutingView(g, NOW).queueUsed, 2);
  assert.equal(f.projection.scoutingView(g, NOW).queueLimit, 2);
});

test('all four actual arrival precisions expose only the original information and own losses', async () => {
  for (const [tech, count, precision] of [[0, 1, 'failed'], [0, 10, 'types'], [3, 1, 'bands'], [5, 1, 'exact']]) {
    const f = await fixture(tech), before = f.game.state.army.scout, march = dispatch(f.game, 'field', count);
    f.game.tick(march.arriveAt, false); f.game.save();
    assert.equal(f.game.validSave(f.game.state), true);
    const raw = f.game.state.scoutIntel.field, node = f.game.getNode('field'), intel = f.projection.intelView(f.game, node, march.arriveAt);
    assert.equal(intel.precision, precision); assert.equal(intel.at, raw.at); assert.equal(intel.expiresAt, raw.expiresAt);
    assert.equal(intel.lost, raw.lost); assert.equal(intel.survivors, raw.survivors); assert.equal(intel.success, raw.success);
    assert.equal(f.game.state.army.scout, before - count, 'survivors are still returning');
    if (precision === 'exact') assert.deepEqual(intel.army, raw.army); else assert.deepEqual(intel.army, {});
    if (precision === 'bands') assert.deepEqual(intel.bands, raw.bands); else assert.deepEqual(intel.bands, {});
    assert.deepEqual(intel.types, raw.types);
    assert.deepEqual(f.dto.nodeView(f.game, node, march.arriveAt).intel, intel);
    const returning = f.projection.scoutMarchesView(f.game, march.arriveAt)[0];
    assert.equal(returning.status, 'return'); assert.equal(returning.type, 'scout');
    assert.equal(returning.count, raw.survivors); assert.equal(returning.lost, raw.lost);
    f.game.tick(march.arriveAt + march.returnSeconds * 1000, false);
    assert.equal(f.game.state.army.scout, before - raw.lost); assert.equal(f.game.state.scoutQueue.length, 0);
  }
});

test('TTL boundary removes old enemy details without changing report times or resetting the report', async () => {
  const f = await fixture(), march = dispatch(f.game); f.game.tick(march.arriveAt, false); f.game.save();
  const raw = f.game.state.scoutIntel.field, before = JSON.stringify(f.game.state);
  assert.equal(f.projection.intelView(f.game, f.game.getNode('field'), raw.expiresAt - 1).precision, 'exact');
  const expired = f.projection.intelView(f.game, f.game.getNode('field'), raw.expiresAt);
  assert.equal(expired.precision, 'expired'); noEnemyDetails(expired);
  assert.equal(expired.at, raw.at); assert.equal(expired.expiresAt, raw.expiresAt);
  assert.equal(expired.lost, raw.lost); assert.equal(expired.survivors, raw.survivors);
  noEnemyDetails(f.dto.nodeView(f.game, f.game.getNode('field'), raw.expiresAt).intel);
  assert.deepEqual(f.dto.nodeView(f.game, f.game.getNode('field'), raw.expiresAt).army, {});
  assert.equal(JSON.stringify(f.game.state), before);
});

test('unknown, hidden, public and legacy never use an unsupported hidden-army fallback', async () => {
  const f = await fixture(), g = f.game;
  const unknown = f.dto.nodeView(g, g.getNode('field'), NOW);
  assert.equal(unknown.intel.precision, 'unknown'); noEnemyDetails(unknown.intel); assert.deepEqual(unknown.army, {});
  g.state.scouted.field = {at: NOW, level: 5, army: {archer: 999}, enemySnapshot: {archer: 999}};
  const legacy = f.dto.nodeView(g, g.getNode('field'), NOW);
  assert.equal(g.intel('field').exact, true); assert.equal(legacy.intel.precision, 'legacy');
  assert.equal(legacy.intel.legacy, true); assert.equal(legacy.intel.success, null); noEnemyDetails(legacy.intel);
  assert.deepEqual(legacy.army, {}); assert.equal(legacy.intel.expiresAt, NOW + 40 * 60000);
  const publicNode = g.nodes.find(node => g.intel(node.id)?.public);
  assert.ok(publicNode); g.state.raided[publicNode.id] = true;
  const publicView = f.dto.nodeView(g, g.getNode(publicNode.id), NOW);
  assert.equal(publicView.intel.precision, 'public'); assert.equal(publicView.intel.public, true);
  assert.deepEqual(publicView.army, publicNode.army); assert.equal(publicView.intel.expiresAt, null);
  g.state.scouted.wood = {at: NOW, level: 5}; g.save();
  const hidden = f.dto.nodeView(g, g.getNode('wood'), NOW);
  assert.equal(hidden.hidden, true); assert.equal(hidden.intel, undefined); assert.equal(hidden.army, undefined);
  assert.equal(f.projection.scoutingView(g, NOW).intelByNode.wood, undefined);
  assert.equal(f.projection.scoutingView(g, NOW).intelByNode[publicNode.id].precision, 'public');
});

test('a modern failure keeps canonical still-valid global legacy fallback, then expires without invented data', async () => {
  const f = await fixture(0), g = f.game; g.state.scouted.field = {at: NOW, level: 5};
  const march = dispatch(g); g.tick(march.arriveAt, false); g.save();
  assert.equal(g.state.scoutIntel.field.success, false); assert.equal(g.intel('field').legacy, true);
  const legacy = f.projection.intelView(g, g.getNode('field'), march.arriveAt);
  assert.equal(legacy.precision, 'legacy'); assert.equal(legacy.at, NOW); noEnemyDetails(legacy);
  const expired = f.projection.intelView(g, g.getNode('field'), NOW + 40 * 60000);
  assert.equal(expired.precision, 'expired'); noEnemyDetails(expired);
  assert.equal(expired.at, march.arriveAt, 'fallback expiry must not renew the modern report');
});

test('all-city scout marches show own counts; current-city reports stay scoped, old global entries stay legacy', async () => {
  const f = await fixture(5), g = f.game, second = foundCity(g);
  const firstMarch = dispatch(g);
  g.switchCity(second); prepareCity(g, 0, 50); g.save();
  const secondMarch = dispatch(g, 'field', 10); g.switchCity('capital');
  g.tick(Math.max(firstMarch.arriveAt, secondMarch.arriveAt), false); g.save();
  const stateBefore = JSON.stringify(g.state), rows = f.projection.scoutMarchesView(g, g.state.last);
  assert.equal(rows.length, 2); assert.deepEqual(new Set(rows.map(row => row.sourceCity)), new Set(['capital', second]));
  assert.equal(rows.find(row => row.sourceCity === second).count, 9); assert.equal(rows.find(row => row.sourceCity === second).lost, 1);
  assert.equal(f.projection.scoutingView(g, g.state.last).intelByNode.field.precision, 'exact');
  const view = f.dto.gameView(g, g.state.last, f.runtime);
  assert.equal(JSON.stringify(g.state), stateBefore);
  for (const city of [...view.cityList, ...view.realmManagement.cities]) for (const row of city.scoutQueue) {
    assert.equal(row.enemySnapshot, undefined); assert.equal(row.outcome, undefined);
    assert.equal(row.recallCommand, undefined); assert.equal(row.selectCommand, undefined);
    assert.equal(row.battleCommand, undefined); assert.equal(row.canStartBattle, false);
  }
  assert.equal(JSON.stringify(view).includes('enemySnapshot'), false);
  g.switchCity(second); assert.equal(f.projection.scoutingView(g, g.state.last).intelByNode.field.precision, 'types');
  g.state.scouted.camp = {at: NOW, level: 5}; g.state.raided.camp = true;
  assert.equal(f.projection.scoutingView(g, g.state.last).intelByNode.camp.precision, 'legacy');
});

test('cross-city scout quotation leaves the selected city, resources, queues and intel untouched', async () => {
  const f = await fixture(), second = foundCity(f.game);
  f.game.switchCity(second); prepareCity(f.game, 3, 30); f.game.switchCity('capital'); f.game.save();
  const before = JSON.stringify(f.game.state), quote = f.quotes.managementQuote(f.runtime,
    {kind: 'scout', args: ['field', 1], sourceCity: second, requestId: 'scout_second_quote'});
  assert.equal(quote.sourceCity, second); assert.equal(quote.quote.precision, 'bands');
  assert.deepEqual(quote.quote.origin, {x: f.game.cityMeta(second).x, y: f.game.cityMeta(second).y});
  assert.equal(quote.quote.command.sourceCity, second); assert.equal(f.game.currentCityId(), 'capital');
  assert.equal(JSON.stringify(f.game.state), before);
});

test('shared presentation hides local reports and scouts and disables the local capability', async () => {
  const f = await fixture(), march = dispatch(f.game); f.game.tick(march.arriveAt, false); f.game.save();
  const publicNode = f.game.nodes.find(node => f.game.intel(node.id)?.public);
  f.game.state.raided[publicNode.id] = true; f.game.save();
  const before = JSON.stringify(f.game.state), view = f.dto.gameView(f.game, march.arriveAt, f.runtime, {shared: true});
  assert.deepEqual(view.scouting, {supported: false, available: 0, queueUsed: 0, queueLimit: 0, intelByNode: {}});
  assert.equal(view.marches.some(row => row.type === 'scout'), false);
  for (const city of [...view.cityList, ...view.realmManagement.cities]) assert.deepEqual(city.scoutQueue, []);
  assert.equal(view.nodes.find(row => row.id === 'field').intel.precision, 'unknown');
  assert.equal(view.nodes.find(row => row.id === publicNode.id).intel.precision, 'public');
  assert.equal(JSON.stringify(f.game.state), before);
});
