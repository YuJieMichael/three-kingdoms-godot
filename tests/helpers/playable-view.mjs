import {createGameRuntime} from '../../vendor/legacy/online/runtime.mjs';
import {gameView, worldView} from '../../bridge/dto.mjs';
const now = 1800000000000, runtime = createGameRuntime({now});
runtime.Game.state.inventory.starterEquipmentBasic = 1;
runtime.Game.state.inventory.starterJewelBox = 1;
// Prepared UI fixture only; natural acquisition is tested by the gameplay path.
runtime.Game.state.army.archer = 30;
runtime.Game.save();
process.stdout.write(JSON.stringify({revision: 0, state: runtime.Game.state,
  view: gameView(runtime.Game, now, runtime), worldSample: worldView(runtime.Game, now)})
  .replace(/[^\x00-\x7f]/g, char => '\\u' + char.charCodeAt(0).toString(16).padStart(4, '0')));
