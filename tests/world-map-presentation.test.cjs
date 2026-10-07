const {test} = require('node:test');
const assert = require('node:assert/strict');

const modules = Promise.all([
  import('../vendor/legacy/online/runtime.mjs'),
  import('../bridge/dto.mjs'),
]);
const NOW = 1800000000000;
const hierarchyFields = ['tier', 'tierName', 'district', 'parent', 'children'];

async function fixture() {
  const [{createGameRuntime}, dto] = await modules;
  const runtime = createGameRuntime({now: NOW});
  return {...runtime, dto};
}

test('fresh visible cities use canonical administrative tiers without treating hall level as a capital rank', async () => {
  const f = await fixture(), world = f.dto.worldView(f.Game, NOW);
  assert.equal(world.tiles.length, 64 * 64);
  const home = world.tiles.find(tile => tile.id === 'home');
  assert.deepEqual({tier: home.tier, tierName: home.tierName}, {tier: 'ordinary', tierName: '普通城池'});
  for (const id of ['yellow_qingshi', 'yellow_baisha', 'yellow_chigang']) {
    const tile = world.tiles.find(row => row.id === id), definition = f.NamedCityData.definition(id);
    assert.equal(tile.kind, 'city');
    assert.equal(tile.faction, 'yellow_turban');
    assert.equal(tile.tier, definition.tier);
    assert.equal(tile.tierName, definition.tierName);
  }
  f.Game.state.buildings.hall = 10;
  f.Game.state.cityLevels[14] = 10;
  const advancedHome = f.dto.worldView(f.Game, NOW).tiles.find(tile => tile.id === 'home');
  assert.equal(advancedHome.tier, 'ordinary');
  assert.equal(advancedHome.level, 10);
});

test('county, prefecture, province and capital silhouettes can all use canonical visible-city metadata', async () => {
  const f = await fixture();
  // Prepared visibility fixture only: the real rule accepts previous raids as
  // discovery. No new map, price, ownership or chapter rule is added here.
  for (const definition of f.NamedCityData.definitions) f.Game.state.raided[definition.id] = true;
  f.Game.state.raided.mine = true;
  assert.equal(f.Game.validSave(f.Game.state), true);
  const world = f.dto.worldView(f.Game, NOW), tiers = new Set();
  for (const definition of f.NamedCityData.definitions) {
    const node = f.Game.getNode(definition.id);
    assert.equal(f.Game.landmarkVisible(node.id), true);
    const tile = world.tiles.find(row => row.id === definition.id);
    assert.ok(tile, definition.id);
    const detail = f.dto.nodeView(f.Game, node, NOW);
    for (const projection of [tile, detail]) {
      assert.equal(projection.kind, 'city');
      assert.equal(projection.tier, definition.tier);
      assert.equal(projection.tierName, definition.tierName);
      assert.equal(Object.hasOwn(projection, 'parent'), false);
      assert.equal(Object.hasOwn(projection, 'children'), false);
      assert.equal(Object.hasOwn(projection, 'district'), false);
    }
    tiers.add(tile.tier);
  }
  assert.deepEqual([...tiers].sort(), ['capital', 'county', 'prefecture', 'province']);
});

test('unopened named cities remain anonymous terrain and never trigger a tier lookup', async () => {
  const f = await fixture(), hidden = f.Game.nodes.filter(node => !f.Game.landmarkVisible(node.id))
    .map(node => f.Game.getNode(node.id));
  assert.ok(hidden.some(node => node.namedCity));
  const lookup = f.Game.namedCityProgress, lookedUp = [];
  f.Game.namedCityProgress = id => {lookedUp.push(id); return lookup(id);};
  const world = f.dto.worldView(f.Game, NOW);
  for (const node of hidden) {
    const tile = world.tiles.find(row => row.x === node.x && row.y === node.y);
    for (const projection of [tile, f.dto.nodeView(f.Game, node, NOW)]) {
      assert.equal(projection.hidden, true);
      assert.equal(projection.selectable, false);
      assert.equal(projection.kind, 'wild');
      assert.equal(projection.name, '未发现据点');
      assert.equal(projection.id, `unknown_${node.x}_${node.y}`);
      for (const field of [...hierarchyFields, 'faction', 'namedCity'])
        assert.equal(Object.hasOwn(projection, field), false, `${node.id}: ${field}`);
    }
    assert.equal(lookedUp.includes(node.id), false);
  }
});

test('wilderness and task landmarks receive no administrative city fields', async () => {
  const f = await fixture(), world = f.dto.worldView(f.Game, NOW);
  const wilderness = world.tiles.find(tile => tile.kind === 'wild' && !tile.hidden);
  const task = world.tiles.find(tile => tile.id === 'field');
  assert.ok(wilderness);
  assert.equal(task.kind, 'landmark');
  for (const projection of [wilderness, task, f.dto.nodeView(f.Game, f.Game.getNode('field'), NOW)])
    for (const field of hierarchyFields) assert.equal(Object.hasOwn(projection, field), false);
});

test('map and target presentation do not write discovery, balances, city development or world coordinates', async () => {
  const f = await fixture();
  const before = JSON.stringify(f.Game.state);
  const coordinates = f.Game.nodes.map(node => [node.id, node.x, node.y]);
  const first = f.dto.worldView(f.Game, NOW);
  for (const node of f.Game.nodes) f.dto.nodeView(f.Game, node, NOW);
  const second = f.dto.worldView(f.Game, NOW);
  assert.deepEqual(second, first);
  assert.equal(JSON.stringify(f.Game.state), before);
  assert.deepEqual(f.Game.nodes.map(node => [node.id, node.x, node.y]), coordinates);
  assert.equal(f.Game.validSave(f.Game.state), true);
});
