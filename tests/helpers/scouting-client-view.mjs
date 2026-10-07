// Isolated UI fixtures, not a natural progression claim. Only this in-memory
// starting boundary is prepared; scouting fees, precision, losses, arrival,
// return and expiry below are settled by the frozen canonical runtime.
import assert from 'node:assert/strict';
import {createGameRuntime, executeGame, seededRandom, copy} from '../../vendor/legacy/online/runtime.mjs';
import {gameView, worldView} from '../../bridge/dto.mjs';
import {managementQuote} from '../../bridge/management-quotes.mjs';

const NOW = 1800000000000;
const authorityId = 'isolated-scouting-client-fixture';
let runtime = createGameRuntime({now: NOW, random: seededRandom(11)}), now = NOW, serial = 0;
const g = runtime.Game, state = g.state;
for (const [site, id, level] of [[0, 'house', 10], [1, 'drill', 10], [2, 'barracks', 10], [3, 'academy', 10]]) {
  state.cityLayout[site] = id; state.cityLevels[site] = level; state.buildings[id] = level;
}
state.population = 1000;
state.res = {food: 1000000, wood: 1000000, stone: 1000000, iron: 1000000, gold: 1000000};
state.army.scout = 256; state.army.archer = 30; state.honors.noble = 10;
g.save(); assert.equal(g.validSave(state), true);
const tiles = Array.from({length: 4096}, (_, index) => g.getWorldTile(index % 64, Math.floor(index / 64)));
const targets = tiles.filter(node => node.wild && node.level === 1)
  .sort((a, b) => Math.hypot(a.x - 32, a.y - 32) - Math.hypot(b.x - 32, b.y - 32));
assert.ok(targets.length >= 6);
const plain = tiles.filter(node => node.wild && node.type === 'plain' && !targets.slice(0, 5).some(t => t.id === node.id))
  .sort((a, b) => Math.hypot(a.x - 32, a.y - 32) - Math.hypot(b.x - 32, b.y - 32))[0];
// Prepared ownership, then canonical paid founding supplies a valid second-city scope.
state.conquered[plain.id] = true; state.landClaims[plain.id] = {at: now, level: plain.level};
state.realm.wildOwners[plain.id] = 'capital'; g.save();
assert.equal(g.validSave(state), true);
function command(type, args, sourceCity = 'capital') {
  const result = executeGame(runtime.Game.state, {commandId: 'scout_fixture_' + String(++serial).padStart(6, '0'),
    expectedRevision: 0, type, args, sourceCity}, now, seededRandom(11));
  runtime = result.runtime; assert.equal(runtime.Game.validSave(result.state), true); return result;
}
const found = g.foundCityQuote(plain.id, '隔离分城');
assert.equal(found.reason, ''); command('foundCity', [plain.id, '隔离分城', found.key]);
const secondCity = 'city_' + plain.id;
function envelope(scope, world = false) {
  const before = JSON.stringify(runtime.Game.state);
  const value = {revision: 4, serverTime: now, authorityId, fixtureScope: 'prepared: ' + scope,
    state: copy(runtime.Game.state), view: gameView(runtime.Game, now, runtime)};
  if (world) value.worldSample = worldView(runtime.Game, now);
  assert.equal(JSON.stringify(runtime.Game.state), before, 'Rendering projection is read-only');
  return value;
}
function advance(timestamp) {
  assert.ok(timestamp >= now); now = timestamp;
  runtime = createGameRuntime({snapshot: runtime.Game.state, now, random: seededRandom(11)});
  runtime.Game.tick(now, true); runtime.Game.save();
  assert.equal(runtime.Game.validSave(runtime.Game.state), true);
}
const unknown = envelope('configured scout stock; no obtained intelligence', true);
const quotes = {}, previews = {}, selected = {};
for (const [index, precision, count] of [[0, 'types', 3], [1, 'bands', 15], [2, 'exact', 63], [3, 'failed', 1]]) {
  const node = targets[index]; selected[precision] = unknown.worldSample.tiles.find(tile => tile.id === node.id);
  const previewRuntime = createGameRuntime({snapshot: unknown.state, now: unknown.serverTime});
  previews[precision] = {...managementQuote(previewRuntime, {kind: 'scout', args: [node.id, count], sourceCity: 'capital', requestId: 'preview_' + precision}),
    revision: 4, serverTime: unknown.serverTime, authorityId};
  const before = JSON.stringify(runtime.Game.state);
  quotes[precision] = {...managementQuote(runtime, {kind: 'scout', args: [node.id, count], sourceCity: 'capital', requestId: 'fixture_' + precision}),
    revision: 4, serverTime: now, authorityId};
  assert.equal(JSON.stringify(runtime.Game.state), before);
  assert.equal(quotes[precision].quote.reason, ''); assert.equal(quotes[precision].quote.precision, precision);
  command('dispatchScout', quotes[precision].quote.command.args);
}
const outbound = envelope('four actual paid canonical scout dispatches');
assert.equal(outbound.view.marches.filter(m => m.type === 'scout').length, 4);
const arrivals = runtime.Game.state.scoutQueue.map(m => m.arriveAt);
advance(Math.max(...arrivals));
const returning = envelope('actual canonical arrivals, report grades and losses');
for (const precision of ['types', 'bands', 'exact', 'failed'])
  assert.equal(returning.view.scouting.intelByNode[selected[precision].id].precision, precision);
assert.equal(returning.view.scouting.intelByNode[selected.types.id].army && Object.keys(returning.view.scouting.intelByNode[selected.types.id].army).length, 0);
assert.equal(Object.keys(returning.view.scouting.intelByNode[selected.bands.id].army).length, 0);
assert.ok(Object.keys(returning.view.scouting.intelByNode[selected.exact.id].army).length > 0);
assert.ok(returning.view.marches.filter(m => m.type === 'scout').every(m => !m.canStartBattle && !m.recallCommand && !m.enemySnapshot));
const returnAt = Math.max(...runtime.Game.state.scoutQueue.map(m => m.end));
advance(returnAt);
const returned = envelope('canonical survivors actually restored, scout queues absent');
assert.equal(returned.view.marches.filter(m => m.type === 'scout').length, 0);
const restoredScouts = runtime.Game.state.army.scout;
const arrivalExact = returning.view.scouting.intelByNode[selected.exact.id];
advance(arrivalExact.expiresAt);
const expired = envelope('same revision, later canonical clock at intelligence expiry');
assert.equal(expired.view.scouting.intelByNode[selected.exact.id].precision, 'expired');
assert.deepEqual(expired.view.scouting.intelByNode[selected.exact.id].army, {});
// Removal is a separate legitimate prepared historical-boundary fixture.
runtime = createGameRuntime({snapshot: returned.state, now: returned.serverTime}); now = returned.serverTime;
delete runtime.Game.state.scoutIntel[selected.exact.id]; runtime.Game.save();
const removed = envelope('old obtained report removed; no replacement intelligence');
assert.equal(removed.view.scouting.intelByNode[selected.exact.id], undefined);
runtime = createGameRuntime({snapshot: returned.state, now: returned.serverTime});
command('switchCity', [secondCity], 'capital');
const switched = envelope('canonical switch to separately scoped founded city');
assert.equal(switched.view.city.id, secondCity);
assert.equal(switched.view.scouting.intelByNode[selected.exact.id], undefined);
const sharedBlocked = copy(returned);
sharedBlocked.fixtureScope = 'prepared: UI shared-mode lock only; not a shared-authority snapshot';
sharedBlocked.view.scouting = {supported: false, available: 0, queueUsed: 0, queueLimit: 0, intelByNode: {}};
sharedBlocked.view.nodes = []; sharedBlocked.view.marches = [];
process.stdout.write(JSON.stringify({unknown, outbound, returning, returned, expired, removed, switched, sharedBlocked, selected, quotes, previews,
  meta: {prepared: true, isolated: true, noHTTP: true, noPlayerSave: true, commandCount: serial, secondCity,
    initialScouts: 256, restoredScouts, expectedLost: 1, exactArmy: arrivalExact.army,
    scope: 'Prepared buildings/resources/scout stock/one owned plain; actual paid founding and all scout settlement use canonical commands'}})
  .replace(/[^\x00-\x7f]/g, char => '\\u' + char.charCodeAt(0).toString(16).padStart(4, '0')));
