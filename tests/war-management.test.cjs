const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const modules = Promise.all([import('../bridge/war-view.mjs'), import('../vendor/legacy/online/runtime.mjs'), import('../bridge/server.mjs')]);
const NOW = 1800000000000;

async function prepared() {
  const [views, runtime] = await modules, r = runtime.createGameRuntime({now: NOW}), g = r.Game, s = g.state;
  const buildings = ['drill', 'tavern', 'inn', 'barracks', 'market', 'academy', 'house', 'wall', 'warehouse', 'beacon'];
  for (const [site, id] of buildings.entries()) {s.cityLayout[site] = id; s.cityLevels[site] = 5; s.buildings[id] = 5;}
  const hall = s.cityLayout.indexOf('hall'); s.cityLevels[hall] = 5; s.buildings.hall = 5;
  s.res = {food: 300000, wood: 180000, stone: 180000, iron: 180000, gold: 80000};
  s.population = 1000; s.army.archer = 500; s.army.cavalry = 300;
  s.stats.victories = 1; s.tech.manufacture = 5; s.tech.shooting = 5;
  s.captives.militia = 12; s.captives.archer = 8;
  assert.equal(r.WarCare.admit(s, `field:capital:${NOW}:fixture`, {militia: 20, archer: 10}, NOW, g.units), null);
  s.heroService.owed.lin = 100; s.heroService.owed.su = 60;
  s.warCare.defense.autoResolve = false;
  g.save(); assert.equal(g.validSave(s), true);
  return {views, runtime, r, g, s};
}

function execute(f, command, now = NOW, snapshot = f.s) {
  return f.runtime.executeGame(snapshot, {commandId: 'war_fixture_0001', expectedRevision: 0, ...command}, now, f.runtime.seededRandom(7));
}

test('war projections preserve original quotes and never mutate the canonical save', async () => {
  const f = await prepared(), before = JSON.stringify(f.s), view = f.views.warView(f.r, {now: NOW});
  assert.equal(JSON.stringify(f.s), before);
  assert.deepEqual(view.hospital.quote.selected, f.g.warCareQuote('all').selected);
  assert.equal(view.hospital.quote.gold, f.g.warCareQuote('all').gold);
  assert.equal(view.hospital.quote.key, f.g.warCareQuote('all').key);
  assert.deepEqual(view.captives.quote.cost, f.g.captiveRecruitAllQuote().cost);
  assert.equal(view.captives.quote.key, f.g.captiveRecruitAllQuote().key);
  assert.equal(view.wages.quote.key, f.g.salaryQuote('all').key);
  assert.equal(view.wages.quote.cost, 160);
  assert.deepEqual(view.civic.rows.find(r => r.id === 'sacrifice').cost, f.g.civicOrderPreview('sacrifice').cost);
  for (const row of view.defenses.rows) {
    assert.deepEqual(row.unitCost, f.g.manual.defenses[row.id].cost);
    assert.deepEqual(row.requirements, f.g.manual.defenses[row.id].requires);
    assert.equal(row.requirement, f.g.defenseRequirements(row.id, 1));
  }
  view.hospital.quote.selected.archer = 0;
  view.defense.doctrine.orders.archer.command = 'fallback';
  assert.equal(JSON.stringify(f.s), before, 'returned DTOs cannot mutate native state');
});

test('whole-class, affordable-class and all healing use native keys and ledger costs', async () => {
  const f = await prepared(), v = f.views.warView(f.r), row = v.hospital.rows.find(r => r.id === 'archer');
  const healed = execute(f, row.choices[0].command), gold = f.s.res.gold;
  assert.equal(healed.state.army.archer, f.s.army.archer + 10);
  assert.equal(healed.state.warCare.wounded.archer, 0);
  assert.equal(healed.state.res.gold, gold - row.choices[0].gold);
  assert.equal(healed.state.warCare.treated.archer, 10);
  assert.throws(() => execute(f, row.choices[0].command, NOW, healed.state), /治疗预览已变化/);
  const all = execute(f, v.hospital.quote.command);
  assert.equal(all.state.warCare.wounded.militia, 0);
  assert.equal(all.state.warCare.wounded.archer, 0);
  assert.equal(all.state.res.gold, gold - v.hospital.quote.gold);
  f.s.res.gold = 100; f.g.save();
  const affordable = f.views.warView(f.r).hospital.rows.find(r => r.id === 'archer').choices[1];
  assert.equal(affordable.count, f.g.warCareQuote('all').rows.find(r => r.id === 'archer').affordable);
  const partial = execute(f, affordable.command);
  assert.equal(partial.state.warCare.wounded.archer, 10 - affordable.count);
  assert.equal(partial.state.res.gold, 100 - affordable.gold);
});

test('automatic treatment uses native affordable order without free soldiers', async () => {
  const f = await prepared(); f.s.res.gold = 100; f.g.save();
  const result = execute(f, {type: 'setAutoHeal', args: [true]});
  assert.equal(result.state.warCare.autoHeal, true);
  assert.ok(result.state.warCare.lastAuto.healed > 0);
  assert.equal(result.state.res.gold, 100 - result.state.warCare.lastAuto.gold);
  assert.equal(Object.values(result.state.warCare.wounded).reduce((a, b) => a + b), 30 - result.state.warCare.lastAuto.healed);
  assert.equal(result.runtime.Game.validSave(result.state), true);
});

test('single and one-click soldier recruitment pay native prices, population and stale plan protection', async () => {
  const f = await prepared(), v = f.views.warView(f.r), row = v.captives.rows.find(r => r.id === 'archer');
  assert.ok(row.choices[0].count > 0); assert.equal(row.choices[0].reason, '');
  const single = execute(f, row.choices[0].command);
  assert.equal(single.state.army.archer, f.s.army.archer + 8);
  assert.equal(single.state.captives.archer, 0);
  for (const [id, cost] of Object.entries(row.choices[0].cost)) assert.equal(single.state.res[id], f.s.res[id] - cost);
  assert.equal(single.state.population, f.s.population - row.choices[0].people);
  assert.throws(() => execute(f, v.captives.quote.command, NOW, single.state), /招降计划已变化/);
  const all = execute(f, v.captives.quote.command);
  assert.equal(Object.values(all.state.army).reduce((a, b) => a + b) - Object.values(f.s.army).reduce((a, b) => a + b), v.captives.quote.count);
  assert.equal(all.state.population, f.s.population - v.captives.quote.people);
  assert.equal(all.state.res.gold, f.s.res.gold - v.captives.quote.cost.gold);
});

test('fortification queue reserves canonical area and charges exactly manual unit cost', async () => {
  const f = await prepared(), v = f.views.warView(f.r), row = v.defenses.rows.find(r => r.id === 'tower');
  assert.equal(row.requirement, '');
  const built = execute(f, {type: 'buildDefense', args: ['tower', 4]});
  assert.equal(built.state.defenseQueue[0].count, 4);
  for (const [id, cost] of Object.entries(row.unitCost)) assert.equal(built.state.res[id], f.s.res[id] - cost * 4);
  const queued = f.views.warView(built.runtime);
  assert.equal(queued.defenses.used, v.defenses.used + row.area * 4);
  assert.throws(() => execute(f, {type: 'buildDefense', args: ['tower', 1]}, NOW, built.state), /工队正在忙碌/);
  f.s.defenses.trap = f.g.defenseCapacity(); f.g.save();
  assert.throws(() => execute(f, {type: 'buildDefense', args: ['tower', 1]}), /城防空间不足/);
  const after = execute(f, {type: 'setTax', args: [20]}, Math.ceil(built.state.defenseQueue[0].end) + 1, built.state);
  assert.equal(after.state.defenses.tower, 4); assert.equal(after.state.defenseQueue.length, 0);
});

test('yellow-turban warning obeys beacon visibility, arrival and canonical defensive rounds', async () => {
  const f = await prepared(), quote = f.views.warView(f.r).defense.profiles.find(p => p.id === 'classic').quotes[0];
  const requested = execute(f, quote.command), arrival = requested.state.cityDefense.incoming.arriveAt;
  assert.equal(arrival, NOW + quote.warningSeconds * 1000);
  assert.throws(() => execute(f, {type: 'startCityDefense', args: [false, 'lin', {archer: 100}]}, NOW, requested.state), /敌军尚未抵达/);
  const beacon = f.runtime.createGameRuntime({snapshot: requested.state, now: NOW});
  beacon.Game.state.buildings.beacon = 0;
  const intel = f.views.warView(beacon).defense.incoming;
  assert.equal(intel.army, null); assert.deepEqual(intel.types, []);
  const start = execute(f, {type: 'startCityDefense', args: [false, 'lin', {archer: 100}]}, arrival, requested.state);
  assert.equal(start.state.cityDefense.battle.drill, false);
  assert.equal(start.state.army.archer, f.s.army.archer - 100);
  const round = execute(f, {type: 'cityDefenseRound', args: []}, arrival, start.state);
  assert.equal(round.state.cityDefense.battle.round, 1);
  const resolved = execute(f, {type: 'resolveCityDefense', args: []}, arrival, round.state);
  assert.equal(resolved.state.cityDefense.battle, null);
  assert.equal(resolved.state.cityDefense.reports.length, 1);
  assert.equal(resolved.runtime.Game.validSave(resolved.state), true);
});

test('drill exit and auto-resolve preserve physical army, resources and injured ledger', async () => {
  const f = await prepared();
  const doctrine = JSON.parse(JSON.stringify(f.s.warCare.defense));
  for (const order of Object.values(doctrine.orders)) order.command = 'advance';
  doctrine.orders.archer.target = 'militia';
  const set = execute(f, {type: 'setDefenseDoctrine', args: [doctrine]});
  assert.deepEqual(set.state.warCare.defense, doctrine);
  const start = execute(f, {type: 'startCityDefense', args: [true, 'lin', {archer: 100}]}, NOW, set.state);
  assert.deepEqual(start.state.cityDefense.battle.doctrine, doctrine);
  assert.throws(() => execute(f, {type: 'setDefenseDoctrine', args: [doctrine]}, NOW, start.state), /已冻结战术/);
  assert.equal(start.state.cityDefense.battle.drill, true);
  assert.deepEqual(start.state.army, f.s.army); assert.deepEqual(start.state.res, f.s.res);
  const exit = execute(f, {type: 'endDefenseDrill', args: []}, NOW, start.state);
  assert.equal(exit.state.cityDefense.battle, null);
  f.s.warCare.defense.autoResolve = true; f.g.save();
  const resolved = execute(f, {type: 'startCityDefense', args: [true, 'lin', {archer: 100}]});
  assert.equal(resolved.state.cityDefense.battle, null);
  assert.equal(resolved.state.cityDefense.drillResult.drill, true);
  assert.deepEqual(resolved.state.army, f.s.army);
  assert.deepEqual(resolved.state.res, f.s.res);
  assert.deepEqual(resolved.state.warCare, f.s.warCare);
});

test('civic orders, sacrifice and arrears pay canonical quotes and policies are saved', async () => {
  const f = await prepared(), v = f.views.warView(f.r), relief = v.civic.rows.find(r => r.id === 'relief');
  const result = execute(f, relief.command);
  assert.equal(result.state.res.food, f.s.res.food - relief.cost.food);
  assert.equal(result.state.morale, f.s.morale + relief.effects.morale);
  assert.throws(() => execute(f, relief.command, NOW, result.state), /安抚冷却中/);
  const sacrifice = v.civic.rows.find(r => r.id === 'sacrifice'), protectedCity = execute(f, sacrifice.command);
  assert.equal(protectedCity.state.res.gold, f.s.res.gold - sacrifice.cost.gold);
  assert.ok(protectedCity.state.governance.wardUntil > NOW);
  const paid = execute(f, v.wages.quote.command);
  assert.equal(paid.state.res.gold, f.s.res.gold - v.wages.quote.cost);
  assert.deepEqual(paid.state.heroService.owed, {});
  assert.throws(() => execute(f, v.wages.quote.command, NOW, paid.state), /欠饷已变化/);
  const policy = execute(f, {type: 'setGovernancePolicy', args: ['autoRelief', true]});
  assert.equal(policy.state.governance.autoRelief, true);
});

test('shared projection restricts private NPC events while retaining own replenishment and civic quotes', async () => {
  const f = await prepared(), view = f.views.warView(f.r, {shared: true});
  assert.equal(view.defense.restricted, true); assert.match(view.defense.reason, /共享房间/);
  assert.equal(view.hospital.quote.reason, ''); assert.equal(view.captives.quote.reason, '');
  assert.equal(view.wages.quote.reason, '');
});

test('hospital command CAS receipt and paid ledger survive local bridge restart exactly once', async t => {
  const f = await prepared(), [, , server] = await modules;
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'kingdom-war-fixture-'));
  const config = {dataDir: path.join(directory, 'save'), port: 0, token: 'war-fixture-private-token', clock: () => NOW};
  let bridge = await server.startBridge(config);
  const request = async (route, body) => {
    const response = await fetch(`http://127.0.0.1:${bridge.port}${route}`, {method: body ? 'POST' : 'GET',
      headers: {Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json'}, ...(body ? {body: JSON.stringify(body)} : {})});
    return {status: response.status, body: await response.json()};
  };
  t.after(async () => {await bridge.close(); await fs.rm(directory, {recursive: true, force: true});});
  const imported = await request('/import', {commandId: 'war_import_0001', expectedRevision: 0, state: f.s});
  assert.equal(imported.status, 200, JSON.stringify(imported.body));
  const command = {commandId: 'war_heal_000001', expectedRevision: imported.body.revision, ...f.views.warView(f.r).hospital.quote.command};
  const results = await Promise.all([request('/command', command), request('/command', command)]);
  assert.equal(results[0].status, 200, JSON.stringify(results[0].body));
  assert.equal(results[1].status, 200, JSON.stringify(results[1].body));
  assert.equal(results.filter(r => r.body.replayed).length, 1);
  const final = await request('/state');
  assert.equal(final.body.state.warCare.wounded.archer, 0);
  assert.equal(final.body.state.res.gold, f.s.res.gold - f.g.warCareQuote('all').gold);
  await bridge.close(); bridge = await server.startBridge(config);
  const resumed = await request('/state'), replay = await request('/command', command);
  assert.equal(replay.body.replayed, true);
  assert.deepEqual(resumed.body.state.warCare, final.body.state.warCare);
  assert.equal(resumed.body.state.res.gold, final.body.state.res.gold);
  assert.equal(resumed.body.revision, final.body.revision);
});
