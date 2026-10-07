const {test} = require('node:test');
const assert = require('node:assert/strict');
const modules = Promise.all([import('../bridge/report-economy.mjs'), import('../vendor/legacy/online/runtime.mjs'), import('../bridge/dto.mjs')]);
const NOW = 1800000000000;
async function fixture() {
  const [projection, canonical, dto] = await modules;
  const runtime = canonical.createGameRuntime({now: NOW});
  return {projection, canonical, dto, runtime, game: runtime.Game};
}
const privateReport = () => ({sourceCity: 'capital', lost: {archer: 3}, wounded: {archer: 2},
  woundedInHospital: true, loot: {food: 500, wood: 40}, bonusLoot: {wood: 7},
  resourceReceipt: {base: {received: {food: 400, wood: 20}}, bonus: {received: {wood: 7}}}});

test('private report uses actual receipts and native recovery quotes without changing state or report', async () => {
  const f = await fixture(), report = privateReport(), stateBefore = JSON.stringify(f.game.state), reportBefore = JSON.stringify(report);
  const result = f.projection.reportEconomy(f.runtime, report);
  assert.equal(result.status, 'delivered');
  assert.deepEqual(result.loot, {food: 500, wood: 47});
  assert.deepEqual(result.received, {food: 400, wood: 27});
  assert.deepEqual(result.replacement.resources, f.game.trainCost('archer', 3));
  assert.equal(result.replacement.people, f.game.units.archer.people * 3);
  assert.equal(result.replacement.soldiers, 3);
  assert.equal(result.treatment.resources.gold, f.runtime.WarCare.price('archer', f.game.units) * 2);
  for (const id of Object.keys(f.game.resources)) assert.equal(result.net.resources[id],
    (result.received[id] || 0) - (result.replacement.resources[id] || 0) - (result.treatment.resources[id] || 0));
  assert.equal(result.net.kind, 'projected');
  assert.ok(result.notes.some(note => note.includes('尚未扣款')));
  assert.equal(JSON.stringify(f.game.state), stateBefore);
  assert.equal(JSON.stringify(report), reportBefore);
  result.permanentLoss.archer = 9; result.replacement.resources.wood = 999;
  assert.equal(JSON.stringify(report), reportBefore);
  assert.equal(JSON.stringify(f.game.state), stateBefore);
});

test('shared attacker cannot treat returning loot as a delivery proof', async () => {
  const f = await fixture(), report = {...privateReport(), shared: true, source: 'actor-a', target: 'actor-b', status: 'return', lootDelivered: false};
  let result = f.projection.reportEconomy(f.runtime, report, {shared: true, actor: 'actor-a'});
  assert.equal(result.status, 'pending'); assert.equal(result.received, null);
  assert.equal(result.net.resources.food, report.loot.food - f.game.trainCost('archer', 3).food);
  result = f.projection.reportEconomy(f.runtime, {...report, status: 'done', lootDelivered: true, receivedResources: {food: 500, wood: 40}}, {shared: true, actor: 'actor-a'});
  assert.equal(result.status, 'delivered'); assert.deepEqual(result.received, {food: 500, wood: 40});
  // Even a delivered boolean without the transaction projection is insufficient.
  result = f.projection.reportEconomy(f.runtime, {...report, status: 'done', lootDelivered: true}, {shared: true, actor: 'actor-a'});
  assert.equal(result.status, 'unknown'); assert.equal(result.net.resources, null);
});

test('stationed cargo and corrupt receipts never claim a completed return or confirmed zero', async () => {
  const f = await fixture(), report = {...privateReport(), shared: true, source: 'actor-a', status: 'stationed', lootDelivered: false};
  const retained = f.projection.reportEconomy(f.runtime, report, {shared: true, actor: 'actor-a'});
  assert.equal(retained.status, 'retained'); assert.equal(retained.received, null);
  for (const invalid of ['bad', -1, NaN, Infinity, null]) {
    const privateResult = f.projection.reportEconomy(f.runtime, {...privateReport(), resourceReceipt: {base: {received: {food: invalid}}, bonus: {received: {}}}});
    assert.equal(privateResult.status, 'unknown'); assert.equal(privateResult.received, null);
    const sharedResult = f.projection.reportEconomy(f.runtime, {...report, status: 'done', lootDelivered: true, receivedResources: {food: invalid}}, {shared: true, actor: 'actor-a'});
    assert.equal(sharedResult.status, 'unknown'); assert.equal(sharedResult.net.resources, null);
  }
});

test('shared defender counts lost supplies and coalition recovery without mislabeling individual costs', async () => {
  const f = await fixture(), report = {...privateReport(), shared: true, source: 'actor-a', target: 'actor-b',
    defenderLost: {militia: 5}, defenderWounded: {militia: 2}, loot: {food: 1200}, targetCity: 'capital'};
  const result = f.projection.reportEconomy(f.runtime, report, {shared: true, actor: 'actor-b'});
  assert.equal(result.scope, 'defenders-total'); assert.equal(result.status, 'lost');
  assert.deepEqual(result.received, {}); assert.deepEqual(result.permanentLoss, {militia: 5});
  assert.deepEqual(result.replacement.resources, f.game.trainCost('militia', 5));
  assert.equal(result.net.resources.food, -1200 - f.game.trainCost('militia', 5).food);
  assert.equal(result.treatment.available, false);
  assert.ok(result.notes.some(note => note.includes('不能分摊到本人')));
});

test('historical receipts and already treated wounds remain estimates rather than an invented paid ledger', async () => {
  const f = await fixture(), report = privateReport();
  assert.equal(f.runtime.WarCare.admit(f.game.state, `field:capital:${NOW}:fixture`, {archer: 2}, NOW, f.game.units), null);
  const before = f.projection.reportEconomy(f.runtime, report);
  assert.equal(before.treatment.currentPool.people, 2);
  assert.equal(f.runtime.WarCare.heal(f.game.state, 'archer', 2, undefined, f.game.units).healed, 2);
  const after = f.projection.reportEconomy(f.runtime, report);
  assert.deepEqual(after.treatment.resources, before.treatment.resources);
  assert.equal(after.treatment.currentPool.people, 0); assert.equal(after.treatment.available, false);
  assert.deepEqual(after.net, before.net);
  assert.ok(after.notes.some(note => note.includes('不能判定本战已治疗人数')));
  const old = f.projection.reportEconomy(f.runtime, {...report, resourceReceipt: undefined, woundedInHospital: undefined});
  assert.equal(old.status, 'unknown'); assert.equal(old.received, null); assert.equal(old.net.resources, null);
  assert.deepEqual(old.treatment.resources, {});
});

test('source-city wound pool, zero delivery and unsupported soldiers remain explicit', async () => {
  const f = await fixture(), report = privateReport(), copy = f.canonical.copy;
  const data = copy(f.game.state.realm.cities.capital.data);
  data.warCare = copy(f.game.state.warCare); data.res = copy(f.game.state.res); data.army = copy(f.game.state.army);
  f.runtime.WarCare.admit(data, `field:second:${NOW}:fixture`, {militia: 4}, NOW, f.game.units);
  f.game.state.realm.cities.second = {id: 'second', name: '第二城', data};
  const result = f.projection.reportEconomy(f.runtime, {...report, sourceCity: 'second'});
  assert.equal(result.cityId, 'second'); assert.equal(result.treatment.currentPool.people, 4);
  assert.equal(f.game.currentCityId(), 'capital');
  const zero = f.projection.reportEconomy(f.runtime, {...report, resourceReceipt: {base: {received: {}}, bonus: {received: {}}}});
  assert.equal(zero.status, 'delivered'); assert.deepEqual(zero.received, {});
  const invalid = f.projection.reportEconomy(f.runtime, {...report, lost: {unknown_unit: 2}});
  assert.equal(invalid.net.resources, null);
  assert.ok(invalid.notes.some(note => note.includes('预算不完整')));
});

test('game DTO enriches copies only and leaves canonical report/save shape unchanged', async () => {
  const f = await fixture(), report = privateReport();
  f.game.state.reports = [report];
  const before = JSON.stringify(f.game.state);
  const view = f.dto.gameView(f.game, NOW, f.runtime);
  assert.equal(view.reports[0].economy.status, 'delivered');
  assert.equal(JSON.stringify(f.game.state), before);
  assert.equal(f.game.state.reports[0].economy, undefined);
});
