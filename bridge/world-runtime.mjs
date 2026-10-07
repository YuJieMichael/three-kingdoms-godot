import crypto from 'node:crypto';
import fs from 'node:fs';
import {createGameRuntime as originalRuntime, runtimeHash as baseRuntimeHash} from '../vendor/legacy/online/runtime.mjs';
import {resolveWild, wildWeight, wildKey, syncWildFields, validWildFields} from './wild-fields.mjs';

// Extend the bundled factory in memory. The pinned vendor source remains unchanged.
// Guard each anchor: an upstream change must fail clearly, never silently patch a different rule.
let source = originalRuntime.toString();
function replaceOnce(before, after) {
  if (source.split(before).length !== 2) throw new Error('Wild-world runtime anchor changed: ' + before.slice(0, 60));
  source = source.replace(before, after);
}
replaceOnce('function wildTile(x,y,context=state){', `function legacyWildTile(x,y,context=state,override=null){`);
replaceOnce('const seed=hash(x,y),district=', 'const seed=override?.seed??hash(x,y),district=');
replaceOnce("const type=river<1?'lake':district<19?'forest':district<35?'mountain':district<48?'hill':district<61?'swamp':district<80?'grass':'plain';",
  "const type=override?.type||(river<1?'lake':district<19?'forest':district<35?'mountain':district<48?'hill':district<61?'swamp':district<80?'grass':'plain');");
replaceOnce('const level=claim?Math.max(0,claim.level-Math.floor((Date.now()-claim.at)/86400000)):base;',
  'const level=override?.level??(claim?Math.max(0,claim.level-Math.floor((Date.now()-claim.at)/86400000)):base);');
replaceOnce('const weight=hash(x+i*7,y+i*13)%(100-allocated||1);',
  'const weight=(override&&!override.legacy?WildFields.weight(seed,i):hash(x+i*7,y+i*13))%(100-allocated||1);');
replaceOnce('function getWorldTile(x,y,context=state){', `function wildTile(x,y,context=state){
    const override=WildFields.resolve(context,x,y,Date.now());
    return {...legacyWildTile(x,y,context,override),wildKey:WildFields.key(context,x,y,Date.now())};
  }
  function getWorldTile(x,y,context=state){`);
replaceOnce('const api={namedCityProgress,', 'const api={legacyWildTile,namedCityProgress,');
const factory = new Function('WildFields', `return (${source});`)({resolve: resolveWild, weight: wildWeight, key: wildKey});
export const runtimeHash = crypto.createHash('sha256').update(baseRuntimeHash + source)
  .update(fs.readFileSync(new URL('./wild-fields.mjs', import.meta.url)))
  .update(fs.readFileSync(new URL('./world-runtime.mjs', import.meta.url))).digest('hex');
export function createGameRuntime(options = {}) {
  if (options.snapshot && !validWildFields(options.snapshot)) throw new Error('Invalid wild-refresh save');
  const runtime = factory(options), game = runtime.Game;
  const now = options.now ?? Date.now();
  syncWildFields(game, now);
  const save = game.save;
  game.save = () => { syncWildFields(game, now); return save(); };
  return runtime;
}
