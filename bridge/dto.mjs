import {copy} from '../vendor/legacy/online/runtime.mjs';
import {heroView} from './hero-view.mjs';
import {progressionView} from './progression-view.mjs';
import {warView} from './war-view.mjs';
import {realmView} from './realm-view.mjs';
import {inventoryView} from './inventory-view.mjs';
import {reportEconomy} from './report-economy.mjs';
import {growthView} from './growth-view.mjs';
import {intelView, scoutingView, scoutMarchesView} from './scouting-view.mjs';
import {buildingComparisons} from './building-comparison.mjs';
import {raidTargetsView} from './raid-targets-view.mjs';
import {battleReview} from './battle-review.mjs';
import {campaignView} from './campaign-view.mjs';
import {conquestSupplyView, conquestReportReceipt} from './conquest-supply.mjs';
import {wildRefreshView} from './wild-fields.mjs';
import {plotEffect} from './plot-effects.mjs';

const point = source => ({x: source?.x ?? 32, y: source?.y ?? 32});
const armyCount = army => Object.values(army || {}).reduce((sum, n) => sum + n, 0);

// The last round belongs only to the latest receipt of this still-present,
// finished battle. Older history entries never inherit a later fight's events.
function battleForReport(game, report) {
  const battle = game.state.battle, latest = game.state.reports[0];
  if (!battle?.finished || !battle.result || !latest || report.id !== latest.id ||
      report.node !== battle.node || report.general !== battle.general ||
      report.sourceCity !== battle.sourceCity || report.round !== battle.round) return null;
  return Object.entries(battle.result).every(([key, value]) =>
    JSON.stringify(report[key]) === JSON.stringify(value)) ? battle : null;
}

// Administrative tiers come from the canonical NamedCityData definition via
// Game's read-only profile. Building levels and map-region centres are not tiers.
// This is called only after visibility is established; parent/children and
// unopened cities are deliberately absent from the map presentation contract.
function cityPresentation(game, node) {
  const profile = game.namedCityProgress(node.id);
  return {tier: profile?.tier || 'ordinary', tierName: profile?.tierName || '普通城池'};
}

/** These are presentation projections. All prices and eligibility come from Game. */
export function nodeView(game, node, now = game.state.last, options = {}) {
  if (!node) return null;
  const visible = node.id === 'home' || game.landmarkVisible(node.id);
  if (!visible) return {
    id: `unknown_${node.x}_${node.y}`, x: node.x, y: node.y,
    name: '未发现据点', terrain: 'plain', tileType: 'plain', kind: 'wild',
    level: 0, owned: false, hidden: true, selectable: false,
  };
  const owned = node.id === 'home' || !!game.state.conquered[node.id] || !!node.ownCity;
  const home = node.id === 'home';
  const city = home || !!node.ownCity || game.isCity(node);
  const intel = home ? null : intelView(game, node, now, options);
  return {
    id: node.id, x: node.x, y: node.y, name: node.name,
    terrain: node.terrain || (home ? 'plain' : node.type), tileType: node.type || node.terrain,
    kind: city ? 'city' : node.wild ? 'wild' : 'landmark',
    level: node.level || 0, owned, hidden: false, selectable: true, wildKey: node.wildKey || null,
    description: node.desc || '', reward: node.reward || '', faction: node.faction || '',
    chapter: node.chapter || null, namedCity: !!node.namedCity, openCity: !!node.openCity,
    ...(city ? cityPresentation(game, node) : {}),
    cityId: home ? 'capital' : node.ownCity || game.cityList().find(city => city.node === node.id)?.id || null,
    army: copy(intel?.army || {}),
    intel: intel ? copy(intel) : null,
    // Hidden guards are not leaked into the rendering DTO. The canonical private save remains intact.
    dispatch: {raid: home ? '请选择城外目标' : game.attackBlocked(node.id, 'raid') || '',
      occupy: home ? '请选择城外目标' : game.attackBlocked(node.id, 'occupy') || ''},
  };
}

export function marchesView(game, now, options = {}) {
  const result = [];
  for (const expedition of game.allExpeditions()) {
    const node = game.getNode(expedition.node), home = game.cityMeta(expedition.sourceCity) || game.home;
    if (!node) continue;
    const returning = expedition.phase === 'return';
    result.push({id: `expedition:${expedition.sourceCity}:${expedition.node}:${expedition.start}`,
      node: expedition.node, label: `${game.general(expedition.general).name} · ${node.name}`,
      from: point(returning ? node : expedition.origin || home), to: point(returning ? expedition.origin || home : node),
      start: expedition.start, arrive: expedition.end, status: expedition.phase,
      army: copy(expedition.army), count: armyCount(expedition.army), general: expedition.general,
      sourceCity: expedition.sourceCity, canStartBattle: expedition.phase === 'march' && expedition.end <= now,
      selectCommand: {type: 'selectExpedition', args: [expedition.node], sourceCity: expedition.sourceCity},
    });
  }
  for (const city of game.cityList()) {
    for (const [nodeId, garrison] of Object.entries(city.garrisons || {})) {
      const node = game.getNode(nodeId); if (!node) continue;
      const returning = garrison.phase === 'return';
      result.push({id: `garrison:${city.id}:${nodeId}`, node: nodeId,
        label: `${game.general(garrison.general).name} · 驻扎 ${node.name}`,
        from: point(node), to: point(returning ? city : node),
        start: garrison.start || garrison.at || now, arrive: returning ? garrison.end : null,
        status: returning ? 'return' : 'stationed', army: copy(garrison.army), count: armyCount(garrison.army),
        general: garrison.general, sourceCity: city.id, canStartBattle: false,
        recallCommand: {type: 'recallGarrison', args: [nodeId], sourceCity: city.id},
      });
    }
  }
  for (const job of game.logisticsList()) {
    const from = game.cityMeta(job.sourceCity), to = game.cityMeta(job.destinationCity);
    if (!from || !to) continue;
    result.push({id: `logistics:${job.id}`, label: job.kind === 'transport' ? '物资运输' : '军队调遣',
      from: point(job.phase === 'return' ? to : from), to: point(job.phase === 'return' ? from : to), start: job.start, arrive: job.end,
      status: job.phase || 'march', sourceCity: job.sourceCity, general: job.general || '',
      army: copy(job.army || {}), count: armyCount(job.army), cargo: copy(job.cargo || {}), canStartBattle: false});
  }
  return [...result, ...scoutMarchesView(game, now, options)];
}

export function worldView(game, now) {
  const tiles = [];
  // Current canonical coordinates are preserved; provinces are a presentation layer in this first migration.
  for (let y = 0; y < game.WORLD_SIZE; y++) for (let x = 0; x < game.WORLD_SIZE; x++) {
    const node = game.getWorldTile(x, y);
    const visible = node.id === 'home' || node.wild || game.landmarkVisible(node.id);
    if (!visible) { tiles.push(nodeView(game, node)); continue; }
    const city = node.id === 'home' || !!node.ownCity || game.isCity(node);
    tiles.push({id: node.id, x, y, name: node.name,
      terrain: node.terrain || (node.id === 'home' ? 'plain' : node.type), tileType: node.type || node.terrain,
      kind: city ? 'city' : node.wild ? 'wild' : 'landmark',
      wildKey: node.wildKey || null, description: node.desc || '', reward: node.reward || '',
      level: node.level || 0, owned: node.id === 'home' || !!game.state.conquered[node.id] || !!node.ownCity,
      hidden: false, selectable: true, faction: node.faction || '', namedCity: !!node.namedCity,
      ...(city ? cityPresentation(game, node) : {})});
  }
  return {width: game.WORLD_SIZE, height: game.WORLD_SIZE, home: point(game.currentHome()),
    tiles, marches: marchesView(game, now), wildRefresh: wildRefreshView(game.state)};
}

export function gameView(game, now, runtime = null, options = {}) {
  const state = game.state;
  const ready = game.missions.find(mission => game.missionReady(mission));
  const mission = ready || game.currentMission();
  const objective = mission ? {id: mission.id, title: mission.title, stage: mission.stage || '',
    description: mission.desc, reward: copy(mission.reward || {}), ready: !!ready,
    action: ready ? 'claimMission' : mission.id === 'gift' ? 'onboarding.claimAvailable' : '',
    args: ready ? [mission.id] : [], route: mission.route || 'city',
    items: copy(mission.items || {}), jewels: copy(mission.jewels || {}), army: copy(mission.army || {})} :
    {id: 'complete', title: '主线任务已完成', description: '继续发展城池和领地', reward: {}, ready: false, action: '', args: []};
  const buildings = state.cityLayout.flatMap((id, site) => {
    if (!id || id === 'reserved') return [];
    const level = state.cityLevels[site], next = level + 1, record = game.buildRecord(id, next);
    const queue = state.buildQueue.find(q => q.site === site);
    return [{id, name: game.buildings[id].name, site, level,
      cost: copy(record?.cost || {}), seconds: record ? game.buildSeconds(id, next) : 0,
      requirement: level >= 10 ? '已达最高等级' : queue ? '正在施工' : game.buildingRequirements(id, next),
      affordable: !!record && game.canPay(record.cost), queue: queue ? copy(queue) : null}];
  });
  const buildOptions = game.cityIds.filter(id => game.buildings[id].repeat || !state.cityLayout.includes(id)).map(id => ({
    id, name: game.buildings[id].name, cost: copy(game.buildRecord(id, 1).cost),
    seconds: game.buildSeconds(id, 1), requirement: game.buildingRequirements(id, 1),
    affordable: game.canPay(game.buildRecord(id, 1).cost),
  }));
  const plots = state.plots.map((plot, index) => {
    const id = plot.type || 'farm', next = plot.type ? plot.level + 1 : 1;
    const record = game.buildRecord(id, next), queue = game.plotJob(index);
    return {index, id: plot.type, name: plot.type ? game.buildings[id].name : '空地', level: plot.level,
      unlocked: index < game.unlockedPlots(), cost: copy(record?.cost || {}),
      seconds: record ? game.plotTime(index, id) : 0, queue: queue ? copy(queue) : null,
      affordable: !!record && game.canPay(record.cost),
      effect: plot.type ? plotEffect(game, plot, plot.type, plot.level < game.plotMaxLevel() && record ? next : null) : null,
      constructionEffect: queue ? plotEffect(game, plot, queue.id, queue.level) : null,
      requirement: !record ? '已达最高等级' : game.buildingRequirements(id, next)};
  });
  // Empty land can become any resource type. Its existing farm-default projection
  // is not the quotation for lumber, quarry or mine; use each first-tier rule.
  const plotOptions = Object.keys(game.plotTypes).map(id => {
    const cost = game.buildRecord(id, 1).cost;
    return {id, name: game.buildings[id].name, cost: copy(cost), seconds: game.buildSeconds(id, 1),
      requirement: game.buildingRequirements(id, 1), affordable: game.canPay(cost), effect: plotEffect(game, null, id, 1)};
  });
  const units = Object.entries(game.units).map(([id, unit]) => ({id, name: unit.name,
    available: state.army[id], cost: game.trainCost(id, 1), seconds: game.trainSeconds(id, 1),
    requirement: game.unitRequirements(id), unlocked: game.unitUnlocked(id),
    people: unit.people || 1, role: unit.role, carry: game.carry({[id]: 1}), stats: copy(game.unitStats(id))}));
  const generals = state.generals.map(id => ({...game.general(id), busy: game.generalBusy(id),
    city: game.heroCity(id), governor: state.governor === id, loyalty: state.heroLoyalty[id]}));
  const rates = game.rates(), governor = game.general(state.governor);
  const market = {level: state.buildings.market, resources: Object.entries(game.resources)
    .filter(([id]) => id !== 'gold').map(([id, resource]) => ({id, name: resource.name,
      buy: copy(game.tradeQuote(id, true)), sell: copy(game.tradeQuote(id, false))}))};
  const governance = {governorId: state.governor,
    population: state.population, maxPopulation: game.maxPop(), freePopulation: game.freePopulation(),
    productionPopulation: {current: state.population, required: game.workers()},
    morale: state.morale, unrest: state.unrest, tax: state.tax,
    targetMorale: game.governanceStatus().moraleTarget, goldPerMinute: rates.gold,
    // These two presentation multipliers mirror engine.js productionBoost/buildSeconds.
    // The production multiplier applies to outer plots, not base income or gold tax.
    productionBoost: 1 + governor.pol / 100 * Math.min(1, governor.lead * 1000 / Math.max(1, state.population)),
    constructionFactor: 1 + state.tech.construction * .1 + governor.pol / 100,
    candidates: generals.map(hero => ({...hero, reason: hero.busy ? '该武将正在出征或驻守' : ''}))};
  // hero-system.js wild.roomUsed includes both wild and defeated captive pools.
  const heldCaptives = (state.wildGenerals?.captives?.length || 0) + (state.heroService?.captives?.length || 0);
  const capacity = game.heroCapacity(), used = state.generals.length + heldCaptives;
  const inn = {level: state.buildings.inn, capacity, used, remaining: Math.max(0, capacity - used),
    refreshReason: state.buildings.inn < 1 ? '请先建造客栈' : '',
    candidates: state.innCandidates.map(hero => ({...copy(hero), affordable: state.res.gold >= hero.price,
      reason: used >= capacity ? '招贤馆没有空闲房间（包含被俘将领）' :
        state.customGenerals.length + heldCaptives >= 100 ? '将领总量已达上限' :
        state.res.gold < hero.price ? '黄金不足' : ''}))};
  const techs = Object.entries(game.manual.technology).map(([id, tech]) => ({
    id, name: tech.name, description: tech.desc, level: state.tech[id],
    cost: copy(game.researchCost(id)), seconds: state.tech[id] >= 10 ? 0 : game.researchSeconds(id),
    requirement: state.tech[id] >= 10 ? '科技已满级' : state.buildings.academy < 1 ? '请先建造书院' :
      state.researchQueue ? '书院正在研究另一项科技' : game.researchRequirements(id),
    affordable: game.canPay(game.researchCost(id)),
  }));
  const queueMetadata = ['build','train','research'].flatMap(queueKind =>
    game.speedupTargets(queueKind, now).map(target => ({...target, queueKind})));
  const inventory = game.manual.shop.filter(item => state.inventory[item.id] > 0).map(item => ({
    id: item.id, name: item.name, count: state.inventory[item.id], effect: item.effect || '',
    description: item.desc || '', queueKind: item.queueKind || null,
    speedup: item.speedup ? copy(item.speedup) : null,
    targets: item.effect === 'speedup' ? queueMetadata.filter(target => target.queueKind === item.queueKind) : [],
    requiresGeneral: ['politics','valor','wisdom','tiger','heroReset'].includes(item.effect),
    requiresText: ['rename','banner'].includes(item.effect),
  }));
  const shop = game.manual.shop.map(item => ({id: item.id, name: item.name, price: item.price || 0,
    effect: item.effect || '', currency: 'gems', description: item.desc || '',
    queueKind: item.queueKind || null, rewardOnly: !!item.rewardOnly, available: !!item.effect && !item.rewardOnly,
    remaining: game.brickPurchaseRemaining(item.id)}));
  const management = runtime ? {
    heroes: heroView(runtime, {...options, now}), progression: progressionView(runtime, {...options, now}),
    warManagement: warView(runtime, {...options, now}), realmManagement: realmView(runtime, {...options, now}),
    inventoryManagement: inventoryView(runtime, {...options, now}), campaign: campaignView(runtime, {...options, now}),
    conquestSupply: conquestSupplyView(runtime, {...options, now})} : {};
  if (runtime) {
    management.growth = growthView(runtime, {...options, now, progression: management.progression});
    management.raidTargets = raidTargetsView(game, management.growth, {...options, now});
    const selected = management.progression.missions.find(row => row.id === objective.id);
    if (selected) { objective.target = selected.target; objective.rewards = selected.rewards; }
  }
  // cityList/realmView previously copied the raw scoutQueue, including hidden enemy snapshots.
  const scoutMarches = scoutMarchesView(game, now, options);
  const safeCities = cities => cities.map(city => ({...copy(city),
    scoutQueue: scoutMarches.filter(march => march.sourceCity === city.id).map(march => copy(march))}));
  if (management.realmManagement) management.realmManagement.cities = safeCities(management.realmManagement.cities);
  return {...management, wildRefresh: wildRefreshView(state), scouting: scoutingView(game, now, options), res: copy(state.res), gold: state.res.gold, gems: state.gems,
    caps: Object.fromEntries(Object.keys(game.resources).map(id => [id, game.capacity(id)])),
    rates: copy(rates), rateUnit: 'per-minute', city: copy(game.cityMeta()), cityList: safeCities(game.cityList()),
    population: state.population, maxPopulation: game.maxPop(), freePopulation: game.freePopulation(),
    morale: state.morale, unrest: state.unrest, tax: state.tax,
    buildings, buildingSlots: state.cityLayout.map((id, site) => ({site, id, level: state.cityLevels[site], reserved: id === 'reserved'})),
    buildOptions, buildingComparisons: buildingComparisons(game), plots, plotOptions, units,
    techs, inventory, shop, market, governance, inn, queueMetadata, autoResearch: state.autoResearch,
    autoResearchStatus: game.autoResearchStatus(),
    queues: {build: copy(state.buildQueue), train: copy(state.trainQueue), research: state.researchQueue ? [copy(state.researchQueue)] : [], defense: copy(state.defenseQueue)},
    queueLimits: {build: game.buildLimit(), train: game.trainingLimit()},
    objective, generals, nodes: game.nodes.filter(node => game.landmarkVisible(node.id)).map(node => nodeView(game, game.getNode(node.id), now, options)),
    marches: marchesView(game, now, options), battle: copy(game.currentBattle()),
    reports: state.reports.map(report => ({...copy(report),
      ...(runtime && !options.shared ? {conquestSupply: conquestReportReceipt(runtime, report)} : {}),
      ...(runtime ? {economy: reportEconomy(runtime, report)} : {}),
      review: battleReview(report, {battle: battleForReport(game, report)})})),
    gifts: {available: game.onboarding.available(state), claimed: copy(state.onboarding.claims)},
  };
}
