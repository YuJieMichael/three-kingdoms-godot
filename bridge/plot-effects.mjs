/** Read-only projections of native plotYield, records, workers and rates. */
const PURPOSES = {
  farm: '生产粮食，供应募兵、行军和士兵日常粮耗。',
  lumber: '生产木材，用于建筑、弓兵与攻城器械。',
  quarry: '生产石料，用于建筑、城墙和城防建设。',
  mine: '生产铁锭，用于建筑与军备生产。',
};

export function plotEffect(game, plot, id, targetLevel = null) {
  const cfg = game.plotTypes[id];
  if (!cfg) return null;
  const currentRecord = plot?.type ? game.buildRecord(plot.type, plot.level) : null;
  const targetRecord = targetLevel === null ? null : game.buildRecord(id, targetLevel);
  const workers = game.workers(), population = game.state.population;
  const currentLabor = Math.min(1, population / Math.max(1, workers));
  const nextWorkers = targetRecord ? workers - (currentRecord?.workers || 0) + targetRecord.workers : workers;
  const nextLabor = Math.min(1, population / Math.max(1, nextWorkers));
  const oldResource = plot?.type ? game.plotTypes[plot.type].resource : null;
  const oldYield = plot?.type ? game.plotYield(plot) : 0;
  const current = oldResource === cfg.resource ? oldYield : 0;
  // plotYield supplies every native modifier. Only total worker demand changes
  // with the proposed field, so adjust its labor factor without mutating state.
  const factor = currentLabor > 0 ? nextLabor / currentLabor : 0;
  const after = targetRecord ? game.plotYield({type: id, level: targetLevel}) * factor : null;
  const sameResourceOthers = game.state.plots.filter(row => row.type && row !== plot && game.plotTypes[row.type].resource === cfg.resource)
    .reduce((n, row) => n + game.plotYield(row), 0);
  const cityNet = game.rates()[cfg.resource];
  const cityNetAfter = after === null ? null : cityNet + after - current + sameResourceOthers * (factor - 1);
  return {resource: cfg.resource, resourceName: game.resources[cfg.resource].name, purpose: PURPOSES[id],
    currentPerHour: current * 60, afterPerHour: after === null ? null : after * 60,
    deltaPerHour: after === null ? null : (after - current) * 60,
    cityNetPerHour: cityNet * 60, cityNetAfterPerHour: cityNetAfter === null ? null : cityNetAfter * 60,
    currentWorkers: currentRecord?.workers || 0, workersAfter: targetRecord?.workers ?? null,
    totalWorkersAfter: nextWorkers, population, laborRatioAfter: nextLabor,
    storageFull: game.state.res[cfg.resource] >= game.capacity(cfg.resource),
    removedResourceName: oldResource && oldResource !== cfg.resource ? game.resources[oldResource].name : null,
    removedPerHour: oldResource && oldResource !== cfg.resource ? oldYield * 60 : 0,
    forecast: '按当前人口、科技、领地与城池加成估算；施工完成后生效。人口变化或仓储限制会影响实际入库。'};
}
