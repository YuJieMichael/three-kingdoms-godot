const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const modules = Promise.all([import('../bridge/progression-view.mjs'), import('../vendor/legacy/online/runtime.mjs'), import('../bridge/server.mjs')]);
const NOW = 1800000000000;

async function fixture(t) {
  const [projection, canonical, bridgeModule] = await modules;
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'shanhece-progression-'));
  const config = {port: 0, dataDir: directory, token: 'isolated-progression-test', clock: () => NOW};
  let bridge = await bridgeModule.startBridge(config), serial = 0;
  const api = {projection, canonical,
    async request(route, body) {
      const response = await fetch(`http://127.0.0.1:${bridge.port}${route}`, {method: body ? 'POST' : 'GET',
        headers: {Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json'}, ...(body ? {body: JSON.stringify(body)} : {})});
      return {status: response.status, body: await response.json()};
    },
    async read() { const result = await this.request('/state'); assert.equal(result.status, 200); return result.body; },
    async send(record, extra = {}) {
      const before = await this.read();
      const input = {commandId: `progression_${++serial}_command`, expectedRevision: before.revision, ...record, ...extra};
      const result = await this.request('/command', input);
      return {...result, input};
    },
    async import(game) { game.save(); assert.equal(game.validSave(game.state), true); const before = await this.read();
      const result = await this.request('/import', {commandId: `progression_${++serial}_import`, expectedRevision: before.revision, state: game.state});
      assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body; },
    async restart() { await bridge.close(); bridge = await bridgeModule.startBridge(config); },
  };
  t.after(async () => { await bridge.close(); await fs.rm(directory, {recursive: true, force: true}); });
  return api;
}

test('progression quotes are read-only, retain all reward types and hide unreached world nodes', async () => {
  const [projection, canonical] = await modules, runtime = canonical.createGameRuntime({now: NOW});
  const before = JSON.stringify(runtime.Game.state), view = projection.progressionView(runtime);
  assert.equal(JSON.stringify(runtime.Game.state), before);
  assert.equal(view.gifts.levels.length, 10); assert.equal(view.gifts.available, 1);
  assert.deepEqual(view.gifts.levels[0].rewards.resources, runtime.OnboardingSystem.quote(runtime.Game.state, 1).resources);
  assert.equal(view.missions.some(m => m.id === 'conquest_wood'), false);
  assert.equal(view.missions.some(m => m.id.startsWith('chapter2_')), false);
  assert.equal(view.chapters[0].next, null); assert.deepEqual(view.chapters[0].visibleNodes, []);
  const mission = view.missions.find(m => m.id === 'army_archer'), original = runtime.Game.missions.find(m => m.id === mission.id);
  assert.deepEqual(mission.rewards.resources, original.reward);
  assert.deepEqual(mission.rewards.items.map(i => [i.id, i.count]), Object.entries(original.items));
  assert.equal(mission.navigate.target, 'archer');
  assert.equal(view.firstBattle.requirementSteps.find(step => step.id === 'barracks').level, runtime.Game.units.archer.requires.buildings.barracks);
  assert.equal(view.firstBattle.requirementSteps.find(step => step.id === 'academy').level, 4);
  assert.equal(view.firstBattle.requirementSteps.find(step => step.id === 'training').level, 4);
  assert.equal(view.firstBattle.requirementSteps.find(step => step.id === 'smith').level, 1);
  assert.equal(view.firstBattle.requirementSteps.find(step => step.id === 'mine').level, 3);
  assert.equal(view.firstBattle.requirementSteps.find(step => step.id === 'mine').current, 0);
  assert.equal(view.firstBattle.next.target, 'drill');
  for (const [id, level] of [['drill', 1], ['barracks', 4], ['academy', 4]]) runtime.Game.state.buildings[id] = level;
  assert.deepEqual(projection.progressionView(runtime).firstBattle.next, {route: 'outer', target: 'mine'});
});

test('first battle completion uses canonical victory, return and 30-archer gates without changing live flags', async () => {
  const [projection, canonical] = await modules, runtime = canonical.createGameRuntime({now: NOW}), state = runtime.Game.state;
  state.stats.victories = 1; state.army.archer = 29;
  assert.match(projection.progressionView(runtime).firstBattle.reason, /30/);
  state.army.archer = 30;
  const before = JSON.stringify(state), quote = projection.progressionView(runtime).firstBattle;
  assert.equal(quote.ready, true); assert.equal(JSON.stringify(state), before); assert.equal(state.onboarding.firstBattle, 'active');
  state.garrisons.field = {phase: 'return', army: {archer: 1}};
  assert.match(projection.progressionView(runtime).firstBattle.reason, /返城/);
  delete state.garrisons.field;
  assert.equal(runtime.Game.completeFirstBattleGuide(), null);
  assert.equal(projection.progressionView(runtime).firstBattle.complete, true);
});

test('chapter progress requires occupation of every second-chapter node, and reveals only reached targets', async () => {
  const [projection, canonical] = await modules, runtime = canonical.createGameRuntime({now: NOW}), state = runtime.Game.state;
  state.conquered.fort = true;
  const nodes = runtime.ChapterData.chapterNodes(2);
  for (const node of nodes.slice(0, -1)) state.conquered[node.id] = true;
  state.raided[nodes.at(-1).id] = true;
  let view = projection.progressionView(runtime);
  assert.equal(view.chapters[0].conquered, 5); assert.equal(view.chapters[1].unlocked, false);
  assert.deepEqual(view.chapters[1].visibleNodes, []);
  for (const mission of view.missions.filter(m => m.id.startsWith('chapter2_'))) assert.equal(runtime.Game.landmarkVisible(mission.target), true);
  state.conquered[nodes.at(-1).id] = true;
  view = projection.progressionView(runtime); assert.equal(view.chapters[1].unlocked, true);
  const thirdMission = runtime.Game.missions.find(m => m.id.startsWith('chapter3_') && m.army);
  state.conquered[thirdMission.node] = true;
  const projected = projection.progressionView(runtime).missions.find(m => m.id === thirdMission.id);
  assert.deepEqual(projected.rewards.army.map(u => [u.id, u.count]), Object.entries(thirdMission.army));
  assert.deepEqual(projected.rewards.jewels.map(j => [j.id, j.count]), Object.entries(thirdMission.jewels));
});

test('shared projections disable private mainline and NPC navigation without exposing chapter targets', async () => {
  const [projection, canonical] = await modules, runtime = canonical.createGameRuntime({now: NOW});
  runtime.Game.state.starterGiftClaimed = true;
  const view = projection.progressionView(runtime, {shared: true});
  assert.equal(view.missions.every(m => !m.ready && m.reason.includes('共享')), true);
  assert.equal(view.firstBattle.ready, false); assert.match(view.firstBattle.navigationReason, /共享/);
  assert.equal(view.chapters.every(c => !c.unlocked && c.next === null && c.visibleNodes.length === 0), true);
  assert.equal(view.gifts.available, 1);
  runtime.Game.state.daily.tasks.push({uid: runtime.Game.state.daily.start + '_999', template: 'victory', status: 'accepted', target: 1, progress: 1, acceptedAt: NOW, tier: 1});
  const restricted = projection.progressionView(runtime, {shared: true});
  assert.match(restricted.daily.claimAll.reason, /逐项/);
  assert.match(restricted.daily.tasks.at(-1).claimReason, /共享/);
});

test('offices require real jewels; office/noble fees and daily salary persist exactly once across receipt retries', async t => {
  const f = await fixture(t), runtime = f.canonical.createGameRuntime({now: NOW}), game = runtime.Game, state = game.state;
  state.prestige = 1000; state.res.gold = 25000;
  const quote = f.projection.progressionView(runtime).honors.promotions.find(p => p.kind === 'office');
  assert.match(quote.reason, /珍珠/); await f.import(game);
  const denied = await f.send(quote.command); assert.equal(denied.status, 400); assert.match(denied.body.error.message, /珍珠/);
  state.jewels.pearl = 11; state.jewels.coral = 5; await f.import(game);
  const office = await f.send(quote.command); assert.equal(office.status, 200, JSON.stringify(office.body));
  assert.equal(office.body.state.jewels.pearl, 10); assert.equal(office.body.state.honors.office, 1);
  const replay = await f.request('/command', office.input); assert.equal(replay.body.replayed, true); assert.equal(replay.body.state.jewels.pearl, 10);
  const promoted = f.canonical.createGameRuntime({snapshot: office.body.state, now: NOW});
  const nobleQuote = f.projection.progressionView(promoted).honors.promotions.find(p => p.kind === 'noble');
  assert.equal(nobleQuote.reason, '');
  const noble = await f.send(nobleQuote.command); assert.equal(noble.status, 200);
  assert.equal(noble.body.state.res.gold, 5000); assert.equal(noble.body.state.jewels.pearl, 0); assert.equal(noble.body.state.jewels.coral, 0);
  const nobleRuntime = f.canonical.createGameRuntime({snapshot: noble.body.state, now: NOW});
  assert.equal(f.projection.progressionView(nobleRuntime).honors.cityLimit, 2);
  const salary = await f.send({type: 'heritage.salary', args: ['office']}); assert.equal(salary.status, 200);
  assert.equal(salary.body.state.res.gold, 6000);
  await f.restart(); const repeated = await f.request('/command', salary.input);
  assert.equal(repeated.body.replayed, true); assert.equal(repeated.body.state.res.gold, 6000);
  const again = await f.send({type: 'heritage.salary', args: ['office']}); assert.equal(again.status, 400); assert.match(again.body.error.message, /今日已领取/);
});

test('daily accept/claim, milestone, exchange and epic donation deduct canonical costs without duplicate awards', async t => {
  const f = await fixture(t), runtime = f.canonical.createGameRuntime({now: NOW}), game = runtime.Game, state = game.state;
  state.cityLayout[0] = 'inn'; state.cityLevels[0] = 1; state.buildings.inn = 1; state.res.gold = 200000;
  state.copper = 80; state.daily.claimed = 3; await f.import(game);
  let view = f.projection.progressionView(runtime);
  const available = view.daily.tasks.find(task => Object.keys(task.payment).length);
  const accepted = await f.send(available.accept); assert.equal(accepted.status, 200);
  const current = f.canonical.createGameRuntime({snapshot: accepted.body.state, now: NOW});
  const task = f.projection.progressionView(current).daily.tasks.find(t => t.id === available.id);
  assert.equal(task.ready, true);
  const before = accepted.body.state, claimed = await f.send(task.claim); assert.equal(claimed.status, 200);
  const resource = Object.keys(task.payment)[0];
  assert.equal(claimed.body.state.res[resource], before.res[resource] - task.payment[resource] + task.rewards.resources[resource]);
  const replay = await f.request('/command', claimed.input); assert.equal(replay.body.replayed, true); assert.deepEqual(replay.body.state.res, claimed.body.state.res);
  const removed = await f.send(task.claim); assert.equal(removed.status, 400);
  const milestone = await f.send(view.daily.milestones[0].command); assert.equal(milestone.status, 200);
  assert.equal(milestone.body.state.inventory.speed_build_15m, 2);
  assert.equal((await f.send(view.daily.milestones[0].command)).status, 400);
  const exchanged = await f.send(view.epic.exchanges.find(offer => offer.id === 'pearl').command); assert.equal(exchanged.status, 200);
  assert.equal(exchanged.body.state.jewels.pearl, 1); assert.equal(exchanged.body.state.copper, before.copper + task.rewards.copper - 40);
  const donation = view.epic.donations.find(d => d.kind === 'resource' && d.id === 'gold');
  const treasury = (await f.read()).state.res.gold, donated = await f.send(donation.command);
  assert.equal(donated.status, 200); assert.equal(donated.body.state.res.gold, treasury - donation.cost);
  assert.equal(donated.body.state.epic.resources.gold, donation.cost);
  assert.equal((await f.send(donation.command)).status, 400);
});

test('ten-tier gift batch is an exactly-once persisted reward, with unclaimed tiers remaining locked', async t => {
  const f = await fixture(t), runtime = f.canonical.createGameRuntime({now: NOW}), game = runtime.Game;
  const hallSite = game.state.cityLayout.indexOf('hall'); game.state.cityLevels[hallSite] = 2; game.state.buildings.hall = 2;
  await f.import(game);
  const quote = f.projection.progressionView(runtime).gifts;
  assert.equal(quote.available, 2); assert.match(quote.levels[2].reason, /官府 3 级/);
  const claimed = await f.send(quote.claimAll.command); assert.equal(claimed.status, 200); assert.deepEqual(claimed.body.state.onboarding.claims, [1, 2]);
  const gold = quote.levels.slice(0, 2).reduce((sum, gift) => sum + gift.rewards.resources.gold, 5000);
  assert.equal(claimed.body.state.res.gold, gold);
  await f.restart(); const replay = await f.request('/command', claimed.input);
  assert.equal(replay.body.replayed, true); assert.equal(replay.body.state.res.gold, gold);
  const fresh = await f.send(quote.claimAll.command); assert.equal(fresh.status, 400); assert.match(fresh.body.error.message, /没有可领取/);
});
