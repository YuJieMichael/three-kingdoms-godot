import {copy} from '../vendor/legacy/online/runtime.mjs';

// Only these two additive capacities are projected. The canonical maxPop()
// sums house records' population, and trainingLimit() sums barracks levels.
// Every canonical barracks record's limit equals its level (verified against
// actual construction completion for all ten tiers in the contract tests).
// Read the original records, never copy their curve or construct a runtime per
// poll. Placement has no capacity multiplier in these existing rules.
const TYPES = {
  house: {field: 'population', getter: 'maxPop', label: '人口上限', notice: '人口上限增加不代表人口立即补满。'},
  barracks: {field: 'limit', getter: 'trainingLimit', label: '可排队训练订单数',
    notice: '训练订单依次开始；队列容量不代表并行训练或训练加速。'},
};

/** Read-only, current owned city only; no tick/save/command or speculative loot. */
export function buildingComparisons(game) {
  const state = game.state, layout = state.cityLayout, levels = state.cityLevels;
  const cityId = game.currentCityId(), queueFull = state.buildQueue.length >= game.buildLimit();
  const emptySite = layout.findIndex(id => id === null);
  const result = {};
  for (const [id, type] of Object.entries(TYPES)) {
    const definition = game.buildings[id], currentCapacity = game[type.getter]();
    const sites = layout.flatMap((value, site) => value === id ? [site] : []);
    const candidate = (site, level, fresh = false) => {
      const queue = state.buildQueue.find(job => job.site === site && job.plot === undefined) || null;
      const maxed = level >= definition.max;
      const targetLevel = maxed ? null : level + 1;
      const record = !queue && !maxed ? game.buildRecord(id, targetLevel) : null;
      const previous = level > 0 ? game.buildRecord(id, level) : null;
      const effectDelta = record ? record[type.field] - (previous?.[type.field] || 0) : null;
      const cost = record ? copy(record.cost) : {};
      const requirement = queue ? '正在施工' : maxed ? '已达最高等级' : game.buildingRequirements(id, targetLevel);
      const affordable = !!record && game.canPay(record.cost);
      const uniqueBlocked = fresh && !definition.repeat && sites.length > 0;
      const reason = requirement || (uniqueBlocked ? '该建筑在本城只能建一座' : '') ||
        (queueFull ? '建造队正在忙碌' : '') || (!affordable ? '建设资源不足' : '');
      const seconds = record ? game.buildSeconds(id, targetLevel) : 0;
      return {site, id, level, targetLevel, cost, time: seconds, seconds,
        effectDelta, capacityAfter: effectDelta === null ? null : currentCapacity + effectDelta,
        requirement, affordable, queue: queue ? copy(queue) : null, available: !reason, reason};
    };
    result[id] = {id, cityId, count: sites.filter(site => levels[site] > 0).length,
      pendingCount: sites.filter(site => levels[site] === 0).length,
      currentCapacity, capacityLabel: type.label, notice: type.notice,
      new: emptySite < 0 ? null : candidate(emptySite, 0, true),
      upgrades: sites.filter(site => levels[site] > 0).map(site => candidate(site, levels[site]))};
  }
  return result;
}
