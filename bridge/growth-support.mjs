import {copy, GameError, validateInput} from '../vendor/legacy/online/runtime.mjs';

const OFFER_ID = 'growth_coral';
const COST = 80;
const LIMIT = 5;
const object = value => !!value && typeof value === 'object' && !Array.isArray(value);

/** Optional save-wide extension; old canonical saves do not need migration. */
export function validGrowthSupport(snapshot) {
  if (!object(snapshot)) return false;
  if (!Object.hasOwn(snapshot, 'growthSupport')) return true;
  const record = snapshot.growthSupport;
  return object(record) && Object.keys(record).length === 2 &&
    Object.hasOwn(record, 'version') && Object.hasOwn(record, 'coralExchanged') &&
    record.version === 1 && Number.isSafeInteger(record.coralExchanged) &&
    record.coralExchanged >= 0 && record.coralExchanged <= LIMIT;
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
  if (input.type !== 'exchangeCopper' || input.args.length !== 1 || input.args[0] !== OFFER_ID) {
    throw new GameError('COMMAND_NOT_ALLOWED', '县城筹备操作参数无效');
  }
  if (shared) throw new GameError('COMMAND_NOT_ALLOWED', '共享模式不开放县城筹备兑换');
  if (!Number.isSafeInteger(now) || now < 0) throw new GameError('BAD_TIME', '结算时间无效');
  const game = runtime.Game;
  if (!validGrowthSupport(game.state) || !game.validSave(copy(game.state))) {
    throw new GameError('BAD_SAVE', '县城筹备兑换无法通过存档校验');
  }
  game.tick(now, true);
  const offer = growthSupportQuote(runtime);
  if (offer.reason) throw new GameError('GAME_RULE', offer.reason);
  game.state.copper -= COST;
  game.state.jewels.coral += 1;
  const claimed = offer.claimed + 1;
  // CitySystem's field list excludes this extension, so the single top-level
  // record remains shared by every owned city and survives canonical migration.
  game.state.growthSupport = {version: 1, coralExchanged: claimed};
  if (game.save() === false) throw new GameError('SAVE_FAILED', '县城筹备兑换保存失败', 500);
  if (!validGrowthSupport(game.state) || !game.validSave(game.state)) {
    throw new GameError('INVALID_RESULT', '县城筹备兑换产生无效状态', 500);
  }
  return {state: copy(game.state), result: {id: OFFER_ID, jewel: 'coral', count: 1,
    copperSpent: COST, claimed, remaining: LIMIT - claimed}, runtime};
}
