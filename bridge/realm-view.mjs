import {copy} from '../vendor/legacy/online/runtime.mjs';

// Governance only exposes a named city already owned by this actor. Its
// undiscovered parent/children and other cities' rules do not enter the DTO.
function ownedCityGovernance(game, city, shared) {
  if (shared || city.capital || !game.state.conquered?.[city.node] ||
      game.state.realm?.cities?.[city.id]?.node !== city.node) return {};
  const progress = game.namedCityProgress(city.node);
  if (!progress?.owned || progress.id !== city.node) return {};
  const identityKeys = ['id', 'name', 'tier', 'tierName', 'plotMax', 'goldFactor', 'owned'];
  const identity = Object.fromEntries(identityKeys.filter(key => Object.hasOwn(progress, key))
    .map(key => [key, copy(progress[key])]));
  const quote = game.namedCityDevelopmentQuote(city.node);
  if (!quote || quote.id !== city.node || quote.city !== city.id) return {identity};
  const quoteKeys = ['id', 'city', 'name', 'tierName', 'claimed', 'ready', 'reason', 'key'];
  const development = Object.fromEntries(quoteKeys.filter(key => Object.hasOwn(quote, key))
    .map(key => [key, copy(quote[key])]));
  development.checks = (Array.isArray(quote.checks) ? quote.checks : [])
    .filter(check => check && typeof check === 'object' && !Array.isArray(check)).map(check =>
    Object.fromEntries(['id', 'current', 'required', 'complete'].filter(key => Object.hasOwn(check, key))
      .map(key => [key, copy(check[key])])));
  development.reward = Object.fromEntries(Object.entries(quote.reward || {})
    .filter(([id, count]) => Object.hasOwn(game.resources, id) && Number.isSafeInteger(count) && count >= 0));
  if (quote.ready === true && quote.claimed === false && quote.reason === '' &&
      typeof quote.key === 'string' && quote.key.length > 0) {
    development.command = {type: 'claimNamedCityDevelopment', args: [quote.id, quote.key]};
  }
  return {identity, development};
}

/** Own-city management. Canonical methods supply plans, costs and eligibility. */
export function realmView(runtime, {shared = false, now = runtime.Game.state.last} = {}) {
  const {Game: g, HeritageSystem: heritage} = runtime, s = g.state;
  const command = (type, args = []) => ({type, args});
  const cities = g.cityList().map(city => ({...copy(city), ...ownedCityGovernance(g, city, shared), selected: city.id === g.currentCityId(),
    command: command('switchCity', [city.id])}));
  const holdings = Object.keys(s.conquered).flatMap(id => {
    const node = g.getNode(id);
    if (!node?.wild || s.realm.wildOwners[id] !== g.currentCityId() || cities.some(city => city.node === id)) return [];
    const garrison = s.garrisons[id], gathering = s.gatherings[id], q = heritage.gatherQuote(s, id);
    const founding = node.type === 'plain' ? g.foundCityQuote(id, '新城') : null;
    return [{id, name: node.name, x: node.x, y: node.y, type: node.type, level: node.level,
      garrison: garrison ? copy(garrison) : null, gathering: gathering ? copy(gathering) : null,
      gatherQuote: q ? copy(q) : null, gatherReason: heritage.gatherReason(s, id),
      foundReason: founding?.reason ?? '请占领平地后建城', foundCost: copy(founding?.cost || {}),
      start: command('heritage.startGather', [id]), collect: command('heritage.collectGather', [id]),
      cancel: command('heritage.cancelGather', [id]), recall: command('recallGarrison', [id])}];
  });
  const templates = g.plotTemplates.map(template => ({...copy(template),
    quotes: ['fill', 'replace'].map(mode => ({...copy(g.plotTemplateQuote(template.id, mode)), mode}))}));
  const roles = Object.fromEntries(Object.entries(heritage.roles).map(([id, name]) => [id,
    {id, name, hero: heritage.roleHero(s, id)}]));
  const generals = s.generals.filter(id => g.heroCity(id) === g.currentCityId())
    .map(id => ({id, name: g.general(id).name, busy: !!g.generalBusy(id)}));
  return {shared, currentCity: g.currentCityId(), cityLimit: g.cityLimit(), cities, holdings, roles, generals,
    logistics: copy(g.logisticsList()).map(job => ({...job, recall: command('recallLogistics', [job.id])})),
    templates, plotTemplate: copy(s.plotTemplate), plotStatus: g.plotTemplateStatus(),
    autoUpgrade: s.autoUpgrade, autoUpgradeStatus: g.autoUpgradeStatus(),
    autoResearch: s.autoResearch, autoResearchStatus: g.autoResearchStatus(),
    automation: copy(s.automation), focuses: copy(g.automation.focuses), serverTime: now,
    foundingReason: shared ? '共享演练尚未开放野地建城' : '',
    gatheringReason: shared ? '共享演练尚未开放私人野地采集' : ''};
}
