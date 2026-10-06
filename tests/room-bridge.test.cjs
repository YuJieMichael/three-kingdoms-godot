const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const crypto=require('node:crypto');
const NOW=1800000000000;
const secret=()=>crypto.randomBytes(32).toString('hex');

async function fixture(t,options={}) {
  const module=await import('../bridge/room-server.mjs'),directory=await fs.mkdtemp(path.join(os.tmpdir(),'tk-rooms-'));
  let now=NOW,bridge,counter=0;
  const configuration={dataDir:path.join(directory,'private'),port:0,settlementIntervalMs:0,clock:()=>now,...options};
  bridge=await module.startRoomsServer(configuration);
  const api={module,directory,configuration,get bridge(){return bridge;},get now(){return now;},
    at(value){assert.ok(value>=now);now=value;},advance(ms){now+=ms;},
    async request(session,route,body,extra={}){
      const headers={'Content-Type':'application/json',...extra.headers};if(session)headers.Authorization='Bearer '+session.accessToken;
      const response=await fetch(bridge.url+route,{method:body===undefined?'GET':'POST',...extra,headers,
        ...(body===undefined?{}:{body:JSON.stringify(body)})});
      const text=await response.text();let value;try{value=JSON.parse(text);}catch{value=text;}
      return {status:response.status,body:value,headers:response.headers};
    },
    async create(capacity=4,name='测试房间',playerName='青龙'){
      const result=await api.request(null,'/lobby/create',{requestId:secret(),roomName:name,capacity,playerName});
      assert.equal(result.status,200,JSON.stringify(result.body));return result.body;
    },
    async join(owner,playerName='白虎'){
      const result=await api.request(null,'/lobby/join',{requestId:secret(),inviteCode:owner.inviteCode,playerName});
      assert.equal(result.status,200,JSON.stringify(result.body));return result.body;
    },
    async read(session){const result=await api.request(session,'/api/state');assert.equal(result.status,200,JSON.stringify(result.body));return result.body;},
    async command(session,type,args=[],extra={}){
      const before=await api.read(session),result=await api.request(session,'/api/command',
        {commandId:'room_fixture_'+String(++counter).padStart(8,'0'),expectedRevision:before.revision,type,args,...extra});
      assert.equal(result.status,200,JSON.stringify(result.body));return result.body;
    },
    async saved(){return JSON.parse(await fs.readFile(path.join(configuration.dataDir,'rooms.json'),'utf8'));},
    async restart(){await bridge.close();bridge=await module.startRoomsServer(configuration);},
  };
  t.after(async()=>{await bridge?.close();await fs.rm(directory,{recursive:true,force:true});});
  return api;
}

function publicRoom(room) {
  assert.deepEqual(Object.keys(room).filter(key=>key!=='seat').sort(),['capacity','id','members','name']);
  for(const member of room.members)assert.deepEqual(Object.keys(member).sort(),['id','name','seat','team']);
}
function noCredentials(payload,sessions) {
  const text=JSON.stringify(payload);
  for(const session of sessions)for(const key of ['accessToken','recoveryKey','inviteCode'])assert.equal(text.includes(session[key]),false,`leaked ${key}`);
}

test('created and joined seats use equal canonical prepared saves with stable private identities',async t=>{
  const f=await fixture(t),sessions=[await f.create(8)];
  for(let seat=2;seat<=8;seat++)sessions.push(await f.join(sessions[0],'城主'+seat));
  assert.equal(new Set(sessions.map(value=>value.actor.id)).size,8);
  assert.equal(new Set(sessions.map(value=>value.authorityId)).size,8);
  const homes=new Set(),runtime=await import('../vendor/shared/runtime.mjs');
  for(const [index,session]of sessions.entries()){
    const state=await f.read(session),health=await f.request(session,'/api/health');
    assert.equal(session.seat,index+1);assert.match(session.actor.id,/^member_[a-f0-9]{32}$/);
    assert.match(session.room.id,/^room_[a-f0-9]{32}$/);assert.equal(state.actor.id,session.actor.id);
    assert.equal(state.authorityId,session.authorityId);assert.equal(health.body.authorityId,session.authorityId);
    assert.equal(state.state.ruler,session.actor.name);assert.equal(state.state.buildings.hall,5);
    assert.deepEqual(state.state.army,{worker:0,militia:0,scout:0,spear:300,shield:0,archer:500,cavalry:600,heavy:0,wagon:0,ballista:0,ram:0,catapult:0});
    assert.deepEqual(state.state.res,{food:300000,wood:180000,stone:180000,iron:180000,gold:80000});
    assert.equal(runtime.createGameRuntime({snapshot:state.state,now:f.now}).Game.validSave(state.state),true);
    assert.equal(state.room.members.length,8);publicRoom(state.room);publicRoom(health.body.room);noCredentials(state,sessions);noCredentials(health.body,sessions);
    assert.equal(state.room.members[index].team,index%2?'red':'blue');
    homes.add(JSON.stringify(state.shared.players.find(value=>value.id===session.actor.id).home));
    assert.equal(state.shared.players.length,8);
  }
  assert.equal(homes.size,8);
  if(process.platform!=='win32'){
    assert.equal((await fs.stat(f.configuration.dataDir)).mode&0o777,0o700);
    assert.equal((await fs.stat(path.join(f.configuration.dataDir,'rooms.json'))).mode&0o777,0o600);
  }
  await f.restart();for(const session of sessions)assert.equal((await f.read(session)).authorityId,session.authorityId);
});

test('create and join replay exact own response and changed request bodies cannot claim another seat',async t=>{
  const f=await fixture(t),input={requestId:secret(),roomName:'幂等创建',capacity:2,playerName:'创建者'};
  const replies=await Promise.all(Array.from({length:8},()=>f.request(null,'/lobby/create',input)));
  replies.forEach(reply=>{assert.equal(reply.status,200);assert.deepEqual(reply.body,replies[0].body);});
  const owner=replies[0].body;assert.equal(f.bridge.snapshot().rooms.length,1);
  const join={requestId:secret(),inviteCode:owner.inviteCode,playerName:'第二席'};
  const joins=await Promise.all(Array.from({length:8},()=>f.request(null,'/lobby/join',join)));
  joins.forEach(reply=>{assert.equal(reply.status,200);assert.deepEqual(reply.body,joins[0].body);});
  assert.equal(f.bridge.snapshot().rooms[0].members.length,2);
  const durable=JSON.stringify(await f.saved());
  for(const [route,body]of [['/lobby/create',{...input,capacity:3}],['/lobby/join',{...join,playerName:'不同名字'}],
    ['/lobby/join',{...join,requestId:input.requestId}]]){
    const result=await f.request(null,route,body);assert.equal(result.status,409);assert.equal(result.body.error.code,'ID_REUSED');
  }
  assert.equal(JSON.stringify(await f.saved()),durable);
  await f.restart();assert.deepEqual((await f.request(null,'/lobby/create',input)).body,owner);
  assert.deepEqual((await f.request(null,'/lobby/join',join)).body,joins[0].body);
});

test('parallel joins cannot exceed capacity and full rooms still resume existing members',async t=>{
  const f=await fixture(t),owner=await f.create(8),replies=await Promise.all(Array.from({length:12},(_,index)=>
    f.request(null,'/lobby/join',{requestId:secret(),inviteCode:owner.inviteCode,playerName:'来客'+index})));
  assert.equal(replies.filter(value=>value.status===200).length,7);
  assert.equal(replies.filter(value=>value.status===409&&value.body.error.code==='ROOM_FULL').length,5);
  const members=(await f.read(owner)).room.members;assert.equal(members.length,8);
  assert.deepEqual(members.map(value=>value.seat).sort((a,b)=>a-b),[1,2,3,4,5,6,7,8]);
  const resumed=await f.request(null,'/lobby/resume',{roomId:owner.room.id,recoveryKey:owner.recoveryKey});
  assert.equal(resumed.status,200);assert.equal(resumed.body.actor.id,owner.actor.id);assert.equal(resumed.body.room.members.length,8);
  assert.equal((await f.request(null,'/lobby/resume',{roomId:owner.room.id,recoveryKey:secret()})).status,401);
});

test('capacity-one room can play, invite nobody and recover without creating a second player',async t=>{
  const f=await fixture(t),owner=await f.create(1);
  const denied=await f.request(null,'/lobby/join',{requestId:secret(),inviteCode:owner.inviteCode,playerName:'旁人'});
  assert.equal(denied.status,409);assert.equal(denied.body.error.code,'ROOM_FULL');
  const changed=await f.command(owner,'setTax',[35]);assert.equal(changed.state.tax,35);
  await f.restart();assert.equal((await f.read(owner)).state.tax,35);
  const resumed=await f.request(null,'/lobby/resume',{roomId:owner.room.id,recoveryKey:owner.recoveryKey});
  assert.equal(resumed.status,200);assert.equal(resumed.body.accessToken,owner.accessToken);assert.equal(resumed.body.authorityId,owner.authorityId);
  assert.equal(resumed.body.room.members.length,1);
});

test('room isolation prevents foreign nodes, attacks, recovery and entity-id interference',async t=>{
  const f=await fixture(t),a=await f.create(2,'甲房'),a2=await f.join(a),b=await f.create(2,'乙房'),b2=await f.join(b);
  for(const session of [a,a2]){
    const state=await f.read(session);assert.deepEqual(state.shared.players.map(value=>value.id).sort(),[a.actor.id,a2.actor.id].sort());
    assert.equal(JSON.stringify(state).includes(b.actor.id),false);assert.equal(JSON.stringify(state).includes(b2.actor.id),false);
    assert.equal((await f.request(session,'/api/node?id='+encodeURIComponent('player_city:'+b.actor.id+':capital'))).status,404);
  }
  assert.equal((await f.request(null,'/lobby/resume',{roomId:b.room.id,recoveryKey:a.recoveryKey})).status,401);
  const before=await f.read(a),denied=await f.request(a,'/api/command',{commandId:'foreign_target_attack',expectedRevision:before.revision,
    type:'shared.attackPlayer',args:[{targetId:b.actor.id,general:'lin',army:{cavalry:10}}]});
  assert.equal(denied.status,400);assert.deepEqual((await f.read(a)).state.army,before.state.army);
  const sameId='same_entity_separate_rooms';
  for(const [actor,target]of [[a,a2],[b,b2]]){
    const result=await f.command(actor,'shared.attackPlayer',[{targetId:target.actor.id,general:'lin',army:{cavalry:10}}],{commandId:sameId});
    assert.equal(result.result.march.id,sameId);
  }
  assert.equal(f.bridge.snapshot().rooms.every(room=>room.data.marches.length===1),true);
  assert.equal((await f.request(a,'/api/state?roomId='+b.room.id)).status,400);
});

test('unauthenticated APIs, forged client authority and foreign browser origins cannot mutate rooms',async t=>{
  const f=await fixture(t),owner=await f.create(),before=await f.read(owner),durable=JSON.stringify(await f.saved());
  for(const route of ['/health','/api/health','/state','/api/world','/node']){
    assert.equal((await f.request(null,route)).status,401);assert.equal((await f.request({accessToken:secret()},route)).status,401);
  }
  const command={commandId:'forged_room_command',expectedRevision:before.revision,type:'setTax',args:[35]};
  for(const forged of [{...command,roomId:owner.room.id},{...command,actorId:owner.actor.id},{...command,state:before.state},
    {...command,type:'shared.settle'},{...command,args:[{now:0}]},{...command,type:'setSpeed',args:[100]}])
    assert.ok((await f.request(owner,'/api/command',forged)).status>=400);
  for(const origin of ['https://evil.example','null','http://127.0.0.1:1']){
    assert.equal((await f.request(owner,'/api/state',undefined,{headers:{Origin:origin}})).status,403);
    assert.equal((await f.request(null,'/lobby/create',{requestId:secret(),roomName:'跨域',capacity:1,playerName:'无效'},
      {headers:{Origin:origin}})).status,403);
  }
  assert.equal((await f.request(owner,'/api/state',undefined,{headers:{Origin:f.bridge.url}})).status,200);
  assert.equal((await f.request(owner,'/api/import',{state:before.state})).status,405);
  assert.equal((await f.request(owner,'/api/export')).status,405);
  assert.equal(JSON.stringify(await f.saved()),durable);
});

test('lobby inputs reject unknown fields, malformed secrets, inherited names and invalid capacities',async t=>{
  const f=await fixture(t),base={requestId:secret(),roomName:'测试',capacity:4,playerName:'城主'},durable=JSON.stringify(await f.saved());
  for(const body of [null,[],{...base,capacity:0},{...base,capacity:9},{...base,capacity:1.2},{...base,requestId:'short'},
    {...base,playerName:''},{...base,playerName:'x'.repeat(21)},{...base,playerName:'a\nb'},{...base,roomName:'x'.repeat(41)},
    {...base,actorId:'victim'},{...base,state:{}},{...base,now:0}])
    assert.ok((await f.request(null,'/lobby/create',body)).status>=400);
  assert.equal((await f.request(null,'/lobby/join',{requestId:secret(),inviteCode:secret(),playerName:'城主'})).status,401);
  assert.equal((await f.request(null,'/lobby/create')).status,405);
  assert.equal((await f.request(null,'/lobby/create?roomId=other',base)).status,400);
  assert.equal(JSON.stringify(await f.saved()),durable);
});

test('allied stationed troops can be recalled and automatically returned without manual battle actions',async t=>{
  const f=await fixture(t),a=await f.create(3),enemy=await f.join(a),ally=await f.join(a),before=await f.read(ally);
  const sent=await f.command(ally,'shared.aid',[{targetId:a.actor.id,general:'lin',army:{spear:50}}]);
  assert.equal(sent.state.army.spear,before.state.army.spear-50);
  const incoming=(await f.read(a)).shared.marches.find(value=>value.id===sent.result.march.id);
  assert.equal(incoming.army,undefined);assert.equal(incoming.general,undefined);assert.equal(incoming.count,null);
  assert.equal((await f.read(enemy)).shared.marches.length,0);
  f.at(sent.result.march.arrive+1);await f.bridge.settle();
  const stationed=(await f.read(ally)).shared.marches.find(value=>value.id===sent.result.march.id);
  assert.equal(stationed.status,'stationed');assert.equal(stationed.recallCommand.type,'shared.recallAid');
  const recalled=await f.command(ally,'shared.recallAid',[{id:stationed.id}]);f.at(recalled.result.returnAt+1);
  await f.restart();const returned=await f.read(ally);
  assert.equal(returned.shared.marches.length,0);assert.equal(returned.state.army.spear,before.state.army.spear);
  const durable=JSON.stringify(await f.saved());await f.bridge.settle();assert.equal(JSON.stringify(await f.saved()),durable);
});

test('server settles battle offline once, keeps participants reports equal and exact cached acknowledgement coherent',async t=>{
  const f=await fixture(t),a=await f.create(3),enemy=await f.join(a),unrelated=await f.join(a),before=await f.read(a);
  const input={commandId:'offline_room_battle',expectedRevision:before.revision,type:'shared.attackPlayer',
    args:[{targetId:enemy.actor.id,general:'lin',army:{cavalry:500}}]};
  const sent=await f.request(a,'/api/command',input);assert.equal(sent.status,200,JSON.stringify(sent.body));
  const enemyMarch=(await f.read(enemy)).shared.marches[0];assert.equal(enemyMarch.army,undefined);assert.equal(enemyMarch.general,undefined);
  assert.equal((await f.read(unrelated)).shared.marches.length,0);
  const march=sent.body.result.march;f.at(march.arrive+Math.max(1000,march.arrive-march.start)+1);await f.restart();
  const attacker=await f.read(a),defender=await f.read(enemy),report=attacker.shared.reports.find(value=>value.id===march.id);
  assert.ok(report);assert.equal(attacker.shared.marches.length,0);assert.equal((await f.read(unrelated)).shared.reports.length,0);
  const defenderReport=defender.shared.reports.find(value=>value.id===march.id);
  for(const key of ['attacker','defender','lost','defenderLost','wounded','defenderWounded','loot','log','won'])assert.deepEqual(report[key],defenderReport[key]);
  assert.equal(report.attacker.cavalry+report.lost.cavalry+report.wounded.cavalry,500);
  assert.equal(attacker.state.army.cavalry,before.state.army.cavalry-500+report.attacker.cavalry);
  const replay=await f.request(a,'/api/command',input);assert.deepEqual(replay.body,{...sent.body,replayed:true});
  const durable=JSON.stringify(await f.saved());await f.bridge.settle();assert.equal(JSON.stringify(await f.saved()),durable);
  assert.deepEqual((await f.read(a)).state.army,attacker.state.army);
});

test('same-room entity-id collisions cannot spend troops while independent actor command receipts remain valid',async t=>{
  const f=await fixture(t),a=await f.create(4),b=await f.join(a),c=await f.join(a),d=await f.join(a);
  const first=await f.command(a,'shared.attackPlayer',[{targetId:b.actor.id,general:'lin',army:{cavalry:10}}],{commandId:'same_room_entity_id'});
  const before=await f.read(c),durable=JSON.stringify(await f.saved());
  const denied=await f.request(c,'/api/command',{commandId:first.result.march.id,expectedRevision:before.revision,
    type:'shared.attackPlayer',args:[{targetId:d.actor.id,general:'lin',army:{cavalry:10}}]});
  assert.equal(denied.status,409);assert.equal(denied.body.error.code,'ENTITY_ID_REUSED');assert.equal(JSON.stringify(await f.saved()),durable);
  for(const session of [c,d])await f.command(session,'setTax',[30],{commandId:'same_id_private_tax'});
  assert.equal((await f.read(c)).state.tax,30);assert.equal((await f.read(d)).state.tax,30);
});

test('winning room raid deducts defender stock and brings real loot home exactly once',async t=>{
  const f=await fixture(t),a=await f.create(4),b=await f.join(a);await f.join(a);const ally=await f.join(a);
  // Both sides started equally. The defender deliberately commits its army away as aid.
  const aid=await f.command(b,'shared.aid',[{targetId:ally.actor.id,general:'lin',army:{cavalry:600,archer:500,spear:300}}]);
  f.at(aid.result.march.arrive);await f.bridge.settle();
  const before=await f.read(a),input={commandId:'winning_equal_start_raid',expectedRevision:before.revision,type:'shared.attackPlayer',
    args:[{targetId:b.actor.id,general:'lin',army:{cavalry:600,archer:500}}]};
  const sent=await f.request(a,'/api/command',input);assert.equal(sent.status,200,JSON.stringify(sent.body));
  const march=sent.body.result.march;f.at(march.arrive);
  const beforeBattle=await f.read(a),targetBefore=await f.read(b);await f.bridge.settle();
  const fought=await f.read(a),targetFought=await f.read(b),report=fought.shared.reports.find(value=>value.id===march.id);
  assert.equal(report.won,true);assert.ok(Object.values(report.loot).some(value=>value>0));
  assert.equal(report.lootDelivered,false);assert.deepEqual(report.receivedResources,{});
  for(const resource of ['food','wood','stone','iron','gold']){
    assert.equal(targetFought.state.res[resource],targetBefore.state.res[resource]-(report.loot[resource]||0));
    assert.equal(fought.state.res[resource],beforeBattle.state.res[resource]);
  }
  const returning=fought.shared.marches.find(value=>value.id===march.id);f.at(returning.returnAt);
  const beforeReturn=await f.read(a);await f.bridge.settle();const delivered=await f.read(a);
  for(const resource of ['food','wood','stone','iron','gold'])assert.equal(delivered.state.res[resource],beforeReturn.state.res[resource]+(report.loot[resource]||0));
  const finalReport=delivered.shared.reports.find(value=>value.id===march.id);
  assert.equal(finalReport.lootDelivered,true);assert.deepEqual(finalReport.receivedResources,report.loot);
  const replay=await f.request(a,'/api/command',input);assert.deepEqual(replay.body,{...sent.body,replayed:true});
  const durable=JSON.stringify(await f.saved());await f.bridge.settle();await f.restart();
  assert.equal(JSON.stringify(await f.saved()),durable);assert.deepEqual((await f.read(a)).state.res,delivered.state.res);
});

test('automatic scheduler settles due aid while every client is offline',async t=>{
  const f=await fixture(t,{settlementIntervalMs:20}),a=await f.create(3);await f.join(a);const ally=await f.join(a);
  const sent=await f.command(ally,'shared.aid',[{targetId:a.actor.id,general:'lin',army:{spear:20}}]);
  f.at(sent.result.march.arrive+1);
  const deadline=Date.now()+3000;
  while(f.bridge.snapshot().rooms[0].data.marches[0].status!=='stationed'&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,20));
  assert.equal(f.bridge.snapshot().rooms[0].data.marches[0].status,'stationed');
  assert.equal((await f.request(a,'/api/health')).body.settlement.ok,true);
});

test('failed settlement persistence rolls back all participants, marching escrow and reports atomically',async t=>{
  const f=await fixture(t),a=await f.create(2),b=await f.join(a),sent=await f.command(a,'shared.attackPlayer',
    [{targetId:b.actor.id,general:'lin',army:{cavalry:500}}]);f.at(sent.result.march.arrive);
  const filename=path.join(f.bridge.dataDir,'rooms.json'),durable=await fs.readFile(filename,'utf8'),originalRename=fs.rename;let injected=false;
  fs.rename=async(...args)=>{if(!injected&&args[1]===filename){injected=true;throw Object.assign(new Error('injected'),{code:'ENOSPC'});}return originalRename(...args);};
  try{await assert.rejects(f.bridge.settle(),error=>error.code==='PERSISTENCE_FAILED');}finally{fs.rename=originalRename;}
  assert.equal(injected,true);assert.equal(await fs.readFile(filename,'utf8'),durable);assert.deepEqual(f.bridge.snapshot(),JSON.parse(durable));
  assert.equal((await f.read(a)).shared.reports.length,0);assert.equal((await f.read(b)).shared.reports.length,0);
  await f.bridge.settle();assert.equal((await f.read(a)).shared.reports.length,1);assert.equal((await f.read(b)).shared.reports.length,1);
});

test('command retries and parallel revisions debit only once and reads never rewrite authoritative data',async t=>{
  const f=await fixture(t),a=await f.create(),before=await f.read(a),input={commandId:'repeat_private_trade',expectedRevision:before.revision,type:'trade',args:['food',100,true]};
  const results=await Promise.all(Array.from({length:10},()=>f.request(a,'/api/command',input)));
  results.forEach(reply=>assert.equal(reply.status,200));assert.equal(results.filter(reply=>reply.body.replayed).length,9);
  const after=await f.read(a);assert.equal(after.state.res.gold,before.state.res.gold-100);
  const concurrency=await Promise.all(Array.from({length:5},(_,index)=>f.request(a,'/api/command',{
    commandId:'parallel_trade_'+index,expectedRevision:after.revision,type:'trade',args:['food',7,true]})));
  assert.equal(concurrency.filter(reply=>reply.status===200).length,1);assert.equal(concurrency.filter(reply=>reply.status===409).length,4);
  const durable=await fs.readFile(path.join(f.configuration.dataDir,'rooms.json'),'utf8');f.advance(600001);
  await f.read(a);await f.request(a,'/api/world');await f.request(a,'/api/health');
  assert.equal(await fs.readFile(path.join(f.configuration.dataDir,'rooms.json'),'utf8'),durable);
});

test('failed create and join atomic commits retain exact world and allow same requests to retry',async t=>{
  const f=await fixture(t),filename=path.join(f.bridge.dataDir,'rooms.json'),originalRename=fs.rename;
  const failOnce=async action=>{
    const durable=await fs.readFile(filename,'utf8');let injected=false,result;
    fs.rename=async(...args)=>{if(!injected&&args[1]===filename){injected=true;throw Object.assign(new Error('injected'),{code:'ENOSPC'});}return originalRename(...args);};
    try{result=await action();}finally{fs.rename=originalRename;}
    assert.equal(injected,true);assert.equal(result.status,503);assert.equal(result.body.error.code,'PERSISTENCE_FAILED');
    assert.equal(await fs.readFile(filename,'utf8'),durable);assert.deepEqual(f.bridge.snapshot(),JSON.parse(durable));
  };
  const create={requestId:secret(),roomName:'写入恢复',capacity:2,playerName:'创建'};
  await failOnce(()=>f.request(null,'/lobby/create',create));const owner=(await f.request(null,'/lobby/create',create)).body;
  assert.equal(f.bridge.snapshot().rooms.length,1);
  const join={requestId:secret(),inviteCode:owner.inviteCode,playerName:'加入'};
  await failOnce(()=>f.request(null,'/lobby/join',join));assert.equal((await f.request(null,'/lobby/join',join)).status,200);
  assert.equal(f.bridge.snapshot().rooms[0].members.length,2);await f.restart();assert.equal((await f.read(owner)).room.members.length,2);
});

test('failed command atomic commit preserves balances and can replay only after a successful retry',async t=>{
  const f=await fixture(t),owner=await f.create(),before=await f.read(owner),filename=path.join(f.bridge.dataDir,'rooms.json'),durable=await fs.readFile(filename,'utf8');
  const input={commandId:'failed_room_trade',expectedRevision:before.revision,type:'trade',args:['food',100,true]},originalRename=fs.rename;let injected=false,denied;
  fs.rename=async(...args)=>{if(!injected&&args[1]===filename){injected=true;throw Object.assign(new Error('injected'),{code:'ENOSPC'});}return originalRename(...args);};
  try{denied=await f.request(owner,'/api/command',input);}finally{fs.rename=originalRename;}
  assert.equal(denied.status,503);assert.equal(await fs.readFile(filename,'utf8'),durable);assert.deepEqual((await f.read(owner)).state.res,before.state.res);
  const retry=await f.request(owner,'/api/command',input);assert.equal(retry.status,200);assert.equal(retry.body.replayed,false);
  const replay=await f.request(owner,'/api/command',input);assert.equal(replay.status,200);assert.deepEqual(replay.body,{...retry.body,replayed:true});
});

test('post-rename directory sync failure restores membership, credentials and join receipt together',
  {skip:process.platform==='win32'},async t=>{
  const f=await fixture(t),owner=await f.create(2),filename=path.join(f.bridge.dataDir,'rooms.json'),
    durable=await fs.readFile(filename,'utf8'),join={requestId:secret(),inviteCode:owner.inviteCode,playerName:'加入者'};
  const originalOpen=fs.open;let injected=false,denied;
  fs.open=async(...args)=>{
    const handle=await originalOpen(...args);
    if(!injected&&args[0]===f.bridge.dataDir&&args[1]==='r'){
      injected=true;return {async sync(){throw Object.assign(new Error('injected directory fsync'),{code:'EIO'});},close:()=>handle.close()};
    }
    return handle;
  };
  try{denied=await f.request(null,'/lobby/join',join);}finally{fs.open=originalOpen;}
  assert.equal(injected,true);assert.equal(denied.status,503);assert.equal(await fs.readFile(filename,'utf8'),durable);
  assert.deepEqual(f.bridge.snapshot(),JSON.parse(durable));await f.restart();
  assert.equal((await f.read(owner)).room.members.length,1);
  const retry=await f.request(null,'/lobby/join',join);assert.equal(retry.status,200);assert.equal(retry.body.room.members.length,2);
  assert.deepEqual((await f.request(null,'/lobby/join',join)).body,retry.body);
});

test('root lock prevents two writers and corrupt worlds are retained rather than regenerated',async t=>{
  const f=await fixture(t),owner=await f.create(),filename=path.join(f.configuration.dataDir,'rooms.json');
  await assert.rejects(f.module.startRoomsServer(f.configuration),error=>error.code==='SAVE_LOCKED');
  await f.bridge.close();const saved=JSON.parse(await fs.readFile(filename,'utf8'));saved.rooms[0].members[0].authorityId='invalid';
  const corrupt=JSON.stringify(saved);await fs.writeFile(filename,corrupt);
  await assert.rejects(f.module.startRoomsServer(f.configuration),error=>error.code==='ROOM_SAVE_CORRUPT');
  assert.equal(await fs.readFile(filename,'utf8'),corrupt);
  await fs.writeFile(filename,'{corrupt');await assert.rejects(f.module.startRoomsServer(f.configuration));assert.equal(await fs.readFile(filename,'utf8'),'{corrupt');
  assert.ok(owner.recoveryKey);
});

test('room service refuses four-account save directories and public listening addresses',async t=>{
  const f=await fixture(t),legacy=path.join(f.directory,'legacy');await fs.mkdir(legacy);
  await fs.writeFile(path.join(legacy,'credentials.json'),'existing private credentials');
  await assert.rejects(f.module.startRoomsServer({...f.configuration,dataDir:legacy}),error=>error.code==='ROOM_DIRECTORY_CONFLICT');
  assert.equal(await fs.readFile(path.join(legacy,'credentials.json'),'utf8'),'existing private credentials');
  await assert.rejects(fs.access(path.join(legacy,'rooms.json')),error=>error.code==='ENOENT');
  const privateSave=path.join(f.directory,'private-progress');await fs.mkdir(privateSave);
  await fs.writeFile(path.join(privateSave,'save.json'),'existing private progress');
  await assert.rejects(f.module.startRoomsServer({...f.configuration,dataDir:privateSave}),error=>error.code==='ROOM_DIRECTORY_CONFLICT');
  assert.equal(await fs.readFile(path.join(privateSave,'save.json'),'utf8'),'existing private progress');
  await assert.rejects(fs.access(path.join(privateSave,'rooms.json')),error=>error.code==='ENOENT');
  for(const host of ['0.0.0.0','192.168.1.1'])await assert.rejects(f.module.startRoomsServer({...f.configuration,host}),/loopback/);
});

test('existing falsy JSON and primitive room files fail closed without replacement',async t=>{
  const f=await fixture(t),filename=path.join(f.bridge.dataDir,'rooms.json');await f.bridge.close();
  for(const source of ['null','false','0','""','[]','"not a room collection"']){
    await fs.writeFile(filename,source);
    await assert.rejects(f.module.startRoomsServer(f.configuration),error=>error.code==='ROOM_SAVE_CORRUPT');
    assert.equal(await fs.readFile(filename,'utf8'),source,'must preserve '+source);
  }
});

test('static lobby and game resources never expose room credentials or symlink escapes',async t=>{
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'tk-room-web-')),webDir=path.join(directory,'web'),lobbyFile=path.join(directory,'lobby.html');
  await fs.mkdir(webDir);await fs.writeFile(path.join(webDir,'index.html'),'<html>game</html>');await fs.writeFile(lobbyFile,'<html>lobby</html>');
  const f=await fixture(t,{webDir,lobbyFile});t.after(()=>fs.rm(directory,{recursive:true,force:true}));const owner=await f.create();
  await fs.symlink(path.join(f.configuration.dataDir,'rooms.json'),path.join(webDir,'leak.json'));
  const lobby=await f.request(null,'/lobby'),game=await f.request(null,'/');
  assert.equal(lobby.body,'<html>lobby</html>');assert.equal(game.body,'<html>game</html>');assert.equal(lobby.headers.get('cross-origin-opener-policy'),'same-origin');
  for(const route of ['/rooms.json','/.shared-bridge.lock','/leak.json','/%5cprivate/rooms.json','/%2e%2e%2fprivate/rooms.json']){
    const result=await f.request(null,route);assert.ok(result.status>=400);noCredentials(result.body,[owner]);
  }
  await assert.rejects(f.module.startRoomsServer({...f.configuration,dataDir:path.join(webDir,'private')}),/separate/);
  await assert.rejects(f.module.startRoomsServer({...f.configuration,readyFile:path.join(f.configuration.dataDir,'rooms.json')}),/private/);
});
