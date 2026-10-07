import {copy, createGameRuntime} from '../vendor/legacy/online/runtime.mjs';
import {supplyWorkshopView} from './supply-workshop.mjs';

/** Inventory projections select existing commands; opening a preview never rolls a box. */
export function inventoryView(runtime, {shared = false, now = Date.now()} = {}) {
  const {Game: game, HeroSystem: hero} = runtime, s = game.state;
  const owned = s.generals.map(id => ({id, name: game.general(id).name, busy: !!game.generalBusy(id)}));
  let resets = null;
  const resetQuotes = () => {
    if (resets) return resets;
    // Reset has no public quote. Preview the ORIGINAL command in independent,
    // in-memory runtimes rather than copying its level-dependent cost formula.
    resets = owned.map(g => {
      const probe = createGameRuntime({snapshot: s, now, random: () => 0.9, externalBusy: owned.filter(row => row.busy).map(row => row.id)});
      const before = probe.Game.state.inventory.resetHero || 0, reason = probe.HeroSystem.reset(g.id);
      return {id: g.id, name: g.name, reason: reason || '', consume: reason ? null : before - (probe.Game.state.inventory.resetHero || 0)};
    });
    return resets;
  };
  const items = game.manual.shop.map(item => {
    const count = s.inventory[item.id] || 0, remaining = game.brickPurchaseRemaining(item.id), dailyLimit = remaining === null ? null : remaining + (s.daily.brickPurchases[item.id] || 0);
    const purchaseReason = item.rewardOnly ? '此物品仅由成长礼包获得，不能购买' : !item.effect ? '该道具依赖尚未接入的系统，暂不出售' : remaining === 0 ? '该种金砖每日限购 '+dailyLimit+' 块，今日剩余 0 块' : s.gems < item.price ? '试玩元宝不足' : '';
    const limit = purchaseReason ? 0 : Math.min(99, remaining ?? 99, item.price > 0 ? Math.floor(s.gems / item.price) : 99);
    let reason = !item.effect || count < 1 ? '没有可使用的道具' : '', targetKind = 'none', targets = [], route = null;
    if (item.effect === 'speedup') {
      targetKind = 'speedup'; targets = game.speedupTargets(item.queueKind, now).map(target => {
        const quote = game.speedupQuote(item.id, target.key, now);
        return {...target, quote, reason: quote.error || (count < 1 ? '没有这件加速道具' : quote.workMs <= 1 ? '任务即将完成，无需加速' : '')};
      });
      if (!targets.length) reason ||= '这项任务已结束或队列已变化，请重新选择';
    } else if (['politics', 'valor', 'wisdom', 'tiger', 'heroReset'].includes(item.effect)) {
      targetKind = 'hero'; targets = item.effect === 'heroReset' && count > 0 ? resetQuotes() : owned.map(row => ({id: row.id, name: row.name, reason: ''}));
      if (!targets.length) reason ||= '请选择将领';
    } else if (item.effect === 'equipmentBox') {
      targetKind = 'slot'; targets = Object.entries(hero.slots).map(([id, name]) => ({id, name, reason: ''}));
      if (s.equipment.length >= s.equipmentCapacity) reason ||= '装备库已满，盒子已保留，请先整理装备';
    } else if (['rename', 'banner'].includes(item.effect)) targetKind = 'text';
    else if (item.effect === 'population' && s.population >= game.maxPop()) reason ||= '人口已达上限';
    else if (item.effect === 'peace' && (s.itemCooldowns.peace || 0) > now) reason ||= '安民告示仍在 3 天冷却';
    else if (item.effect === 'recruit' && s.buildings.inn < 1) reason ||= '请先建造客栈';
    else if (item.effect === 'equipmentRack' && s.equipmentCapacity >= 500) reason ||= '装备容量已达 500 格';
    else if (item.effect === 'equipmentMaterial') {reason = '强化宝珠在装备详情中使用'; route = {route: 'heroes', target: 'equipment', label: '前往装备强化'};}
    else if (item.effect === 'blueprint') {reason = '图纸在建筑升至 10 级时自动消耗，请在建筑页面使用'; route = {route: 'city', target: 'blueprint', label: '前往城内建设'};}
    return {id: item.id, name: item.name, category: item.category || '宝物', description: item.desc || '', effect: item.effect,
      count, rewardOnly: !!item.rewardOnly, supported: !!item.effect, price: item.price,
      purchase: {limit, reason: purchaseReason, remaining, dailyLimit,
        // Small numeric table keeps total prices in the rule service, not GDScript.
        costs: Array.from({length: 99}, (_, index) => item.price * (index + 1))},
      use: {reason, targetKind, targets, maxLength: item.effect === 'rename' ? 12 : item.effect === 'banner' ? 2 : null, route}};
  });
  const workshop = supplyWorkshopView(runtime, {shared});
  items.push(...workshop.items);
  const opened = s.onboarding.lastOpen;
  let lastOpen = null;
  if (opened?.kind === 'jewel') lastOpen = {kind: 'jewel', name: runtime.Progression.jewels[opened.id].name, count: opened.count};
  else if (opened?.kind === 'equipment') {
    const equipment = s.equipment.find(row => row.id === opened.id);
    lastOpen = {kind: 'equipment', name: equipment ? hero.itemName(equipment) : '装备', count: 1};
  }
  return copy({items, categories: [...new Set(items.map(item => item.category))], gems: s.gems, shared, lastOpen,
    owned, slots: hero.slots, starterSupply: workshop.starter});
}
