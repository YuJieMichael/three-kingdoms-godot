// Read-only presentation of the canonical progression systems. No award or
// promotion is applied here; commands still run through executeGame/CAS.
import {growthSupportQuote} from './growth-support.mjs';
const copy = value => JSON.parse(JSON.stringify(value));
const command = (type, args = []) => ({type, args});
const SHARED_REASON = '共享演练尚未接入私人据点主线，请切换本机进度继续';
const COMBAT_METRICS = /^(victory|kill|occupy|capture|wild_victory|siege_victory|win_level_|raid_)/;

export function progressionView(runtime, options = {}) {
  const {Game: game, Progression: progression, HeritageSystem: heritage, ChapterData: chapters} = runtime;
  const onboarding = runtime.OnboardingSystem || game.onboarding, state = game.state;
  const now = options.now ?? state.last, shared = !!options.shared;
  const items = game.manual.shop, jewels = progression.jewels;
  const rewards = (resources = {}, itemCounts = {}, jewelCounts = {}, army = {}, extra = {}) => ({
    resources: copy(resources),
    items: Object.entries(itemCounts).map(([id, count]) => ({id, name: items.find(item => item.id === id)?.name || id, count})),
    jewels: Object.entries(jewelCounts).map(([id, count]) => ({id, name: jewels[id]?.name || id, count})),
    army: Object.entries(army).map(([id, count]) => ({id, name: game.units[id]?.name || id, count})),
    ...extra,
  });
  const probe = (method, ...args) => progression[method](copy(state), ...args, now) || '';
  const visible = id => !!game.getNode(id) && game.landmarkVisible(id);
  const targetFor = mission => {
    if (mission.node) return mission.node;
    if (/^(develop_|expand_|field3_|study_|specialize_|army_|conquest_)/.test(mission.id))
      return mission.id.replace(/^(develop_|expand_|field3_|study_|specialize_|army_|conquest_)/, '').replace(/_\d+$/, '');
    if (mission.id.startsWith('hall_')) return 'hall';
    return ({house: 'house', house2: 'house', population: 'house', hall2: 'hall',
      warehouse: 'warehouse', warehouse3: 'warehouse', drill: 'drill', barracks: 'barracks', spearReady: 'combat',
      trained20: 'militia', trained60: 'archer', farm: 'farm', lumber: 'lumber', quarry: 'quarry', mine: 'mine',
      firstVictory: 'field', field: 'field', camp: 'camp', fort: 'fort'})[mission.id] || '';
  };
  const worldTarget = mission => mission.node || (mission.id.startsWith('conquest_') ? mission.id.slice(9) : ['field', 'camp', 'fort'].find(id => id === mission.id));
  const current = game.currentMission();
  const missions = game.missions.filter(mission => {
    const node = worldTarget(mission);
    return !node || visible(node) || game.missionClaimed(mission.id);
  }).map(mission => {
    const claimed = game.missionClaimed(mission.id), ready = game.missionReady(mission), target = targetFor(mission);
    const currentStatus = game.buildings[target] && mission.route === 'inner' ? `当前${game.buildings[target].name} ${state.buildings[target]}级` :
      game.manual.technology[target] && mission.route === 'research' ? `当前${game.manual.technology[target].name} ${state.tech[target]}级` :
      game.units[target] && mission.route === 'army' ? `当前城内${game.units[target].name} ${state.army[target]}人` :
      mission.id.startsWith('population') ? `当前人口 ${state.population} · 累计训练 ${state.stats.trained}` :
      /^(trained|victories)/.test(mission.id) ? `当前累计${mission.id.startsWith('trained') ? '训练 ' + state.stats.trained + '人' : '胜利 ' + state.stats.victories + '场'}` : '';
    return {id: mission.id, title: mission.title, stage: mission.stage || '', description: mission.desc,
      route: mission.route || 'city', target: target.startsWith('chapter') && !visible(target) ? '' : target,
      current: current?.id === mission.id, currentStatus, claimed, ready: !shared && ready,
      reason: shared ? SHARED_REASON : claimed ? '奖励已领取' : ready ? '' : '目标尚未达成',
      rewards: rewards(mission.reward, mission.items, mission.jewels, mission.army, {prestige: 300}),
      claim: command('claimMission', [mission.id]), navigate: {route: mission.route || 'city', target},
      navigationReason: shared ? SHARED_REASON : target && mission.route === 'world' && !visible(target) ? '当前据点尚未开放' : ''};
  });
  const accepted = state.daily.tasks.filter(task => task.status === 'accepted').length;
  const dailyTasks = state.daily.tasks.map(task => {
    const definition = progression.definition(task), reward = progression.reward(task), item = progression.taskItem(state, task);
    const ready = progression.taskReady(state, task), blocked = shared && COMBAT_METRICS.test(definition.metric || '');
    return {id: task.uid, title: definition.title, description: definition.desc, status: task.status,
      progress: definition.resource ? Math.min(task.target, state.res[definition.resource]) : task.progress,
      target: task.target, payment: definition.resource ? {[definition.resource]: task.target} : {},
      route: definition.route, ready: ready && !blocked, reason: blocked ? SHARED_REASON : '',
      rewards: rewards({...reward.resources, gold: reward.gold}, {[item.id]: 1}, {}, {}, {prestige: reward.prestige, copper: reward.copper}),
      accept: command('acceptDaily', [task.uid]), acceptReason: blocked ? SHARED_REASON : task.status !== 'available' ? '已接取' : probe('accept', task.uid),
      claim: command('claimDaily', [task.uid]), claimReason: blocked ? SHARED_REASON : ready ? '' : '接取后完成目标才能领取',
      abandon: command('abandonDaily', [task.uid]), abandonReason: task.status !== 'accepted' ? '尚未接取' : ''};
  });
  // Batch claiming must not bypass the disabled private-combat cards in shared
  // mode; city-management tasks remain individually claimable.
  const blockedDailyReady = shared && state.daily.tasks.some(task =>
    COMBAT_METRICS.test(progression.definition(task).metric || '') && progression.taskReady(state, task));
  const milestones = progression.milestones.map(milestone => ({count: milestone.count,
    claimed: state.daily.milestoneClaims.includes(milestone.count),
    reason: probe('claimMilestone', milestone.count), command: command('claimDailyMilestone', [milestone.count]),
    rewards: rewards({food: milestone.resources, wood: milestone.resources, stone: milestone.resources, iron: milestone.resources, gold: milestone.gold}, milestone.items)}));
  const donations = [
    ...Object.keys(progression.resourceDonations).map(id => ['resource', id, game.resources[id].name]),
    ...Object.keys(progression.troopDonations).map(id => ['troop', id, game.units[id].name]),
    ...Object.keys(jewels).map(id => ['jewel', id, jewels[id].name]),
  ].map(([kind, id, name]) => ({...copy(progression.donationQuote(state, kind, id)), name,
    command: command('donateEpic', [kind, id])}));
  const exchanges = progression.exchangeOffers(state).map(offer => ({...copy(offer),
    reason: probe('exchange', offer.id), command: command('exchangeCopper', [offer.id]),
    claimed: state.daily.exchangeClaims.filter(id => id === offer.id).length}));
  if (!shared) exchanges.unshift(growthSupportQuote(runtime));
  const promotions = ['office', 'noble'].map(kind => {
    const quote = copy(heritage.promotionQuote(state, kind));
    return {kind, current: copy(heritage[kind](state)), ...quote, command: command('heritage.promote', [kind]),
      cost: rewards({gold: quote?.rule?.gold || 0}, {}, quote?.rule?.jewels || {})};
  });
  const salaries = ['office', 'noble'].map(kind => {
    const quote = copy(heritage.salaryQuote(state, kind));
    return {kind, ...quote, reason: quote.row.salary < 1 ? '晋升后才能领取俸禄' : quote.claimed ? '今日已领取，北京时间05:00重置' : '',
      command: command('heritage.salary', [kind]), rewards: rewards(quote.reward)};
  });
  const chapterRows = [2, 3].map(chapter => {
    const progress = chapters.progress(state, chapter), nodes = chapters.chapterNodes(chapter);
    return {chapter, title: chapters.chapterTitle(chapter), unlocked: !shared && progress.unlocked,
      reason: shared ? SHARED_REASON : !progress.unlocked ? chapter === 2 ? '先占领古渡县城' : '先占领古渡县城，并完成第二章全部六关' : '',
      conquered: progress.conquered, claimed: progress.claimed, total: nodes.length,
      next: !shared && progress.next && visible(progress.next.id) ? {id: progress.next.id, name: progress.next.name} : null,
      visibleNodes: shared ? [] : nodes.filter(node => visible(node.id)).map(node => ({id: node.id, name: node.name,
        conquered: !!state.conquered[node.id], claimed: game.missionClaimed('chapter' + chapter + '_' + node.id)}))};
  });
  const giftLevels = Array.from({length: 10}, (_, i) => onboarding.quote(state, i + 1)).map(quote => ({
    level: quote.level, title: quote.title, unlocked: quote.unlocked, claimed: quote.claimed,
    reason: quote.claimed ? '这一阶礼包已领取' : !quote.unlocked ? '需要官府 ' + quote.level + ' 级' : '',
    command: command('onboarding.claim', [quote.level]), rewards: rewards(quote.resources, quote.items),
  }));
  // completeFirstBattle only writes this copied onboarding flag. Its checks use
  // the same live Game expedition set as the command, so no rule is reimplemented.
  const guideState = {...state, onboarding: {...state.onboarding}};
  const firstBattleReason = onboarding.completeFirstBattle(guideState) || '';
  const archerRequirements = copy(game.units.archer.requires);
  // Game exposes structured building prerequisites and formatted research
  // prerequisites. Resolve the latter by canonical display names for navigation
  // only; the command still rechecks the actual rule table on the server.
  const techConditions = id => game.researchRuleText(id).split('、').flatMap(text => {
    const match = /^(.+?)\s+(\d+)\s*级$/.exec(text.trim());
    if (!match) return [];
    const building = Object.keys(game.buildings).find(key => game.buildings[key].name === match[1]);
    const tech = Object.keys(game.manual.technology).find(key => game.manual.technology[key].name === match[1]);
    return building || tech ? [{kind: building ? 'building' : 'tech', id: building || tech, level: Number(match[2])}] : [];
  });
  const valueFor = (kind, id) => kind === 'building' ? game.requirementLevel(id) : state.tech[id];
  const conditionsFor = (kind, id) => kind === 'building' ? game.buildingConditions(id, valueFor(kind, id) + 1) : techConditions(id);
  const steps = new Map();
  const appendStep = (kind, id, level, seen = new Set()) => {
    const key = kind + ':' + id;
    if (seen.has(key)) return;
    seen = new Set([...seen, key]);
    const existing = steps.get(key);
    if (!existing || existing.level < level) steps.set(key, {id, kind, name: kind === 'building' ? game.buildings[id].name : game.manual.technology[id].name, level, current: valueFor(kind, id)});
    if (valueFor(kind, id) < level) for (const condition of conditionsFor(kind, id))
      if (condition.kind === 'building' || condition.kind === 'tech') appendStep(condition.kind, condition.id, condition.level, seen);
  };
  const missingStep = (kind, id, level, seen = new Set()) => {
    if (valueFor(kind, id) >= level) return null;
    const key = kind + ':' + id;
    if (!seen.has(key)) {
      seen = new Set([...seen, key]);
      for (const condition of conditionsFor(kind, id)) if (condition.kind === 'building' || condition.kind === 'tech') {
        const missing = missingStep(condition.kind, condition.id, condition.level, seen);
        if (missing) return missing;
      }
    }
    return {route: kind === 'building' ? Object.hasOwn(game.plotTypes, id) ? 'outer' : 'inner' : 'research', target: id};
  };
  for (const [id, level] of Object.entries(archerRequirements.buildings)) appendStep('building', id, level);
  for (const [id, level] of Object.entries(archerRequirements.tech)) appendStep('tech', id, level);
  let next = {route: 'army', target: 'archer'};
  if (!game.unitUnlocked('archer')) {
    next = Object.entries(archerRequirements.buildings).map(([id, level]) => missingStep('building', id, level)).find(Boolean) ||
      Object.entries(archerRequirements.tech).map(([id, level]) => missingStep('tech', id, level)).find(Boolean) || next;
  } else if (state.army.archer >= 30 && !state.stats.victories) next = {route: 'world', target: 'field'};
  else if (game.allExpeditions().length || Object.values(state.garrisons).some(garrison => garrison.phase === 'return')) next = {route: 'marches', target: ''};
  return {
    shared, reason: shared ? SHARED_REASON : '', missions,
    claimMissions: {command: command('claimReadyMissions'), reason: shared ? SHARED_REASON : missions.some(m => m.ready) ? '' : '暂无可领取奖励'},
    daily: {tasks: dailyTasks, accepted, limit: progression.ACCEPT_LIMIT, claimed: state.daily.claimed,
      resetAt: state.daily.start + progression.DAY, milestones,
      claimAll: {command: command('claimReadyDaily'), reason: blockedDailyReady ? '共享房间请逐项领取可办理的每日任务' : dailyTasks.some(task => task.ready) ? '' : '暂无已完成的每日任务'}},
    epic: {groups: copy(progression.groups(state)), donations, exchanges, countyUnlocked: progression.countyUnlocked(state),
      countyReason: shared ? SHARED_REASON : game.attackBlocked('fort', 'occupy') || '', copper: state.copper},
    honors: {office: copy(heritage.office(state)), noble: copy(heritage.noble(state)), promotions, salaries,
      prestige: state.prestige, jewels: Object.entries(jewels).map(([id, jewel]) => ({id, name: jewel.name, count: state.jewels[id]})),
      cityLimit: game.cityLimit(), cities: game.cityList().length},
    chapters: chapterRows,
    gifts: {levels: giftLevels, available: giftLevels.filter(gift => gift.unlocked && !gift.claimed).length,
      claimed: copy(state.onboarding.claims), claimAll: {command: command('onboarding.claimAvailable'),
        reason: giftLevels.some(gift => gift.unlocked && !gift.claimed) ? '' : '当前没有可领取的礼包'}},
    firstBattle: {complete: state.onboarding.firstBattle === 'complete', ready: !shared && !firstBattleReason && state.onboarding.firstBattle !== 'complete',
      reason: shared ? SHARED_REASON : state.onboarding.firstBattle === 'complete' ? '首战引导已完成' : firstBattleReason,
      archers: state.army.archer, target: 30, victories: state.stats.victories,
      requirement: game.unitRequirements('archer') || '', requirements: archerRequirements,
      requirementSteps: [...steps.values()],
      next, navigationReason: shared ? SHARED_REASON : '', finish: command('completeFirstBattleGuide')},
  };
}
