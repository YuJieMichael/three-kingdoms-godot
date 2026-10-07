import crypto from 'node:crypto';
import {copy, createGameRuntime, GameError, seededRandom} from '../vendor/legacy/online/runtime.mjs';
import {createRoundEvidence, collectRoundEvidence, battleReview} from './battle-review.mjs';

const MAX_SESSIONS = 4;
const IDLE_MS = 20 * 60 * 1000;
const MAX_RECEIPTS = 128;
const requestKey = value => typeof value === 'string' && /^[a-zA-Z0-9_-]{8,100}$/.test(value);
const sessionKey = value => typeof value === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value);
const object = value => !!value && typeof value === 'object' && !Array.isArray(value);
const orders = new Set(['advance', 'hold', 'fallback']);
const SCENARIOS = Object.freeze({
  shield_archer: {
    id: 'shield_archer', title: '刀盾护弓 · 推进与固守', node: 'field', mode: 'raid', seed: 1101,
    description: '独立借调演练：我方24刀盾、30弓箭手，练习敌军18义兵、8长枪、12弓箭手。编制为固定试玩设置，兵种属性和回合动作使用原规则。',
    objective: '推进刀盾承担接触，弓兵进入射程后固守；观察真实攻击对象、射程和伤亡。',
    army: {shield: 24, archer: 30}, enemy: {militia: 18, spear: 8, archer: 12},
    initialOrders: {shield: 'advance', archer: 'hold'},
  },
  spear_cavalry: {
    id: 'spear_cavalry', title: '长枪抗骑 · 保护弓阵', node: 'field', mode: 'raid', seed: 1102,
    description: '独立借调演练：我方30长枪、18弓箭手，练习敌军18轻骑、8弓箭手。编制为固定试玩设置，克制、移动和伤害由原规则结算。',
    objective: '让长枪接触轻骑，调整弓阵位置与目标；观察枪对骑与骑对弓的实际克制。',
    army: {spear: 30, archer: 18}, enemy: {cavalry: 18, archer: 8},
    initialOrders: {spear: 'advance', archer: 'hold'},
  },
  siege_guard: {
    id: 'siege_guard', title: '护卫器械 · 河洛东门', node: 'luo_gate', mode: 'occupy', seed: 1103,
    description: '独立借调演练：我方450刀盾、240长枪、420弓箭手、12冲车、2投石车。使用原第三章河洛东门守军与18000耐久包铁城门；门墙、箭楼和破门规则保留。借调编制为试玩设置，未完成正式章节也可进入此隔离练习。',
    objective: '推进护卫和冲车，选择城门目标；先破真实城门再清守军，观察箭楼、器械伤亡与破门回合。',
    army: {shield: 450, spear: 240, archer: 420, ram: 12, catapult: 2},
    initialOrders: {shield: 'advance', spear: 'advance', archer: 'advance', ram: 'advance', catapult: 'advance'},
  },
});

const stable = value => Array.isArray(value) ? value.map(stable) : object(value) ?
  Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])])) : value;
const fingerprint = input => JSON.stringify(stable(input));
const safeTime = now => {
  if (!Number.isSafeInteger(now) || now < 1 || now > Number.MAX_SAFE_INTEGER - IDLE_MS)
    throw new GameError('BAD_TIME', '演练服务时间无效');
  return now;
};

function validateRequest(input) {
  if (!object(input) || !requestKey(input.requestId) || !['start', 'order', 'round', 'end', 'sync'].includes(input.action))
    throw new GameError('BAD_PRACTICE_REQUEST', '演练请求编号或动作无效');
  const allowed = input.action === 'start' ? ['requestId', 'action', 'sessionId', 'revision', 'scenario'] :
    ['end', 'sync'].includes(input.action) ? ['requestId', 'action', 'sessionId', 'revision'] :
      ['requestId', 'action', 'sessionId', 'revision', 'type', 'args'];
  if (Object.keys(input).some(key => !allowed.includes(key)))
    throw new GameError('BAD_PRACTICE_REQUEST', '演练请求含不支持的字段，不能导入存档或资源');
  const hasSession = Object.hasOwn(input, 'sessionId'), hasRevision = Object.hasOwn(input, 'revision');
  if (hasSession !== hasRevision || input.action !== 'start' && !hasSession ||
      hasSession && (!sessionKey(input.sessionId) || !Number.isSafeInteger(input.revision) || input.revision < 0))
    throw new GameError('BAD_PRACTICE_REVISION', '请选择有效演练会话及版本');
  if (input.action === 'start') {
    if (typeof input.scenario !== 'string' || !Object.hasOwn(SCENARIOS, input.scenario))
      throw new GameError('BAD_PRACTICE_SCENARIO', '请选择刀盾护弓、长枪抗骑或器械破门演练');
  } else if (input.action === 'round') {
    if (input.type !== undefined && input.type !== 'battleRound' ||
        input.args !== undefined && (!Array.isArray(input.args) || input.args.length !== 0))
      throw new GameError('BAD_PRACTICE_ACTION', '下一回合参数无效');
  } else if (input.action === 'order') {
    const args = input.args;
    if (!Array.isArray(args) || !['setBattleOrders', 'setBattleOrder'].includes(input.type))
      throw new GameError('BAD_PRACTICE_ACTION', '演练只支持兵队军令与下一回合');
    if (input.type === 'setBattleOrders' ? args.length !== 1 || !orders.has(args[0]) :
        ![2, 3].includes(args.length) || typeof args[0] !== 'string' || args[0].length > 40 ||
        !orders.has(args[1]) || args.length === 3 && (typeof args[2] !== 'string' || args[2].length > 40))
      throw new GameError('BAD_PRACTICE_ACTION', '演练军令或目标参数无效');
  }
  return input;
}

function assertCanonical(game) {
  if (game.save() === false || !game.validSave(game.state))
    throw new GameError('INVALID_PRACTICE_STATE', '借调演练无法通过原规则校验，正式存档未改变', 500);
}

/** Prepared borrowed scenario in an entirely new canonical runtime, never a player clone. */
function prepareScenario(scenario, now) {
  const runtime = createGameRuntime({now, random: seededRandom(scenario.seed)}), game = runtime.Game, state = game.state;
  const site = state.cityLayout.indexOf(null);
  if (site < 0) throw new GameError('PRACTICE_UNAVAILABLE', '演练校场预置失败', 500);
  state.cityLayout[site] = 'drill'; state.cityLevels[site] = 1; state.buildings.drill = 1;
  const army = Object.fromEntries(Object.keys(game.units).map(id => [id, scenario.army[id] || 0]));
  for (const [id, count] of Object.entries(army)) state.army[id] = count;
  for (const [id, command] of Object.entries(scenario.initialOrders)) state.tactics[id].command = command;
  if (scenario.mode === 'occupy') {
    // This temporary progression opens the ACTUAL gate node. Neither fort nor
    // any other node is renamed into a gate or assigned a fabricated wall.
    state.conquered.fort = true;
    for (const node of runtime.ChapterData.chapterNodes(2)) state.conquered[node.id] = true;
    state.conquered.luo_outpost = true;
  }
  assertCanonical(game);
  if (!game.landmarkVisible(scenario.node) || game.attackBlocked(scenario.node, scenario.mode))
    throw new GameError('PRACTICE_UNAVAILABLE', '演练目标未按原章节规则开放', 500);
  const node = game.getNode(scenario.node);
  if (scenario.mode === 'occupy' && (!node.fortification || node.fortification.hp !== 18000 || node.id !== 'luo_gate'))
    throw new GameError('PRACTICE_UNAVAILABLE', '河洛东门规则已变化，请更新演练预置', 500);
  const dispatchError = game.dispatch(scenario.node, 'lin', army, scenario.mode, true);
  if (dispatchError) throw new GameError('PRACTICE_UNAVAILABLE', '借调队伍不能按原规则出征：' + dispatchError, 500);
  // The drill begins at arrival. These timestamps affect only the borrowed
  // temporary expedition, not any real route or the player's rule clock.
  state.expedition.start = now - 1; state.expedition.end = now;
  if (scenario.enemy) state.expedition.enemySnapshot = copy(scenario.enemy);
  assertCanonical(game);
  const startError = game.startBattle();
  if (startError) throw new GameError('PRACTICE_UNAVAILABLE', '借调交战无法开始：' + startError, 500);
  state.battle.auto = false;
  if (state.battle.rules !== 2 || scenario.mode === 'occupy' && state.battle.gate?.maxHp !== 18000)
    throw new GameError('PRACTICE_UNAVAILABLE', '演练回合或城门规则不匹配', 500);
  assertCanonical(game);
  return copy(state);
}

function practiceResult(battle) {
  if (!battle.finished) return null;
  const receipt = battle.result || {};
  return {practice: true, won: !!receipt.won, round: battle.round,
    lost: copy(receipt.lost || {}), wounded: copy(receipt.wounded || {}), back: copy(receipt.back || {}),
    xp: 0, failure: copy(receipt.failure || null),
    summary: '借调演练结束：本次损失、伤兵、缴获、经验与占领结果均不进入正式城池。'};
}

function practiceView(session) {
  const {state, scenario} = session, battle = copy(state.battle), result = practiceResult(battle);
  battle.nodeName = scenario.title + ' · 借调演练';
  battle.result = result;
  if (battle.finished) {
    // Canonical settlement happened only in disposable RAM. Do not describe
    // its temporary receipts as the player's real inventory or return march.
    battle.log = battle.log.filter(line => !/(战利品|入库|返城|招降|缴获|收容俘虏|负重|声望|军功|资源|装备|珍珠|黄金|幸存部队|领地归属|占领成功|攻城获胜|俘获将领|释放将领)/.test(line));
    battle.log.push(result.summary);
  }
  return {sessionId: session.id, revision: session.revision, scenario: scenario.id,
    title: scenario.title, description: scenario.description,
    objective: scenario.objective, borrowed: true, rewardPolicy: 'none',
    battle, units: copy(session.units), result,
    review: battleReview(result || {}, {battle: state.battle, evidence: session.evidence, practice: true})};
}

/** Small authenticated-bridge-local RAM store. No file storage and no player-state arguments. */
export class PracticeSessions {
  constructor() { this.sessions = new Map(); this.receipts = new Map(); }

  clear() { this.sessions.clear(); this.receipts.clear(); }

  cleanup(now) {
    for (const [id, session] of this.sessions) if (session.expiresAt <= now) this.sessions.delete(id);
    for (const [id, receipt] of this.receipts) if (receipt.expiresAt <= now) this.receipts.delete(id);
  }

  execute(input, now, authorityId) {
    safeTime(now); validateRequest(input); this.cleanup(now);
    const key = fingerprint(input), receipt = this.receipts.get(input.requestId);
    if (receipt) {
      if (receipt.fingerprint !== key) throw new GameError('PRACTICE_ID_REUSED', '同一演练请求编号不能用于其他参数', 409);
      return {...copy(receipt.response), replayed: true};
    }
    let session = input.sessionId ? this.sessions.get(input.sessionId) : null;
    if (input.sessionId && !session) throw new GameError('PRACTICE_EXPIRED', '演练已结束或过期，请重新选择借调场景', 409);
    if (session && input.action !== 'sync' && input.revision !== session.revision)
      throw new GameError('PRACTICE_REVISION_CONFLICT', '演练已更新，请使用当前演练版本', 409);
    if (session && input.action !== 'sync' && session.revision >= Number.MAX_SAFE_INTEGER)
      throw new GameError('PRACTICE_REVISION_LIMIT', '演练版本达到上限，请结束后重开', 409);
    let value = null;
    if (input.action === 'start') {
      if (!session && this.sessions.size >= MAX_SESSIONS)
        throw new GameError('PRACTICE_LIMIT', '最多同时保留4个借调演练，请先结束已有演练', 409);
      const scenario = SCENARIOS[input.scenario], state = prepareScenario(scenario, now);
      const metadata = createGameRuntime({snapshot: state, now, random: seededRandom(scenario.seed)}).Game;
      const units = Object.fromEntries(Object.entries(metadata.units).map(([id, unit]) =>
        [id, {name: unit.name, role: unit.role || '', ...copy(metadata.unitStats(id))}]));
      session = {id: session?.id || crypto.randomUUID(), revision: session ? session.revision + 1 : 0,
        scenario, state, units, evidence: createRoundEvidence(), expiresAt: now + IDLE_MS};
      value = practiceView(session);
      this.sessions.set(session.id, session);
    } else if (input.action === 'sync') {
      // Read the live RAM session after a known revision conflict. Snapshot,
      // revision and round evidence stay unchanged; no runtime is reconstructed.
      value = practiceView(session);
      session.expiresAt = now + IDLE_MS;
    } else if (input.action === 'end') {
      this.sessions.delete(session.id);
    } else {
      if (session.state.battle.finished) throw new GameError('PRACTICE_FINISHED', '演练已经结算，可重开比较另一组指令', 409);
      // Every command runs against an isolated candidate. Failed validation or
      // review leaves the previous practice snapshot and player save untouched.
      // Borrowed scenarios replay a fixed round sequence. Extra order edits
      // increment the CAS revision but must not change the next round's RNG.
      const runtime = createGameRuntime({snapshot: session.state, now, random: seededRandom(session.scenario.seed + session.state.battle.round)});
      const game = runtime.Game, type = input.action === 'round' ? 'battleRound' : input.type;
      const result = game[type](...(input.args || []));
      if (typeof result === 'string' && result || result?.error) throw new GameError('PRACTICE_RULE', typeof result === 'string' ? result : result.error);
      assertCanonical(game);
      const evidence = copy(session.evidence);
      if (input.action === 'round') collectRoundEvidence(game.state.battle.currentRoundSummary, evidence, {battle: game.state.battle});
      const candidate = {...session, revision: session.revision + 1, state: copy(game.state), evidence, expiresAt: now + IDLE_MS};
      value = practiceView(candidate);
      this.sessions.set(candidate.id, candidate);
    }
    const response = {ok: true, requestId: input.requestId, authorityId, serverTime: now, practice: value};
    this.receipts.set(input.requestId, {fingerprint: key, response: copy(response), expiresAt: now + IDLE_MS});
    while (this.receipts.size > MAX_RECEIPTS) this.receipts.delete(this.receipts.keys().next().value);
    return response;
  }
}
