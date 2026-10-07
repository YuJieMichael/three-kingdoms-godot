const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const NOW = 1800000000000;
const modules = Promise.all([import('../bridge/server.mjs'), import('../vendor/legacy/online/runtime.mjs'),
  import('../bridge/dto.mjs'), import('../scripts/progression_playtest.mjs')]);

async function fixture(t) {
  const [server, canonical, dto, pacing] = await modules;
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'shanhece-growth-http-'));
  let now = NOW, bridge, serial = 0;
  const config = {port: 0, dataDir: directory, token: 'isolated-growth-http-test', clock: () => now};
  bridge = await server.startBridge(config);
  const f = {canonical, dto, pacing, directory,
    async request(route, input) {
      const response = await fetch(`http://127.0.0.1:${bridge.port}${route}`, {
        method: input ? 'POST' : 'GET', headers: {Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json'},
        ...(input ? {body: JSON.stringify(input)} : {})});
      return {status: response.status, body: await response.json()};
    },
    async read() { const response = await this.request('/state'); assert.equal(response.status, 200); return response.body; },
    async input(type = 'exchangeCopper', args = ['growth_coral']) {
      const before = await this.read();
      return {commandId: `growth_http_${++serial}_command`, expectedRevision: before.revision, type, args};
    },
    async import(state) {
      const before = await this.read();
      return this.request('/import', {commandId: `growth_http_${++serial}_import`, expectedRevision: before.revision, state});
    },
    async restart(days = 0) { await bridge.close(); now += days * 86400000; bridge = await server.startBridge(config); },
    offer(view) { return view.progression.epic.exchanges.find(row => row.id === 'growth_coral'); },
    prepared() {
      // Explicit gate/transaction fixture, not natural pacing evidence.
      const runtime = canonical.createGameRuntime({now});
      runtime.Game.state.conquered.camp = true;
      runtime.Game.state.copper = 400;
      runtime.Game.save();
      assert.equal(runtime.Game.validSave(runtime.Game.state), true);
      return canonical.copy(runtime.Game.state);
    },
  };
  t.after(async () => { await bridge.close(); await fs.rm(directory, {recursive: true, force: true}); });
  return f;
}

test('normal first victory HTTP projects its actual receipts and growth without modifying the report', async t => {
  const f = await fixture(t), session = f.pacing.firstBattle(new f.pacing.PacingSession({seed: 604}));
  const imported = await f.import(session.state); assert.equal(imported.status, 200);
  const current = await f.read(), report = current.view.reports[0], receipt = report.resourceReceipt;
  assert.equal(report.economy.status, 'delivered');
  for (const id of Object.keys(report.economy.received)) assert.equal(report.economy.received[id],
    (receipt.base.received[id] || 0) + (receipt.bonus.received[id] || 0));
  assert.ok(current.view.growth.current);
  assert.equal(current.state.reports[0].economy, undefined);
  assert.ok(f.offer(current.view).reason.includes('营寨'));
  const denied = await f.request('/command', await f.input());
  assert.equal(denied.status, 400);
  assert.equal((await f.read()).revision, current.revision);
});

test('county preparation uses CAS, durable replay and a save-wide cap across daily refresh and restart', async t => {
  const f = await fixture(t), initial = f.prepared();
  assert.equal((await f.import(initial)).status, 200);
  const before = await f.read(), one = await f.input(), two = {...one, commandId: one.commandId + '_other'};
  const concurrent = await Promise.all([f.request('/command', one), f.request('/command', two)]);
  assert.deepEqual(concurrent.map(r => r.status).sort(), [200, 409]);
  const accepted = concurrent.find(r => r.status === 200);
  const usedInput = accepted === concurrent[0] ? one : two;
  const replay = await f.request('/command', usedInput);
  assert.equal(replay.status, 200); assert.equal(replay.body.replayed, true);
  assert.equal(replay.body.revision, before.revision + 1);
  assert.equal(replay.body.state.copper, 320);
  assert.equal(replay.body.state.jewels.coral, initial.jewels.coral + 1);
  await f.restart(1);
  const durableReplay = await f.request('/command', usedInput);
  assert.equal(durableReplay.status, 200); assert.equal(durableReplay.body.replayed, true);
  assert.equal((await f.read()).state.growthSupport.coralExchanged, 1);
  for (let n = 1; n < 5; n++) assert.equal((await f.request('/command', await f.input())).status, 200);
  const finished = await f.read();
  assert.equal(f.offer(finished.view).remaining, 0);
  assert.equal(finished.state.copper, 0);
  assert.equal(finished.state.jewels.coral, initial.jewels.coral + 5);
  const denied = await f.request('/command', await f.input()); assert.equal(denied.status, 400);
  await f.restart(1);
  const reopened = await f.read();
  assert.equal(f.offer(reopened.view).claimed, 5); assert.equal(f.offer(reopened.view).remaining, 0);
  assert.equal(reopened.revision, finished.revision);
});

test('invalid extension counters and arguments are rejected without replacing the last valid save', async t => {
  const f = await fixture(t); assert.equal((await f.import(f.prepared())).status, 200);
  const before = await f.read();
  for (const counter of [-1, 6, 1.5, '2', null]) {
    const candidate = f.canonical.copy(before.state);
    candidate.growthSupport = {version: 1, coralExchanged: counter};
    assert.equal((await f.import(candidate)).status, 400);
  }
  for (const args of [['growth_coral', 1], ['growth_coral', {}]]) {
    assert.equal((await f.request('/command', await f.input('exchangeCopper', args))).status, 400);
  }
  const after = await f.read();
  assert.equal(after.revision, before.revision);
  assert.equal(after.state.copper, before.state.copper);
  assert.deepEqual(after.state.jewels, before.state.jewels);
});

test('shared progression never exposes the local county preparation offer', async t => {
  const f = await fixture(t), runtime = f.canonical.createGameRuntime({snapshot: f.prepared(), now: NOW});
  const view = f.dto.gameView(runtime.Game, NOW, runtime, {shared: true});
  assert.equal(f.offer(view), undefined);
  assert.deepEqual(view.growth.advice, []);
  assert.throws(() => f.canonical.executeGame(runtime.Game.state,
    {commandId: 'shared_growth_reject', expectedRevision: 0, type: 'exchangeCopper', args: ['growth_coral']}, NOW),
  /商品已刷新/);
});
