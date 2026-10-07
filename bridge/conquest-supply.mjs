import {randomInt} from 'node:crypto';
import {copy, createGameRuntime, GameError, validateInput} from '../vendor/legacy/online/runtime.mjs';
import {CONQUEST_BUNDLES, conquestGems} from './conquest-supply-data.mjs';
import {grantEarnedSupplyBundle} from './supply-workshop.mjs';

const object = value => !!value && typeof value === 'object' && !Array.isArray(value);
const int = value => Number.isSafeInteger(value) && value >= 0;
let metadata;
function catalogue() {
  if (metadata) return metadata;
  const {Game: game} = createGameRuntime({now: Date.UTC(2026, 0, 1), random: () => 0.5});
  const nodes = new Map(game.nodes.map(node => [node.id, game.isCity(node) ? 'city' : 'wild']));
  const pool = game.manual.shop.filter(item => item.effect && !item.rewardOnly).map(item => ({
    kind: 'item', id: item.id, name: item.name, weight: item.price >= 100 ? 1 : 8}));
  pool.push(...Object.entries(CONQUEST_BUNDLES).map(([id, name]) => ({kind: 'bundle', id, name, weight: id === 'supply_siege' ? 3 : 8})));
  metadata = {nodes, pool};
  return metadata;
}

function nodeKind(id) {
  const wild = /^wild_(\d+)_(\d+)$/.exec(id);
  if (wild) return Number(wild[1]) < 64 && Number(wild[2]) < 64 && `wild_${Number(wild[1])}_${Number(wild[2])}` === id ? 'wild' : null;
  return catalogue().nodes.get(id) || null;
}
function empty() { return {version: 1, enabled: false, records: {}}; }
function availablePool(game) {
  return catalogue().pool.filter(drop => drop.kind === 'bundle' || (game.state.inventory[drop.id] || 0) < Number.MAX_SAFE_INTEGER);
}
export function validConquestSupply(state) {
  if (!object(state)) return false;
  if (!Object.hasOwn(state, 'conquestSupply')) return true;
  const r = state.conquestSupply;
  if (!object(r) || Object.keys(r).length !== 3 || r.version !== 1 || typeof r.enabled !== 'boolean' || !object(r.records)) return false;
  const rows = Object.entries(r.records), {nodes, pool} = catalogue();
  if (rows.length > 4096 + nodes.size) return false;
  return rows.every(([id, row]) => object(row) && Object.keys(row).length === 7 && ['wild', 'city'].includes(row.kind) && nodeKind(id) === row.kind &&
    ['baseline', 'disabled', 'rewarded'].includes(row.status) && int(row.level) && row.level >= 1 && row.level <= 10 && int(row.at) &&
    typeof row.sourceCity === 'string' && row.sourceCity.length <= 100 && int(row.gems) &&
    (row.status === 'rewarded' ? row.gems <= conquestGems(row.kind, row.level) && !!row.sourceCity &&
      object(row.drop) && Object.keys(row.drop).length === 2 && pool.some(drop => drop.kind === row.drop.kind && drop.id === row.drop.id) : row.gems === 0 && row.drop === null));
}

export function conquestNodeQuote(game, node, mode = 'occupy') {
  const kind = nodeKind(node.id), enabled = game.state.conquestSupply?.enabled === true;
  const first = !!kind && !game.state.conquestSupply?.records[node.id] && !game.state.conquered[node.id];
  return {enabled, eligible: !!kind && mode === 'occupy', first,
    gems: kind ? conquestGems(kind, Math.max(1, Math.min(10, node.level || 1))) : 0,
    reason: !enabled ? '征战补给模式尚未开启' : !kind || mode !== 'occupy' ? '额外补给用于野地／据点与城池占领' :
      !first ? '此地点的首次占领份额已处理，重占不再发放' : '真正占领后自动获得元宝与随机商城道具 ×1'};
}

export function conquestSupplyView(runtime, {shared = false} = {}) {
  const game = runtime.Game, r = game.state.conquestSupply || empty(), pool = availablePool(game);
  const totalWeight = pool.reduce((n, row) => n + row.weight, 0);
  const rewarded = Object.entries(r.records).filter(([, row]) => row.status === 'rewarded');
  return {shared, enabled: !shared && r.enabled, reason: shared ? '征战补给模式用于本机PVE进度' : '',
    earnedGems: rewarded.reduce((n, [, row]) => n + row.gems, 0), rewarded: rewarded.length,
    history: shared ? [] : rewarded.sort((a, b) => b[1].at - a[1].at).slice(0, 8).map(([id, row]) => ({
      node: id, name: game.getNode(id)?.name || id, kind: row.kind, gems: row.gems, at: row.at,
      itemName: catalogue().pool.find(drop => drop.kind === row.drop.kind && drop.id === row.drop.id).name})),
    pool: shared ? [] : pool.map(row => ({id: row.id, kind: row.kind, name: row.name, percent: 100 * row.weight / totalWeight})),
    command: {type: 'conquest.setEnabled', args: [!r.enabled]}};
}

export function executeConquestSetting(runtime, input, now) {
  validateInput(input);
  if (input.type !== 'conquest.setEnabled' || input.args.length !== 1 || typeof input.args[0] !== 'boolean')
    throw new GameError('BAD_CONQUEST_MODE', '请选择开启或暂停征战补给模式');
  const game = runtime.Game;
  game.tick(now, true);
  const r = copy(game.state.conquestSupply || empty());
  // Initial opt-in never pays retroactive prizes for already-owned/imported land.
  for (const id of Object.keys(game.state.conquered)) {
    if (!game.state.conquered[id] || r.records[id] || !nodeKind(id)) continue;
    const node = game.getNode(id);
    if (node) r.records[id] = {status: 'baseline', kind: nodeKind(id), level: Math.max(1, Math.min(10, node.level || 1)),
      at: now, sourceCity: '', gems: 0, drop: null};
  }
  r.enabled = input.args[0]; game.state.conquestSupply = r;
  if (!validConquestSupply(game.state) || !game.validSave(game.state) || game.save() === false)
    throw new GameError('INVALID_RESULT', '征战补给设置无法通过存档校验');
  return {runtime, state: copy(game.state), result: {enabled: r.enabled}};
}

/** Capture only a real player-issued occupancy round, before native settlement. */
export function captureConquestContext(game, input) {
  const b = game.state.battle;
  if (input.type !== 'battleRound' || !game.state.conquestSupply || !b || b.finished || b.mode !== 'occupy' ||
      game.state.expedition?.node !== b.node || game.state.expedition?.general !== b.general || !nodeKind(b.node)) return null;
  if (game.state.expedition.sourceCity && game.state.expedition.sourceCity !== game.currentCityId()) return null;
  return {battle: b, node: b.node, general: b.general, sourceCity: game.currentCityId(), already: !!game.state.conquered[b.node]};
}

/** Supplemental reward only after actual ownership changes. Same CAS/receipt as the battle. */
export function settleConquestSupply(runtime, context, now) {
  if (!context) return null;
  const game = runtime.Game, b = game.state.battle, result = b?.result, node = game.getNode(context.node);
  if (b !== context.battle || !b.finished || b.node !== context.node || b.general !== context.general || context.already ||
      !result?.won || result.mode !== 'occupy' || result.claimed !== true || !game.state.conquered[context.node] ||
      game.currentCityId() !== context.sourceCity || game.state.conquestSupply.records[context.node]) return null;
  if (node.wild && game.state.realm.wildOwners[context.node] !== context.sourceCity ||
      game.isCity(node) && !game.cityList().some(city => city.node === context.node)) return null;
  const report = game.state.reports[0];
  if (!report || report.node !== context.node || report.general !== context.general || report.sourceCity !== context.sourceCity ||
      !int(report.id) || report.won !== true || report.claimed !== true || report.mode !== 'occupy') return null;
  const r = game.state.conquestSupply, kind = nodeKind(context.node), level = Math.max(1, Math.min(10, node.level || 1));
  const row = {status: r.enabled ? 'rewarded' : 'disabled', kind, level, at: report.id, sourceCity: context.sourceCity, gems: 0, drop: null};
  r.records[context.node] = row;
  if (r.enabled) {
    const pool = availablePool(game);
    let pick = randomInt(pool.reduce((n, drop) => n + drop.weight, 0));
    const chosen = pool.find(drop => (pick -= drop.weight) < 0);
    row.drop = {kind: chosen.kind, id: chosen.id};
    row.gems = Math.min(conquestGems(kind, level), Number.MAX_SAFE_INTEGER - game.state.gems);
    game.state.gems += row.gems;
    if (chosen.kind === 'bundle') grantEarnedSupplyBundle(game, chosen.id);
    else game.state.inventory[chosen.id] = (game.state.inventory[chosen.id] || 0) + 1;
  }
  if (!validConquestSupply(game.state) || !game.validSave(game.state) || game.save() === false)
    throw new GameError('INVALID_RESULT', '占领补给无法通过存档校验');
  return row.status === 'rewarded' ? conquestReportReceipt(runtime, report) : null;
}

export function conquestReportReceipt(runtime, report) {
  const row = runtime.Game.state.conquestSupply?.records[report.node];
  if (!row || row.status !== 'rewarded' || row.at !== report.id || row.sourceCity !== report.sourceCity ||
      report.won !== true || report.claimed !== true || report.mode !== 'occupy') return null;
  const drop = catalogue().pool.find(value => value.kind === row.drop.kind && value.id === row.drop.id);
  return {node: report.node, gems: row.gems, item: {...copy(row.drop), name: drop.name, count: 1}};
}
