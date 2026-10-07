import {copy} from '../vendor/legacy/online/runtime.mjs';

/** Read-only presentation of the existing hero rules. Never runs a command. */
export function heroView(runtime, {shared = false} = {}) {
  const {Game: game, HeroSystem: hero, Progression: progression} = runtime;
  const s = game.state, busyReason = id => !s.generals.includes(id) ? '请选择已招募将领' : game.generalBusy(id) ? '将领出征或驻守中，请返城后调整' : '';
  const owned = s.generals.map(id => {
    const general = game.general(id), busy = busyReason(id), drill = hero.drillQuote(s, id);
    return {...general, id, city: game.heroCity(id), busy: !!busy, reason: busy,
      loyalty: hero.wild.loyalty(s, id), points: hero.remaining(s, id), allocated: copy(s.heroPoints[id]),
      specialization: {profile: copy(game.generalGrowth.profile(s, id)),
        statBonus: copy(game.generalGrowth.statBonus(s, id)),
        routes: game.generalGrowth.routes.map(route => ({...copy(route),
          quote: copy(game.generalGrowth.trainQuote(s, id, route.id, {generalBusy: game.generalBusy}))}))},
      drill: {...drill, reason: busy || (s.buildings.drill < 1 ? '请先建造校场' : general.level >= 10000 ? '将领已达最高等级' : drill.used >= 3 ? '今日已操练 3 次，北京时间 05:00 重置' : s.res.gold < drill.cost ? '黄金不足' : '')},
      rewards: ['gold', 'jewels'].map(method => hero.wild.rewardQuote(s, id, method)),
      salary: game.salaryQuote(id)};
  });
  const wild = hero.wild.codex(s).map(row => {
    // The codex contains generator anchors and base stats. Only a discovered,
    // active lead gets coordinates; guards are never copied into this DTO.
    const node = row.status === 'active' && row.node ? game.getNode(row.node) : null;
    const portrait = hero.wild.portraitQuote(s, row.line);
    return {line: row.line, name: row.name, title: row.title, region: row.region,
      status: row.status, locked: row.locked, reason: row.reason, portrait: copy(portrait),
      node: node ? {id: node.id, name: node.name, x: node.x, y: node.y, level: node.level} : null,
      dispatchReason: shared ? '共享房间暂不开放私人野将出征' : !node ? '请先打听可用线索' : !row.portraitOwned ? '请先购买画像，才能俘获这名将领' : game.attackBlocked(node.id, 'raid') || ''};
  });
  const captives = [
    ...(s.wildGenerals?.captives || []).map(c => ({id: c.id, name: c.hero.name, title: c.hero.title, level: c.hero.level, loyalty: c.loyalty, kind: 'wild',
      quotes: ['gold', 'jewels'].map(method => hero.wild.recruitQuote(s, c.id, method)), release: hero.wild.releaseQuote(s, c.id)})),
    ...(s.heroService?.captives || []).map(c => ({id: c.id, name: c.hero.name, title: c.hero.title || '战败俘将', level: c.level, loyalty: 40, kind: 'defeated',
      quotes: ['gold', 'jewels'].map(method => {const q = game.defeatedHeroQuote(c.id, method); return q ? {...q, method} : null;}).filter(Boolean), release: null})),
  ];
  const equipment = s.equipment.map(e => {
    const q = hero.enhanceQuote(e), wearer = e.hero ? busyReason(e.hero) : '';
    return {...copy(e), enhanceLevel: e.enhance, name: hero.itemName(e), slotName: hero.slots[e.slot], quality: hero.qualities[e.tier], requiredLevel: hero.requiredLevel(e), stats: hero.stats(e),
      wearerName: e.hero ? game.general(e.hero).name : '',
      equip: owned.map(g => ({id: g.id, name: g.name, reason: busyReason(g.id) || wearer || (g.level < hero.requiredLevel(e) ? '需要将领 '+hero.requiredLevel(e)+' 级' : '')})),
      unequipReason: !e.hero ? '装备未穿戴' : wearer,
      enhance: {...q, reason: wearer || (s.buildings.smith < 1 ? '请先建造铁匠铺' : e.enhance >= 10 ? '强化已达 +10' : s.res.gold < q.gold || (s.inventory.pearl || 0) < q.pearls ? '黄金或强化宝珠不足' : '')},
      salvageReason: e.hero ? '请先卸下装备' : ''};
  });
  const forge = Object.keys(hero.slots).flatMap(slot => [1, 2, 3].map(tier => {
    const q = hero.forgeQuote(slot, tier);
    return {slot, tier, name: hero.names[slot][tier], quality: hero.qualities[tier], ...copy(q),
      reason: s.buildings.smith < q.smith ? '需要 '+q.smith+' 级铁匠铺' : s.equipment.length >= s.equipmentCapacity ? '装备库已满' : !game.canPay(q.cost) ? '打造材料不足' : ''};
  }));
  const items = game.manual.shop.filter(item => ['politics', 'valor', 'wisdom', 'tiger'].includes(item.effect) && (s.inventory[item.id] || 0) > 0)
    .map(item => ({id: item.id, name: item.name, description: item.desc || '', count: s.inventory[item.id], effect: item.effect}));
  return copy({owned, wild, captives, equipment, forge, items, shared,
    attrs: hero.attrs, slots: hero.slots, capacity: hero.wild.roomCapacity(s), used: hero.wild.roomUsed(s),
    equipmentCapacity: s.equipmentCapacity, smithLevel: s.buildings.smith,
    discoverReason: s.buildings.inn < 1 ? '请先建造 1 级客栈' : '',
    giftReason: s.heroGiftClaimed ? '将领装备礼包已领取' : s.equipment.length + 8 > s.equipmentCapacity ? '需要 8 格装备空间' : '',
    expansions: ['rack', 'rackAdvanced'].map(id => ({id, name: game.manual.shop.find(item => item.id === id)?.name || id, count: s.inventory[id] || 0,
      reason: (s.inventory[id] || 0) < 1 ? '没有武器架' : s.equipmentCapacity >= 500 ? '装备容量已达 500 格' : ''})),
    jewels: Object.fromEntries(Object.entries(progression.jewels).map(([id, data]) => [id, data.name]))});
}
