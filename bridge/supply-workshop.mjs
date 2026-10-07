import {copy, GameError, validateInput} from '../vendor/legacy/online/runtime.mjs';

// Optional prototype items. Native item IDs, resource caps and queues stay in Game.
const offers = [
  {id: 'supply_choice', name: '百工调拨令', price: 22, limit: 10,
    description: '开包时选择建设、研究或练兵，固定获得对应15分钟加速 ×4。按当前需要调拨，合计1小时；不直接完成队列。',
    choices: ['build', 'research', 'train'].map(kind => ({id: kind,
      name: {build: '建设加速', research: '研究加速', train: '练兵加速'}[kind], items: {[`speed_${kind}_15m`]: 4}}))},
  {id: 'supply_rations', name: '行军粮秣包', price: 12, limit: 10,
    description: '固定粮食 +10000。用于行军、募兵或伤兵治疗；资源装不下时保留包裹。', resources: {food: 10000}},
  {id: 'supply_recovery', name: '返城整备包', price: 55, limit: 5,
    description: '固定获得练兵1小时加速 ×2、典民令 ×1，粮食 +5000、黄金 +2000。人口与练兵道具需另行使用，不直接补满部队。',
    items: {speed_train_1h: 2, population: 1}, resources: {food: 5000, gold: 2000}},
  {id: 'supply_siege', name: '攻城筹备包', price: 90, limit: 5,
    description: '固定获得建设1小时加速 ×2、练兵1小时加速 ×2，石料 +10000、铁锭 +5000。帮助准备器械，仍需满足原募兵条件。',
    items: {speed_build_1h: 2, speed_train_1h: 2}, resources: {stone: 10000, iron: 5000}},
];
const ids = new Map(offers.map(row => [row.id, row]));
const commands = new Set(['supplies.buy', 'supplies.open', 'supplies.claimStarter']);
const object = value => !!value && typeof value === 'object' && !Array.isArray(value);
const int = value => Number.isSafeInteger(value) && value >= 0;
const empty = () => ({version: 1, stock: {}, purchases: {}, starterClaimed: false});
const starterItems = {speed_build_1h: 4, speed_research_1h: 2, speed_train_1h: 1};
export const isSupplyCommand = type => commands.has(type);

export function validSupplyWorkshop(state) {
  if (!object(state)) return false;
  if (!Object.hasOwn(state, 'supplyWorkshop')) return true;
  const r = state.supplyWorkshop;
  return object(r) && Object.keys(r).length === 4 && r.version === 1 && typeof r.starterClaimed === 'boolean' &&
    object(r.stock) && object(r.purchases) && Object.entries(r.purchases).every(([id, n]) => ids.has(id) && int(n) && n <= ids.get(id).limit) &&
    Object.entries(r.stock).every(([id, n]) => ids.has(id) && int(n) &&
      n <= (r.purchases[id] || 0) + (r.starterClaimed && id === 'supply_choice' ? 1 : 0));
}

function contentsReason(game, contents) {
  for (const [id, n] of Object.entries(contents.items || {})) {
    if (!game.manual.shop.some(row => row.id === id && row.effect) || !int(n) ||
      !int(game.state.inventory[id] || 0) || !int((game.state.inventory[id] || 0) + n)) return '道具内容或库存无效';
  }
  for (const [id, n] of Object.entries(contents.resources || {})) {
    if (!Object.hasOwn(game.resources, id) || !int(n) || !Number.isFinite(game.state.res[id]) ||
      game.state.res[id] + n > game.capacity(id)) return `${game.resources[id]?.name || id}容量不足；包裹保留，请腾出空间或提升仓储`;
  }
  return '';
}

function starterView(game, shared) {
  const reason = shared ? '首战工程补给用于本机进度' : game.state.supplyWorkshop?.starterClaimed ? '本存档已领取' :
    game.state.onboarding.firstBattle === 'complete' ? '首战引导已完成，本补给仅用于首战准备' :
    game.state.buildings.hall < 1 ? '官府达到1级后领取' : contentsReason(game, {items: starterItems});
  return {name: '首战工程补给', description: '一次性免费领取：建设1小时加速 ×4、研究1小时加速 ×2、练兵1小时加速 ×1、百工调拨令 ×1。先安排当前工程，再按成长路线预览使用。',
    claimed: !!game.state.supplyWorkshop?.starterClaimed, reason,
    command: {type: 'supplies.claimStarter', args: []}};
}

export const starterSupplyQuote = (runtime, {shared = false} = {}) => starterView(runtime.Game, shared);

export function supplyWorkshopView(runtime, {shared = false} = {}) {
  const game = runtime.Game, state = game.state, r = state.supplyWorkshop || empty();
  const items = shared ? [] : offers.map(offer => {
    const count = r.stock[offer.id] || 0, remaining = offer.limit - (r.purchases[offer.id] || 0);
    const reason = !remaining ? '本存档限购份额已用完' : state.gems < offer.price ? '试玩元宝不足' : '';
    const choices = (offer.choices || []).map(row => ({id: row.id, name: row.name, reason: contentsReason(game, row)}));
    return {id: offer.id, name: offer.name, category: '创新军需', effect: 'supplyBundle', count,
      description: offer.description + `\n试玩设计 · 本存档限购 ${offer.limit} 包，跨城共用。`, trial: true,
      supported: true, rewardOnly: false, price: offer.price, buyType: 'supplies.buy', openType: 'supplies.open',
      purchase: {reason, limit: reason ? 0 : Math.min(99, remaining, Math.floor(state.gems / offer.price)),
        remaining, dailyLimit: offer.limit, period: 'save', costs: Array.from({length: 99}, (_, i) => offer.price * (i + 1))},
      use: {targetKind: choices.length ? 'choice' : 'none', targets: choices,
        reason: count < 1 ? '没有这件包裹' : choices.length ? '' : contentsReason(game, offer), route: null}};
  });
  return {items, starter: starterView(game, shared)};
}

function grant(game, contents) {
  for (const [id, n] of Object.entries(contents.items || {})) game.state.inventory[id] = (game.state.inventory[id] || 0) + n;
  for (const [id, n] of Object.entries(contents.resources || {})) game.state.res[id] += n;
}

/** Private CAS candidate only. All failures discard the candidate and keep receipts unchanged. */
export function executeSupplyCommand(runtime, input, now) {
  validateInput(input);
  if (!commands.has(input.type) || !validSupplyWorkshop(runtime.Game.state)) throw new GameError('BAD_SUPPLIES', '军需记录或操作无效');
  const game = runtime.Game;
  game.tick(now, true);
  const r = copy(game.state.supplyWorkshop || empty());
  let result;
  if (input.type === 'supplies.claimStarter') {
    if (input.args.length) throw new GameError('BAD_SUPPLIES', '首战补给参数无效');
    const quote = starterView(game, false);
    if (quote.reason) throw new GameError('GAME_RULE', quote.reason);
    grant(game, {items: starterItems});
    r.starterClaimed = true; r.stock.supply_choice = (r.stock.supply_choice || 0) + 1;
    result = {items: copy(starterItems), bundles: {supply_choice: 1}, free: true};
  } else {
    const offer = ids.get(input.args[0]);
    if (!offer) throw new GameError('BAD_SUPPLIES', '军需包不存在');
    if (input.type === 'supplies.buy') {
      const count = input.args[1], purchased = r.purchases[offer.id] || 0, cost = count * offer.price;
      if (input.args.length !== 2 || !int(count) || count < 1 || count > 99 || purchased + count > offer.limit)
        throw new GameError('GAME_RULE', '购买数量超过本存档限购份额');
      if (!int(game.state.gems) || game.state.gems < cost) throw new GameError('GAME_RULE', '试玩元宝不足');
      game.state.gems -= cost; r.purchases[offer.id] = purchased + count;
      r.stock[offer.id] = (r.stock[offer.id] || 0) + count;
      result = {bundle: offer.id, count, gemsSpent: cost};
    } else {
      if (!(r.stock[offer.id] > 0)) throw new GameError('GAME_RULE', '没有这件包裹');
      const choice = offer.choices?.find(row => row.id === input.args[1]);
      if (offer.choices ? input.args.length !== 2 || !choice : input.args.length !== 1)
        throw new GameError('BAD_SUPPLIES', '请明确选择合法的调拨方向');
      const contents = choice || offer, reason = contentsReason(game, contents);
      if (reason) throw new GameError('GAME_RULE', reason);
      grant(game, contents); r.stock[offer.id] -= 1;
      result = {bundle: offer.id, choice: choice?.id || null, items: copy(contents.items || {}), resources: copy(contents.resources || {})};
    }
  }
  game.state.supplyWorkshop = r;
  if (!validSupplyWorkshop(game.state) || !game.validSave(game.state) || game.save() === false)
    throw new GameError('INVALID_RESULT', '军需操作无法通过存档校验');
  return {state: copy(game.state), result, runtime};
}
