const {test} = require('node:test');
const assert = require('node:assert/strict');
const modules = Promise.all([import('../bridge/growth-support.mjs'), import('../vendor/legacy/online/runtime.mjs')]);
const NOW = 1800000000000;

async function fixture({copper = 1000, camp = true, coral = 0, snapshot, now = NOW} = {}) {
  const [support, canonical] = await modules;
  const runtime = canonical.createGameRuntime({now, snapshot, random: canonical.seededRandom(7)});
  const game = runtime.Game, state = game.state;
  if (snapshot === undefined) {
    if (camp) state.conquered.camp = true;
    state.copper = copper;
    state.jewels.coral = coral;
    game.save();
  }
  assert.equal(game.validSave(state), true, 'fixture must pass unchanged canonical save rules');
  let sequence = 0;
  const command = (args = ['growth_coral'], type = 'exchangeCopper') => ({commandId: `growth_support_${++sequence}`, expectedRevision: sequence - 1, type, args});
  return {support, canonical, runtime, game, state, command, now,
    quote: options => support.growthSupportQuote(runtime, options),
    execute: (input = command(), options) => support.executeGrowthSupport(runtime, input, now, options)};
}

test('old-save offer is read-only, save-wide and keeps the exact private command', async () => {
  const f = await fixture(), before = JSON.stringify(f.state);
  assert.equal(Object.hasOwn(f.state, 'growthSupport'), false);
  assert.deepEqual(f.quote(), {id: 'growth_coral', name: '县城筹备 · 珊瑚 ×1', cost: 80,
    claimed: 0, remaining: 5, limit: 5, period: 'save', reason: '',
    command: {type: 'exchangeCopper', args: ['growth_coral']}});
  assert.equal(JSON.stringify(f.state), before, 'quoting must not tick, initialize, or save');
  const modified = f.quote(); modified.command.args[0] = 'pearl'; modified.remaining = 999;
  assert.deepEqual(f.quote().command, {type: 'exchangeCopper', args: ['growth_coral']});
  assert.equal(f.quote().remaining, 5);
  assert.equal(JSON.stringify(f.state), before);
});

test('occupation of camp is the gate; raiding it or owning copper alone cannot unlock', async () => {
  const f = await fixture({camp: false, copper: 800});
  f.state.raided.camp = true; f.game.save();
  assert.match(f.quote().reason, /占领黄巾营寨/);
  const before = JSON.stringify(f.state);
  assert.throws(() => f.execute(), error => error.code === 'GAME_RULE' && /占领黄巾营寨/.test(error.message));
  assert.equal(f.state.copper, 800); assert.equal(f.state.jewels.coral, 0);
  assert.equal(Object.hasOwn(f.state, 'growthSupport'), false);
  assert.equal(JSON.stringify(f.state), before, 'failed same-time gate check cannot change a saved fixture');
  f.state.conquered.camp = true; f.game.save();
  assert.equal(f.state.buildings.inn, 0, 'no unrequested inn condition is added to this route');
  assert.equal(f.quote().reason, '');
});

test('80 copper purchases exactly one coral, records one claim and uses native tick/save', async () => {
  const f = await fixture({copper: 80, coral: 7});
  const tick = f.game.tick, calls = [];
  f.game.tick = (now, persist) => {calls.push({now, persist}); return tick(now, persist);};
  const executed = f.execute();
  assert.equal(executed.runtime, f.runtime);
  assert.equal(executed.state.copper, 0); assert.equal(executed.state.jewels.coral, 8);
  assert.deepEqual(executed.state.growthSupport, {version: 1, coralExchanged: 1});
  assert.deepEqual(executed.result, {id: 'growth_coral', jewel: 'coral', count: 1, copperSpent: 80, claimed: 1, remaining: 4});
  assert.deepEqual(calls, [{now: NOW, persist: true}]);
  assert.equal(f.game.validSave(executed.state), true);
  assert.equal(f.support.validGrowthSupport(executed.state), true);
  executed.state.growthSupport.coralExchanged = 0;
  assert.equal(f.state.growthSupport.coralExchanged, 1, 'returned snapshot must not alias the live counter');
});

test('insufficient copper and numeric overflow cannot grant or consume resources', async () => {
  const f = await fixture({copper: 79});
  assert.match(f.quote().reason, /铜钱不足/);
  assert.throws(() => f.execute(), error => error.code === 'GAME_RULE' && /铜钱不足/.test(error.message));
  assert.equal(f.state.copper, 79); assert.equal(f.state.jewels.coral, 0);
  assert.equal(Object.hasOwn(f.state, 'growthSupport'), false);
  const full = await fixture({coral: Number.MAX_SAFE_INTEGER});
  assert.match(full.quote().reason, /数值上限/);
  assert.throws(() => full.execute(), /数值上限/);
  assert.equal(full.state.copper, 1000); assert.equal(full.state.jewels.coral, Number.MAX_SAFE_INTEGER);
});

test('five exchanges exhaust the single save-wide cap regardless of current coral stock', async () => {
  const f = await fixture({copper: 800});
  for (let claimed = 1; claimed <= 5; claimed++) {
    const executed = f.execute();
    assert.equal(executed.state.copper, 800 - 80 * claimed);
    assert.equal(executed.state.growthSupport.coralExchanged, claimed);
    assert.equal(f.quote().remaining, 5 - claimed);
  }
  assert.equal(f.state.jewels.coral, 5);
  assert.match(f.quote().reason, /本存档.*限额已用完/);
  // Spending coral on the original honors system never restores this quota.
  f.state.jewels.coral = 0; f.game.save();
  assert.throws(() => f.execute(), /本存档.*限额已用完/);
  assert.equal(f.state.copper, 400); assert.equal(f.state.jewels.coral, 0);
  assert.equal(f.state.growthSupport.coralExchanged, 5);
});

test('native reload and daily resets preserve the lifetime cap without altering old saves', async () => {
  const f = await fixture();
  for (let i = 0; i < 5; i++) f.execute();
  const snapshot = f.canonical.copy(f.state), before = JSON.stringify(snapshot);
  const later = await fixture({snapshot, now: NOW + f.runtime.Progression.DAY * 3});
  assert.equal(JSON.stringify(snapshot), before, 'runtime migration must not mutate the supplied old snapshot');
  assert.deepEqual(later.state.growthSupport, {version: 1, coralExchanged: 5});
  assert.equal(later.quote().period, 'save'); assert.equal(later.quote().remaining, 0);
  assert.ok(later.state.daily.start > f.state.daily.start, 'the actual canonical daily board has advanced');
  assert.throws(() => later.execute(), /本存档.*限额已用完/);
  const old = await fixture({camp: true});
  const oldState = old.canonical.copy(old.state);
  const reloaded = await fixture({snapshot: oldState});
  assert.equal(Object.hasOwn(reloaded.state, 'growthSupport'), false);
  assert.equal(reloaded.quote().claimed, 0);
  assert.equal(old.support.validGrowthSupport(oldState), true);
});

test('counter and currency stay global across real canonical city switches', async () => {
  const f = await fixture({copper: 800}), node = f.game.getNode('fort');
  const data = f.canonical.copy(f.state.realm.cities.capital.data);
  data.governor = null; data.cityRoles = {commander: '', counsellor: ''};
  f.state.conquered.fort = true;
  f.state.realm.cities.city_fort = {id: 'city_fort', name: '测试县城', node: 'fort', x: node.x, y: node.y,
    capital: false, createdAt: NOW, data};
  f.game.save(); assert.equal(f.game.validSave(f.state), true);
  f.execute();
  assert.equal(f.game.switchCity('city_fort'), null);
  assert.equal(f.quote().claimed, 1); assert.equal(f.state.copper, 720);
  f.execute();
  assert.equal(f.game.switchCity('capital'), null);
  assert.equal(f.quote().claimed, 2); assert.equal(f.quote().remaining, 3);
  assert.equal(f.state.copper, 640); assert.equal(f.state.jewels.coral, 2);
  for (const city of Object.values(f.state.realm.cities)) {
    assert.equal(Object.hasOwn(city.data, 'growthSupport'), false, 'counter must never be copied into a city scope');
  }
  assert.equal(f.game.validSave(f.state), true);
});

test('canonical migration, later native commands and reloading preserve the extension', async () => {
  const f = await fixture(); f.execute(); f.execute();
  const snapshot = f.canonical.copy(f.state);
  const migrated = f.game.migrateSave(snapshot);
  assert.deepEqual(migrated.growthSupport, {version: 1, coralExchanged: 2});
  assert.equal(f.game.validSave(migrated), true);
  const executed = f.canonical.executeGame(snapshot, {commandId: 'native_tax_after_support', expectedRevision: 2,
    type: 'setTax', args: [25]}, NOW, f.canonical.seededRandom(8));
  assert.deepEqual(executed.state.growthSupport, {version: 1, coralExchanged: 2});
  const reloaded = await fixture({snapshot: executed.state});
  assert.equal(reloaded.state.tax, 25); assert.equal(reloaded.quote().claimed, 2);
});

test('original 40-copper pearl offer and five-coral public rank threshold remain unchanged', async () => {
  const f = await fixture();
  const nobleBefore = f.canonical.copy(f.runtime.HeritageSystem.promotionQuote(f.state, 'noble').rule);
  assert.equal(nobleBefore.jewels.coral, 5);
  assert.equal(f.runtime.Progression.exchangeOffers(f.state).find(row => row.id === 'pearl').cost, 40);
  f.execute();
  assert.deepEqual(f.runtime.HeritageSystem.promotionQuote(f.state, 'noble').rule, nobleBefore);
  f.state.cityLayout[0] = 'inn'; f.state.cityLevels[0] = 1; f.state.buildings.inn = 1;
  f.game.save();
  const oldCopper = f.state.copper, oldPearls = f.state.jewels.pearl;
  assert.equal(f.game.exchangeCopper('pearl'), null);
  assert.equal(f.state.copper, oldCopper - 40); assert.equal(f.state.jewels.pearl, oldPearls + 1);
  assert.equal(f.state.growthSupport.coralExchanged, 1);
});

test('shared quote and execution reject this route while the original shared executor lacks its id', async () => {
  const f = await fixture(), before = JSON.stringify(f.state);
  assert.match(f.quote({shared: true}).reason, /共享模式/);
  assert.equal(JSON.stringify(f.state), before);
  assert.throws(() => f.execute(f.command(), {shared: true}), error => error.code === 'COMMAND_NOT_ALLOWED' && /共享/.test(error.message));
  assert.equal(JSON.stringify(f.state), before);
  assert.throws(() => f.canonical.executeGame(f.state, f.command(), NOW, f.canonical.seededRandom(4)), error =>
    error.code === 'GAME_RULE' && /商品已刷新/.test(error.message));
  assert.equal(JSON.stringify(f.state), before, 'vanilla runtime receives a disposable copy');
});

test('only validated metadata, exact command type and one exact offer id can execute', async () => {
  const f = await fixture(), before = JSON.stringify(f.state);
  for (const input of [null, {}, {...f.command(), commandId: 'bad'}, {...f.command(), expectedRevision: -1},
    f.command([], 'exchangeCopper'), f.command(['growth_coral', 2]), f.command(['pearl']),
    f.command([null]), f.command([['growth_coral']]), f.command(['growth_coral'], 'hero.exchangeCopper')]) {
    assert.throws(() => f.execute(input), error => error instanceof f.canonical.GameError);
    assert.equal(JSON.stringify(f.state), before, 'malformed commands are rejected before native tick or mutation');
  }
  assert.throws(() => f.support.executeGrowthSupport(f.runtime, f.command(), NaN), error => error.code === 'BAD_TIME');
  assert.equal(JSON.stringify(f.state), before);
});

test('optional counter validation is exact and rejects corrupted records without repairing them', async () => {
  const f = await fixture();
  for (const count of [0, 1, 5]) assert.equal(f.support.validGrowthSupport({growthSupport: {version: 1, coralExchanged: count}}), true);
  assert.equal(f.support.validGrowthSupport({}), true);
  for (const record of [null, undefined, [], {}, {version: 1}, {coralExchanged: 0},
    {version: 2, coralExchanged: 0}, {version: '1', coralExchanged: 0},
    {version: 1, coralExchanged: -1}, {version: 1, coralExchanged: 6},
    {version: 1, coralExchanged: 0.5}, {version: 1, coralExchanged: '0'},
    {version: 1, coralExchanged: NaN}, {version: 1, coralExchanged: 0, daily: 0}]) {
    assert.equal(f.support.validGrowthSupport({growthSupport: record}), false);
    f.state.growthSupport = record;
    const copper = f.state.copper, coral = f.state.jewels.coral;
    assert.match(f.quote().reason, /记录无效/); assert.equal(f.quote().claimed, null); assert.equal(f.quote().remaining, 0);
    assert.throws(() => f.execute(), error => error.code === 'BAD_SAVE');
    assert.equal(f.state.copper, copper); assert.equal(f.state.jewels.coral, coral);
    assert.equal(f.state.growthSupport, record, 'malformed counter must not be replaced with a fresh quota');
  }
  for (const invalid of [null, undefined, [], false]) assert.equal(f.support.validGrowthSupport(invalid), false);
});
