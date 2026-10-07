import {GameError, copy, createGameRuntime} from '../vendor/legacy/online/runtime.mjs';
import {scopedRuntime} from '../vendor/shared/runtime.mjs';
import {scoutQuoteView} from './scouting-view.mjs';

const object = value => !!value && typeof value === 'object' && !Array.isArray(value);
const kinds = new Set(['foundCity', 'transport', 'redeploy', 'march', 'scout']);

/** A quotation runs on a disposable runtime. It never writes a save or receipt. */
export function managementQuote(runtime, input, {shared = false} = {}) {
  if (!object(input) || Object.keys(input).some(key => !['kind', 'args', 'sourceCity', 'requestId'].includes(key)) ||
      !kinds.has(input.kind) || !Array.isArray(input.args) || JSON.stringify(input.args).length > 16000 ||
      typeof input.requestId !== 'string' || !/^[a-zA-Z0-9_-]{1,100}$/.test(input.requestId))
    throw new GameError('BAD_QUOTE', '预览请求无效');
  let g = runtime.Game;
  const args = input.args;
  const text = (value, max = 100) => typeof value === 'string' && value.length <= max;
  if (input.sourceCity !== undefined && !text(input.sourceCity)) throw new GameError('BAD_CITY', '出发城市格式无效');
  const city = input.sourceCity || g.currentCityId();
  if (!Object.hasOwn(g.state.realm.cities, city)) throw new GameError('CITY_NOT_OWNED', '城市不属于你');
  if (input.kind === 'scout') {
    if (shared) throw new GameError('COMMAND_NOT_ALLOWED', '共享演练尚未开放本机侦察');
    if (args.length !== 2 || !text(args[0]) || !Number.isSafeInteger(args[1]) || args[1] < 1 || args[1] > 1000)
      throw new GameError('BAD_QUOTE', '请选择目标和 1–1000 名斥候');
    // Preserve even a caller's disposable runtime when previewing a different source city.
    if (city !== g.currentCityId()) g = createGameRuntime({snapshot: copy(g.state), now: g.state.last}).Game;
  }
  if (city !== g.currentCityId()) g.switchCity(city);
  const counts = (value, keys) => object(value) && Object.entries(value).every(([key, n]) =>
    keys.includes(key) && Number.isSafeInteger(n) && n >= 0);
  let quote;
  if (input.kind === 'scout') {
    if (!g.getNode(args[0])) throw new GameError('NODE_NOT_FOUND', '目标不存在', 404);
    if (!g.landmarkVisible(args[0])) throw new GameError('NODE_HIDDEN', '请先完成当前任务据点', 403);
    const q = g.scoutQuote(...args);
    if (!q) throw new GameError('BAD_QUOTE', '侦察条件无效');
    quote = {...scoutQuoteView(q), sourceCity: city, reason: q.reason || '',
      command: {type: 'dispatchScout', args: [...args, q.key], sourceCity: city}};
  } else if (input.kind === 'foundCity') {
    if (shared) throw new GameError('COMMAND_NOT_ALLOWED', '共享演练尚未开放野地建城');
    if (args.length !== 2 || !text(args[0]) || !text(args[1], 12)) throw new GameError('BAD_QUOTE', '请选择野地和城名');
    const q = g.foundCityQuote(...args);
    quote = {name: q.name, cost: copy(q.cost), reason: q.reason || '', key: q.key,
      command: {type: 'foundCity', args: [...args, q.key], sourceCity: city}};
  } else if (input.kind === 'transport' || input.kind === 'redeploy') {
    const transport = input.kind === 'transport';
    if (args.length !== (transport ? 4 : 3) || !text(args[0]) ||
        !counts(args[1], Object.keys(g.units)) || !text(args.at(-1)) ||
        transport && !counts(args[2], Object.keys(g.resources))) throw new GameError('BAD_QUOTE', '运输或调遣参数无效');
    const q = transport ? g.transportQuote(...args) : g.redeployQuote(...args);
    quote = {...copy(q), reason: q.reason || '', command: {type: transport ? 'sendTransport' : 'redeployArmy',
      args: [...args, q.key], sourceCity: city}};
  } else {
    if (shared) throw new GameError('COMMAND_NOT_ALLOWED', '共享演练请使用玩家战争出征');
    if (args.length !== 5 || !text(args[0]) || !text(args[1]) || !counts(args[2], Object.keys(g.units)) ||
        !['raid', 'occupy'].includes(args[3]) || typeof args[4] !== 'boolean') throw new GameError('BAD_QUOTE', '出征参数无效');
    if (!g.getNode(args[0])) throw new GameError('NODE_NOT_FOUND', '目标不存在', 404);
    if (!g.landmarkVisible(args[0])) throw new GameError('NODE_HIDDEN', '请先完成当前任务据点', 403);
    const q = g.marchQuote(args[0], args[2], args[1]), before = g.state.res.food;
    // dispatch supplies the complete eligibility and fee; the mutated clone is discarded.
    const reason = g.dispatch(...args) || '';
    quote = {...copy(q), reason, foodCost: reason ? null : before - g.state.res.food,
      carry: g.carry(args[2]), command: {type: 'dispatch', args: copy(args), sourceCity: city}};
  }
  return {requestId: input.requestId, kind: input.kind, sourceCity: city, quote};
}

export function sharedManagementQuote(context, actor, input) {
  const row = context.players.find(player => player.id === actor);
  if (!row) throw new GameError('NOT_JOINED', '账号尚未加入房间', 404);
  const runtime = scopedRuntime(row.state, context.serverTime, context.marches, actor);
  return {...managementQuote(runtime, input, {shared: true}), revision: row.revision, serverTime: context.serverTime};
}
