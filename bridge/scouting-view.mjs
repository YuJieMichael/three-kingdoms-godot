import {copy} from '../vendor/legacy/online/runtime.mjs';

const object = value => !!value && typeof value === 'object' && !Array.isArray(value);
const integer = value => Number.isSafeInteger(value) && value >= 0;
const precisions = ['failed', 'types', 'bands', 'exact'];
const point = value => ({x: value?.x ?? 32, y: value?.y ?? 32});
const visible = (game, node) => !!node && (node.id === 'home' || game.landmarkVisible(node.id));
const blank = () => ({precision: 'unknown', at: null, expiresAt: null, army: {}, bands: {}, types: [],
  success: null, lost: null, survivors: null, legacy: false, public: false});
const army = (game, value) => object(value) ? Object.fromEntries(Object.entries(value)
  .filter(([id, count]) => Object.hasOwn(game.units, id) && integer(count))) : {};

/** Current-city modern intelligence plus the canonical global legacy fallback. */
export function intelView(game, node, now = game.state.last, {shared = false} = {}) {
  const result = blank();
  if (!visible(game, node) || node.id === 'home') return result;
  const canonical = game.intel(node.id);
  if (canonical?.public) return {...result, precision: 'public', public: true, success: true,
    army: army(game, node.army), types: Object.keys(army(game, node.army)).filter(id => node.army[id] > 0)};
  if (shared) return result;
  const report = game.state.scoutIntel?.[node.id];
  if (object(report) && report.success === true && report.expiresAt > now &&
      integer(report.quality) && report.quality >= 1 && report.quality <= 3) {
    const precision = precisions[report.quality];
    const types = Array.isArray(report.types) ? report.types.filter(id => Object.hasOwn(game.units, id)) : [];
    const bands = precision === 'bands' && object(report.bands) ? Object.fromEntries(types.flatMap(id => {
      const band = report.bands[id];
      return object(band) && integer(band.min) && integer(band.max) && band.max >= band.min ?
        [[id, {min: band.min, max: band.max}]] : [];
    })) : {};
    return {...result, precision, at: report.at, expiresAt: report.expiresAt, success: true,
      lost: integer(report.lost) ? report.lost : null, survivors: integer(report.survivors) ? report.survivors : null,
      types: [...new Set(types)], bands, army: precision === 'exact' ? army(game, report.army) : {}};
  }
  // The canonical old scouted table is global, with no source-city evidence.
  // Keep its legitimate fallback after a failed modern scout, without inventing modern precision or numbers.
  const legacy = game.state.scouted?.[node.id];
  const legacyExpiry = object(legacy) && integer(legacy.at) && integer(legacy.level) ?
    legacy.at + (15 + legacy.level * 5) * 60000 : null;
  if (legacyExpiry !== null && legacyExpiry > now) return {...result, precision: 'legacy', legacy: true,
    at: legacy.at, expiresAt: legacyExpiry};
  if (object(report)) return {...result, precision: report.expiresAt <= now ? 'expired' : 'failed',
    at: integer(report.at) ? report.at : null, expiresAt: integer(report.expiresAt) ? report.expiresAt : null,
    success: typeof report.success === 'boolean' ? report.success : null,
    lost: integer(report.lost) ? report.lost : null, survivors: integer(report.survivors) ? report.survivors : null};
  if (legacyExpiry !== null) return {...result, precision: 'expired', legacy: true,
    at: legacy.at, expiresAt: legacyExpiry};
  return result;
}

/** Selected-city reports, source-unknown legacy entries, and already-public chapter targets. */
export function scoutingView(game, now = game.state.last, {shared = false} = {}) {
  const supported = !shared && typeof game.scoutQuote === 'function';
  if (!supported) return {supported: false, available: 0, queueUsed: 0, queueLimit: 0, intelByNode: {}};
  const ids = new Set(Object.keys(game.state.scoutIntel || {}));
  for (const id of Object.keys(game.state.scouted || {})) ids.add(id);
  for (const node of game.nodes) if (visible(game, node) && game.intel(node.id)?.public) ids.add(node.id);
  const intelByNode = {};
  for (const id of ids) {
    const node = game.getNode(id);
    if (!visible(game, node)) continue;
    intelByNode[id] = intelView(game, node, now);
  }
  const target = game.nodes.find(node => visible(game, node) && node.id !== 'home');
  const quote = target ? game.scoutQuote(target.id, 1) : null;
  return {supported, available: game.state.army.scout || 0,
    queueUsed: (game.state.scoutQueue || []).length, queueLimit: quote?.queueLimit ?? 0, intelByNode};
}

/** A queue carries private enemy snapshots. Expose only routing and the player's own settled counts. */
export function scoutMarchesView(game, now = game.state.last, {shared = false} = {}) {
  if (shared) return [];
  const rows = [];
  for (const city of game.cityList()) for (const march of city.scoutQueue || []) {
    const node = game.getNode(march.node);
    if (!visible(game, node)) continue;
    const returning = march.phase === 'return';
    const lost = returning && integer(march.outcome?.lost) ? march.outcome.lost : null;
    const survivors = returning && integer(march.outcome?.survivors) ? march.outcome.survivors : null;
    rows.push({id: `scout:${city.id}:${march.id}`, type: 'scout', node: node.id, label: `斥候 · ${node.name}`,
      sourceCity: city.id, from: point(returning ? march.target : march.origin),
      to: point(returning ? march.origin : march.target), start: march.start, arrive: march.end,
      status: returning ? 'return' : 'march', remainingMs: Math.max(0, march.end - now),
      sentCount: march.scouts, count: returning ? survivors : march.scouts, lost, survivors,
      canStartBattle: false});
  }
  return rows;
}

/** Restrict previews to the original quote's presentation fields, including the stale-quote key. */
export function scoutQuoteView(quote) {
  const keys = ['node', 'name', 'count', 'scouts', 'origin', 'target', 'distance', 'seconds', 'returnSeconds',
    'cost', 'queueLimit', 'counterLevel', 'tech', 'ttlMs', 'quality', 'precision', 'success', 'expectedLost', 'reason', 'key'];
  return Object.fromEntries(keys.filter(key => Object.hasOwn(quote, key)).map(key => [key, copy(quote[key])]));
}
