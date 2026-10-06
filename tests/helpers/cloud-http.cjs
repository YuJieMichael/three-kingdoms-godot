// Test-only HTTP harness; production code never imports this module.
const assert=require('node:assert/strict');
const fs=require('node:fs/promises');
const os=require('node:os');
const path=require('node:path');
const crypto=require('node:crypto');
const secret=()=>crypto.randomBytes(32).toString('hex');
const NOW=1800000000000;

async function fixture(t,options={}) {
  const [serverModule,authModule,storeModule]=await Promise.all([import('../../bridge/room-server.mjs'),import('../../bridge/supabase-auth.mjs'),import('../../bridge/room-store.mjs')]);
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'tk-cloud-'));let now=NOW,bridge,auth,counter=0;
  const {startFakeSupabase}=await import('./fake-supabase.mjs');
  const provider=await startFakeSupabase(()=>now),publicOrigin='http://127.0.0.1:17359';
  const makeAuth=()=>authModule.createSupabaseAuth({url:provider.url,publishableKey:'sb_publishable_local_test_key',
    allowedEmails:[' ALICE@test.invalid ','bob@test.invalid'],allowInsecureLocal:true,clock:()=>now,...options.auth});
  const config={dataDir:path.join(directory,'private'),port:0,clock:()=>now,settlementIntervalMs:0,
    storageFactory:options.storageFactory||(({dataDir,now})=>storeModule.openRoomStore(dataDir,now))};
  const start=async()=>{auth=makeAuth();bridge=await serverModule.startRoomsServer({...config,cloudAccount:{auth,publicOrigin,allowInsecureLocal:true,limits:options.limits}});};
  await start();
  const f={directory,provider,publicOrigin,config,serverModule,authModule,storeModule,get bridge(){return bridge;},get auth(){return auth;},get now(){return now;},
    at(value){assert.ok(value>=now);now=value;},advance(ms){now+=ms;},
    async request(account,member,route,body,extra={}){
      const headers={'Content-Type':'application/json',...extra.headers};
      if(account)headers['X-Account-Session']=account.sessionToken;if(member)headers.Authorization='Bearer '+member.accessToken;
      const response=await fetch(bridge.url+route,{method:body===undefined?'GET':'POST',...extra,headers,...(body===undefined?{}:{body:JSON.stringify(body)})});
      const text=await response.text();let value;try{value=JSON.parse(text);}catch{value=text;}
      return {status:response.status,body:value,headers:response.headers};
    },
    async login(email='alice@test.invalid'){
      const result=await f.request(null,null,'/auth/login',{email,password:'correct-test-password'});assert.equal(result.status,200,JSON.stringify(result.body));return result.body;
    },
    async create(account,capacity=2){const result=await f.request(account,null,'/lobby/create',{requestId:secret(),roomName:'账号房间',capacity,playerName:'创建者'});assert.equal(result.status,200,JSON.stringify(result.body));return result.body;},
    async join(account,member){const result=await f.request(account,null,'/lobby/join',{requestId:secret(),inviteCode:member.inviteCode,playerName:'加入者'});assert.equal(result.status,200,JSON.stringify(result.body));return result.body;},
    async read(account,member){const result=await f.request(account,member,'/api/state');assert.equal(result.status,200,JSON.stringify(result.body));return result.body;},
    async command(account,member,type,args=[]){const before=await f.read(account,member),result=await f.request(account,member,'/api/command',
      {commandId:'cloud_command_'+String(++counter).padStart(8,'0'),expectedRevision:before.revision,type,args});assert.equal(result.status,200,JSON.stringify(result.body));return result.body;},
    async restart(){await bridge.close();await start();},
    saved(){return options.readSaved?options.readSaved():fs.readFile(path.join(bridge.dataDir,'rooms.json'),'utf8');},
  };
  t.after(async()=>{await bridge?.close();await provider.close();await fs.rm(directory,{recursive:true,force:true});});return f;
}

module.exports={fixture};
