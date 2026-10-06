const {test}=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const crypto=require('node:crypto');
const secret=()=>crypto.randomBytes(32).toString('hex');
const ALICE='11111111-1111-4111-8111-111111111111',BOB='22222222-2222-4222-8222-222222222222';


const {fixture}=require('./helpers/cloud-http.cjs');

test('real REST password/getUser chain returns only opaque account session with HttpOnly cookie',async t=>{
  const f=await fixture(t);assert.deepEqual((await f.request(null,null,'/auth/config')).body,{enabled:true});
  const result=await f.request(null,null,'/auth/login',{email:' ALICE@test.invalid ',password:'correct-test-password'},
    {headers:{Origin:f.publicOrigin}});assert.equal(result.status,200);
  assert.match(result.body.sessionToken,/^[a-f0-9]{64}$/);assert.deepEqual(result.body.user,{id:ALICE,email:'alice@test.invalid'});
  assert.deepEqual(Object.keys(result.body).sort(),['ok','sessionToken','user']);
  const cookie=result.headers.get('set-cookie');assert.match(cookie,/HttpOnly/);assert.match(cookie,/SameSite=Strict/);assert.match(cookie,/Path=\//);
  assert.equal(f.provider.calls[0].grant,'password');assert.equal(f.provider.calls[1].path,'/auth/v1/user');
  const me=await f.request(null,null,'/auth/me',undefined,{headers:{Cookie:cookie.split(';')[0],Origin:f.publicOrigin}});
  assert.equal(me.status,200);assert.deepEqual(me.body,{ok:true,user:result.body.user});
  assert.equal(JSON.stringify(me.body).includes('supabase-access'),false);assert.equal(JSON.stringify(me.body).includes('user_metadata'),false);
  assert.equal((await f.saved()).includes('correct-test-password'),false);assert.equal((await f.saved()).includes(result.body.sessionToken),false);
});

test('every protected operation rechecks Supabase user; metadata cannot bind another account',async t=>{
  const f=await fixture(t),alice=await f.login(),a=await f.create(alice),before=f.provider.calls.filter(value=>value.path==='/auth/v1/user').length;
  await f.read(alice,a);await f.request(alice,a,'/api/world');await f.request(alice,a,'/api/health');await f.request(alice,null,'/lobby/mine');
  const after=f.provider.calls.filter(value=>value.path==='/auth/v1/user').length;assert.equal(after-before,4);
  const stored=JSON.parse(await f.saved());assert.equal(stored.rooms[0].members[0].accountId,ALICE);assert.notEqual(stored.rooms[0].members[0].accountId,BOB);
  const mine=await f.request(alice,null,'/lobby/mine');assert.equal(mine.body.rooms.length,1);
  for(const key of ['accessToken','recoveryKey','inviteCode','accountId'])assert.equal(JSON.stringify(mine.body).includes(key),false,key);
});

test('account session and room bearer must both match; recovery secrets never replace cloud identity',async t=>{
  const f=await fixture(t),alice=await f.login(),bob=await f.login('bob@test.invalid'),a=await f.create(alice),b=await f.join(bob,a),durable=await f.saved();
  assert.equal((await f.request(null,a,'/api/state')).status,401);assert.equal((await f.request(alice,null,'/api/state')).status,401);
  assert.equal((await f.request(bob,a,'/api/state')).status,403);assert.equal((await f.request(alice,b,'/api/state')).status,403);
  assert.equal((await f.request(bob,null,'/lobby/account-resume',{roomId:a.room.id})).body.actor.id,b.actor.id);
  assert.equal((await f.request(alice,null,'/lobby/resume',{roomId:a.room.id,recoveryKey:b.recoveryKey})).status,405);
  assert.equal((await f.request(null,null,'/lobby/join',{requestId:secret(),inviteCode:a.inviteCode,playerName:'未登录'})).status,401);
  assert.equal((await f.request(alice,a,'/api/state',undefined,{headers:{Cookie:'tk_account_session='+bob.sessionToken}})).status,401);
  assert.equal(await f.saved(),durable);
});

test('same account across devices recovers one permanent full-room seat and cached enrollments remain own',async t=>{
  const f=await fixture(t),alice1=await f.login(),owner=await f.create(alice1,1),alice2=await f.login(),joined=await f.join(alice2,owner);
  assert.equal(joined.actor.id,owner.actor.id);assert.equal(joined.authorityId,owner.authorityId);assert.equal(joined.room.members.length,1);
  const restore=await f.request(alice2,null,'/lobby/account-resume',{roomId:owner.room.id});assert.equal(restore.status,200);assert.equal(restore.body.accessToken,owner.accessToken);
  const input={requestId:secret(),roomName:'请求绑定',capacity:2,playerName:'本人'};
  const first=await f.request(alice1,null,'/lobby/create',input),same=await f.request(alice2,null,'/lobby/create',input);
  assert.equal(first.status,200);assert.deepEqual(same.body,first.body);
  const bob=await f.login('bob@test.invalid'),foreign=await f.request(bob,null,'/lobby/create',input);
  assert.equal(foreign.status,409);assert.equal(foreign.body.error.code,'ID_REUSED');assert.equal(JSON.stringify(foreign.body).includes(owner.accessToken),false);
});

test('failed getUser and removed user fail closed without reading or mutating game progress',async t=>{
  const f=await fixture(t),alice=await f.login(),member=await f.create(alice),before=await f.read(alice,member),durable=await f.saved();
  f.provider.unavailable=true;
  const denied=await f.request(alice,member,'/api/command',{commandId:'outage_state_write',expectedRevision:before.revision,type:'setTax',args:[35]});
  assert.equal(denied.status,503);assert.equal(denied.body.error.code,'AUTH_UNAVAILABLE');assert.equal(JSON.stringify(denied.body).includes('provider detail'),false);
  assert.equal((await f.request(alice,member,'/api/state')).status,503);assert.equal(await f.saved(),durable);
  f.provider.unavailable=false;f.provider.users.delete('alice@test.invalid');
  assert.equal((await f.request(alice,member,'/api/state')).status,401);assert.equal(await f.saved(),durable);
});

test('refresh rotation is serialized and account identity changes invalidate the opaque session',async t=>{
  const f=await fixture(t),alice=await f.login(),a=await f.create(alice);f.advance(40000);
  const replies=await Promise.all(Array.from({length:6},()=>f.request(alice,a,'/api/health')));
  replies.forEach(reply=>assert.equal(reply.status,200));assert.equal(f.provider.calls.filter(value=>value.grant==='refresh_token').length,1);
  f.provider.identityOverride=f.provider.users.get('bob@test.invalid');
  assert.equal((await f.request(alice,a,'/api/state')).status,401);f.provider.identityOverride=null;
  assert.equal((await f.request(alice,a,'/api/state')).status,401);
});

test('logout revokes RAM immediately, clears cookie and uses only provider local-session logout',async t=>{
  const f=await fixture(t),alice=await f.login(),member=await f.create(alice),other=await f.login();
  const result=await f.request(alice,null,'/auth/logout',{});assert.equal(result.status,200);assert.match(result.headers.get('set-cookie'),/Max-Age=0/);
  assert.equal((await f.request(alice,member,'/api/state')).status,401);assert.equal((await f.request(other,member,'/api/state')).status,200);
  assert.ok(f.provider.calls.some(value=>value.path==='/auth/v1/logout'));
  f.provider.unavailable=true;const failed=await f.request(other,null,'/auth/logout',{});assert.equal(failed.status,503);assert.equal(failed.headers.get('set-cookie'),null);
  f.provider.unavailable=false;assert.equal((await f.request(other,member,'/api/state')).status,401);
  const retry=await f.request(other,null,'/auth/logout',{});assert.equal(retry.status,200);assert.match(retry.headers.get('set-cookie'),/Max-Age=0/);
});

test('Web account context prevents an uncommitted nonce or logout crossing a replaced HttpOnly cookie',async t=>{
  const f=await fixture(t),alice=await f.login(),bob=await f.login('bob@test.invalid'),durable=await f.saved(),
    pending={requestId:secret(),roomName:'原页面未提交的操作',capacity:2,playerName:'原账号席位'},
    cookie=(account,expected)=>({headers:{Cookie:'tk_account_session='+account.sessionToken,Origin:f.publicOrigin,'X-Expected-Account':expected}});
  const switched=await f.request(null,null,'/lobby/create',pending,cookie(bob,ALICE));
  assert.equal(switched.status,401);assert.equal(switched.body.error.code,'ACCOUNT_CHANGED');assert.equal(await f.saved(),durable);
  assert.equal((await f.request(bob,null,'/lobby/mine')).body.rooms.length,0);
  const logoutCalls=f.provider.calls.filter(value=>value.path==='/auth/v1/logout').length;
  const wrongLogout=await f.request(null,null,'/auth/logout',{},cookie(bob,ALICE));
  assert.equal(wrongLogout.status,401);assert.equal(wrongLogout.body.error.code,'ACCOUNT_CHANGED');assert.equal(wrongLogout.headers.get('set-cookie'),null);
  assert.equal(f.provider.calls.filter(value=>value.path==='/auth/v1/logout').length,logoutCalls);
  assert.equal((await f.request(null,null,'/auth/me',undefined,cookie(bob,BOB))).body.user.id,BOB,'other tab account remains logged in');
  const restored=await f.request(null,null,'/lobby/create',pending,cookie(alice,ALICE));assert.equal(restored.status,200);
  assert.equal(JSON.parse(await f.saved()).rooms[0].members[0].accountId,ALICE);
  assert.equal((await f.request(null,null,'/lobby/create',pending,cookie(bob,ALICE))).status,401,'cached receipt never changes the expected account check');
  assert.equal((await f.request(alice,restored.body,'/api/state',undefined,{headers:{'X-Expected-Account':BOB}})).status,401,'expected id cannot override verified authority');
  assert.equal((await f.request(alice,restored.body,'/api/state')).status,200,'omitting context preserves native compatibility');
  const preflight=await fetch(f.bridge.url+'/lobby/create',{method:'OPTIONS',headers:{Origin:f.publicOrigin,'Access-Control-Request-Headers':'X-Expected-Account'}});
  assert.equal(preflight.status,204);assert.match(preflight.headers.get('access-control-allow-headers'),/X-Expected-Account/);
});

test('account credentials cannot be supplied through query/body overrides and foreign CSRF login fails before provider',async t=>{
  const f=await fixture(t),alice=await f.login(),a=await f.create(alice),calls=f.provider.calls.length,durable=await f.saved();
  for(const origin of ['https://evil.invalid','null','http://localhost:17359'])assert.equal((await f.request(null,null,'/auth/login',
    {email:'alice@test.invalid',password:'correct-test-password'},{headers:{Origin:origin}})).status,403);
  assert.equal(f.provider.calls.length,calls);
  assert.equal((await f.request(alice,null,'/lobby/mine?accountId='+BOB)).status,400);
  assert.equal((await f.request(alice,null,'/lobby/account-resume',{roomId:a.room.id,accountId:BOB})).status,400);
  assert.equal((await f.request(alice,null,'/lobby/join',{requestId:secret(),inviteCode:a.inviteCode,playerName:'骗取',accountId:BOB})).status,400);
  assert.equal((await f.request(null,null,'/auth/login',{email:'alice@test.invalid',password:'correct-test-password'},
    {headers:{'Content-Type':'text/plain'}})).status,415);
  assert.equal(await f.saved(),durable);
});

test('closed allowlist, confirmed email and malformed provider responses never authorize metadata claims',async t=>{
  const f=await fixture(t),calls=f.provider.calls.length;
  assert.equal((await f.request(null,null,'/auth/login',{email:'unknown@test.invalid',password:'correct-test-password'})).status,401);
  assert.equal(f.provider.calls.length,calls);
  f.provider.users.get('alice@test.invalid').email_confirmed_at=null;
  assert.equal((await f.request(null,null,'/auth/login',{email:'alice@test.invalid',password:'correct-test-password'})).status,403);
  f.provider.users.get('alice@test.invalid').email_confirmed_at='2026-01-01T00:00:00Z';
  f.provider.tokenUserOverride=f.provider.users.get('bob@test.invalid');
  const alice=await f.login();assert.equal(alice.user.id,ALICE,'password response user field is ignored; fresh /user is authoritative');
});

test('login and protected-operation rate limits apply before forwarding more passwords or game reads',async t=>{
  const f=await fixture(t,{limits:{loginPerMinute:2,requestsPerMinute:2}}),alice=await f.login();await f.login('bob@test.invalid');
  const calls=f.provider.calls.length,result=await f.request(null,null,'/auth/login',{email:'alice@test.invalid',password:'correct-test-password'});
  assert.equal(result.status,429);assert.equal(f.provider.calls.length,calls);
  assert.equal((await f.request(alice,null,'/lobby/mine')).status,200);assert.equal((await f.request(alice,null,'/lobby/mine')).status,200);
  assert.equal((await f.request(alice,null,'/lobby/mine')).status,429);
});

test('room total/per-account limits preserve replay and same-account existing-seat recovery',async t=>{
  const f=await fixture(t,{limits:{maxRooms:1,maxRoomsPerAccount:1}}),alice=await f.login(),bob=await f.login('bob@test.invalid'),owner=await f.create(alice);
  for(const account of [alice,bob]){
    const denied=await f.request(account,null,'/lobby/create',{requestId:secret(),roomName:'超过上限',capacity:2,playerName:'新席位'});
    assert.equal(denied.status,409);assert.equal(denied.body.error.code,'ROOM_LIMIT');
  }
  const joined=await f.join(bob,owner);assert.equal(joined.room.members.length,2);
  assert.equal((await f.join(bob,owner)).actor.id,joined.actor.id);
});

test('RAM sessions expire and do not survive restart; a fresh verified login restores original identity and offline battle',async t=>{
  const f=await fixture(t,{auth:{sessionTTL:60000}}),alice=await f.login(),bob=await f.login('bob@test.invalid'),a=await f.create(alice),b=await f.join(bob,a);
  const before=await f.read(alice,a),sent=await f.command(alice,a,'shared.attackPlayer',[{targetId:b.actor.id,general:'lin',army:{cavalry:500}}]);
  const march=sent.result.march;f.at(march.arrive+Math.max(1000,march.arrive-march.start)+1);await f.restart();
  assert.equal((await f.request(alice,a,'/api/state')).status,401);
  const fresh=await f.login(),restored=await f.request(fresh,null,'/lobby/account-resume',{roomId:a.room.id});
  assert.equal(restored.status,200);assert.equal(restored.body.actor.id,a.actor.id);assert.equal(restored.body.authorityId,a.authorityId);
  const state=await f.read(fresh,restored.body),report=state.shared.reports.find(value=>value.id===march.id);
  assert.ok(report);assert.equal(state.shared.marches.length,0);assert.equal(state.state.army.cavalry,before.state.army.cavalry-500+report.attacker.cavalry);
  f.advance(60001);assert.equal((await f.request(fresh,restored.body,'/api/state')).status,401);
});


test('cloud configuration requires HTTPS origin, storage and publishable Auth key; cookie stays secure outside test mode',async t=>{
  const f=await fixture(t),dummy={authenticate(){},login(){},logout(){}};
  await assert.rejects(f.serverModule.startRoomsServer({...f.config,cloudAccount:{auth:dummy,publicOrigin:'http://game.invalid'}}),/HTTPS/);
  await assert.rejects(f.serverModule.startRoomsServer({...f.config,storageFactory:null,cloudAccount:{auth:dummy,publicOrigin:'https://game.invalid'}}),/storage/);
  assert.throws(()=>f.authModule.createSupabaseAuth({url:'https://project.supabase.co',publishableKey:'sb_secret_forbidden_server_key',allowedEmails:['alice@test.invalid']}),/publishable/);
  const isolated=path.join(f.directory,'secure'),auth=f.authModule.createSupabaseAuth({url:f.provider.url,publishableKey:'sb_publishable_local_test_key',allowedEmails:['alice@test.invalid'],allowInsecureLocal:true,clock:()=>f.now});
  const service=await f.serverModule.startRoomsServer({...f.config,dataDir:isolated,cloudAccount:{auth,publicOrigin:'https://game.invalid'}});
  try{
    const result=await fetch(service.url+'/auth/login',{method:'POST',headers:{'Content-Type':'application/json',Origin:'https://game.invalid'},body:JSON.stringify({email:'alice@test.invalid',password:'correct-test-password'})});
    assert.equal(result.status,200);assert.match(result.headers.get('set-cookie'),/; Secure/);
  }finally{await service.close();}
});

test('public readiness contains no identity and returns503 when injected durable storage loses authority',async t=>{
  const f=await fixture(t),store=await f.storeModule.openRoomStore(path.join(f.directory,'ready'),f.now);let healthy=true;
  store.healthy=()=>healthy;
  const service=await f.serverModule.startRoomsServer({dataDir:path.join(f.directory,'ready'),port:0,storage:store,settlementIntervalMs:0});
  try{
    const first=await fetch(service.url+'/readyz'),ready=await first.json();assert.equal(first.status,200);assert.deepEqual(Object.keys(ready).sort(),['ok','settlement']);
    healthy=false;const result=await fetch(service.url+'/readyz');assert.equal(result.status,503);assert.equal((await result.json()).ok,false);
  }finally{await service.close();}
});
