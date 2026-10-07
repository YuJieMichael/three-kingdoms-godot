import {copy, createGameRuntime, GameError, validateInput} from '../vendor/legacy/online/runtime.mjs';

const OFFER_ID = 'growth_coral';
const COST = 80;
const LIMIT = 5;
const object = value => !!value && typeof value === 'object' && !Array.isArray(value);
// Optional prototype supply prices. Promotion requirements remain canonical;
// these fixed copper prices are clearly marked as this game's trial design.
const PREPARATION_PRICES = Object.freeze({pearl: 40, coral: 80, glass: 120, amber: 160,
  agate: 200, crystal: 240, jadeite: 280, jade: 320, nightPearl: 400});
let catalogue = null;

function preparationCatalogue() {
  if (catalogue) return catalogue;
  // Native getters expose the preserved rank table. This isolated metadata
  // reader never receives a player's save or executes a gameplay command.
  const {Game: game, HeritageSystem: heritage} = createGameRuntime({now: Date.UTC(2026, 0, 1), random: () => 0.5});
  const rows = new Map();
  for (const kind of ['office', 'noble']) for (let rank = 1; rank < 100; rank++) {
    const state = {...game.state, honors: {...game.state.honors, [kind]: rank}};
    const row = kind === 'office' ? heritage.office(state) : heritage.noble(state);
    if (!row) break;
    for (const [jewel, limit] of Object.entries(row.promotion?.jewels || {})) {
      if (!Object.hasOwn(PREPARATION_PRICES, jewel) || kind === 'noble' && rank === 1 && jewel === 'coral') continue;
      const id = `growth_prepare_${kind}_${rank}_${jewel}`;
      rows.set(id, {id, kind, rank, jewel, limit, stage: row.name, cost: PREPARATION_PRICES[jewel]});
    }
  }
  catalogue = rows;
  return catalogue;
}

export const isGrowthSupportOffer = id => typeof id === 'string' && (id === OFFER_ID || id.startsWith('growth_prepare_'));

/** Optional save-wide extension; old canonical saves do not need migration. */
export function validGrowthSupport(snapshot) {
  if (!object(snapshot)) return false;
  if (!Object.hasOwn(snapshot, 'growthSupport')) return true;
  const record = snapshot.growthSupport;
  if (!object(record) || !Number.isSafeInteger(record.coralExchanged) || record.coralExchanged < 0 || record.coralExchanged > LIMIT) return false;
  if (record.version === 1) return Object.keys(record).length === 2 && Object.hasOwn(record, 'version') && Object.hasOwn(record, 'coralExchanged');
  if (record.version !== 2 || Object.keys(record).length !== 3 || !Object.hasOwn(record, 'version') ||
    !Object.hasOwn(record, 'coralExchanged') || !Object.hasOwn(record, 'preparation') || !object(record.preparation)) return false;
  const entries = Object.entries(record.preparation), rules = preparationCatalogue();
  return entries.length <= rules.size && entries.every(([id, count]) => rules.has(id) &&
    Number.isSafeInteger(count) && count >= 0 && count <= rules.get(id).limit &&
    rules.get(id).rank <= (snapshot.honors?.[rules.get(id).kind] ?? -2) + 1);
}

/** Only the two current next-promotion stages are quoted. Future offers are
 * never purchasable just by inventing their IDs. A rank's quota never resets. */
export function growthPreparationQuotes(runtime, {shared = false} = {}) {
  if (shared) return [];
  const {Game: game, HeritageSystem: heritage, Progression: progression} = runtime, state = game.state;
  if (!validGrowthSupport(state)) return [];
  const rows = [];
  for (const kind of ['office', 'noble']) {
    const promotion = heritage.promotionQuote(state, kind);
    if (!promotion?.next) continue;
    for (const [jewel, required] of Object.entries(promotion.rule.jewels)) {
      const id = `growth_prepare_${kind}_${promotion.next.id}_${jewel}`, rule = preparationCatalogue().get(id);
      if (!rule) continue;
      const claimed = state.growthSupport?.preparation?.[id] || 0, owned = state.jewels[jewel], remaining = rule.limit - claimed;
      let reason = state.conquered?.camp !== true ? '先占领黄巾营寨，开放晋升筹备' :
        !Number.isSafeInteger(state.copper) || state.copper < 0 || !Number.isSafeInteger(owned) || owned < 0 ? '铜钱或珍宝记录无效' :
        owned >= required ? '本次晋升所需珍宝已备齐' : remaining <= 0 ? '本次晋升的固定筹备份额已用完' :
        state.copper < rule.cost ? `铜钱不足：需要 ${rule.cost}` : '';
      if (owned >= Number.MAX_SAFE_INTEGER) reason = '珍宝数量达到上限';
      rows.push({...rule, name: `${rule.stage}筹备 · ${progression.jewels[jewel].name} ×1`,
        claimed, remaining, period: 'rank', owned, required, missing: Math.max(0, required - owned), reason,
        trial: true, command: {type: 'exchangeCopper', args: [id]}});
    }
  }
  return rows;
}

/** Deterministic, read-only offer. Never initializes a counter or resets daily. */
export function growthSupportQuote(runtime, {shared = false} = {}) {
  const state = runtime.Game.state;
  const valid = validGrowthSupport(state);
  const claimed = valid ? state.growthSupport?.coralExchanged ?? 0 : null;
  let reason = '';
  if (shared) reason = '共享模式不开放县城筹备兑换，请切换本机进度';
  else if (!valid) reason = '县城筹备兑换记录无效';
  else if (state.conquered?.camp !== true) reason = '先占领黄巾营寨，开放县城筹备兑换';
  else if (claimed >= LIMIT) reason = '本存档珊瑚筹备兑换限额已用完（5 枚）';
  else if (!Number.isSafeInteger(state.copper) || state.copper < 0 ||
    !Number.isSafeInteger(state.jewels?.coral) || state.jewels.coral < 0) reason = '铜钱或珊瑚记录无效';
  else if (state.jewels.coral >= Number.MAX_SAFE_INTEGER) reason = '珊瑚数量达到数值上限';
  else if (state.copper < COST) reason = '铜钱不足：需要 80';
  return {id: OFFER_ID, name: '县城筹备 · 珊瑚 ×1', cost: COST, claimed,
    remaining: valid ? LIMIT - claimed : 0, limit: LIMIT, period: 'save', reason,
    command: {type: 'exchangeCopper', args: [OFFER_ID]}};
}

/** Executes only on the private bridge's disposable canonical runtime/CAS candidate. */
export function executeGrowthSupport(runtime, input, now, {shared = false} = {}) {
  validateInput(input);
  if (input.type !== 'exchangeCopper' || input.args.length !== 1 || !isGrowthSupportOffer(input.args[0])) {
    throw new GameError('COMMAND_NOT_ALLOWED', '晋升筹备操作参数无效');
  }
  if (shared) throw new GameError('COMMAND_NOT_ALLOWED', '共享模式不开放阶段筹备兑换');
  if (!Number.isSafeInteger(now) || now < 0) throw new GameError('BAD_TIME', '结算时间无效');
  const game = runtime.Game;
  if (!validGrowthSupport(game.state) || !game.validSave(copy(game.state))) {
    throw new GameError('BAD_SAVE', '晋升筹备兑换无法通过存档校验');
  }
  game.tick(now, true);
  const offer = input.args[0] === OFFER_ID ? growthSupportQuote(runtime) :
    growthPreparationQuotes(runtime).find(row => row.id === input.args[0]);
  if (!offer) throw new GameError('GAME_RULE', '这项筹备不属于当前晋升阶段，请刷新后选择');
  if (offer.reason) throw new GameError('GAME_RULE', offer.reason);
  game.state.copper -= offer.cost;
  const jewel = offer.jewel || 'coral';
  game.state.jewels[jewel] += 1;
  const claimed = offer.claimed + 1;
  // CitySystem's field list excludes this extension, so the single top-level
  // record remains shared by every owned city and survives canonical migration.
  const old = game.state.growthSupport;
  if (offer.id === OFFER_ID) game.state.growthSupport = old?.version === 2 ?
    {...old, coralExchanged: claimed} : {version: 1, coralExchanged: claimed};
  else game.state.growthSupport = {version: 2, coralExchanged: old?.coralExchanged || 0,
    preparation: {...(old?.preparation || {}), [offer.id]: claimed}};
  if (game.save() === false) throw new GameError('SAVE_FAILED', '晋升筹备兑换保存失败', 500);
  if (!validGrowthSupport(game.state) || !game.validSave(game.state)) {
    throw new GameError('INVALID_RESULT', '晋升筹备兑换产生无效状态', 500);
  }
  return {state: copy(game.state), result: {id: offer.id, jewel, count: 1,
    copperSpent: offer.cost, claimed, remaining: offer.limit - claimed}, runtime};
}
