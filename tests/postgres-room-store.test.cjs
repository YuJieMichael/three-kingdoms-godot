const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
let fixture,connectionString,admin,modulePG,rooms,MemoryStore,handleRequest;
const secret=()=>crypto.randomBytes(32).toString('hex');
const namespace=()=>`test_${secret().slice(0,18)}`;
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));

before(async()=>{
  const [pgFixture,store,roomStore,memory,service]=await Promise.all([
    import('./helpers/postgres-fixture.mjs'),import('../bridge/postgres-room-store.mjs'),
    import('../bridge/room-store.mjs'),import('../vendor/shared/memory-store.mjs'),import('../vendor/shared/service.mjs')]);
  modulePG=store;rooms=roomStore;MemoryStore=memory.MemoryStore;handleRequest=service.handleRequest;
  fixture=await pgFixture.startPostgresFixture();connectionString=fixture.connectionString;admin=fixture.db;
});
after(async()=>{await fixture?.close();});

async function open(t,options={}){
  const store=await modulePG.openPostgresRoomStore({connectionString,namespace:namespace(),requireTLS:false,heartbeatMs:0,...options});
  t.after(()=>store.close());return store;
}
async function register(store,accountId=crypto.randomUUID(),capacity=8){
  return store.transaction(async candidate=>{
    const session=await rooms.createRoom(candidate,{roomName:'数据库攻防',playerName:'测试城主',capacity},Date.now(),accountId);
    candidate.requests.push({id:secret(),operation:'create',hash:secret(),roomId:session.room.id,actorId:session.actor.id,accountId,response:session});
    return session;
  });
}
async function durable(store){return (await admin.query(`select version,snapshot from ${modulePG.ROOM_WORLD_TABLE} where namespace=$1`,[store.namespace])).rows[0];}

test('real PostgreSQL migration creates a private JSONB table with RLS and no client grants',async()=>{
  const version=(await admin.query('show server_version')).rows[0].server_version;assert.match(version,/^17\.10/);
  const table=(await admin.query("select relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='game_private' and c.relname='room_worlds'")).rows[0];
  assert.equal(table.relrowsecurity,true);
  for(const role of ['anon','authenticated']){
    await admin.query(`set role ${role}`);
    try{await assert.rejects(admin.query('select snapshot from game_private.room_worlds'),error=>error.code==='42501');}
    finally{await admin.query('reset role');}
  }
  // A future accidental table grant must still not expose private snapshots:
  // real non-owner roles receive no rows while RLS has no client policies.
  const probe=namespace();
  await admin.query('insert into game_private.room_worlds(namespace,version,snapshot) values($1,1,$2::jsonb)',[probe,JSON.stringify({schema:1,profile:'local-room-rehearsal-1',rooms:[],requests:[]})]);
  for(const role of ['anon','authenticated']){
    await admin.query(`grant usage on schema game_private to ${role}`);
    await admin.query(`grant select on game_private.room_worlds to ${role}`);
    try{
      await admin.query(`set role ${role}`);
      assert.deepEqual((await admin.query('select snapshot from game_private.room_worlds where namespace=$1',[probe])).rows,[]);
    }finally{
      await admin.query('reset role');
      await admin.query(`revoke all on table game_private.room_worlds from ${role}`);
      await admin.query(`revoke all on schema game_private from ${role}`);
    }
  }
  for(const value of [null,[],{},false])await assert.rejects(admin.query('insert into game_private.room_worlds(namespace,version,snapshot) values($1,1,$2::jsonb)',[namespace(),JSON.stringify(value)]),error=>error.code==='23514');
});

test('production DB options require verified TLS and prohibit transaction pooling',()=>{
  for(const url of ['https://db.invalid/x','postgres://a:b@db.invalid:6543/x','postgres://a:b@db.invalid/x?pgbouncer=true','postgres://a:b@db.invalid/x?pool_mode=transaction','postgres://a:b@db.invalid/x?sslmode=no-verify','postgres://a:b@db.invalid/x?sslmode=disable'])assert.throws(()=>modulePG.databaseConnectionOptions(url,true));
  const options=modulePG.databaseConnectionOptions('postgres://a:b@db.invalid:5432/x?sslmode=require',true);
  assert.deepEqual(options.ssl,{rejectUnauthorized:true});assert.ok(!options.connectionString.includes('sslmode'));
  assert.throws(()=>modulePG.advisoryLockKey('bad namespace'));assert.equal(modulePG.advisoryLockKey('three-kingdoms'),modulePG.advisoryLockKey('three-kingdoms'));
});

test('dedicated real PostgreSQL sessions reject a second writer and independently allow another namespace',async t=>{
  const store=await open(t);await register(store);
  await assert.rejects(modulePG.openPostgresRoomStore({connectionString,namespace:store.namespace,requireTLS:false,heartbeatMs:0}),error=>error.code==='SAVE_LOCKED');
  const other=await open(t);assert.equal(other.snapshot().rooms.length,0);
  const before=store.snapshot();await store.close();
  const resumed=await open(t,{namespace:store.namespace});assert.deepEqual(resumed.snapshot(),before);assert.equal(resumed.healthy(),true);
});

test('real DB snapshot commits membership, private credentials and exact registration receipts together',async t=>{
  const store=await open(t),accountId=crypto.randomUUID(),session=await register(store,accountId),saved=await durable(store);
  assert.deepEqual(saved.snapshot,store.snapshot());assert.equal(saved.version,'2');
  assert.deepEqual(store.identityForToken(session.accessToken),{roomId:session.room.id,actorId:session.actor.id});
  assert.equal(store.recover(session.room.id,session.recoveryKey).actor.id,session.actor.id);
  assert.equal(store.identityForToken(session.inviteCode),null);assert.equal(store.recover(session.room.id,session.inviteCode),null);
  assert.equal(saved.snapshot.rooms[0].members[0].accountId,accountId);
  assert.equal(saved.snapshot.requests[0].accountId,accountId);
  const copy=store.snapshot();copy.rooms.length=0;assert.equal(store.snapshot().rooms.length,1);
});

test('one account keeps one existing room seat even at capacity and duplicate account records are rejected',async t=>{
  const store=await open(t),accountId=crypto.randomUUID(),session=await register(store,accountId,1);
  const same=await store.transaction(candidate=>rooms.joinRoom(candidate.rooms[0],'不同昵称',Date.now(),accountId));
  assert.equal(same.actor.id,session.actor.id);assert.equal(store.snapshot().rooms[0].members.length,1);
  await assert.rejects(store.transaction(candidate=>rooms.joinRoom(candidate.rooms[0],'第二账号',Date.now(),crypto.randomUUID())),error=>error.code==='ROOM_FULL');
  const before=await durable(store);
  await assert.rejects(store.transaction(candidate=>{candidate.requests[0].accountId=crypto.randomUUID();}),error=>error.code==='ROOM_SAVE_CORRUPT');
  assert.deepEqual(await durable(store),before);assert.equal(store.healthy(),true);
  const invalid=store.snapshot();invalid.rooms[0].members[0].accountId='not-a-uuid';assert.throws(()=>rooms.validateStored(invalid,Date.now()));
  const duplicate=store.snapshot();duplicate.rooms[0].capacity=2;
  await rooms.joinRoom(duplicate.rooms[0],'不同城主',Date.now(),crypto.randomUUID());
  duplicate.rooms[0].members[1].accountId=accountId.toUpperCase();
  assert.throws(()=>rooms.validateStored(duplicate,Date.now()),error=>error.code==='ROOM_SAVE_CORRUPT');
});

test('adapter serializes parallel candidates so capacity and canonical state cannot lose updates',async t=>{
  const store=await open(t),session=await register(store,crypto.randomUUID(),2);
  const result=await Promise.allSettled(Array.from({length:5},(_,index)=>store.transaction(async candidate=>{
    await delay(4);return rooms.joinRoom(candidate.rooms[0],'城主'+index,Date.now(),crypto.randomUUID());
  })));
  assert.equal(result.filter(value=>value.status==='fulfilled').length,1);
  assert.equal(store.snapshot().rooms[0].members.length,2);assert.equal(store.room(session.room.id).members.length,2);
});

test('SQL failure rolls back durable data and fails closed instead of writing a stale cached snapshot',async t=>{
  const {Client}=await import('pg');let client,injected=false;
  const store=await open(t,{clientFactory:options=>{client=new Client(options);const query=client.query.bind(client);client.query=async(text,values)=>{if(injected&&text.startsWith('update game_private'))throw Object.assign(new Error('injected write failure'),{code:'57014'});return query(text,values);};return client;}});
  await register(store);const before=await durable(store);injected=true;
  await assert.rejects(store.transaction(candidate=>{candidate.rooms[0].name='未提交';}),error=>error.code==='PERSISTENCE_FAILED');
  assert.deepEqual(await durable(store),before);assert.equal(store.health().ok,false);
  assert.throws(()=>store.snapshot());assert.throws(()=>store.room(before.snapshot.rooms[0].id));
  await assert.rejects(store.transaction(()=>{}));
});

test('a lost COMMIT acknowledgement preserves real canonical command receipts and requires restart before reading',async t=>{
  const {Client}=await import('pg');let loseAck=false;
  const store=await open(t,{clientFactory:options=>{const client=new Client(options),query=client.query.bind(client);client.query=async(text,values)=>{const result=await query(text,values);if(loseAck&&text==='commit'){loseAck=false;throw Object.assign(new Error('lost commit ack'),{code:'ECONNRESET'});}return result;};return client;}});
  const session=await register(store),roomId=session.room.id,commandId='database_unknown_ack';loseAck=true;
  const input={op:'command',realm:roomId,commandId,expectedRevision:1,type:'setTax',args:[32]};
  await assert.rejects(store.transaction(async candidate=>{const room=candidate.rooms[0],memory=new MemoryStore(room.data);await handleRequest(memory,session.actor.id,input,Date.now());room.data=memory.data;}));
  assert.equal(store.healthy(),false);assert.throws(()=>store.snapshot());
  const saved=await durable(store);assert.equal(saved.snapshot.rooms[0].data.players[0].state.tax,32);
  assert.equal(saved.snapshot.rooms[0].data.receipts.filter(row=>row.id===commandId).length,1);
  await store.close();const resumed=await open(t,{namespace:store.namespace});
  const memory=new MemoryStore(resumed.snapshot().rooms[0].data),replay=await handleRequest(memory,session.actor.id,input,Date.now());
  assert.equal(replay.replayed,true);assert.equal(memory.data.players[0].state.tax,32);assert.equal(memory.data.receipts.filter(row=>row.id===commandId).length,1);
});

test('CAS version conflict detects unexpected database writes and disables stale cached service',async t=>{
  const store=await open(t);await register(store);await admin.query('update game_private.room_worlds set version=version+1 where namespace=$1',[store.namespace]);
  const before=await durable(store);await assert.rejects(store.transaction(candidate=>{candidate.rooms[0].name='不应覆盖';}),error=>error.code==='REVISION_CONFLICT');
  assert.deepEqual(await durable(store),before);assert.equal(store.healthy(),false);assert.throws(()=>store.snapshot());
});

test('lost advisory ownership and real backend termination fail closed on reads and writes',async t=>{
  const {Client}=await import('pg');let held;
  const store=await open(t,{heartbeatMs:20,clientFactory:options=>(held=new Client(options))});await register(store);
  await held.query('select pg_advisory_unlock_all()');const deadline=Date.now()+3000;while(store.healthy()&&Date.now()<deadline)await delay(20);
  assert.equal(store.healthy(),false);assert.throws(()=>store.identityForToken(secret()));await assert.rejects(store.transaction(()=>{}));
  await store.close();let connection;
  const disconnected=await open(t,{clientFactory:options=>(connection=new Client(options))});
  const pid=(await connection.query('select pg_backend_pid() as pid')).rows[0].pid;
  await admin.query('select pg_terminate_backend($1)',[pid]);const end=Date.now()+3000;while(disconnected.healthy()&&Date.now()<end)await delay(20);
  assert.equal(disconnected.healthy(),false);assert.throws(()=>disconnected.snapshot());
});

test('backups read complete committed snapshots and restoration requires stopped writer plus explicit replacement',async t=>{
  const store=await open(t),session=await register(store),options={connectionString,namespace:store.namespace,requireTLS:false};
  const backup=await modulePG.readPostgresBackup(options);assert.deepEqual(backup.snapshot,store.snapshot());assert.equal(backup.namespace,store.namespace);
  await assert.rejects(modulePG.restorePostgresBackup({...options,snapshot:backup.snapshot,replace:true}),error=>error.code==='SAVE_LOCKED');
  await store.close();await assert.rejects(modulePG.restorePostgresBackup({...options,snapshot:backup.snapshot}),error=>error.code==='RESTORE_TARGET_EXISTS');
  const target=namespace();await modulePG.restorePostgresBackup({...options,namespace:target,snapshot:backup.snapshot});
  const recovered=await open(t,{namespace:target});assert.equal(recovered.recover(session.room.id,session.recoveryKey).actor.id,session.actor.id);await recovered.close();
  const restore=await modulePG.restorePostgresBackup({...options,snapshot:backup.snapshot,replace:true});assert.equal(restore.ok,true);assert.equal(restore.version,'3');
});
