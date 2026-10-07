import {intelView} from './scouting-view.mjs';

/** Explain visible matchups, never simulate damage, reveal stale intel or predict a win. */
export function formationView(game, node, army, generalId, mode, now) {
  // Native landmarkVisible treats virtual military nodes as ordinary targets;
  // their tier gate must also hold before adding enemy data to a quote.
  const orderVisible = !node.orderRoute || game.warOrders.unlocked(game.state) && !node.encounter &&
    node.orderTier <= game.warOrders.maxTier(game.state, node.orderRoute) &&
    (!node.challengeId || node.orderTier <= game.state.warOrders.cleared[node.orderRoute]);
  const intel = orderVisible ? intelView(game, node, now) : {public: false, precision: 'unknown', army: {}};
  const known = intel.public || intel.precision === 'exact';
  const own = Object.entries(army).filter(([id, n]) => game.units[id] && n > 0).map(([id, count]) => ({
    id, name: game.units[id].name, count, stats: game.unitStats(id), carryPerSoldier: game.carry({[id]: 1})}));
  const total = own.reduce((n, row) => n + row.count, 0), general = game.general(generalId);
  const enemy = known ? intel.army : {}, has = id => (army[id] || 0) > 0, foe = id => (enemy[id] || 0) > 0;
  const strengths = [], risks = [], suggestions = [];
  if (known && has('spear') && foe('cavalry')) strengths.push('长枪兵攻击轻骑兵有克制加成；接敌与指定目标仍需军令安排。');
  if (known && has('cavalry') && foe('archer')) strengths.push('轻骑兵攻击弓箭兵有克制加成；能否接近取决于战场距离与军令。');
  if (known && has('shield') && foe('archer')) strengths.push('敌弓攻击刀盾兵的伤害系数较低；刀盾需要先接敌，不会自动替其他队伍挡箭。');
  if (known && has('archer') && foe('shield')) risks.push('弓箭兵打刀盾兵伤害较低，可调整目标或增加近战输出。');
  if (known && has('archer') && foe('cavalry') && !has('spear')) risks.push('敌轻骑克制弓队，当前没有长枪兵；考虑增援或用军令控制接敌。');
  if (known && foe('archer') && !has('shield')) suggestions.push('敌军有弓箭兵：刀盾护卫、快骑接近或远程集火各有代价。');
  const ranged = own.filter(row => row.stats.range >= 1000).reduce((n, row) => n + row.count, 0);
  if (ranged === total && total > 0) risks.push('全军均为远程兵种，敌近战接近后缺少前排；保持射程优势。');
  if (orderVisible && mode === 'occupy' && (game.isCity(node) || node.fortification) && !has('ram') && !has('catapult'))
    risks.push('本次占领有门墙，未携带冲车或投石车；普通兵也能攻门，但可能耗费更多回合。');
  if (total > general.lead * 100) risks.push('出征人数超过将领统率覆盖范围，战斗中的勇武加成会受到影响。');
  if (!known) risks.push('守军没有当前精确情报，无法分析敌方兵种组合；先侦察，旧情报和人数区间不当作精确兵力。');
  return {own, total, known, precision: intel.precision,
    enemy: known ? Object.entries(enemy).filter(([, n]) => n > 0).map(([id, count]) => ({id, name: game.units[id]?.name || id, count})) : [],
    strengths, risks, suggestions, note: '阵容分析只解释当前数据和原克制关系，不预测胜率。守军民兵、城防与抵达后的变化以实际战场为准。'};
}
