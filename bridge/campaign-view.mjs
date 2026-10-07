import {copy} from '../vendor/legacy/online/runtime.mjs';
import {intelView} from './scouting-view.mjs';

/** Native repeatable PVE routes, not a second battle/reward implementation. */
export function campaignView(runtime, {shared = false, now = runtime.Game.state.last} = {}) {
  const {Game: game, WarOrders: orders} = runtime, state = game.state, ledger = state.warOrders;
  const unlocked = !shared && orders.unlocked(state);
  const reason = shared ? '共享房间使用玩家战争；战役军令用于本机征战' : unlocked ? '' : '先占领第二章北境大营，开放战役军令';
  const targetView = node => {
    const challenge = node.challengeId ? orders.challenge(node.challengeId) : null;
    const completed = challenge ? ledger.challenges.completed[node.id] === true : node.orderTier <= ledger.cleared[node.orderRoute];
    const first = !challenge && !completed, intel = intelView(game, node, now);
    return {id: node.id, name: node.name, level: node.level, desc: node.desc,
      orderRoute: node.orderRoute, orderTier: node.orderTier, hidden: false, owned: false, selectable: true,
      intel, army: intel.public ? copy(intel.army) : {}, completed, first,
      reason: game.attackBlocked(node.id, 'occupy') || '',
      points: orders.points(node, first), bonus: challenge && !completed ? challenge.bonus : 0,
      condition: challenge?.condition || '', hint: challenge?.hint || orders.routes[node.orderRoute].hint,
      lastAttempt: challenge ? copy(ledger.challenges.lastAttempts[node.id] || null) : null,
      gate: node.fortification ? {name: node.fortification.name, hp: node.fortification.hp} : null};
  };
  const routes = Object.entries(orders.routes).map(([id, route]) => ({id, name: route.name, hint: route.hint,
    cleared: ledger.cleared[id], wins: ledger.wins[id], max: orders.MAX_TIER,
    recoverySeconds: Math.max(0, Math.ceil((ledger.nextAt[id] - now) / 1000)),
    targets: unlocked ? [
      ...Array.from({length: orders.maxTier(state, id)}, (_, i) => orders.getNode(`order_${id}_${i + 1}`)),
      ...orders.challenges.filter(row => row.route === id && !row.encounter && row.tier <= ledger.cleared[id])
        .map(row => orders.getNode(row.id)),
    ].map(targetView) : []}));
  const offers = unlocked ? orders.offers.map(offer => {
    const item = game.manual.shop.find(row => row.id === offer.id);
    return {...offer, name: item?.name || offer.id, description: item?.desc || '',
      owned: state.inventory[offer.id] || 0, reason: ledger.merit < offer.cost ? '军功不足' : '',
      command: {type: 'war.exchange', args: [offer.id]}};
  }) : [];
  return {shared, unlocked, reason, merit: ledger.merit, earned: ledger.earned, spent: ledger.spent,
    routes, offers, last: copy(ledger.last)};
}
