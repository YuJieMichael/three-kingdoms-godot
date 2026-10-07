// Isolated, reproducible rule-clock playtest. Never imports player saves or serves HTTP.
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createGameRuntime, executeGame, seededRandom, copy, runtimeHash} from '../vendor/legacy/online/runtime.mjs';
import {progressionView} from '../bridge/progression-view.mjs';
import {executeGrowthSupport, growthSupportQuote, validGrowthSupport} from '../bridge/growth-support.mjs';
import {reportEconomy} from '../bridge/report-economy.mjs';

export const START = 1800000000000;
const MINUTE = 60000;
const resources = ['food', 'wood', 'stone', 'iron', 'gold'];
const delta = (before, after) => Object.fromEntries(resources.map(id => [id, (after[id] || 0) - (before[id] || 0)]));

export class PacingSession {
  constructor({accelerate = true, speedupPolicy = 'cover', seed = 604, maxDays = 7, growthSupport = false} = {}) {
    this.now = START;
    this.random = seededRandom(seed);
    this.accelerate = accelerate;
    this.speedupPolicy = speedupPolicy;
    this.dailyEnabled = false;
    this.growthSupport = growthSupport;
    this.snapshots = [];
    this.limit = START + maxDays * 86400000;
    this.runtime = createGameRuntime({now: this.now, random: this.random});
    this.state = copy(this.runtime.Game.state);
    this.report = {schema: 1, runtimeHash, seed, accelerate, speedupPolicy, growthSupport, start: START, methodology: 'Fresh canonical runtime; legal executeGame commands; simulated rule clock, not human elapsed time; no injected resources/army/save; earned speedups only; serial prerequisite route is a measured policy, not an optimal-time proof. Cover policy selects the shortest owned fixed speedup that completes the queue, or the longest smaller item. Conserve policy refuses items with less than 25% duration utilization. Optional private growth support is an explicit bridge command spending normally earned copper, not a canonical rule change.',
      commands: [], waits: [], queues: [], speedups: [], milestones: [], bottlenecks: [], battles: [], gatherings: [], supportExchanges: [], dailyClaims: 0, trades: []};
  }
  read() {
    this.runtime = createGameRuntime({snapshot: this.state, now: this.now, random: this.random});
    this.state = copy(this.runtime.Game.state);
    return this.runtime;
  }
  command(type, args = []) {
    const before = this.state;
    const input = {type, args, commandId: 'pacing_' + String(this.report.commands.length + 1).padStart(7, '0'), expectedRevision: this.report.commands.length};
    try {
      const support = type === 'exchangeCopper' && args[0] === 'growth_coral';
      if (support && !this.growthSupport) throw new Error('Growth support is disabled for this baseline');
      const result = support ? executeGrowthSupport(this.read(), input, this.now) : executeGame(this.state, input, this.now, this.random);
      this.runtime = result.runtime;
      this.state = result.state;
      this.report.commands.push({atMinutes: (this.now - START) / MINUTE, type, args: copy(args), resourceDelta: delta(before.res, this.state.res), copperDelta: this.state.copper - before.copper, jewelDelta: Object.fromEntries(Object.keys(before.jewels).map(id => [id, this.state.jewels[id] - before.jewels[id]])), inventoryDelta: Object.fromEntries([...new Set([...Object.keys(before.inventory), ...Object.keys(this.state.inventory)])].map(id => [id, (this.state.inventory[id] || 0) - (before.inventory[id] || 0)]).filter(([, value]) => value)), ok: true});
      if (support) this.report.supportExchanges.push({atMinutes: (this.now - START) / MINUTE, ...copy(result.result), copperBefore: before.copper, copperAfter: this.state.copper, coralBefore: before.jewels.coral, coralAfter: this.state.jewels.coral});
      return result.result;
    } catch (error) {
      this.report.commands.push({atMinutes: (this.now - START) / MINUTE, type, args: copy(args), ok: false, reason: error.message});
      throw error;
    }
  }
  waitUntil(end, reason, details = {}) {
    end = Math.max(this.now, Math.ceil(end));
    if (end > this.limit) throw new Error('Simulation horizon reached: ' + reason);
    const from = this.now;
    const before = copy(this.state.res);
    while (this.now < end) {
      // Frequent simulated checks preserve the canonical eight-hour offline cap.
      this.now = Math.min(end, this.now + 3600000);
      const runtime = createGameRuntime({snapshot: this.state, now: this.now, random: this.random});
      runtime.Game.tick(this.now, true);
      runtime.Game.save();
      if (!runtime.Game.validSave(runtime.Game.state)) throw new Error('Invalid clock-settled state');
      this.state = copy(runtime.Game.state);
      this.runtime = runtime;
    }
    this.report.waits.push({reason, fromMinutes: (from - START) / MINUTE, toMinutes: (this.now - START) / MINUTE, minutes: (this.now - from) / MINUTE, resourceDelta: delta(before, this.state.res), ...details});
  }
  rewards() {
    for (let pass = 0; pass < 100; pass++) {
      const runtime = this.read(), game = runtime.Game;
      if (runtime.OnboardingSystem.available(game.state).length) this.command('onboarding.claimAvailable');
      else if (game.missions.some(m => game.missionReady(m))) this.command('claimReadyMissions');
      else if (this.dailyEnabled && this.dailyReward()) continue;
      else return;
    }
    throw new Error('Reward loop did not settle');
  }
  dailyReward() {
    const runtime = this.read(), progression = runtime.Progression;
    const accepted = this.state.daily.tasks.filter(t => t.status === 'accepted');
    const ready = accepted.find(t => progression.taskReady(this.state, t));
    if (ready) {
      this.command('claimDaily', [ready.uid]);
      this.report.dailyClaims++;
      return true;
    }
    const milestone = [3, 6, 10].find(n => this.state.daily.claimed >= n && !this.state.daily.milestoneClaims.includes(n));
    if (milestone) {
      this.command('claimDailyMilestone', [milestone]);
      return true;
    }
    const useful = /^(donate_|build$|fields$|cityBuild$|research$|militaryResearch$|productionResearch$|train$|archers$|victory$|raid$|raid_|kills$|occupy$|highVictory3$|highVictory5$|trade)/;
    const next = accepted.length < 12 && this.state.daily.tasks.find(t => t.status === 'available' && useful.test(t.template));
    if (next) {
      this.command('acceptDaily', [next.uid]);
      return true;
    }
    return false;
  }
  milestone(id) {
    const runtime = this.read(), game = runtime.Game;
    this.report.milestones.push({id, atMinutes: (this.now - START) / MINUTE, res: copy(this.state.res), army: copy(this.state.army), population: this.state.population, freePopulation: game.freePopulation(), gifts: copy(this.state.onboarding.claims), prestige: this.state.prestige, copper: this.state.copper, jewels: copy(this.state.jewels), buildings: copy(this.state.buildings), tech: copy(this.state.tech), epic: copy(this.state.epic), victories: this.state.stats.victories, honors: copy(this.state.honors), conquered: copy(this.state.conquered), dailyClaims: this.report.dailyClaims});
    if (['first-guide-complete', 'county-occupied-natural', 'chapter2-completed-natural'].includes(id)) this.snapshots.push({id, clock: this.now, state: copy(this.state)});
  }
  finishQueue(kind, selector = () => true) {
    let game = this.read().Game;
    const queues = () => kind === 'build' ? this.state.buildQueue : kind === 'train' ? this.state.trainQueue : this.state.researchQueue ? [this.state.researchQueue] : [];
    const initial = queues().find(selector);
    if (!initial) throw new Error('Missing queue: ' + kind);
    const key = game.speedupKey(kind, initial);
    const entry = {kind, id: initial.id, level: initial.level, count: initial.count, startMinutes: (this.now - START) / MINUTE, workMinutes: (initial.end - Math.max(initial.start, this.now)) / MINUTE, originalEndMinutes: (initial.end - START) / MINUTE};
    while (this.accelerate && queues().some(q => game.speedupKey(kind, q) === key)) {
      game = this.read().Game;
      const target = game.speedupTargets(kind, this.now).find(q => q.key === key);
      if (!target || target.workSeconds <= 0.001) break;
      const owned = game.manual.shop.filter(item => item.effect === 'speedup' && item.queueKind === kind && this.state.inventory[item.id] > 0 && Number.isFinite(item.speedup.seconds) && (this.speedupPolicy !== 'conserve' || target.workSeconds >= item.speedup.seconds / 4));
      const fit = owned.filter(item => item.speedup.seconds <= target.workSeconds).sort((a, b) => b.speedup.seconds - a.speedup.seconds);
      const covering = owned.filter(item => item.speedup.seconds >= target.workSeconds).sort((a, b) => a.speedup.seconds - b.speedup.seconds);
      const nonfixed = this.dailyEnabled && game.manual.shop.filter(item => item.effect === 'speedup' && item.queueKind === kind && this.state.inventory[item.id] > 0 && (item.speedup.minHours || item.speedup.ratio) && (item.speedup.minHours ? target.workSeconds >= item.speedup.minHours * 3600 : target.workSeconds >= 900));
      const item = (this.speedupPolicy === 'cover' ? covering[0] || fit[0] : fit[0] || covering[0]) || (nonfixed && nonfixed[0]);
      if (!item) break;
      const used = this.command('useSpeedup', [item.id, key]);
      this.report.speedups.push({atMinutes: (this.now - START) / MINUTE, kind, target: initial.id, item: item.id, requestedMinutes: used.requestedMs / MINUTE, removedMinutes: used.removedMs / MINUTE, wastedMinutes: Math.max(0, used.requestedMs - used.removedMs) / MINUTE});
    }
    const remaining = queues().find(q => game.speedupKey(kind, q) === key);
    if (remaining) this.waitUntil(remaining.end, kind + ':' + initial.id, {queue: kind});
    entry.finishedMinutes = (this.now - START) / MINUTE;
    entry.waitMinutes = entry.finishedMinutes - entry.startMinutes;
    this.report.queues.push(entry);
    this.rewards();
  }
  ensureResources(cost, purpose) {
    let loops = 0;
    while (!this.read().Game.canPay(cost)) {
      const game = this.runtime.Game, missing = Object.fromEntries(Object.entries(cost).filter(([id, amount]) => this.state.res[id] < amount).map(([id, amount]) => [id, amount - this.state.res[id]]));
      const rates = game.rates();
      if (this.dailyEnabled && this.state.buildings.market > 0) {
        const buy = Object.keys(missing).find(id => id !== 'gold' && game.tradeQuote(id, true).limit >= 1);
        if (buy) {
          const amount = Math.min(Math.ceil(missing[buy]), game.tradeQuote(buy, true).limit);
          this.command('trade', [buy, amount, true]);
          this.report.trades.push({atMinutes: (this.now - START) / MINUTE, resource: buy, amount, purpose});
          this.rewards();
          continue;
        }
      }
      const blocked = Object.keys(missing).filter(id => rates[id] <= 0 || game.capacity(id) < cost[id]);
      this.report.bottlenecks.push({atMinutes: (this.now - START) / MINUTE, purpose, kind: 'resources', missing, ratesPerMinute: copy(rates), capacity: Object.fromEntries(resources.map(id => [id, game.capacity(id)])), blocked});
      if (blocked.length || loops++ > 24) throw new Error(purpose + ': cannot naturally accrue ' + blocked.join(', '));
      const minutes = Math.max(...Object.entries(missing).map(([id, amount]) => amount / rates[id]));
      this.waitUntil(this.now + Math.min(60, minutes + 0.1) * MINUTE, 'resources:' + purpose, {missing});
      this.rewards();
    }
  }
  building(id, target) {
    for (let guard = 0; guard < 20 && this.read().Game.requirementLevel(id) < target; guard++) {
      let game = this.runtime.Game;
      const level = game.requirementLevel(id) + 1;
      for (const condition of game.buildingConditions(id, level)) {
        if (condition.kind === 'building') this.building(condition.id, condition.level);
        if (condition.kind === 'tech') this.research(condition.id, condition.level);
        if (condition.kind === 'item' && !(this.state.inventory[condition.id] >= condition.level)) throw new Error(id + ': missing prerequisite item ' + condition.id);
      }
      game = this.read().Game;
      const plot = Object.hasOwn(game.plotTypes, id);
      const site = plot ? this.state.plots.findIndex(p => p.type === id) : this.state.cityLayout.includes(id) ? this.state.cityLayout.indexOf(id) : this.state.cityLayout.indexOf(null);
      const targetSite = site >= 0 ? site : plot ? this.state.plots.findIndex(p => p.type === null) : -1;
      if (targetSite < 0) throw new Error(id + ': no available slot');
      this.ensureResources(game.buildRecord(id, level).cost, 'building:' + id + ':' + level);
      this.command(plot ? 'developPlot' : 'queueBuilding', [targetSite, id]);
      this.finishQueue('build', q => plot ? q.plot === targetSite : q.site === targetSite);
    }
    if (this.read().Game.requirementLevel(id) < target) throw new Error('Building guard: ' + id);
  }
  research(id, target = this.state.tech[id] + 1) {
    while (this.state.tech[id] < target) {
      const game = this.read().Game;
      for (const text of game.researchRuleText(id).split('、')) {
        const match = /^(.+?)\s+(\d+)\s*级$/.exec(text.trim());
        if (!match) continue;
        const building = Object.keys(game.buildings).find(key => game.buildings[key].name === match[1]);
        const tech = Object.keys(game.manual.technology).find(key => game.manual.technology[key].name === match[1]);
        if (building) this.building(building, Number(match[2]));
        else if (tech) this.research(tech, Number(match[2]));
      }
      this.ensureResources(this.read().Game.researchCost(id), 'research:' + id);
      this.command('research', [id]);
      this.finishQueue('research');
    }
  }
  train(id, count) {
    if (count <= 0) return;
    const game = this.read().Game;
    if (game.unitRequirements(id)) throw new Error('Training prerequisites: ' + game.unitRequirements(id));
    this.ensureResources(game.trainCost(id, count), 'train:' + id + ':' + count);
    let guard = 0;
    while (this.read().Game.freePopulation() < count * game.units[id].people) {
      if (this.state.inventory.population > 0 && this.state.population < this.runtime.Game.maxPop()) this.command('useItem', ['population']);
      else {
        this.report.bottlenecks.push({atMinutes: (this.now - START) / MINUTE, kind: 'population', purpose: 'train:' + id, wanted: count * game.units[id].people, free: this.runtime.Game.freePopulation(), maximum: this.runtime.Game.maxPop(), committed: this.runtime.Game.committed()});
        if (this.runtime.Game.maxPop() - this.runtime.Game.workers() < count * game.units[id].people || guard++ > 12) throw new Error('Insufficient population capacity for ' + id);
        this.waitUntil(this.now + 30 * MINUTE, 'population:' + id);
      }
    }
    this.command('train', [id, count]);
    this.finishQueue('train', q => q.id === id);
  }
  battle(node, army, mode = 'raid', returnAfterOccupy = true) {
    const blocked = this.read().Game.attackBlocked(node, mode);
    if (blocked) throw new Error(node + ': ' + blocked);
    if ((this.state.cooldowns[node] || 0) > this.now) this.waitUntil(this.state.cooldowns[node], 'cooldown:' + node);
    const started = this.now;
    this.command('dispatch', [node, 'lin', army, mode, returnAfterOccupy]);
    this.waitUntil(this.state.expedition.end, 'march:' + node);
    this.command('startBattle');
    for (let round = 0; round < 30 && !this.state.battle.finished; round++) this.command('battleRound');
    const result = copy(this.state.battle.result);
    const canonicalReport = {node, sourceCity: this.state.battle.sourceCity || 'capital', ...result};
    const economy = reportEconomy(this.read(), canonicalReport);
    this.report.battles.push({node, mode, army: copy(army), round: this.state.battle.round, startMinutes: (started - START) / MINUTE, endMinutes: (this.now - START) / MINUTE, result, economy});
    if (this.state.expedition?.phase === 'return') this.waitUntil(this.state.expedition.end, 'return:' + node);
    this.rewards();
    return result;
  }
}

export function firstBattle(session) {
  session.rewards();
  session.milestone('fresh-gifts');
  session.building('house', 2);
  session.building('hall', 2);
  for (const type of ['farm', 'lumber', 'quarry', 'mine']) session.building(type, 1);
  for (let guard = 0; guard < 60; guard++) {
    const game = session.read().Game;
    const next = progressionView(session.runtime, {now: session.now}).firstBattle.next;
    if (next.route === 'army') break;
    if (next.route === 'inner' || next.route === 'outer') session.building(next.target, game.requirementLevel(next.target) + 1);
    else if (next.route === 'research') session.research(next.target);
    else throw new Error('Unexpected first-battle route: ' + JSON.stringify(next));
  }
  session.milestone('archer-unlocked');
  session.train('archer', 30);
  session.milestone('30-archers-ready');
  const result = session.battle('field', {archer: 30});
  if (!result.won) throw new Error('Canonical first battle was lost');
  session.milestone('first-victory-returned');
  session.train('archer', 30 - session.state.army.archer);
  session.command('completeFirstBattleGuide');
  session.milestone('first-guide-complete');
  return session;
}

// A declared repeatable policy, with bounded raids. It is not an optimized build
// order and never imports the prepared late-game fixture used by other tests.
export function naturalMidgame(session, {maxRaids = 80, hallTarget = 6, gather = false} = {}) {
  if (!Number.isInteger(hallTarget) || hallTarget < 6 || hallTarget > 9) throw new Error('Natural hall target must be 6–9');
  session.report.midgamePolicy = {hallTarget, raidTarget: 'mine', maxRaids, archerTarget: 300, earnedEquipment: true, earnedHeroPoints: true, paidHealing: true, dailyTasksAfterFirstBattle: true, gather};
  session.dailyEnabled = true;
  session.rewards();
  session.building('market', 1);
  session.building('inn', 1);
  session.building('hall', 4);
  session.building('house', 4);
  session.milestone('hall4-natural');
  session.command('hero.gift');
  const prepareHero = () => {
    const runtime = session.read(), hero = runtime.HeroSystem;
    const points = hero.remaining(session.state, 'lin');
    if (points) session.command('hero.allocate', ['lin', {atk: points, def: 0, pol: 0, wis: 0, lead: 0}]);
    for (const slot of Object.keys(hero.slots)) {
      const equipment = session.state.equipment.filter(e => e.slot === slot && (!e.hero || e.hero === 'lin') && hero.requiredLevel(e) <= session.state.generalLevels.lin).sort((a, b) => b.tier * (1 + b.enhance * .15) - a.tier * (1 + a.enhance * .15))[0];
      if (equipment && equipment.hero !== 'lin') session.command('hero.equip', [equipment.id, 'lin']);
    }
  };
  const reinforce = desired => {
    const healing = session.read().Game.warCareQuote();
    if (healing && !healing.reason) session.command('healWounded', ['all', null, healing.key]);
    while (session.state.army.archer < desired) {
      const game = session.read().Game;
      const size = Math.min(desired - session.state.army.archer, Math.max(1, Math.floor((game.maxPop() * 0.75 - game.workers()) / game.units.archer.people)));
      session.train('archer', size);
    }
    prepareHero();
  };
  reinforce(300);
  session.milestone('300-archers-natural');
  for (const node of ['wood', 'pass', 'camp', 'mine']) {
    const result = session.battle(node, {archer: session.state.army.archer}, node === 'camp' ? 'occupy' : 'raid');
    if (!result.won) throw new Error('Natural army lost at ' + node);
    reinforce(300);
    session.milestone('cleared-' + node);
  }
  session.building('hall', hallTarget);
  session.building('house', 6);
  for (const id of session.read().Game.manual.shop.filter(item => item.effect === 'jewelBox').map(item => item.id)) {
    while (session.state.inventory[id] > 0) session.command('onboarding.openItem', [id]);
  }
  session.milestone('hall' + hallTarget + '-natural');
  for (const id of resources) {
    if (session.state.epic.resources[id] >= 100000) continue;
    session.ensureResources({[id]: 100000}, 'epic-donation:' + id);
    session.command('donateEpic', ['resource', id]);
  }
  reinforce(1300);
  session.command('donateEpic', ['troop', 'archer']);
  session.milestone('epic-resources-troops-natural');
  for (let raid = 0; raid < maxRaids; raid++) {
    session.rewards();
    if (!session.state.honors.office && session.state.jewels.pearl >= 1) session.command('heritage.promote', ['office']);
    if (!session.state.honors.noble && !session.read().HeritageSystem.promotionQuote(session.state, 'noble').reason) session.command('heritage.promote', ['noble']);
    for (const id of Object.keys(session.state.jewels)) {
      const protectedAmount = id === 'pearl' && !session.state.honors.noble ? 10 : id === 'coral' && !session.state.honors.noble ? 5 : 0;
      while (session.state.epic.treasures < 2 && session.state.jewels[id] >= 10 + protectedAmount) session.command('donateEpic', ['jewel', id]);
    }
    if (session.read().Game.countyUnlocked() && (session.state.honors.noble || gather || session.growthSupport)) break;
    const result = session.battle('mine', {archer: session.state.army.archer});
    if (!result.won) throw new Error('Natural repeating raid lost at mine');
    reinforce(300);
  }
  if (session.growthSupport && session.read().Game.countyUnlocked() && !session.state.honors.noble) {
    session.rewards();
    while (session.state.jewels.coral < 5) {
      const offer = growthSupportQuote(session.read());
      if (offer.reason) {
        session.report.bottlenecks.push({kind: 'growth-support', atMinutes: (session.now - START) / MINUTE, offer});
        throw new Error('Earned copper support blocked: ' + offer.reason);
      }
      session.command(offer.command.type, offer.command.args);
    }
    session.milestone('earned-copper-coral-natural');
    if (!session.read().HeritageSystem.promotionQuote(session.state, 'noble').reason) session.command('heritage.promote', ['noble']);
  }
  if (gather && session.read().Game.countyUnlocked() && !session.state.honors.noble) {
    naturalLakeGathering(session);
    if (!session.read().HeritageSystem.promotionQuote(session.state, 'noble').reason) session.command('heritage.promote', ['noble']);
  }
  const game = session.read().Game;
  const gates = {epicGroups: session.runtime.Progression.groups(session.state), noble: session.runtime.HeritageSystem.promotionQuote(session.state, 'noble'), raidLimit: maxRaids, battles: session.report.battles.length};
  session.milestone('county-gate-check');
  if (!game.countyUnlocked() || !session.state.honors.noble) {
    session.report.bottlenecks.push({kind: 'county-gate', atMinutes: (session.now - START) / MINUTE, ...copy(gates)});
    throw new Error('Natural county gate remains after bounded earned-reward raids; see county-gate evidence');
  }
  reinforce(1000);
  for (let attacks = 0; attacks < 5 && !session.state.conquered.fort; attacks++) {
    const result = session.battle('fort', {archer: session.state.army.archer}, 'occupy');
    if (!result.won) throw new Error('Natural county attack lost; siege strength must improve');
    reinforce(1000);
  }
  if (!session.state.conquered.fort) throw new Error('Natural county is not occupied');
  session.milestone('county-occupied-natural');
  for (const node of session.read().ChapterData.chapterNodes(2)) {
    const result = session.battle(node.id, {archer: session.state.army.archer}, 'occupy');
    if (!result.won) throw new Error('Natural chapter-two attack lost at ' + node.id);
    reinforce(1000);
    session.milestone('chapter2-' + node.id);
  }
  session.milestone('chapter2-completed-natural');
  return session;
}

export function naturalLakeGathering(session) {
  let game = session.read().Game;
  const home = game.currentHome();
  const candidates = Array.from({length: 4096}, (_, i) => game.getWorldTile(i % 64, Math.floor(i / 64))).filter(node => node.wild && node.type === 'lake' && node.level > 0 && node.level <= 5 && !session.state.conquered[node.id]).sort((a, b) => a.level - b.level || Math.hypot(a.x - home.x, a.y - home.y) - Math.hypot(b.x - home.x, b.y - home.y));
  const target = candidates[0];
  if (!target) throw new Error('No reachable level 1–5 lake candidate');
  session.report.gatheringPolicy = {target: copy(target), collectionHours: 4, maximumBatches: 30, coralTarget: 5, reacquireAfterDecay: true};
  const result = session.battle(target.id, {archer: session.state.army.archer}, 'occupy', false);
  if (!result.won || !session.state.garrisons[target.id]) throw new Error('Natural lake occupation did not station survivors');
  session.milestone('lake-stationed-natural');
  let batches = 0;
  while (session.state.jewels.coral < 5 && batches++ < 30) {
    game = session.read().Game;
    let reason = session.runtime.HeritageSystem.gatherReason(session.state, target.id);
    if (reason && game.getNode(target.id).level === 0) {
      session.report.bottlenecks.push({kind: 'gathering-decay', node: target.id, atMinutes: (session.now - START) / MINUTE, reason, coral: session.state.jewels.coral});
      session.command('recallGarrison', [target.id]);
      session.waitUntil(session.state.garrisons[target.id].end, 'garrison-return:' + target.id);
      session.command('abandonWild', [target.id]);
      const renewed = session.battle(target.id, {archer: session.state.army.archer}, 'occupy', false);
      if (!renewed.won || !session.state.garrisons[target.id]) throw new Error('Natural decayed lake could not be occupied again');
      reason = session.read().HeritageSystem.gatherReason(session.state, target.id);
    }
    if (reason) {
      session.report.bottlenecks.push({kind: 'gathering', node: target.id, atMinutes: (session.now - START) / MINUTE, reason, level: game.getNode(target.id).level, coral: session.state.jewels.coral});
      throw new Error('Natural lake gathering blocked: ' + reason);
    }
    session.command('heritage.startGather', [target.id]);
    const started = session.now, beforeJewels = copy(session.state.jewels), stationed = copy(session.state.garrisons[target.id].army);
    // Four hours is a declared regular collection policy, above the one-hour
    // minimum and below the 24-hour roll cap; no random seed is reset.
    const hours = 4;
    const upkeep = session.read().Game.upkeep(stationed) * 2 * hours;
    session.waitUntil(started + hours * 3600000, 'gathering:' + target.id, {hours, stationed, canonicalStationaryFoodCost: upkeep});
    const quote = session.read().HeritageSystem.gatherQuote(session.state, target.id);
    session.command('heritage.collectGather', [target.id]);
    session.report.gatherings.push({node: target.id, batch: batches, startMinutes: (started - START) / MINUTE, endMinutes: (session.now - START) / MINUTE, hours, canonicalStationaryFoodCost: upkeep, quote: copy(quote), jewelDelta: Object.fromEntries(Object.keys(beforeJewels).map(id => [id, session.state.jewels[id] - beforeJewels[id]])), stationed});
    session.rewards();
  }
  session.milestone('lake-gathering-finished-natural');
  if (session.state.jewels.coral < 5) throw new Error('Natural gathering policy horizon ended before five coral');
  session.command('recallGarrison', [target.id]);
  session.waitUntil(session.state.garrisons[target.id].end, 'garrison-return:' + target.id);
  session.rewards();
}

export function markdown(report) {
  const lines = ['# 自然成长规则时钟诊断', '', report.methodology, '', `随机种子 ${report.seed}；规则 hash ${report.runtimeHash}。所有等待由模拟时钟推进，未改变规则倍率、随机种子、兵力或资源。串行路线不是最短时间证明。`, '', '| 里程碑 | 模拟分钟 |', '|---|---:|', ...report.milestones.map(m => `| ${m.id} | ${m.atMinutes.toFixed(3)} |`), '', `加速道具使用 ${report.speedups.length} 次，移除规则工作时间 ${report.speedups.reduce((n, s) => n + s.removedMinutes, 0).toFixed(3)} 分钟，溢出 ${report.speedups.reduce((n, s) => n + s.wastedMinutes, 0).toFixed(3)} 分钟。`, '', '| 队列 | 项目 | 原工作分钟 | 实际模拟等待 |', '|---|---|---:|---:|', ...report.queues.map(q => `| ${q.kind} | ${q.id} ${q.level ?? q.count ?? ''} | ${q.workMinutes.toFixed(3)} | ${q.waitMinutes.toFixed(3)} |`), '', '## 湖泊采集', '', '驻扎需要真实占领与城内现有部队；每次至少 1 小时，珠宝每整小时随机，最长计 24 小时。下表粮耗为规则双倍驻军消耗；资源净变化另在 JSON waits 中记录。', '', '| 批次 | 湖泊 | 规则小时 | 珊瑚 | 粮耗 | 每小时任意珠宝概率 |', '|---:|---|---:|---:|---:|---:|', ...(report.gatherings || []).map(g => `| ${g.batch} | ${g.node} | ${g.hours} | ${g.jewelDelta.coral} | ${g.canonicalStationaryFoodCost} | ${(g.quote.chance * 100).toFixed(2)}% |`), '', '## 瓶颈', '', ...report.bottlenecks.map(b => '- ' + JSON.stringify(b)), '', '## 完成边界', '', report.error || (report.milestones.some(m => m.id === 'chapter2-completed-natural') ? '首战、正常四项史诗/爵位、县城与第二章六关及任务领奖均由合法命令完成；这是一个固定种子的规则路线，不能保证随机珠宝所需时长，不能替代人工真实等待实玩。' : '首战闭环由合法规则命令完成；不是人工真实等待体验证明。')];
  return lines.join('\n') + '\n';
}

export async function run({output = '.local/pacing-0604', accelerate = true, speedupPolicy = 'cover', seed = 604, midgame = true, maxRaids = 80, maxDays = 7, hallTarget = 6, gather = false, growthSupport = false} = {}) {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), 'shanhece-pacing-'));
  const session = new PacingSession({accelerate, speedupPolicy, seed, maxDays, growthSupport});
  try {
    await fs.writeFile(path.join(temporary, 'fresh.json'), JSON.stringify(session.state));
    firstBattle(session);
    await fs.mkdir(output, {recursive: true});
    await fs.writeFile(path.join(output, `${accelerate ? speedupPolicy : 'no-speedups'}-snapshot.json`), JSON.stringify(session.state, null, 2));
    if (midgame) naturalMidgame(session, {maxRaids, hallTarget, gather});
  } catch (error) {
    session.report.error = error.message;
  }
  session.report.elapsedMinutes = (session.now - START) / MINUTE;
  session.report.snapshotClock = session.now;
  session.report.validSave = session.read().Game.validSave(session.state);
  session.report.validGrowthSupport = validGrowthSupport(session.state);
  await fs.mkdir(output, {recursive: true});
  await fs.writeFile(path.join(output, 'report.json'), JSON.stringify(session.report, null, 2));
  await fs.writeFile(path.join(output, 'report.md'), markdown(session.report));
  await fs.writeFile(path.join(output, 'final-state.json'), JSON.stringify(session.state, null, 2));
  for (const snapshot of session.snapshots) await fs.writeFile(path.join(output, snapshot.id + '.json'), JSON.stringify(snapshot.state, null, 2));
  await fs.rm(temporary, {recursive: true, force: true});
  return session.report;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const report = await run({output: args.includes('--output') ? args[args.indexOf('--output') + 1] : '.local/pacing-0604', accelerate: !args.includes('--no-speedups'), speedupPolicy: args.includes('--greedy') ? 'greedy' : args.includes('--conserve') ? 'conserve' : 'cover', midgame: !args.includes('--first-only'), maxRaids: args.includes('--max-raids') ? Number(args[args.indexOf('--max-raids') + 1]) : 80, maxDays: args.includes('--max-days') ? Number(args[args.indexOf('--max-days') + 1]) : 7, hallTarget: args.includes('--hall-target') ? Number(args[args.indexOf('--hall-target') + 1]) : 6, seed: args.includes('--seed') ? Number(args[args.indexOf('--seed') + 1]) : 604, gather: args.includes('--gather'), growthSupport: args.includes('--growth-support')});
  console.log(JSON.stringify({elapsedMinutes: report.elapsedMinutes, milestones: report.milestones.map(({id, atMinutes}) => ({id, atMinutes})), speedups: report.speedups.length, error: report.error || null, validSave: report.validSave}));
  process.exitCode = report.error ? 1 : 0;
}
