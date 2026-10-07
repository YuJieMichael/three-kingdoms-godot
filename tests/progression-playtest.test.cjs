'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');

const load = () => import('../scripts/progression_playtest.mjs');

test('fresh earned-speedup route wins, returns and refills without injected resources or troops', async () => {
  const {PacingSession, firstBattle} = await load();
  const session = firstBattle(new PacingSession({seed: 604, speedupPolicy: 'cover'}));
  assert.equal(session.read().Game.validSave(session.state), true);
  assert.deepEqual(session.state.onboarding.claims, [1, 2]);
  assert.equal(session.state.army.archer, 30);
  assert.equal(session.state.stats.victories, 1);
  assert.equal(session.state.expedition, null);
  assert.equal(session.report.battles[0].result.won, true);
  assert.deepEqual(session.report.battles[0].economy.received, {food: 583, wood: 117});
  assert.deepEqual(session.report.battles[0].economy.replacement.resources, {food: 600, wood: 700, iron: 600});
  assert.equal(session.report.battles[0].economy.net.kind, 'projected');
  assert.ok(session.report.battles[0].result.lost.archer > 0);
  assert.ok(!session.report.commands.some(c => ['grantTestSupplies', 'setSpeed', 'importSave', 'claimTrialGems', 'buyItem'].includes(c.type)));
  const inventory = {};
  for (const command of session.report.commands) {
    assert.equal(command.ok, true);
    for (const [id, amount] of Object.entries(command.inventoryDelta)) {
      inventory[id] = (inventory[id] || 0) + amount;
      assert.ok(inventory[id] >= 0, `${id} must be earned before consumption`);
    }
  }
  assert.equal(session.report.speedups.length, session.report.commands.filter(c => c.type === 'useSpeedup').length);
  assert.ok(session.report.milestones.at(-1).atMinutes < 1);
});

test('private support spends normally earned copper and retains every natural epic and county gate', async () => {
  const {PacingSession, firstBattle, naturalMidgame} = await load();
  const session = firstBattle(new PacingSession({seed: 604, growthSupport: true}));
  naturalMidgame(session, {maxRaids: 40});
  assert.equal(session.state.conquered.fort, true);
  assert.equal(session.state.growthSupport.coralExchanged, 4);
  assert.equal(session.report.supportExchanges.length, 4);
  for (const exchange of session.report.supportExchanges) {
    assert.equal(exchange.copperBefore - exchange.copperAfter, 80);
    assert.equal(exchange.coralAfter - exchange.coralBefore, 1);
  }
  let copper = 0;
  for (const command of session.report.commands) {
    copper += command.copperDelta;
    assert.ok(copper >= 0, 'copper must be earned before spending');
  }
  assert.equal(copper, session.state.copper);
  assert.equal(session.report.battles.filter(b => b.node === 'fort').length, 3);
  assert.equal(session.state.missionClaims.filter(id => id.startsWith('chapter2_')).length, 6);
  assert.equal(session.report.milestones.at(-1).id, 'chapter2-completed-natural');
  assert.equal(session.read().Game.validSave(session.state), true);
  assert.ok(!session.report.commands.some(c => ['grantTestSupplies', 'importSave', 'setSpeed', 'buyItem'].includes(c.type)));
});

test('unaccelerated baseline accounts for the whole canonical rule-clock wait', async () => {
  const {PacingSession, firstBattle} = await load();
  const session = firstBattle(new PacingSession({accelerate: false, seed: 604}));
  const elapsed = session.report.milestones.at(-1).atMinutes;
  assert.ok(elapsed > 700 && elapsed < 900, 'baseline must retain hours of real queue work');
  assert.equal(session.report.speedups.length, 0);
  assert.ok(Math.abs(session.report.waits.reduce((n, w) => n + w.minutes, 0) - elapsed) < 0.001);
  assert.equal(session.read().Game.validSave(session.state), true);
  assert.equal(session.state.army.archer, 30);
});

test('same fresh seed and command policy reproduce canonical results and inventories', async () => {
  const {PacingSession, firstBattle} = await load();
  const a = firstBattle(new PacingSession({seed: 604}));
  const b = firstBattle(new PacingSession({seed: 604}));
  assert.deepEqual(a.report, b.report);
  assert.deepEqual(a.state, b.state);
});

test('clock horizon reports an unfinished queue rather than fabricating completion', async () => {
  const {PacingSession, firstBattle} = await load();
  const session = new PacingSession({accelerate: false, maxDays: 1 / 1440});
  assert.throws(() => firstBattle(session), /Simulation horizon reached/);
  assert.ok(session.state.buildQueue.length > 0);
  assert.equal(session.state.stats.victories, 0);
  assert.equal(session.read().Game.validSave(session.state), true);
});

test('bounded natural midgame pays epic costs and opens earned boxes but never bypasses county gates', async () => {
  const {PacingSession, firstBattle, naturalMidgame} = await load();
  const session = firstBattle(new PacingSession({seed: 604}));
  assert.throws(() => naturalMidgame(session, {maxRaids: 0}), /Natural county gate remains/);
  assert.deepEqual(session.state.onboarding.claims, [1, 2, 3, 4, 5, 6]);
  assert.equal(session.state.inventory.starterJewelBox, 0);
  assert.equal(session.state.epic.troops, 2);
  for (const amount of Object.values(session.state.epic.resources)) assert.equal(amount, 100000);
  assert.equal(session.state.conquered.fort, undefined);
  assert.equal(session.report.bottlenecks.at(-1).kind, 'county-gate');
  assert.ok(session.report.commands.some(c => c.type === 'onboarding.openItem'));
  assert.ok(session.report.commands.some(c => c.type === 'hero.equip'));
  assert.equal(session.read().Game.validSave(session.state), true);
});
