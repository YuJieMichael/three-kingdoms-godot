const test = require('node:test');
const assert = require('node:assert/strict');
const {performance} = require('node:perf_hooks');

const NOW = 1800000000000;
const imports = Promise.all([
  import('../vendor/legacy/online/runtime.mjs'),
  import('../bridge/building-comparison.mjs'),
  import('../bridge/dto.mjs'),
  import('../bridge/shared-dto.mjs'),
  import('../bridge/shared-scenario.mjs'),
]);

async function fixture(rows = []) {
  const [canonical, projection, dto] = await imports;
  const runtime = canonical.createGameRuntime({now: NOW, random: canonical.seededRandom(1)}), game = runtime.Game;
  const state = game.state;
  state.cityLevels[14] = state.buildings.hall = 10;
  // Canonical prerequisites, including drill for barracks, are satisfied by
  // actual unique structures. No building requirement is stubbed or skipped.
  const prerequisites = game.cityIds.filter(id => !['house', 'barracks', 'hall'].includes(id));
  for (const [index, id] of prerequisites.entries()) {
    state.cityLayout[23 + index] = id;
    state.cityLevels[23 + index] = state.buildings[id] = 10;
  }
  for (const resource of Object.keys(state.res)) state.res[resource] = 1e9;
  for (const tech of Object.keys(state.tech)) state.tech[tech] = 10;
  for (const item of game.manual.shop) if (item.effect === 'blueprint') state.inventory[item.id] = 100;
  for (const [site, id, level] of rows) {
    state.cityLayout[site] = id;
    state.cityLevels[site] = level;
    state.buildings[id] = Math.max(state.buildings[id], level);
  }
  game.save();
  assert.equal(game.validSave(state), true, 'fixture remains an actual canonical save');
  return {canonical, projection, dto, runtime, game};
}

function capacity(game, id) { return id === 'house' ? game.maxPop() : game.trainingLimit(); }

function assertCompletesExactly(f, quote) {
  const clone = f.canonical.createGameRuntime({snapshot: f.game.state, now: NOW, random: f.canonical.seededRandom(1)});
  const game = clone.Game, before = capacity(game, quote.id), resources = {...game.state.res};
  assert.equal(game.queueBuilding(quote.site, quote.id), null);
  const job = game.state.buildQueue.find(row => row.site === quote.site);
  assert.deepEqual(job.paid, quote.cost);
  assert.equal(job.level, quote.targetLevel);
  assert.ok(Math.abs((job.end - job.start) / 1000 - quote.time) < 0.001);
  assert.equal(capacity(game, quote.id), before, 'enqueue never grants completed capacity');
  for (const [id, price] of Object.entries(quote.cost)) assert.equal(resources[id] - game.state.res[id], price);
  game.tick(job.end + 1, false);
  assert.equal(game.state.cityLevels[quote.site], quote.targetLevel);
  assert.equal(capacity(game, quote.id) - before, quote.effectDelta);
  assert.equal(capacity(game, quote.id), quote.capacityAfter);
}

test('new house and barracks quote canonical fees, time, and actual completed capacity', async () => {
  const f = await fixture(), before = JSON.stringify(f.game.state);
  const view = f.projection.buildingComparisons(f.game);
  assert.deepEqual(Object.keys(view), ['house', 'barracks']);
  for (const id of ['house', 'barracks']) {
    const row = view[id];
    assert.equal(row.cityId, f.game.currentCityId());
    assert.equal(row.count, 0); assert.equal(row.pendingCount, 0);
    assert.equal(row.currentCapacity, capacity(f.game, id));
    assert.equal(row.new.site, 0); assert.equal(row.new.targetLevel, 1);
    assert.equal(row.new.available, true); assert.equal(row.new.requirement, '');
    assert.equal(row.new.affordable, true); assert.equal(row.new.time, row.new.seconds);
    assertCompletesExactly(f, row.new);
  }
  assert.match(view.barracks.notice, /依次开始.*不代表并行/);
  assert.match(view.house.notice, /不代表人口立即补满/);
  assert.equal(JSON.stringify(f.game.state), before, 'comparison and completion probes leave the live fixture untouched');
});

test('all canonical tiers and mixed duplicate levels match actual upgrades rather than max-level summaries', async () => {
  const f = await fixture([[0, 'house', 1], [3, 'house', 4], [7, 'house', 9], [1, 'barracks', 2], [4, 'barracks', 6]]);
  const compared = f.projection.buildingComparisons(f.game);
  assert.equal(compared.house.count, 3); assert.equal(compared.barracks.count, 2);
  assert.equal(compared.house.currentCapacity, f.game.maxPop());
  assert.equal(compared.barracks.currentCapacity, f.game.trainingLimit());
  assert.deepEqual(compared.house.upgrades.map(row => [row.site, row.level]), [[0, 1], [3, 4], [7, 9]]);
  for (const id of ['house', 'barracks']) for (const quote of compared[id].upgrades) assertCompletesExactly(f, quote);
  for (const id of ['house', 'barracks']) for (let level = 1; level <= 10; level++) {
    const tier = await fixture([[0, id, level]]), row = tier.projection.buildingComparisons(tier.game)[id];
    if (id === 'barracks') assert.equal(tier.game.buildRecord(id, level).limit, level,
      'canonical table contribution is equivalent to trainingLimit with no extra base, cap or bonus');
    assert.equal(row.currentCapacity, capacity(tier.game, id));
    assertCompletesExactly(tier, row.new);
    if (level < 10) assertCompletesExactly(tier, row.upgrades[0]);
    else {
      const max = row.upgrades[0];
      assert.equal(max.available, false); assert.equal(max.targetLevel, null);
      assert.equal(max.effectDelta, null); assert.equal(max.capacityAfter, null);
      assert.equal(max.time, 0); assert.deepEqual(max.cost, {});
      assert.equal(max.reason, '已达最高等级');
    }
  }
});

test('pending foundations and active upgrades never offer duplicate upgrade projections or inflate capacity', async () => {
  const f = await fixture([[0, 'house', 2], [1, 'barracks', 1]]);
  assert.equal(f.game.queueBuilding(0, 'house'), null);
  assert.equal(f.game.queueBuilding(2, 'barracks'), null);
  const before = JSON.stringify(f.game.state), view = f.projection.buildingComparisons(f.game);
  assert.equal(view.house.currentCapacity, f.game.maxPop());
  assert.equal(view.barracks.currentCapacity, 1);
  assert.equal(view.barracks.count, 1); assert.equal(view.barracks.pendingCount, 1);
  assert.deepEqual(view.barracks.upgrades.map(row => row.site), [1], 'level-zero construction is not an upgrade candidate');
  const upgrade = view.house.upgrades[0];
  assert.equal(upgrade.reason, '正在施工'); assert.equal(upgrade.available, false);
  assert.equal(upgrade.effectDelta, null); assert.equal(upgrade.capacityAfter, null);
  assert.deepEqual(upgrade.queue, f.game.state.buildQueue[0]);
  assert.equal(view.house.new.reason, '建造队正在忙碌');
  assert.equal(view.barracks.upgrades[0].available, false);
  view.house.upgrades[0].queue.end = 0;
  assert.equal(JSON.stringify(f.game.state), before, 'returned queue objects are independent copies');
});

test('full city, reserved plots, canonical prerequisites, unique restriction and current affordability remain explicit', async () => {
  const f = await fixture([[0, 'house', 2], [1, 'barracks', 3]]);
  f.game.state.cityLayout[2] = 'house'; f.game.state.cityLevels[2] = 1;
  const next = f.projection.buildingComparisons(f.game);
  assert.equal(next.house.new.site, 3, 'new chooses the smallest actual null site and never a reserved slot');
  for (const resource of Object.keys(f.game.state.res)) f.game.state.res[resource] = 0;
  const poor = f.projection.buildingComparisons(f.game);
  for (const id of ['house', 'barracks']) {
    assert.equal(poor[id].new.affordable, false); assert.equal(poor[id].new.available, false);
    assert.equal(poor[id].new.reason, '建设资源不足');
    assert.equal(poor[id].upgrades[0].affordable, false);
  }
  const denied = f.canonical.createGameRuntime({now: NOW}).Game;
  const missing = f.projection.buildingComparisons(denied).barracks.new;
  assert.equal(missing.requirement, denied.buildingRequirements('barracks', 1));
  assert.ok(missing.requirement); assert.equal(missing.available, false);
  f.game.buildings.house.repeat = false;
  assert.equal(f.projection.buildingComparisons(f.game).house.new.reason, '该建筑在本城只能建一座');
  f.game.buildings.house.repeat = true;
  for (let site = 0; site < 36; site++) if (f.game.state.cityLayout[site] === null) {
    f.game.state.cityLayout[site] = 'house'; f.game.state.cityLevels[site] = 1;
  }
  const full = f.projection.buildingComparisons(f.game);
  assert.equal(full.house.new, null); assert.equal(full.barracks.new, null);
  assert.ok(full.house.upgrades.every(row => ![14, 15, 20, 21].includes(row.site)));
});

test('DTO reads preserve live time, resources, reports and queues, and nested returned quotations cannot mutate state', async () => {
  const f = await fixture([[0, 'house', 4], [1, 'barracks', 3]]), before = JSON.stringify(f.game.state);
  const direct = f.projection.buildingComparisons(f.game);
  const view = f.dto.gameView(f.game, NOW, f.runtime);
  assert.deepEqual(view.buildingComparisons, direct);
  view.buildingComparisons.house.new.cost.food = -1;
  view.buildingComparisons.barracks.upgrades[0].cost.wood = -1;
  const reread = f.projection.buildingComparisons(f.game);
  assert.ok(reread.house.new.cost.food > 0); assert.ok(reread.barracks.upgrades[0].cost.wood > 0);
  assert.equal(JSON.stringify(f.game.state), before);
});

test('shared projections expose only the actor current city and public enemy nodes never contain comparison data', async () => {
  const [canonical, projection, , sharedDto, scenario] = await imports;
  const context = {...await scenario.createRehearsal(NOW), serverTime: NOW};
  const actor = context.players[0], enemy = context.players[1];
  const enemyRuntime = canonical.createGameRuntime({snapshot: enemy.state, now: NOW});
  const enemySite = enemyRuntime.Game.state.cityLayout.indexOf('house');
  enemyRuntime.Game.state.cityLevels[enemySite] = enemyRuntime.Game.state.buildings.house = 10;
  enemyRuntime.Game.save();
  enemy.state = canonical.copy(enemyRuntime.Game.state);
  const runtime = canonical.createGameRuntime({snapshot: actor.state, now: NOW}), game = runtime.Game;
  const view = sharedDto.sharedEnvelope(context, actor.id, 'qa-authority', {id: actor.id, name: actor.name});
  assert.deepEqual(view.view.buildingComparisons, projection.buildingComparisons(game));
  assert.notEqual(view.view.buildingComparisons.house.currentCapacity, enemyRuntime.Game.maxPop(),
    'actor and enemy have deliberately distinct capacities, so actor projection cannot accidentally use the enemy');
  const before = JSON.stringify(context);
  const publicNode = sharedDto.sharedNodeView(context, actor.id, sharedDto.playerNodeId(enemy.id), 'qa-authority', {id: actor.id});
  assert.equal(Object.hasOwn(publicNode.node, 'buildingComparisons'), false);
  assert.equal(JSON.stringify(context), before);
  assert.notEqual(view.view.buildingComparisons.house.cityId, enemy.id);
});

test('switching the owned current city replaces every candidate identity and uses only its actual capacities', async () => {
  const f = await fixture([[0, 'house', 3], [1, 'barracks', 2]]);
  const plain = Array.from({length: 4096}, (_, i) => f.game.getWorldTile(i % 64, Math.floor(i / 64)))
    .find(node => node.wild && node.type === 'plain');
  f.game.state.honors.noble = 10;
  f.game.state.conquered[plain.id] = true;
  f.game.state.landClaims[plain.id] = {at: NOW, level: plain.level};
  f.game.state.realm.wildOwners[plain.id] = 'capital';
  const quote = f.game.foundCityQuote(plain.id, '对照副城');
  assert.equal(quote.reason, '');
  assert.equal(f.game.foundCity(plain.id, quote.name, quote.key), null);
  f.game.save();
  assert.equal(f.game.validSave(f.game.state), true);
  const capital = f.projection.buildingComparisons(f.game);
  const secondId = 'city_' + plain.id;
  assert.equal(f.game.switchCity(secondId), null);
  for (const [site, id, level] of [[0, 'house', 7], [1, 'barracks', 8]]) {
    f.game.state.cityLayout[site] = id;
    f.game.state.cityLevels[site] = f.game.state.buildings[id] = level;
  }
  f.game.save();
  assert.equal(f.game.validSave(f.game.state), true);
  const before = JSON.stringify(f.game.state), second = f.projection.buildingComparisons(f.game);
  assert.equal(second.house.cityId, secondId); assert.equal(second.barracks.cityId, secondId);
  assert.equal(second.house.currentCapacity, f.game.maxPop());
  assert.equal(second.barracks.currentCapacity, f.game.trainingLimit());
  assert.notEqual(second.house.currentCapacity, capital.house.currentCapacity);
  assert.notEqual(second.barracks.currentCapacity, capital.barracks.currentCapacity);
  assert.equal(second.house.upgrades[0].level, 7); assert.equal(second.barracks.upgrades[0].level, 8);
  assert.equal(JSON.stringify(f.game.state), before, 'reading never switches city or updates time');
  assert.equal(f.game.switchCity('capital'), null);
  assert.deepEqual(f.projection.buildingComparisons(f.game), capital);
});

test('high-frequency dense-city comparisons are bounded and do not allocate per-candidate runtimes', async t => {
  const rows = Array.from({length: 14}, (_, site) => [site, site % 2 ? 'barracks' : 'house', 1 + site % 9]);
  const f = await fixture(rows), before = JSON.stringify(f.game.state);
  const read = () => f.projection.buildingComparisons(f.game);
  for (let i = 0; i < 100; i++) read();
  global.gc?.();
  const memoryBefore = process.memoryUsage().heapUsed, start = performance.now();
  for (let i = 0; i < 1000; i++) read();
  const elapsed = performance.now() - start;
  global.gc?.();
  const heapDelta = process.memoryUsage().heapUsed - memoryBefore;
  t.diagnostic(`1000 comparisons: ${elapsed.toFixed(2)} ms (${(elapsed / 1000).toFixed(3)} ms/read), retained heap delta ${heapDelta} bytes, gc=${!!global.gc}`);
  assert.equal(JSON.stringify(f.game.state), before);
  assert.ok(elapsed < 5000, 'capacity projection stays bounded independently of expensive game-runtime construction');
  if (global.gc) assert.ok(heapDelta < 8 * 1024 * 1024, 'polling does not retain a runtime/cache per view');
  f.dto.gameView(f.game, NOW, f.runtime);
  global.gc?.();
  const viewHeapBefore = process.memoryUsage().heapUsed, viewStart = performance.now();
  for (let i = 0; i < 20; i++) f.dto.gameView(f.game, NOW, f.runtime);
  const viewElapsed = performance.now() - viewStart;
  global.gc?.();
  const viewHeapDelta = process.memoryUsage().heapUsed - viewHeapBefore;
  t.diagnostic(`20 integrated gameViews: ${viewElapsed.toFixed(2)} ms (${(viewElapsed / 20).toFixed(3)} ms/read), retained heap delta ${viewHeapDelta} bytes, gc=${!!global.gc}`);
  assert.equal(JSON.stringify(f.game.state), before, 'repeated integrated DTO reads do not alter live state');
  if (global.gc) assert.ok(viewHeapDelta < 8 * 1024 * 1024, 'integrated polling does not retain capacity predictions');
});
