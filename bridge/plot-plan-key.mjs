import crypto from 'node:crypto';

/** Bind a native plan and affected field levels to its preview. */
export function plotPlanKey(game, quote) {
  const state = game.state;
  const payload = {city: game.currentCityId(), id: quote.id, mode: quote.mode,
    tasks: quote.tasks, counts: quote.projectedCounts, cost: quote.cost,
    affected: (quote.tasks || []).map(task => [task.index, state.plots[task.index]?.type,
      state.plots[task.index]?.level]), reserve: state.automation.reserve};
  return crypto.createHash('sha256').update(JSON.stringify(payload)).digest('hex');
}
