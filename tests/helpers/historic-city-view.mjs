import {createGameRuntime} from '../../vendor/legacy/online/runtime.mjs';
import {gameView, worldView} from '../../bridge/dto.mjs';

// Prepared developed-city presentation fixture. This never loads a player's save
// and is not a measurement of natural progression or an alternative rule system.
const now = 1800000000000;
const runtime = createGameRuntime({now});
const game = runtime.Game;
const state = game.state;
const sites = state.cityLayout.flatMap((id, site) => id === null ? [site] : []);
const types = game.cityIds.filter(id => id !== 'hall');
for (const [offset, id] of types.entries()) {
  const site = sites[offset];
  state.cityLayout[site] = id;
  state.cityLevels[site] = 4;
  state.buildings[id] = 4;
}
let nextSite = types.length;
for (const id of ['house', 'house', 'barracks', 'warehouse']) {
  const site = sites[nextSite++];
  state.cityLayout[site] = id;
  state.cityLevels[site] = 3;
}
state.cityLevels[14] = 10;
state.buildings.hall = 10;
state.population = 1200;
for (const id of Object.keys(state.res)) state.res[id] = 200000;
state.plots = state.plots.map((plot, index) => ({type: index < 27 ? ['farm', 'farm', 'lumber', 'quarry', 'mine'][index % 5] : null, level: index < 27 ? 3 : 0}));
game.save();
process.stdout.write(JSON.stringify({revision: 0, state, view: gameView(game, now, runtime), worldSample: worldView(game, now)}));
