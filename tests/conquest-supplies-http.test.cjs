const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const ROOT = process.env.TK_PACKAGE_SERVICE || path.resolve(__dirname, '..');
const load = name => import(pathToFileURL(path.join(ROOT, name)).href);
const modules = Promise.all([load('bridge/server.mjs'), load('vendor/legacy/online/runtime.mjs')]);

async function fixture(t) {
  const [server, native] = await modules;
  const dataDir = await fs.mkdtemp(path.join(os.tmpdir(), 'conquest-package-'));
  let now = 1800000000000, bridge, serial = 0;
  const config = {dataDir, port: 0, token: 'isolated-conquest-test', clock: () => now};
  bridge = await server.startBridge(config);
  const f = {
    native, get now() { return now; }, advance(ms) { now += ms; },
    async request(route, body) {
      const response = await fetch(`http://127.0.0.1:${bridge.port}${route}`, {
        method: body ? 'POST' : 'GET', headers: {Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json'},
        ...(body ? {body: JSON.stringify(body)} : {})});
      return {status: response.status, body: await response.json()};
    },
    async read() { const r = await this.request('/state'); assert.equal(r.status, 200); return r.body; },
    async input(type, args = []) {
      return {commandId: `conquest_test_${++serial}`, expectedRevision: (await this.read()).revision, type, args};
    },
    async command(type, args = []) {
      const input = await this.input(type, args), r = await this.request('/command', input);
      assert.equal(r.status, 200, JSON.stringify(r.body)); return {...r.body, input};
    },
    async import(state) {
      const r = await this.request('/import', {commandId: `conquest_import_${++serial}`, expectedRevision: (await this.read()).revision, state});
      assert.equal(r.status, 200, JSON.stringify(r.body));
    },
    async restart() { await bridge.close(); bridge = await server.startBridge(config); },
    async win(id) {
      // Strong fictional army fixture; this still runs real marching and combat settlement.
      const sent = await this.command('dispatch', [id, 'lin', {archer: 1000}, 'occupy', true]);
      this.advance(sent.state.expedition.end - now + 1);
      await this.command('startBattle');
      let result;
      for (let i = 0; i < 30; i++) {
        result = await this.command('battleRound');
        if (result.state.battle.finished) break;
      }
      assert.equal(result.state.battle.result.won, true);
      assert.equal(result.state.battle.result.claimed, true);
      return result;
    },
  };
  t.after(async () => { await bridge.close(); await fs.rm(dataDir, {recursive: true, force: true}); });
  return f;
}

test('packaged starter and choice supplies persist, replay once and enforce purchase caps', async t => {
  const f = await fixture(t);
  const base = await f.read(), gift = await f.command('supplies.claimStarter');
  assert.equal(gift.state.inventory.speed_build_1h, (base.state.inventory.speed_build_1h || 0) + 4);
  assert.equal(gift.state.supplyWorkshop.stock.supply_choice, 1);
  assert.equal((await f.request('/command', gift.input)).body.replayed, true);
  assert.equal((await f.request('/command', await f.input('supplies.claimStarter'))).status, 400);
  const opened = await f.command('supplies.open', ['supply_choice', 'research']);
  assert.equal(opened.state.inventory.speed_research_15m, (gift.state.inventory.speed_research_15m || 0) + 4);
  const game = f.native.createGameRuntime({snapshot: opened.state, now: f.now}).Game;
  game.state.gems = 1000; game.state.res.food = game.capacity('food'); game.save();
  await f.import(game.state);
  const bought = await f.command('supplies.buy', ['supply_rations', 10]);
  assert.equal(bought.state.gems, 880);
  assert.equal((await f.request('/command', await f.input('supplies.buy', ['supply_rations', 1]))).status, 400);
  assert.equal((await f.request('/command', await f.input('supplies.open', ['supply_rations']))).status, 400);
  await f.restart();
  const resumed = await f.read();
  assert.equal(resumed.state.supplyWorkshop.stock.supply_rations, 10);
  assert.equal(resumed.state.supplyWorkshop.purchases.supply_rations, 10);
  assert.equal(resumed.revision, bought.revision);
});

test('actual first occupation awards once, persists its random draw, and paused occupation never pays retroactively', async t => {
  const f = await fixture(t), game = f.native.createGameRuntime({now: f.now}).Game, s = game.state;
  s.cityLayout[0] = 'drill'; s.cityLevels[0] = 2; s.buildings.drill = 2;
  s.res = {food: 100000, wood: 100000, stone: 100000, iron: 100000, gold: 100000};
  s.army.archer = 1000; s.conquered.camp = true; game.save();
  assert.equal(game.validSave(s), true); await f.import(s);
  const enabled = await f.command('conquest.setEnabled', [true]);
  assert.equal(enabled.state.conquestSupply.records.camp.status, 'baseline');
  assert.equal(enabled.state.gems, s.gems);
  const won = await f.win('field'), receipt = won.result.conquestSupply;
  assert.ok(receipt, 'real final battle round must produce an occupation receipt');
  assert.equal(receipt.gems, 3 + 2 * game.getNode('field').level);
  assert.equal(won.state.gems, enabled.state.gems + receipt.gems);
  assert.equal(won.state.reports[0].conquestSupply, undefined, 'native report stays unchanged');
  assert.deepEqual(won.view.reports[0].conquestSupply, receipt);
  const replay = await f.request('/command', won.input);
  assert.equal(replay.body.replayed, true); assert.deepEqual(replay.body.result.conquestSupply, receipt);
  await f.restart();
  const resumed = await f.read(); assert.equal(resumed.state.gems, won.state.gems);
  assert.deepEqual(resumed.state.conquestSupply, won.state.conquestSupply);
  f.advance(resumed.state.expedition.end - f.now + 1);
  await f.command('setTax', [20]);
  await f.command('conquest.setEnabled', [false]);
  const prepared = f.native.createGameRuntime({snapshot: (await f.read()).state, now: f.now}).Game;
  prepared.state.army.archer = 1000; prepared.save(); await f.import(prepared.state);
  const wild = Array.from({length: 4096}, (_, i) => prepared.getWorldTile(i % 64, Math.floor(i / 64)))
    .find(node => node.wild && node.level === 1);
  const paused = await f.win(wild.id);
  assert.equal(paused.result.conquestSupply, undefined);
  assert.equal(paused.state.conquestSupply.records[wild.id].status, 'disabled');
  const reenabled = await f.command('conquest.setEnabled', [true]);
  assert.equal(reenabled.state.gems, paused.state.gems);
  assert.equal(reenabled.view.conquestSupply.rewarded, 1);
});
