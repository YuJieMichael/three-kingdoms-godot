const {test} = require('node:test');
const assert = require('node:assert/strict');
const modules = Promise.all([import('../bridge/growth-view.mjs'), import('../bridge/progression-view.mjs'), import('../vendor/legacy/online/runtime.mjs')]);
const NOW = 1800000000000;

async function fixture() {
  const [growth, progression, canonical] = await modules;
  const runtime = canonical.createGameRuntime({now: NOW, random: () => 0.9});
  return {runtime, game: runtime.Game, state: runtime.Game.state,
    view: options => growth.growthView(runtime, {now: NOW, ...options}), progression};
}

function countyReady(f) {
  f.state.onboarding.firstBattle = 'complete';
  f.state.epic.legacyAccess = true;
  f.state.honors.noble = 1;
  for (const id of ['field', 'wood', 'pass', 'camp', 'mine']) f.state.conquered[id] = true;
}

test('growth is read-only, reuses the first-battle projection and excludes unreached nodes', async () => {
  const f = await fixture(), before = JSON.stringify(f.state), guide = f.progression.progressionView(f.runtime).firstBattle;
  const view = f.view();
  assert.equal(JSON.stringify(f.state), before);
  assert.equal(view.stage.id, 'first_battle');
  assert.ok(view.current.description.includes('30名弓箭手'));
  assert.equal(view.current.description.includes('请先完成一次出征胜利'), false);
  assert.deepEqual({route: view.current.navigate.route, target: view.current.navigate.target}, guide.next);
  assert.equal(view.gaps.find(g => g.id === 'army:archer').required, guide.target);
  assert.equal(view.source, null); assert.equal(view.combat, null);
  const worldTargets = [view.current.navigate, ...view.advice.map(row => row.navigate)]
    .filter(row => row?.route === 'world').map(row => row.target);
  for (const node of f.game.nodes.filter(node => !f.game.landmarkVisible(node.id))) {
    // `mine` is also the public resource-building ID; only world navigation
    // targets/source and the actual node name identify the hidden landmark.
    assert.equal(worldTargets.includes(node.id), false, node.id + ' must not be a world target');
    assert.equal(JSON.stringify(view).includes(node.name), false, node.name + ' must remain undisclosed');
  }
  const projected = f.progression.progressionView(f.runtime);
  assert.deepEqual(f.view({progression: projected}), view);
});

test('shared growth does not expose any private route, owned accelerations or chapter source', async () => {
  const f = await fixture(); countyReady(f); f.state.conquered.fort = true;
  f.state.inventory.speed_build_3h = 99;
  const before = JSON.stringify(f.state), view = f.view({shared: true});
  assert.equal(JSON.stringify(f.state), before);
  assert.match(view.reason, /共享/); assert.equal(view.current, null); assert.equal(view.source, null);
  assert.deepEqual(view.gaps, []); assert.deepEqual(view.advice, []);
  assert.equal(view.speedup.ownedCount, 0); assert.equal(view.combat, null);
  assert.equal(JSON.stringify(view).includes('north_road'), false);
});

test('epic route derives four real gates and keeps county capacity distinct from raid permission', async () => {
  const f = await fixture(); f.state.onboarding.firstBattle = 'complete';
  let view = f.view();
  assert.equal(view.stage.id, 'county_access'); assert.equal(view.current.navigate.route, 'epic');
  assert.equal(view.gaps.find(g => g.id === 'epic:kills').required, f.runtime.Progression.targets.kills);
  assert.equal(view.gaps.find(g => g.id === 'epic:resources').required,
    Object.values(f.runtime.Progression.resourceDonations).reduce((sum, r) => sum + r.amount, 0));
  assert.equal(view.advice.some(row => row.id === 'county-capacity'), true);
  assert.equal(view.source, null); assert.equal(JSON.stringify(view).includes('古渡'), false);
  f.state.epic.kills = f.runtime.Progression.targets.kills;
  view = f.view(); assert.equal(view.current.id, 'epic:resources');
  const donation = f.progression.progressionView(f.runtime).epic.donations.find(row => row.kind === 'resource' && row.id === 'food');
  assert.equal(view.gaps.find(g => g.id === 'resource:food').required, donation.cost);
  f.state.epic.legacyAccess = true;
  view = f.view(); assert.equal(view.stage.id, 'county_honors'); assert.equal(view.current.id, 'promote:office');
  f.state.honors.office = 1;
  view = f.view(); assert.equal(view.current.id, 'promote:noble');
  const noble = f.runtime.HeritageSystem.promotionQuote(f.state, 'noble');
  assert.equal(view.gaps.find(g => g.id === 'jewel:pearl').required, noble.rule.jewels.pearl);
  assert.equal(view.gaps.find(g => g.id === 'resource:gold').required, noble.rule.gold);
});

test('county occupation immediately advances, raids do not clear chapter gates, and completion exposes only the next open node', async () => {
  const f = await fixture(); countyReady(f);
  let view = f.view(); assert.equal(view.current.navigate.target, 'fort'); assert.equal(view.source.id, 'fort');
  assert.equal(view.combat.intelKnown, false); assert.deepEqual(view.combat.enemyArmy, {});
  f.state.conquered.fort = true;
  view = f.view(); assert.equal(view.stage.id, 'chapter2'); assert.equal(view.current.navigate.target, 'north_road');
  assert.equal(view.combat.intelKnown, true); assert.deepEqual(view.combat.enemyArmy, f.game.getNode('north_road').army);
  assert.equal(JSON.stringify(view).includes('north_granary'), false);
  f.state.raided.north_road = true;
  view = f.view(); assert.equal(view.stage.progress, 0); assert.equal(view.current.navigate.target, 'north_road');
  const nodes = f.runtime.ChapterData.chapterNodes(2);
  for (let index = 0; index < nodes.length; index++) {
    f.state.conquered[nodes[index].id] = true;
    view = f.view(); assert.equal(view.stage.progress, index + 1);
    if (index + 1 < nodes.length) assert.equal(view.current.navigate.target, nodes[index + 1].id);
  }
  assert.equal(view.stage.id, 'chapter2_complete'); assert.equal(view.current.navigate.target, 'luo_outpost');
  assert.equal(JSON.stringify(view).includes('luo_gate'), false);
  assert.equal(f.state.missionClaims.includes('chapter2_north_keep'), false, 'unclaimed awards do not stall true occupation progress');
});

test('public intel is respected; unavailable enemy composition is never replaced by the private node army', async () => {
  const f = await fixture(); countyReady(f);
  let view = f.view(); assert.equal(view.combat.enemyCount, null);
  const original = f.game.intel;
  f.game.intel = () => ({precision: 'band', band: '一小队'});
  view = f.view(); assert.deepEqual(view.combat.enemyArmy, {}); assert.equal(view.combat.enemyCount, null);
  f.game.intel = () => ({precision: 'exact', army: {archer: 7, spear: 8}});
  view = f.view(); assert.deepEqual(view.combat.enemyArmy, {archer: 7, spear: 8}); assert.equal(view.combat.enemyCount, 15);
  assert.equal(view.combat.armyLimit, f.game.armyLimit());
  f.game.intel = original;
});

test('owned speedup suggestion uses the smallest completing item and reports lost duration', async () => {
  const f = await fixture();
  f.state.buildQueue.push({id: 'drill', site: 0, level: 1, start: NOW, end: NOW + 8 * 60000});
  f.state.inventory.speed_build_15m = 6; f.state.inventory.speed_build_1h = 2;
  f.state.inventory.speed_research_3h = 4;
  const before = JSON.stringify(f.state), speedup = f.view().speedup;
  assert.equal(JSON.stringify(f.state), before); assert.equal(speedup.ownedCount, 12);
  assert.equal(speedup.suggestion.itemId, 'speed_build_15m');
  assert.equal(speedup.suggestion.shortenMinSeconds, 480); assert.equal(speedup.suggestion.remainingMaxSeconds, 0);
  assert.equal(speedup.suggestion.wasteMinSeconds, 420); assert.equal(speedup.suggestion.wasteMaxSeconds, 420);
  assert.equal(speedup.suggestion.conserve, false);
  f.state.buildQueue[0].end = NOW + 2 * 60000;
  assert.equal(f.view().speedup.suggestion.conserve, true);
});

test('acceleration includes queued waiting, ratio/random ranges and canonical quote rejection without rolling', async () => {
  const f = await fixture();
  f.state.buildQueue.push({id: 'drill', site: 0, level: 1, start: NOW + 3600000, end: NOW + 7200000});
  f.state.inventory.speed_build_1h = 1;
  let suggestion = f.view().speedup.suggestion;
  assert.equal(suggestion.waitSeconds, 3600); assert.equal(suggestion.remainingMinSeconds, 3600);
  f.state.inventory.speed_build_1h = 0; f.state.inventory.speed_build_30pct = 1;
  suggestion = f.view().speedup.suggestion;
  assert.equal(suggestion.shortenMinSeconds, 1080); assert.equal(suggestion.remainingMaxSeconds, 6120);
  f.state.inventory.speed_build_30pct = 0; f.state.inventory.speed_build_15_30h = 1;
  f.state.buildQueue[0].start = NOW; f.state.buildQueue[0].end = NOW + 40 * 3600000;
  const before = JSON.stringify(f.state); suggestion = f.view().speedup.suggestion;
  assert.equal(JSON.stringify(f.state), before);
  assert.equal(suggestion.shortenMinSeconds, 15 * 3600); assert.equal(suggestion.shortenMaxSeconds, 30 * 3600);
  assert.equal(suggestion.remainingMinSeconds, 10 * 3600); assert.equal(suggestion.remainingMaxSeconds, 25 * 3600);
  const original = f.game.speedupQuote;
  f.game.speedupQuote = () => ({reason: 'fixture: canonical target is stale'});
  assert.equal(f.view().speedup.suggestion, null);
  f.game.speedupQuote = () => ({error: 'fixture: canonical target is stale'});
  assert.equal(f.view().speedup.suggestion, null);
  f.game.speedupQuote = original; f.state.buildQueue = [];
  assert.equal(f.view().speedup.suggestion, null); assert.equal(f.view().speedup.ownedCount, 1);
});

test('recovery advice uses canonical price/rates/capacity, and never promises waiting for negative production', async () => {
  const f = await fixture(); f.state.res.food = 0; f.state.res.wood = 0;
  const before = JSON.stringify(f.state), view = f.view();
  assert.equal(JSON.stringify(f.state), before);
  const payment = f.game.buildRecord('drill', 1).cost;
  for (const row of view.gaps.filter(g => g.id.startsWith('resource:'))) assert.equal(row.required, payment[row.id.slice(9)]);
  const recovery = view.advice.find(row => row.id === 'resource-recovery');
  assert.match(recovery.text, /净产.*分钟可补足/);
  f.state.army.archer = 100000;
  assert.ok(f.game.rates().food < 0);
  const negative = f.view().advice.find(row => row.id === 'resource-recovery');
  assert.match(negative.text, /恢复生产/); assert.equal(negative.text.includes('分钟可补足'), false);
  f.state.onboarding.firstBattle = 'complete'; f.state.epic.kills = f.runtime.Progression.targets.kills;
  const capacity = f.view().advice.find(row => row.id === 'resource-recovery');
  assert.match(capacity.text, /容量/); assert.equal(capacity.navigate.target, 'warehouse');
});


test('county jewel shortfall directs to capped copper preparation and owned boxes without spending', async () => {
  const f = await fixture();
  f.state.onboarding.firstBattle = 'complete'; f.state.epic.legacyAccess = true;
  f.state.conquered.camp = true; f.state.honors.office = 1;
  const box = f.game.manual.shop.find(item => item.effect === 'jewelBox');
  f.state.inventory[box.id] = 1;
  const before = JSON.stringify(f.state), view = f.view();
  assert.equal(view.current.id, 'promote:noble');
  const advice = view.advice.find(row => row.id === 'county-preparation');
  assert.ok(advice.text.includes('80')); assert.ok(advice.text.includes('5/5'));
  assert.deepEqual(advice.navigate, {route: 'epic', target: 'exchange', label: '查看县城筹备兑换'});
  assert.equal(view.advice.find(row => row.id === 'owned-jewel-boxes').navigate.target, box.id);
  assert.equal(JSON.stringify(f.state), before);
  f.state.growthSupport = {version: 1, coralExchanged: 5}; f.state.inventory[box.id] = 0;
  const exhausted = f.view();
  assert.equal(exhausted.advice.some(row => row.id === 'county-preparation'), false);
  const gathering = exhausted.advice.find(row => row.id === 'jewel-gathering');
  assert.ok(gathering.text.includes('随机')); assert.equal(gathering.navigate.route, 'holdings');
});
