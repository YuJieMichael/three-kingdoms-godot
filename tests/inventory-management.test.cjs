const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const modules = Promise.all([import('../bridge/inventory-view.mjs'), import('../vendor/legacy/online/runtime.mjs')]);
const NOW = 1800000000000;

async function fixture() {
  const [{inventoryView}, {createGameRuntime, executeGame}] = await modules;
  let runtime = createGameRuntime({now: NOW, random: () => 0.9}), sequence = 0;
  const s = runtime.Game.state;
  s.gems = 5000; for (const key of Object.keys(s.res)) s.res[key] = 2000000;
  for (const [site, id, level] of [[1, 'inn', 1], [2, 'drill', 1], [3, 'tavern', 6], [4, 'smith', 1]]) {s.cityLayout[site] = id; s.cityLevels[site] = level; s.buildings[id] = level;}
  runtime.Game.save(); assert.equal(runtime.Game.validSave(s), true);
  return {get runtime() {return runtime;}, get state() {return runtime.Game.state;}, view: () => inventoryView(runtime, {now: NOW}),
    item: id => inventoryView(runtime, {now: NOW}).items.find(row => row.id === id),
    command(type, args = []) {
      const result = executeGame(runtime.Game.state, {commandId: `inventory_test_${++sequence}`, expectedRevision: sequence - 1, type, args}, NOW, () => 0.9);
      runtime = result.runtime; return result;
    }};
}

test('inventory previews do not mutate or draw boxes; canonical speedup target/key is used exactly', async () => {
  const f = await fixture(); f.state.inventory.speed_build_15m = 1; f.runtime.Game.save();
  f.command('queueBuilding', [0, 'house']);
  const before = JSON.stringify(f.state), item = f.item('speed_build_15m'), target = item.use.targets[0];
  assert.deepEqual(target.quote, f.runtime.Game.speedupQuote(item.id, target.key, NOW));
  assert.equal(JSON.stringify(f.state), before); assert.equal(f.state.onboarding.lastOpen, null);
  assert.equal(target.quote.overflow, true);
  f.command('useSpeedup', [item.id, target.key]);
  assert.equal(f.state.inventory[item.id], 0); assert.equal(f.state.buildings.house, 1);
  assert.throws(() => f.command('useSpeedup', [item.id, target.key]), /任务已结束或队列已变化/);
});

test('selected equipment box slot and jewel box receipts follow original rules, preserving full-capacity boxes', async () => {
  const f = await fixture(); f.state.inventory.starterEquipmentBasic = 2; f.state.inventory.starterJewelBox = 1; f.runtime.Game.save();
  const before = JSON.stringify(f.state), box = f.item('starterEquipmentBasic');
  assert.deepEqual(box.use.targets.map(row => row.id), Object.keys(f.runtime.HeroSystem.slots));
  assert.equal(JSON.stringify(f.state), before);
  f.command('onboarding.openItem', [box.id, 'helmet']);
  assert.equal(f.state.equipment[0].slot, 'helmet'); assert.equal(f.view().lastOpen.name, f.runtime.HeroSystem.itemName(f.state.equipment[0]));
  const jewels = {...f.state.jewels}; f.command('onboarding.openItem', ['starterJewelBox']);
  const receipt = f.state.onboarding.lastOpen; assert.equal(receipt.kind, 'jewel'); assert.ok(receipt.count >= 2 && receipt.count <= 5);
  assert.equal(f.state.jewels[receipt.id], jewels[receipt.id] + receipt.count);
  while (f.state.equipment.length < f.state.equipmentCapacity) f.runtime.HeroSystem.addEquipment(f.state, 'weapon', 1);
  f.runtime.Game.save();
  assert.equal(f.item(box.id).use.reason, '装备库已满，盒子已保留，请先整理装备');
  assert.throws(() => f.command('onboarding.openItem', [box.id, 'armor']), /装备库已满，盒子已保留/);
  assert.equal(f.state.inventory[box.id], 1);
});

test('hero reset quote executes only an isolated original rule; targeted buffs and text changes use canonical commands', async () => {
  const f = await fixture(); f.state.generalLevels.lin = 12; f.state.inventory.resetHero = 2; f.state.inventory.politics = 1; f.state.inventory.rename = 1; f.state.inventory.banner = 1;
  f.runtime.HeroSystem.init(f.state); f.runtime.Game.save();
  f.command('hero.allocate', ['lin', {atk: 1, def: 0, pol: 0, wis: 0, lead: 0}]);
  const before = JSON.stringify(f.state), q = f.item('resetHero').use.targets.find(row => row.id === 'lin');
  assert.equal(q.reason, ''); assert.equal(JSON.stringify(f.state), before);
  const count = f.state.inventory.resetHero; f.command('useItem', ['resetHero', 'lin']);
  assert.equal(f.state.inventory.resetHero, count - q.consume); assert.equal(f.state.heroPoints.lin.atk, 0);
  f.state.inventory.resetHero = 2; f.runtime.Game.save();
  assert.equal(f.item('resetHero').use.targets.find(row => row.id === 'lin').reason, '这位将领没有已分配属性点');
  f.command('useItem', ['politics', 'lin']); assert.ok(f.state.buffs['politics:lin']);
  assert.throws(() => f.command('useItem', ['rename', '', '名字超过十二个字符就应该失败']), /名称长度不合适/);
  assert.equal(f.state.inventory.rename, 1); f.command('useItem', ['rename', '', '山河城主']); assert.equal(f.state.ruler, '山河城主');
  f.command('useItem', ['banner', '', '策']); assert.equal(f.state.banner, '策');
  f.state.inventory.resetHero = 2; f.state.heroPoints.lin.atk = 1; f.runtime.Game.save(); f.runtime.Game.setExternalGeneralBusy(['lin']);
  assert.ok(f.item('resetHero').use.targets.find(row => row.id === 'lin').reason.includes('出征'));
});

test('purchase projections honor original 99-item bound, affordability, reward-only and daily brick restrictions', async () => {
  const f = await fixture(), item = f.item('politics'), before = f.state.gems;
  assert.equal(item.purchase.limit, 99); assert.equal(item.purchase.costs[98], f.runtime.Game.manual.shop.find(row => row.id === 'politics').price * 99);
  f.command('buyItem', [item.id, 99]); assert.equal(f.state.gems, before - item.purchase.costs[98]);
  assert.throws(() => f.command('buyItem', [item.id, 100]), /请选择购买数量/);
  const brick = f.item('goldBrick'), remain = f.runtime.Game.brickPurchaseRemaining(brick.id), gems = f.state.gems;
  assert.equal(brick.purchase.limit, remain); f.command('buyItem', [brick.id, remain]);
  assert.equal(f.state.gems, gems - brick.purchase.costs[remain - 1]);
  const blocked = f.item(brick.id); assert.equal(blocked.purchase.limit, 0); assert.equal(blocked.purchase.remaining, 0);
  assert.throws(() => f.command('buyItem', [brick.id, 1]), error => error.message === blocked.purchase.reason);
  const reward = f.item('starterJewelBox'); assert.equal(reward.purchase.limit, 0);
  assert.throws(() => f.command('buyItem', [reward.id, 1]), error => error.message === reward.purchase.reason);
  f.state.gems = 0; f.runtime.Game.save(); assert.equal(f.item('politics').purchase.reason, '试玩元宝不足');
  assert.equal(f.item('pearl').use.route.target, 'equipment'); assert.equal(f.item('blueprint').use.route.route, 'city');
});

test('real HTTP bulk purchase receipt replays once and persists after bridge restart in isolated storage', async t => {
  const {startBridge} = await import('../bridge/server.mjs'), directory = await fs.mkdtemp(path.join(os.tmpdir(), 'shanhece-inventory-'));
  const configuration = {dataDir: directory, port: 0, token: 'inventory-isolated-token', clock: () => NOW};
  let bridge = await startBridge(configuration);
  t.after(async () => {await bridge.close(); await fs.rm(directory, {recursive: true, force: true});});
  async function request(route, body) {
    const result = await fetch(`http://127.0.0.1:${bridge.port}${route}`, {method: body === undefined ? 'GET' : 'POST', headers: {Authorization: `Bearer ${configuration.token}`, 'Content-Type': 'application/json'}, ...(body === undefined ? {} : {body: JSON.stringify(body)})});
    const json = await result.json(); assert.equal(result.status, 200, JSON.stringify(json)); return json;
  }
  const initial = await request('/state'), command = {commandId: 'inventory_purchase_once', expectedRevision: initial.revision, type: 'buyItem', args: ['politics', 2]};
  const bought = await request('/command', command), repeated = await request('/command', command);
  assert.equal(repeated.replayed, true); assert.deepEqual(repeated.state, bought.state);
  assert.equal(bought.state.gems, initial.state.gems - 40); assert.equal(bought.state.inventory.politics, (initial.state.inventory.politics || 0) + 2);
  await bridge.close(); bridge = await startBridge(configuration);
  const resumed = await request('/state'); assert.equal(resumed.state.gems, bought.state.gems); assert.equal(resumed.state.inventory.politics, bought.state.inventory.politics);
  assert.equal((await request('/command', command)).replayed, true);
});
