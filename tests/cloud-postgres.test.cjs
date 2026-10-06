const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const crypto=require('node:crypto');
const {fixture}=require('./helpers/cloud-http.cjs');

test('real PostgreSQL and verified cloud accounts settle offline loot and return once across server restarts',async t=>{
  const {startPostgresFixture}=await import('./helpers/postgres-fixture.mjs'),
    {openPostgresRoomStore,ROOM_WORLD_TABLE}=await import('../bridge/postgres-room-store.mjs');
  const database=await startPostgresFixture(),namespace='cloud_http_'+crypto.randomBytes(8).toString('hex');let f;
  try{
    f=await fixture(t,{auth:{allowedEmails:['alice@test.invalid','bob@test.invalid','charlie@test.invalid','dave@test.invalid']},
      storageFactory:({now})=>openPostgresRoomStore({connectionString:database.connectionString,namespace,now,requireTLS:false,heartbeatMs:20}),
      readSaved:async()=>JSON.stringify((await database.db.query(`select snapshot from ${ROOM_WORLD_TABLE} where namespace=$1`,[namespace])).rows[0].snapshot)});
  }catch(error){await database.close();throw error;}
  t.after(()=>database.close());
  f.provider.users.set('charlie@test.invalid',{id:'33333333-3333-4333-8333-333333333333',email:'charlie@test.invalid',email_confirmed_at:'2026-01-01T00:00:00Z'});
  f.provider.users.set('dave@test.invalid',{id:'44444444-4444-4444-8444-444444444444',email:'dave@test.invalid',email_confirmed_at:'2026-01-01T00:00:00Z'});
  let alice=await f.login(),bob=await f.login('bob@test.invalid');
  const a=await f.create(alice,4),b=await f.join(bob,a);
  await f.join(await f.login('charlie@test.invalid'),a);const ally=await f.join(await f.login('dave@test.invalid'),a);
  const aid=await f.command(bob,b,'shared.aid',[{targetId:ally.actor.id,general:'lin',army:{cavalry:600,archer:500,spear:300}}]);
  f.at(aid.result.march.arrive);await f.bridge.settle();
  const before=await f.read(alice,a),input={commandId:'postgres_cloud_offline_raid',expectedRevision:before.revision,
    type:'shared.attackPlayer',args:[{targetId:b.actor.id,general:'lin',army:{cavalry:600,archer:500}}]};
  const sent=await f.request(alice,a,'/api/command',input);assert.equal(sent.status,200,JSON.stringify(sent.body));
  const march=sent.body.result.march;f.at(march.arrive);const targetBefore=await f.read(bob,b);await f.restart();
  assert.equal((await f.request(alice,a,'/api/state')).status,401,'RAM account session never survives restart');
  alice=await f.login();bob=await f.login('bob@test.invalid');
  const recovered=await f.request(alice,null,'/lobby/account-resume',{roomId:a.room.id});
  assert.equal(recovered.status,200);assert.equal(recovered.body.actor.id,a.actor.id);assert.equal(recovered.body.authorityId,a.authorityId);
  const fought=await f.read(alice,a),targetFought=await f.read(bob,b),report=fought.shared.reports.find(value=>value.id===march.id);
  assert.equal(report.won,true);assert.equal(report.lootDelivered,false);assert.ok(Object.values(report.loot).some(value=>value>0));
  assert.equal(fought.shared.reports.filter(value=>value.id===march.id).length,1);
  for(const resource of ['food','wood','stone','iron','gold'])assert.equal(targetFought.state.res[resource],targetBefore.state.res[resource]-(report.loot[resource]||0));
  const returning=fought.shared.marches.find(value=>value.id===march.id);assert.equal(returning.status,'return');
  f.at(returning.returnAt);const beforeReturn=await f.read(alice,a);await f.restart();alice=await f.login();
  const delivered=await f.read(alice,a),finalReport=delivered.shared.reports.find(value=>value.id===march.id);
  assert.equal(finalReport.lootDelivered,true);assert.deepEqual(finalReport.receivedResources,report.loot);
  for(const resource of ['food','wood','stone','iron','gold'])assert.equal(delivered.state.res[resource],beforeReturn.state.res[resource]+(report.loot[resource]||0));
  for(const troop of ['cavalry','archer'])assert.equal(delivered.state.army[troop],before.state.army[troop]-({cavalry:600,archer:500}[troop])+report.attacker[troop]);
  const replay=await f.request(alice,a,'/api/command',input);assert.deepEqual(replay.body,{...sent.body,replayed:true});
  const durable=await f.saved();await f.bridge.settle();await f.restart();alice=await f.login();
  assert.equal(await f.saved(),durable);assert.deepEqual((await f.read(alice,a)).state.res,delivered.state.res);
  assert.equal((await f.read(alice,a)).shared.reports.filter(value=>value.id===march.id).length,1);
  assert.equal((await fs.readdir(f.bridge.dataDir)).includes('rooms.json'),false,'cloud storage never falls back to local JSON');
});
