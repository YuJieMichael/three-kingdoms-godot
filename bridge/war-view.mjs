import {copy} from '../vendor/legacy/online/runtime.mjs';

const command = (type, args = []) => ({type, args});
const PRIVATE_REASON = '共享房间使用玩家攻防，私人黄巾来袭和守城演练不可用';

/** Presentation only: quotes, keys and eligibility remain in the canonical runtime. */
export function warView(runtime, options = {shared: false}) {
  const {Game: g, NPCDefense: npc, NPCDefenseData: npcData} = runtime, s = g.state;
  const now = options.now ?? s.last, shared = !!options.shared;
  const name = id => g.units[id]?.name || id;
  const healAll = g.warCareQuote('all'), captiveAll = g.captiveRecruitAllQuote();
  const hospitalRows = healAll.rows.filter(row => row.count > 0).map(row => {
    const full = g.warCareQuote(row.id);
    const affordable = g.warCareQuote(row.id, row.affordable);
    return {...copy(row), name: name(row.id), choices: [
      {...copy(full), label: '治疗全部本类', command: command('healWounded', [row.id, full.count, full.key])},
      {...copy(affordable), label: '治疗黄金可负担人数', command: command('healWounded', [row.id, affordable.count, affordable.key])},
    ]};
  });
  const captiveRows = captiveAll.rows.map(row => {
    const full = g.captiveRecruitQuote(row.id, row.available);
    const planned = g.captiveRecruitQuote(row.id, row.count);
    return {...copy(row), name: name(row.id), choices: [
      {...copy(full), count: row.available, label: '招降全部本类', command: command('recruitCaptives', [row.id, row.available])},
      {...copy(planned), count: row.count, label: '按一键方案招降本类', command: command('recruitCaptives', [row.id, row.count])},
    ]};
  });
  const held = npc.heldDefenses(s);
  const defenseRows = Object.entries(g.manual.defenses).map(([id, defense]) => ({
    id, name: defense.name, count: s.defenses[id] || 0, held: held[id] || 0,
    unitCost: copy(defense.cost), baseSeconds: defense.time, area: defense.area,
    requirements: copy(defense.requires || []), requirement: g.defenseRequirements(id, 1),
    requirementsText: (defense.requires || []).map(req => `${req.kind === 'building' ? g.buildings[req.id]?.name || req.id : g.manual.technology[req.id]?.name || req.id} ${req.level} 级`).join('、'),
  }));
  const profiles = (npcData.profiles || npc.profiles).filter(p => !p.regional).map(profile => ({
    id: profile.id, name: profile.name, description: profile.description,
    quotes: Array.from({length: profile.id === 'classic' ? npcData.classicMaxLevel : npcData.maxLevel}, (_, i) => {
      const q = npc.challengeQuote(s, profile.id, i + 1);
      return q ? {...copy(q), command: command('requestCityDefense', [q.profile, q.level, q.key])} : null;
    }).filter(Boolean),
  }));
  const incoming = npc.beaconIntel(s);
  const generals = s.generals.map(id => ({id, name: g.general(id).name,
    reason: g.generalBusy(id) ? '守将正在出征或驻守，请选择留城将领' :
      id !== s.governor && Object.values(s.cityRoles || {}).includes(id) ? '主将或军师正在任职，请先卸任；城守可亲自守城' : ''}));
  const civicIds = [...Object.keys(g.manual.civic.comfort), ...Object.keys(g.manual.civic.levyMultipliers).map(id => `levy_${id}`)];
  const salaryAll = g.salaryQuote('all'), status = g.governanceStatus();
  return {
    shared, cityId: g.currentCityId(), cityName: g.cityMeta(g.currentCityId())?.name || '当前城池', now,
    unitNames: Object.fromEntries(Object.entries(g.units).map(([id, unit]) => [id, unit.name])),
    hospital: {quote: {...copy(healAll), command: command('healWounded', ['all', null, healAll.key])},
      rows: hospitalRows, autoHeal: !!s.warCare.autoHeal, lastAuto: copy(healAll.lastAuto)},
    captives: {quote: {...copy(captiveAll), command: command('recruitAllCaptives', [captiveAll.key])}, rows: captiveRows},
    defenses: {capacity: g.defenseCapacity(), used: g.defenseUsed(), rows: defenseRows, queue: copy(s.defenseQueue)},
    defense: {restricted: shared, reason: shared ? PRIVATE_REASON : '', unlocked: npc.unlocked(s),
      profiles, incoming: copy(incoming), autoEnabled: !!s.cityDefense.autoEnabled,
      nextAt: s.cityDefense.nextAt, wave: s.cityDefense.wave, wins: s.cityDefense.wins,
      doctrine: copy(s.warCare.defense), generals, governor: s.governor,
      army: Object.entries(g.units).map(([id, unit]) => ({id, name: unit.name, available: s.army[id] || 0})),
      startReason: s.cityDefense.battle ? '已有守城战或演练正在进行' : s.battle && !s.battle.finished ? '请先结束当前出征战斗' : '',
      battle: copy(s.cityDefense.battle), report: copy(s.cityDefense.drillResult || s.cityDefense.reports[0] || null)},
    civic: {population: s.population, morale: s.morale, unrest: s.unrest,
      wardUntil: s.governance.wardUntil, blessingUntil: s.governance.blessingUntil,
      rows: civicIds.map(id => ({...copy(g.civicOrderPreview(id)), command: command('executeCivicOrder', [id])}))},
    wages: {status: copy(status), quote: {...copy(salaryAll), command: command('payHeroArrears', ['all', salaryAll.key])},
      rows: salaryAll.rows.map(row => {const q = g.salaryQuote(row.id); return {...copy(row), quote: {...copy(q), command: command('payHeroArrears', [row.id, q.key])}};}),
      policies: {eventsEnabled: !!s.governance.eventsEnabled, autoRelief: !!s.governance.autoRelief},
      log: copy(s.governance.log), salaryLog: copy(s.heroService.log)},
  };
}
