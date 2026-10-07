// UI-only snapshots. Natural first-battle states come from legal canonical
// commands; later chapter/shared boundaries are explicitly prepared in memory.
// No file, HTTP service, player save, or browser storage is opened here.
import assert from 'node:assert/strict';
import {PacingSession, firstBattle} from '../../scripts/progression_playtest.mjs';
import {createGameRuntime, copy} from '../../vendor/legacy/online/runtime.mjs';
import {gameView, worldView} from '../../bridge/dto.mjs';
import {reportEconomy} from '../../bridge/report-economy.mjs';
import {createRehearsal, SHARED_REALM, REHEARSAL_ACTORS} from '../../bridge/shared-scenario.mjs';
import {MemoryStore} from '../../vendor/shared/memory-store.mjs';
import {handleRequest} from '../../vendor/shared/service.mjs';
import {sharedEnvelope, sharedWorldView} from '../../bridge/shared-dto.mjs';

function envelope(runtime, now, scope, world = false) {
  const before = JSON.stringify(runtime.Game.state);
  const value = {revision: 0, serverTime: now, state: copy(runtime.Game.state),
    view: gameView(runtime.Game, now, runtime), fixtureScope: scope};
  if (world) value.worldSample = worldView(runtime.Game, now);
  assert.equal(JSON.stringify(runtime.Game.state), before, 'UI projection must not change canonical state');
  return value;
}

class CapturedFirstBattle extends PacingSession {
  command(type, args = []) {
    const result = super.command(type, args);
    if (!this.queued) {
      const candidate = envelope(this.runtime, this.now, 'natural: earned current-prerequisite queue');
      if (candidate.view.growth.speedup.suggestion) this.queued = candidate;
    }
    if (type === 'battleRound' && this.state.battle?.finished && !this.battleSettled)
      this.battleSettled = envelope(this.runtime, this.now, 'natural: first battle settled; return separate');
    return result;
  }
}

const session = firstBattle(new CapturedFirstBattle({seed: 604, speedupPolicy: 'cover'}));
assert.ok(session.queued?.view.growth.speedup.suggestion, 'Natural route must earn an owned usable acceleration');
assert.equal(session.state.army.archer, 30);
assert.equal(session.state.stats.victories, 1);
assert.equal(session.state.onboarding.firstBattle, 'complete');
assert.equal(session.state.expedition, null);
assert.equal(session.read().Game.validSave(session.state), true);
assert.ok(!session.report.commands.some(row => ['grantTestSupplies', 'setSpeed', 'importSave', 'claimTrialGems', 'buyItem'].includes(row.type)));
const natural = envelope(session.runtime, session.now, 'natural: fresh seed604, first victory, return and 30-archer refill', true);
const naturalReport = natural.view.reports.find(row => row.node === 'field');
assert.ok(naturalReport?.resourceReceipt?.base?.received && naturalReport?.resourceReceipt?.bonus?.received);
assert.equal(naturalReport.economy.status, 'delivered');

// Historical boundary: deliberately remove only unavailable old proof fields.
// No new receipt or income is created; the same report must become unknown.
const historicalRuntime = createGameRuntime({snapshot: session.state, now: session.now});
const historical = historicalRuntime.Game.state.reports.find(row => row.node === 'field');
delete historical.resourceReceipt;
delete historical.woundedInHospital;
const oldReport = envelope(historicalRuntime, session.now, 'prepared: natural report with legacy proof fields absent');
assert.equal(oldReport.view.reports.find(row => row.node === 'field').economy.status, 'unknown');

// Later chapter boundary verifies immediate UI routing, not natural attainability.
const chapterRuntime = createGameRuntime({snapshot: session.state, now: session.now});
Object.assign(chapterRuntime.Game.state.conquered, {fort: true, north_road: true});
const chapter = envelope(chapterRuntime, session.now, 'prepared: county and first second-chapter occupation', true);
assert.equal(chapter.view.growth.current.navigate.target, 'north_granary');
const completedChapterRuntime = createGameRuntime({snapshot: session.state, now: session.now});
completedChapterRuntime.Game.state.conquered.fort = true;
for (const node of completedChapterRuntime.ChapterData.chapterNodes(2))
  completedChapterRuntime.Game.state.conquered[node.id] = true;
const chapterComplete = envelope(completedChapterRuntime, session.now,
  'prepared: second chapter occupation complete, awards unclaimed', true);
assert.equal(chapterComplete.view.growth.stage.id, 'chapter2_complete');
assert.equal(chapterComplete.view.growth.stage.progress, chapterComplete.view.growth.stage.total);

// Existing rehearsal is a declared prepared scenario. Battle and delivery below
// run the real transaction engine; receivedResources is never fabricated.
const store = new MemoryStore(await createRehearsal(session.now));
let sharedNow = session.now, serial = 0;
const attacker = REHEARSAL_ACTORS[0], defender = REHEARSAL_ACTORS[2];
async function command(type, args = []) {
  const row = store.data.players.find(row => row.id === attacker.id);
  return handleRequest(store, attacker.id, {op: 'command', realm: SHARED_REALM,
    commandId: 'growth_economy_shared_' + String(++serial).padStart(6, '0'),
    expectedRevision: row.revision, type, args}, sharedNow);
}
async function shared(scope, actor = attacker) {
  const context = await store.context(actor.id, SHARED_REALM, null, sharedNow);
  const before = JSON.stringify(context);
  const value = sharedEnvelope(context, actor.id, 'isolated-growth-economy-authority', actor);
  value.fixtureScope = scope;
  assert.equal(JSON.stringify(context), before, 'Shared UI projection must leave its context unchanged');
  return value;
}
const preparedArmy = copy(store.data.players.find(row => row.id === attacker.id).state.army);
const sent = await command('shared.attackPlayer', [{targetId: defender.id, general: 'lin', army: preparedArmy}]);
sharedNow = sent.result.march.arrive;
await command('shared.settle');
const pending = await shared('prepared rehearsal: canonical shared battle; cargo not returned');
const sharedId = sent.result.march.id;
const pendingReport = pending.view.reports.find(row => row.id === sharedId);
assert.equal(pendingReport.economy.status, 'pending');
assert.equal(pendingReport.economy.received, null);
const returnAt = store.data.marches.find(row => row.id === sharedId).returnAt;
assert.ok(returnAt > sharedNow);
sharedNow = returnAt;
const returned = await command('shared.settle');
const actualReturn = returned.result.receipts.find(row => row.id === sharedId && row.status === 'returned');
assert.ok(actualReturn, 'Actual canonical return transaction is the only delivery proof');
const delivered = await shared('prepared rehearsal: actual shared return transaction committed');
const deliveredReport = delivered.view.reports.find(row => row.id === sharedId);
assert.equal(deliveredReport.economy.status, 'delivered');
assert.deepEqual(deliveredReport.economy.received, actualReturn.loot);
const defenderView = await shared('prepared rehearsal: defender aggregate recovery scope', defender);
assert.equal(defenderView.view.reports.find(row => row.id === sharedId).economy.scope, 'defenders-total');
const sharedWorld = sharedWorldView(await store.context(attacker.id, SHARED_REALM, null, sharedNow),
  attacker.id, 'isolated-growth-economy-authority', attacker);

// A boolean alone cannot turn cargo estimates into a confirmed actual deposit.
const proofless = copy(delivered);
const prooflessReport = proofless.view.reports.find(row => row.id === sharedId);
delete prooflessReport.receivedResources;
prooflessReport.economy = reportEconomy(createGameRuntime({snapshot: proofless.state, now: sharedNow}), prooflessReport,
  {shared: true, actor: attacker.id});
assert.equal(prooflessReport.economy.status, 'unknown');

process.stdout.write(JSON.stringify({natural, queued: session.queued, battleSettled: session.battleSettled,
  oldReport, chapter, chapterComplete, pending, delivered, defenderView, proofless, sharedWorld,
  meta: {natural: true, naturalCommands: session.report.commands.length, naturalVictories: session.state.stats.victories,
    earnedGifts: session.state.onboarding.claims, returnedArchers: session.state.army.archer,
    sharedPrepared: true, sharedReportId: sharedId, sharedActualReturn: actualReturn, method: session.report.methodology}})
  .replace(/[^\x00-\x7f]/g, char => '\\u' + char.charCodeAt(0).toString(16).padStart(4, '0')));
