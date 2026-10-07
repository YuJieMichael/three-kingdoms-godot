import {intelView} from './scouting-view.mjs';

const RESOURCE_IDS = ['food', 'wood', 'stone', 'iron', 'gold'];
const NEARBY_RADIUS = 8;
const LIST_LIMIT = 5;
const positive = value => Number.isFinite(value) && value > 0;
const amount = value => Number.isFinite(value) && value >= 0 ? value : 0;
const resourcesOnly = value => Object.fromEntries(RESOURCE_IDS.map(id => [id, amount(value?.[id])]));

/**
 * Current owned city, read-only. Unknown wild-land loot encodes guard value in
 * the canonical generator: never project or rank those amounts without public
 * or live exact intelligence. No commands, ticks, saves, forecasts or win odds.
 */
export function raidTargetsView(game, growth = {}, options = {}) {
  const now = options.now ?? game.state.last;
  const emptyLists = () => Object.fromEntries(RESOURCE_IDS.map(id => [id, []]));
  if (options.shared) return {supported: false, sourceCity: null, defaultResource: 'food', resources: [],
    lists: emptyLists(), referenceArmy: null, notes: ['共享房间尚未开放私人野地掠夺推荐。']};

  const state = game.state, home = game.currentHome();
  const gaps = Array.isArray(growth.gaps) ? growth.gaps : [];
  const resourceRows = RESOURCE_IDS.map(id => ({id, name: game.resources[id].name,
    gap: amount(gaps.find(row => row?.id === 'resource:' + id)?.missing)}));
  const defaultResource = resourceRows.find(row => row.gap > 0)?.id || 'food';
  const army = Object.fromEntries(Object.keys(game.units).map(id => [id,
    Number.isSafeInteger(state.army[id]) && state.army[id] >= 0 ? state.army[id] : 0]));
  const armyCount = game.totalArmy(army), limit = game.armyLimit();
  const withinLimit = armyCount > 0 && armyCount <= limit;
  const referenceArmy = {count: armyCount, limit, capacity: game.carry(army), withinLimit,
    reason: !armyCount ? '城内没有可参考的兵力，先训练部队再核对运力。' :
      !withinLimit ? '城内全部兵力超过单队人数上限，收益仅显示目标基础物资；请在配兵页面选择合法队伍。' :
        '参考运力使用城内全部兵力，假设战斗获胜且全部兵力幸存；正式出征请重新配兵预览。'};
  const candidates = new Map(), ownedCoordinates = new Set(game.cityList().map(city => `${city.x}:${city.y}`));
  const add = node => {
    if (!node || node.id === 'home' || ownedCoordinates.has(`${node.x}:${node.y}`) ||
        !game.landmarkVisible(node.id) || game.attackBlocked(node.id, 'raid') ||
        state.conquered[node.id] && (node.wild || game.isCity(node)) ||
        state.cooldowns[node.id] > now || candidates.has(node.id)) return;
    candidates.set(node.id, node);
  };
  // Bounded local search avoids scanning all 4096 fields on every view refresh.
  for (let y = Math.max(0, home.y - NEARBY_RADIUS); y <= Math.min(game.WORLD_SIZE - 1, home.y + NEARBY_RADIUS); y++) {
    for (let x = Math.max(0, home.x - NEARBY_RADIUS); x <= Math.min(game.WORLD_SIZE - 1, home.x + NEARBY_RADIUS); x++) add(game.getWorldTile(x, y));
  }
  // Existing visible objectives remain useful beyond the bounded local search.
  // Do not walk the entire intelligence history or clone the complete world.
  for (const node of game.nodes) if (game.landmarkVisible(node.id)) add(game.getNode(node.id));

  const lists = emptyLists();
  for (const node of candidates.values()) {
    const intel = intelView(game, node, now);
    const known = intel.public === true || intel.precision === 'exact';
    // Only resource kind is read for unknown fields. Never copy army, raw loot,
    // town population, original-node objects or hidden generator metadata.
    const kinds = node.wild ? [game.terrainTypes[node.type]?.resource].filter(Boolean) :
      Object.keys(node.loot || {}).filter(id => RESOURCE_IDS.includes(id) && id !== 'gold');
    const loot = known ? resourcesOnly(game.attackInfo(node.id, 'raid')?.loot) : null;
    const preview = known && withinLimit ? game.lootPreview(node.id, 'raid', army) : null;
    const carried = preview ? resourcesOnly(preview.loot) : null;
    const base = {id: node.id, name: node.name, x: node.x, y: node.y, level: node.level || 0,
      kind: game.isCity(node) ? 'city' : node.wild ? 'wild' : 'landmark',
      distance: Math.hypot(node.x - home.x, node.y - home.y), intelPrecision: intel.precision,
      rewardKnown: known, repeated: !!state.raided[node.id],
      cargoLoaded: preview ? amount(preview.loaded) : null,
      cargoDiscarded: preview ? amount(preview.discarded) : null};
    for (const resource of RESOURCE_IDS) {
      if (known ? !positive(loot[resource]) : !kinds.includes(resource)) continue;
      lists[resource].push({...base, resource, potential: known ? loot[resource] : null,
        carried: carried ? carried[resource] : null});
    }
  }
  for (const id of RESOURCE_IDS) {
    lists[id].sort((a, b) => Number(b.rewardKnown) - Number(a.rewardKnown) ||
      (b.carried ?? b.potential ?? 0) - (a.carried ?? a.potential ?? 0) ||
      a.distance - b.distance || a.level - b.level || a.id.localeCompare(b.id));
    lists[id] = lists[id].slice(0, LIST_LIMIT);
  }
  return {supported: true, sourceCity: game.currentCityId(), defaultResource,
    resources: resourceRows, referenceArmy, lists, radius: NEARBY_RADIUS, limit: LIST_LIMIT,
    notes: [
      '搜索当前城横纵各8格范围及已开放据点；每种资源最多显示5处目标。',
      '已知目标按参考可装载收益排序，未侦察目标按距离排序。未知资源金额须先获得精确侦察情报。',
      '数值为获胜前提下的基础物资，尚未扣除粮耗、战损和治疗费用；随机额外掉落另计。',
      '收益预览不表示获胜概率或已经入库的可用库存；实际战果与收取情况见战报。',
      '基础掠夺不含黄金；黄金缺口请结合任务、民政和金砖兑换筹备。',
    ]};
}
