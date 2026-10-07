// Read-only recovery budgets. These are not a paid ledger or a gold valuation.
const RESOURCES = ['food', 'wood', 'stone', 'iron', 'gold'];
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const receiptResources = value => object(value) && RESOURCES.every(id =>
  !Object.hasOwn(value, id) || Number.isFinite(value[id]) && value[id] >= 0);
const resources = value => Object.fromEntries(RESOURCES.flatMap(id =>
  Number.isFinite(value?.[id]) && value[id] >= 0 ? [[id, value[id]]] : []));
const add = (...rows) => rows.reduce((result, row) => {
  for (const [id, value] of Object.entries(resources(row))) result[id] = (result[id] || 0) + value;
  return result;
}, {});

/** Quotes only; never heal, train, switch city, or write a canonical report. */
export function reportEconomy(runtime, report, options = {}) {
  const game = runtime.Game, shared = !!options.shared || !!report.shared;
  const defending = shared && report.source !== options.actor;
  const cityId = (defending ? report.targetCity : report.sourceCity) || 'capital';
  const city = game.getCityState(cityId);
  const lost = defending ? report.defenderLost : report.lost;
  const wounded = defending ? report.defenderWounded : report.wounded;
  const permanentLoss = {}, replacement = {resources: {}, soldiers: 0, people: 0};
  let knownCosts = true;
  for (const [id, count] of Object.entries(lost || {})) {
    if (!Number.isSafeInteger(count) || count < 0) { knownCosts = false; continue; }
    if (!count) continue;
    if (!game.units[id]) { knownCosts = false; continue; }
    permanentLoss[id] = count;
    replacement.resources = add(replacement.resources, game.trainCost(id, count));
    replacement.soldiers += count;
    replacement.people += count * (game.units[id].people || 1);
  }
  const notes = ['按当前规则估算恢复预算，尚未扣款；资源分别计算，不折算黄金。'];
  if (defending) notes.push('守方合计含盟友，恢复预算不能分摊到本人。');
  if (!city) notes.push('原出发/驻守城池已不属于你，当前伤兵池无法查询。');
  let treatmentGold = 0, treatmentPeople = 0;
  const hospitalReport = shared || report.woundedInHospital === true;
  if (hospitalReport) for (const [id, count] of Object.entries(wounded || {})) {
    if (!Number.isSafeInteger(count) || count < 0) { knownCosts = false; continue; }
    if (!count) continue;
    const price = runtime.WarCare.price(id, game.units);
    if (!Number.isFinite(price)) { knownCosts = false; continue; }
    treatmentGold += count * price;
    treatmentPeople += count;
  }
  if (!hospitalReport) notes.push('旧战报未使用付费伤兵营，不追加治疗预算。');
  const pool = city ? runtime.WarCare.quote(city, 'all', undefined, game.units) : null;
  const treatment = {
    resources: treatmentGold ? {gold: treatmentGold} : {}, people: treatmentPeople,
    available: !defending && !!pool?.count && !pool.reason,
    reason: defending ? '守方合计含盟友伤兵，请分别查看自己的伤兵营。' :
      !city ? '原城池伤兵池不可查询' : pool?.reason || '',
    currentPool: pool ? {people: pool.count, gold: pool.gold} : null,
  };
  notes.push('治疗预算按本战伤兵估算，并非仍需支付；当前伤兵池另算，不能判定本战已治疗人数。');
  const loot = add(report.loot, shared ? null : report.bonusLoot);
  let status = 'unknown', received = null;
  if (shared) {
    if (defending) { status = 'lost'; received = {}; }
    else if (report.lootDelivered === true && receiptResources(report.receivedResources)) {
      status = 'delivered'; received = resources(report.receivedResources);
    } else if (report.status === 'stationed') status = 'retained';
    else if (report.status === 'return' || report.lootDelivered === false) status = 'pending';
  } else {
    const receipt = report.resourceReceipt;
    // Missing old receipts cannot prove that cargo actually reached storage.
    if (receiptResources(receipt?.base?.received) && receiptResources(receipt?.bonus?.received)) {
      status = 'delivered'; received = add(receipt.base.received, receipt.bonus.received);
    }
    if (status === 'delivered') notes.push('本机战斗按现有规则在战果结算时入库，部队返城另计。');
  }
  if (status === 'unknown') notes.push('此战报缺少入库凭据，不能确认实际收入。');
  if (status === 'pending') notes.push('战利品尚未交付，预计收支不能作为可用库存。');
  if (!knownCosts) notes.push('部分兵种或人数无法按当前规则报价，恢复预算不完整。');
  const base = status === 'lost' ? Object.fromEntries(RESOURCES.map(id => [id, -(loot[id] || 0)])) :
    received !== null ? received : ['pending', 'retained'].includes(status) ? loot : null;
  const net = {kind: 'projected', resources: base && knownCosts ? Object.fromEntries(RESOURCES.map(id =>
    [id, (base[id] || 0) - (replacement.resources[id] || 0) - (treatment.resources[id] || 0)])) : null};
  return {basis: 'current-canonical-prices', scope: defending ? 'defenders-total' : 'own-force',
    cityId, status, loot, received, permanentLoss, replacement, treatment, net, notes};
}
