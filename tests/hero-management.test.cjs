const {test} = require('node:test');
const assert = require('node:assert/strict');
const modules = Promise.all([import('../bridge/hero-view.mjs'), import('../vendor/legacy/online/runtime.mjs')]);
const NOW = 1800000000000;

async function fixture() {
  const [{heroView}, {createGameRuntime, executeGame}] = await modules;
  let runtime = createGameRuntime({now: NOW, random: () => 0.9}), sequence = 0;
  const s = runtime.Game.state;
  for (const [site, id, level] of [[0, 'inn', 1], [1, 'tavern', 6], [2, 'drill', 1], [3, 'smith', 6]]) {
    s.cityLayout[site] = id; s.cityLevels[site] = level; s.buildings[id] = level;
  }
  for (const key of Object.keys(s.res)) s.res[key] = 2000000;
  for (const key of Object.keys(s.jewels)) s.jewels[key] = 20;
  runtime.HeroSystem.addXp(s, 'lin', 80);
  runtime.Game.save(); assert.equal(runtime.Game.validSave(s), true);
  return {
    get runtime() {return runtime;}, get state() {return runtime.Game.state;}, view: options => heroView(runtime, options),
    command(type, args = []) {
      const result = executeGame(runtime.Game.state, {commandId: `hero_test_${++sequence}`, expectedRevision: sequence - 1, type, args}, NOW, () => 0.9);
      runtime = result.runtime; return result;
    },
  };
}

test('hero projection reuses canonical quotations without mutation or unknown guard/anchor leaks', async () => {
  const f = await fixture(), before = JSON.stringify(f.state), dto = f.view(), h = dto.owned.find(row => row.id === 'lin');
  assert.deepEqual(h.drill, {...f.runtime.HeroSystem.drillQuote(f.state, 'lin'), reason: ''});
  assert.deepEqual(h.rewards[0], f.runtime.HeroSystem.wild.rewardQuote(f.state, 'lin', 'gold'));
  assert.deepEqual(dto.forge[8].cost, f.runtime.HeroSystem.forgeQuote(dto.forge[8].slot, dto.forge[8].tier).cost);
  assert.equal(JSON.stringify(f.state), before);
  assert.equal(dto.wild.every(row => row.node === null && !Object.hasOwn(row, 'anchor') && !Object.hasOwn(row, 'army') && !Object.hasOwn(row, 'atk')), true);
  dto.owned[0].allocated.atk = 9000;
  assert.equal(f.state.heroPoints[dto.owned[0].id].atk, 0);
});

test('real portrait and both wild recruitment payment paths use canonical fees and changing keys', async () => {
  for (const method of ['gold', 'jewels']) {
    const f = await fixture(); f.command('wild.discover');
    const lead = f.view().wild.find(row => row.line === 'wanderer');
    assert.ok(lead.node && lead.dispatchReason.includes('画像'));
    assert.equal(Object.hasOwn(lead.node, 'army'), false);
    assert.equal(f.view({shared: true}).wild.find(row => row.line === 'wanderer').dispatchReason, '共享房间暂不开放私人野将出征');
    const oldGems = f.state.gems;
    f.command('wild.buyPortrait', ['wanderer', lead.portrait.key]);
    assert.equal(f.state.gems, oldGems - lead.portrait.price);
    assert.throws(() => f.command('wild.buyPortrait', ['wanderer', lead.portrait.key]), /画像报价或线索已变化/);
    const rumor = f.state.wildGenerals.rumors.find(row => row.line === 'wanderer');
    const result = f.runtime.HeroSystem.wild.settle(f.state, f.runtime.Game.getNode(rumor.node), {finished: false, mode: 'raid', enemy: [{hp: 0}]}, true, NOW);
    assert.equal(result.status, 'captured'); f.runtime.Game.save(); assert.equal(f.runtime.Game.validSave(f.state), true);
    const captive = f.view().captives.find(row => row.kind === 'wild'), q = captive.quotes.find(row => row.method === method);
    assert.deepEqual(q, f.runtime.HeroSystem.wild.recruitQuote(f.state, captive.id, method));
    const gold = f.state.res.gold, jewels = {...f.state.jewels};
    f.command('wild.recruit', [captive.id, method, q.key]);
    assert.equal(f.state.res.gold, gold - q.cost.gold);
    for (const [id, amount] of Object.entries(q.cost.jewels)) assert.equal(f.state.jewels[id], jewels[id] - amount);
    assert.equal(f.state.generals.includes(captive.id), true); assert.equal(f.state.heroLoyalty[captive.id], 40);
    assert.equal(f.view().captives.some(row => row.id === captive.id), false);
  }
});

test('defeated captives expose their original recruitment quote and reject insufficient funds', async () => {
  const f = await fixture(), [{}, {createGameRuntime}] = await modules, loser = createGameRuntime({now: NOW});
  const l = loser.Game.state; l.generals.push('yan'); l.generalLevels.yan = 1; l.generalXp.yan = 0;
  loser.HeroSystem.init(l); l.heroLoyalty.yan = 40; loser.Game.save();
  assert.equal(f.runtime.GovernanceSystem.captureDefeated(l, f.state, 'yan', NOW).status, 'captured');
  f.runtime.Game.save(); assert.equal(f.runtime.Game.validSave(f.state), true);
  const captive = f.view().captives.find(row => row.kind === 'defeated'), q = captive.quotes.find(row => row.method === 'gold');
  assert.deepEqual(q, {...f.runtime.Game.defeatedHeroQuote(captive.id, 'gold'), method: 'gold'});
  const before = f.state.res.gold;
  f.command('recruitDefeatedHero', [captive.id, 'gold', q.key]);
  assert.equal(f.state.res.gold, before - q.cost.gold); assert.equal(f.state.heroLoyalty[captive.id], 40);
  const reward = f.view().owned.find(row => row.id === captive.id).rewards[0];
  f.state.res.gold = 0; f.runtime.Game.save();
  assert.equal(f.view().owned.find(row => row.id === captive.id).rewards[0].reason, '黄金不足');
  assert.throws(() => f.command('wild.reward', [captive.id, 'gold', reward.key]), /黄金不足/);
});

test('real cultivation/equipment commands preserve original costs, points and busy restrictions', async () => {
  const f = await fixture();
  assert.equal(f.view().owned.find(row => row.id === 'lin').points, 3);
  f.command('hero.allocate', ['lin', {atk: 1, def: 0, pol: 2, wis: 0, lead: 0}]);
  assert.equal(f.view().owned.find(row => row.id === 'lin').points, 0);
  const drill = f.view().owned.find(row => row.id === 'lin').drill, gold = f.state.res.gold;
  f.command('hero.drill', ['lin']); assert.equal(f.state.res.gold, gold - drill.cost); assert.equal(f.view().owned.find(row => row.id === 'lin').drill.used, 1);
  f.command('hero.gift'); assert.equal(f.view().equipment.length, 8); assert.equal(f.view().giftReason, '将领装备礼包已领取');
  const first = f.view().equipment[0]; f.command('hero.equip', [first.id, 'lin']);
  assert.equal(f.state.equipment.find(row => row.id === first.id).hero, 'lin');
  const q = f.view().equipment.find(row => row.id === first.id).enhance, beforeGold = f.state.res.gold, beforePearls = f.state.inventory.pearl;
  assert.deepEqual({gold: q.gold, pearls: q.pearls}, f.runtime.HeroSystem.enhanceQuote(f.state.equipment.find(row => row.id === first.id)));
  f.command('hero.enhance', [first.id]); assert.equal(f.state.res.gold, beforeGold - q.gold); assert.equal(f.state.inventory.pearl, beforePearls - q.pearls);
  assert.equal(f.view().equipment.find(row => row.id === first.id).salvageReason, '请先卸下装备');
  assert.throws(() => f.command('hero.salvage', [first.id]), /请先卸下装备/);
  f.command('hero.unequip', [first.id]); f.command('hero.salvage', [first.id]); assert.equal(f.state.equipment.some(row => row.id === first.id), false);
  const forge = f.view().forge.find(row => row.slot === 'armor' && row.tier === 2), resources = {...f.state.res};
  f.command('hero.forge', [forge.slot, forge.tier]);
  for (const [id, cost] of Object.entries(forge.cost)) assert.equal(f.state.res[id], resources[id] - cost);
  f.state.inventory.politics = 1; f.runtime.Game.save(); assert.equal(f.view().items.find(row => row.id === 'politics').count, 1);
  f.command('useItem', ['politics', 'lin']); assert.equal(f.state.inventory.politics, 0); assert.ok(f.state.buffs['politics:lin']);
  f.runtime.Game.setExternalGeneralBusy(['lin']);
  const busy = f.view().owned.find(row => row.id === 'lin'); assert.ok(busy.drill.reason.includes('出征')); assert.ok(busy.rewards[0].reason.includes('返城'));
  assert.ok(f.view().equipment[0].equip.find(row => row.id === 'lin').reason.includes('出征'));
  assert.equal(f.runtime.Game.validSave(f.state), true);
});
