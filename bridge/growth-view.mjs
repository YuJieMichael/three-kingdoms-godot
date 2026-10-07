import {progressionView} from './progression-view.mjs';

const copy = value => JSON.parse(JSON.stringify(value));
const SHARED_REASON = '共享演练尚未接入私人据点成长路线，请切换本机进度继续';
const navigation = (route, target = '', label = '前往办理') => ({route, target, label});

/** A route through existing rules. This projection never claims, trains or spends. */
export function growthView(runtime, options = {}) {
  const {Game: game, Progression: rules, HeritageSystem: heritage, ChapterData: chapters} = runtime;
  const state = game.state, now = options.now ?? state.last;
  if (options.shared) return {shared: true, reason: SHARED_REASON,
    stage: {id: 'shared', title: '私人成长路线', progress: 0, total: 0}, current: null,
    source: null, gaps: [], advice: [], speedup: {ownedCount: 0, items: [], suggestion: null}, combat: null};

  // gameView may pass its already-created progression projection to avoid a
  // second walk through the task/quote tables. Standalone callers remain useful.
  const progression = options.progression || progressionView(runtime, {...options, now});
  const result = {shared: false, reason: '', stage: null, current: null,
    source: null, gaps: [], advice: [], speedup: null, combat: null};
  const gap = (id, label, current, required, unit = '') => ({id, label, current, required,
    missing: Math.max(0, required - current), unit});
  const addAdvice = (id, text, navigate) => result.advice.push({id, text, ...(navigate ? {navigate} : {})});
  let cost = {}, queueGoal = null;
  const resourceGaps = payment => Object.entries(payment).filter(([, amount]) => amount > 0)
    .map(([id, amount]) => gap('resource:' + id, game.resources[id].name, state.res[id], amount))
    .filter(row => row.missing > 0);
  const currentStep = (id, title, description, navigate, reason = '') => {
    result.current = {id, title, description, navigate, reason};
  };
  const visibleNode = id => id && game.landmarkVisible(id) ? game.getNode(id) : null;
  const worldStep = node => {
    if (!node || !game.landmarkVisible(node.id)) return;
    currentStep('occupy:' + node.id, '占领' + node.name, node.desc || '',
      navigation('world', node.id, '查看目标与配兵'), game.attackBlocked(node.id, 'occupy') || '');
    result.source = {id: node.id, name: node.name, level: node.level, chapter: node.chapter || null};
    const intel = game.intel(node.id), known = !!(intel?.public || intel?.exact || intel?.precision === 'exact');
    const enemyArmy = known ? copy(intel?.army || node.army || {}) : {};
    const availableCount = game.totalArmy(state.army);
    result.combat = {target: node.id, name: node.name, intelKnown: known, enemyArmy,
      enemyCount: known ? game.totalArmy(enemyArmy) : null, availableCount, armyLimit: game.armyLimit(),
      blocked: result.current.reason};
    addAdvice('combat-preparation', known ?
      `公开守军 ${result.combat.enemyCount} 人；城内现有 ${availableCount} 人，校场单队上限 ${game.armyLimit()} 人。按配兵预览核对粮草与运载，不把人数相同视为胜利保证。` :
      '尚无精确守军情报。先查看目标并侦察，再按配兵预览核对兵种、行军粮草与运载。', navigation('world', node.id, '查看配兵预览'));
  };

  if (state.conquered.fort) {
    const chapter = progression.chapters.find(row => row.chapter === 2);
    const complete = chapters.completed(state, 2);
    result.stage = {id: complete ? 'chapter2_complete' : 'chapter2', title: complete ? '第二章已平定' : chapters.chapterTitle(2),
      progress: chapter.conquered, total: chapter.total};
    if (!complete) worldStep(visibleNode(chapter.next?.id));
    else {
      const next = progression.chapters.find(row => row.chapter === 3)?.next;
      const node = visibleNode(next?.id);
      if (node) {
        worldStep(node);
        result.current.title = '继续前往' + node.name;
      } else currentStep('chapter2_complete', '第二章六关已占领', '已完成当前成长路线，可查看章节进度和已达成奖励。', navigation('chapters', '', '查看章节进度'));
    }
  } else if (!progression.firstBattle.complete) {
    const guide = progression.firstBattle, next = guide.next;
    result.stage = {id: 'first_battle', title: '首战准备', progress: guide.victories > 0 ? 1 : 0, total: 1};
    const step = guide.requirementSteps.find(row => row.id === next.target && row.current < row.level);
    const name = step?.name || game.units[next.target]?.name || visibleNode(next.target)?.name || '首战引导';
    currentStep('first_battle', guide.ready ? '确认首战衔接完成' : step ? `准备${name} ${step.current + 1} 级` :
      next.route === 'army' ? '补足城内弓箭手' : next.route === 'world' ? '完成首次出征' : '等待出征部队返城',
    guide.ready ? '已取得首次胜利、部队已返城，城内弓箭手达到引导目标。' :
      step ? `当前先完成${name}的前置建设，再补齐军营与科技、训练${guide.target}名弓箭手；具体缺口见下方。` : guide.reason,
    navigation(guide.ready ? 'missions' : next.route, guide.ready ? 'firstBattle' : next.target,
      guide.ready ? '查看首战引导' : '前往当前一步'));
    result.gaps = guide.requirementSteps.filter(row => row.current < row.level)
      .map(row => gap(row.kind + ':' + row.id, row.name, row.current, row.level, '级'));
    if (guide.archers < guide.target) result.gaps.push(gap('army:archer', game.units.archer.name, guide.archers, guide.target, '人'));
    if (!guide.victories) result.gaps.push(gap('first_victory', '首次出征胜利', 0, 1, '次'));
    if (step) {
      queueGoal = {kind: step.kind === 'building' ? 'build' : 'research', id: step.id};
      const queued = step.kind === 'building' ? state.buildQueue.some(q => q.id === step.id) : state.researchQueue?.id === step.id;
      if (!queued) cost = step.kind === 'building' ? game.buildRecord(step.id, step.current + 1)?.cost || {} : game.researchCost(step.id);
    } else if (next.route === 'army') {
      queueGoal = {kind: 'train', id: 'archer'};
      const queued = state.trainQueue.filter(q => q.id === 'archer').reduce((sum, q) => sum + q.count, 0);
      const count = Math.max(0, guide.target - guide.archers - queued);
      if (queued) addAdvice('queued-archers', `已有 ${queued} 名弓箭手在训练；引导以实际返城和训练完成后的城内人数为准。`, navigation('army', 'archer', '查看练兵'));
      if (count) {
        cost = game.trainCost('archer', count);
        const people = count * (game.units.archer.people || 1);
        if (game.freePopulation() < people) result.gaps.push(gap('population', '空闲人口', game.freePopulation(), people, '人'));
      }
    }
    // A prerequisite can already be queued even while another missing step is
    // selected. Offer an owned acceleration for that real prerequisite too.
    if (!queueGoal || !queueRows(queueGoal.kind).some(q => q.id === queueGoal.id)) {
      const queued = guide.requirementSteps.filter(row => row.current < row.level)
        .map(row => ({kind: row.kind === 'building' ? 'build' : 'research', id: row.id}))
        .find(goal => queueRows(goal.kind).some(q => q.id === goal.id));
      if (queued) queueGoal = queued;
    }
  } else {
    const groups = progression.epic.groups, unfinished = groups.filter(row => row.progress < 1);
    if (!progression.epic.countyUnlocked) {
      result.stage = {id: 'county_access', title: '史诗与官爵', progress: groups.length - unfinished.length, total: groups.length};
      const group = unfinished[0];
      currentStep('epic:' + group.id, '推进' + group.name, group.detail, navigation('epic', '', '查看史诗门槛'));
      result.gaps = [gap('epic:kills', '黄巾头巾', state.epic.kills, rules.targets.kills, '件'),
        gap('epic:resources', '军资捐献', Object.values(state.epic.resources).reduce((sum, n) => sum + n, 0),
          Object.values(rules.resourceDonations).reduce((sum, row) => sum + row.amount, 0)),
        gap('epic:troops', '勤王诏', state.epic.troops, rules.targets.troops),
        gap('epic:treasures', '贡品录', state.epic.treasures, rules.targets.treasures)].filter(row => row.missing > 0);
      // Each quote still owns eligibility, quantities and points. Present one
      // feasible donation or its actual shortfall, rather than inventing a grind.
      const kind = {resources: 'resource', troops: 'troop', treasures: 'jewel'}[group.id];
      const donations = progression.epic.donations.filter(row => row.kind === kind && !row.reason.includes('已完成'));
      const donation = donations.find(row => !row.reason) || donations[0];
      if (donation?.kind === 'resource') cost = {[donation.id]: donation.cost};
      if (donation?.kind === 'troop') {
        result.gaps.push(gap('donation:' + donation.id, donation.name + '可捐兵力', state.army[donation.id], donation.cost, '人'));
        addAdvice('troop-donation', `本项捐献需 ${donation.name} ${donation.cost} 人，捐后离开军队；县城出征兵力应另行保留。`, navigation('epic', '', '查看捐献费用'));
      }
      if (donation?.kind === 'jewel') result.gaps.push(gap('donation:' + donation.id, donation.name, state.jewels[donation.id], donation.cost, '枚'));
      const next = game.nextLandmark();
      const node = visibleNode(next?.id);
      if (group.id === 'kills' && node && !game.isCity(node)) addAdvice('epic-raids', '头巾来自获胜的野地／黄巾据点掠夺；占领胜利不增加这一项。', navigation('world', node.id, '查看当前公开据点'));
      if (game.cityList().length >= game.cityLimit()) addAdvice('county-capacity', `现有 ${game.cityList().length} 城，爵位允许 ${game.cityLimit()} 城；占领县城还需在官爵中增加城池名额。`, navigation('honors', '', '查看官爵门槛'));
    } else if (game.cityList().length >= game.cityLimit()) {
      const noble = heritage.promotionQuote(state, 'noble');
      const kind = noble?.rule && state.honors.office < noble.rule.office ? 'office' : 'noble';
      const quote = heritage.promotionQuote(state, kind), rule = quote?.rule;
      result.stage = {id: 'county_honors', title: '扩充城池名额', progress: game.cityList().length, total: game.cityLimit()};
      currentStep('promote:' + kind, quote?.next ? '晋升' + quote.next.name : '查看城池名额', quote?.reason || '晋升条件已满足，请在官职爵位中确认费用。', navigation('honors', '', '查看官爵与费用'));
      if (rule) {
        result.gaps = [gap('prestige', '声望', state.prestige, rule.prestige), gap('office', '官职阶位', state.honors.office, rule.office),
          gap('hall', '官府', state.buildings.hall, rule.hall, '级'), ...Object.entries(rule.jewels)
            .map(([id, n]) => gap('jewel:' + id, rules.jewels[id].name, state.jewels[id], n, '枚'))].filter(row => row.missing > 0);
        cost = {gold: rule.gold};
      }
    } else {
      result.stage = {id: 'county_conquest', title: '推进公开据点', progress: 0, total: 1};
      const next = game.nextLandmark();
      worldStep(visibleNode(next?.id));
    }
  }

  result.gaps.push(...resourceGaps(cost));
  const missingJewels = result.gaps.filter(row => row.id.startsWith('jewel:'));
  const coralGap = missingJewels.find(row => row.id === 'jewel:coral');
  const preparation = progression.epic.exchanges.find(row => row.id === 'growth_coral');
  if (coralGap && preparation?.remaining > 0) {
    addAdvice('county-preparation', `珊瑚还缺 ${coralGap.missing} 枚；县城筹备每枚需 ${preparation.cost} 铜钱，全存档剩余 ${preparation.remaining}/${preparation.limit} 枚。${preparation.reason || '可在兑换页面逐枚确认。'} 铜钱通过每日任务获得。`, navigation('epic', 'exchange', '查看县城筹备兑换'));
  }
  if (missingJewels.length) {
    const boxes = game.manual.shop.filter(item => item.effect === 'jewelBox' && state.inventory[item.id] > 0);
    if (boxes.length) addAdvice('owned-jewel-boxes', `已拥有 ${boxes.reduce((sum, item) => sum + state.inventory[item.id], 0)} 个珠宝盒；开箱种类和数量随机，请先核对结果再筹备晋升。`, navigation('inventory', boxes[0].id, '查看已拥有珠宝盒'));
    else if (!coralGap || !preparation?.remaining) addAdvice('jewel-gathering', '驻地采集是另一种珠宝来源：先占领1级以上野地并派将驻扎，采集至少1小时。珊瑚可从湖泊采集；每小时随机判定，不保证获得。', navigation('holdings', '', '查看领地采集'));
  }
  const missingResource = result.gaps.find(row => row.id.startsWith('resource:'));
  if (missingResource) {
    const id = missingResource.id.slice(9), rate = game.rates()[id], cap = game.capacity(id);
    const text = missingResource.required > cap ? `${missingResource.label}需要 ${missingResource.required}，当前容量 ${cap}；先提升仓储或领取已解锁补给。` :
      rate > 0 ? `${missingResource.label}还缺 ${Math.ceil(missingResource.missing)}；当前净产 ${rate.toFixed(1)}/分钟，保持现状约 ${Math.ceil(missingResource.missing / rate)} 分钟可补足。` :
        `${missingResource.label}还缺 ${Math.ceil(missingResource.missing)}，当前净产 ${rate.toFixed(1)}/分钟；先恢复生产或领取已达成补给。`;
    const target = Object.keys(game.plotTypes).find(key => game.plotTypes[key].resource === id);
    addAdvice('resource-recovery', text, missingResource.required > cap ? navigation('inner', 'warehouse', '查看仓储') :
      target ? navigation('outer', target, '恢复资源生产') : navigation('civic', '', '查看民政与收入'));
  }
  if (progression.gifts.available) addAdvice('unclaimed-gifts', `还有 ${progression.gifts.available} 阶已解锁礼包可领取，可补充资源与加速。`, navigation('gift', '', '查看已解锁礼包'));
  else {
    const count = progression.missions.filter(row => row.ready && !row.claimed).length;
    if (count) addAdvice('earned-rewards', `已有 ${count} 项主线奖励达成，领取后可补充物资；路线仍按真实占领进度推进。`, navigation('missions', '', '查看已达成奖励'));
  }
  if (!result.current) currentStep('route', '查看成长进度', '当前目标将在进度刷新后显示。', navigation('missions', '', '查看进度'));
  result.speedup = speedupView();
  return result;

  function queueRows(kind) {
    return kind === 'build' ? state.buildQueue : kind === 'train' ? state.trainQueue : state.researchQueue ? [state.researchQueue] : [];
  }
  function speedupView() {
    const items = game.manual.shop.filter(item => item.effect === 'speedup' && state.inventory[item.id] > 0)
      .map(item => ({id: item.id, name: item.name, count: state.inventory[item.id], queueKind: item.queueKind}));
    const candidates = [];
    if (queueGoal) for (const row of queueRows(queueGoal.kind).filter(q => q.id === queueGoal.id)) {
      const key = game.speedupKey(queueGoal.kind, row);
      const target = game.speedupTargets(queueGoal.kind, now).find(target => target.key === key);
      if (!target) continue;
      for (const item of items.filter(item => item.queueKind === queueGoal.kind)) {
        const quote = game.speedupQuote(item.id, key, now);
        if (quote.error || quote.reason || quote.workMs <= 1) continue;
        candidates.push({itemId: item.id, itemName: item.name, count: item.count, targetKey: key, targetName: target.name,
          waitSeconds: quote.waitMs / 1000, workSeconds: quote.workMs / 1000,
          shortenMinSeconds: Math.min(quote.workMs, quote.minMs) / 1000,
          shortenMaxSeconds: Math.min(quote.workMs, quote.maxMs) / 1000,
          remainingMinSeconds: (quote.waitMs + quote.afterMinMs) / 1000,
          remainingMaxSeconds: (quote.waitMs + quote.afterMaxMs) / 1000,
          wasteMinSeconds: Math.max(0, quote.minMs - quote.workMs) / 1000,
          wasteMaxSeconds: Math.max(0, quote.maxMs - quote.workMs) / 1000,
          overflowSeconds: Math.max(0, quote.maxMs - quote.workMs) / 1000,
          // A presentation recommendation, not a restriction on useSpeedup:
          // preserve an item when more than half its guaranteed duration wastes.
          conserve: quote.minMs > quote.workMs * 2,
          navigate: navigation('inventory', item.id, '查看已入库加速')});
      }
    }
    candidates.sort((a, b) => a.remainingMaxSeconds - b.remainingMaxSeconds || a.overflowSeconds - b.overflowSeconds || a.itemId.localeCompare(b.itemId));
    return {ownedCount: items.reduce((sum, item) => sum + item.count, 0), items, suggestion: candidates[0] || null};
  }
}
