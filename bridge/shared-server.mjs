import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {GameError, validateInput, gameActions, runtimeHash, copy} from '../vendor/shared/runtime.mjs';
import {handleRequest} from '../vendor/shared/service.mjs';
import {openSharedStore, atomicSharedJSON} from './shared-store.mjs';
import {sharedEnvelope, sharedWorldView, sharedNodeView} from './shared-dto.mjs';
import {SHARED_REALM} from './shared-scenario.mjs';

const MAX_BODY=128*1024,MAX_PENDING=64;
const within=(root,target)=>target===root||target.startsWith(root+path.sep);
const object=value=>!!value&&typeof value==='object'&&!Array.isArray(value);
const namespaces=/^(?:wild\.(?:discover|buyPortrait|recruit|reward|release)|hero\.(?:allocate|reset|drill|gift|equip|unequip|forge|enhance|salvage|expand)|heritage\.(?:assign|promote|salary|startGather|collectGather|cancelGather)|war\.exchange|onboarding\.(?:claim|claimAvailable|openItem|hide))$/;
const sharedActions=new Set(['shared.attackPlayer','shared.aid','shared.recallAid','shared.hunt','shared.createAlliance','shared.joinAlliance','shared.leaveAlliance','shared.endProtection','shared.declareWar','shared.peace','shared.setDiplomacy','shared.markOperation','shared.removeOperation','shared.marketCreate','shared.marketBuy','shared.marketCancel']);
const marchCreators=new Set(['shared.attackPlayer','shared.aid','shared.hunt','shared.marketBuy']);
// This rehearsal validates shared player warfare; private-coordinate NPC battles remain local-only.
const localBattleActions=new Set(['dispatch','scout','dispatchScout','startBattle','battleRound','setBattleOrder','setBattleOrders','recall','dismissBattle','selectExpedition','requestCityDefense','startCityDefense','cityDefenseRound','endDefenseDrill','resolveCityDefense','submitBattleTactic','cancelBattleTactic','startRegionalFront']);
const protectedFields=new Set(['actor','actorId','user','userId','owner','ownerId','source','sourceId','seller','sellerId','buyer','buyerId','authorityId','state','snapshot','clock','now','serverTime','start','arrive','returnAt','declaredAt','startsAt','endsAt','createdAt','expiresAt','won','statsSnapshot','generalSnapshot','loot','revision']);
const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8','.webmanifest':'application/manifest+json','.txt':'text/plain; charset=utf-8','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.svg':'image/svg+xml','.ico':'image/x-icon','.webp':'image/webp','.woff':'font/woff','.woff2':'font/woff2','.ttf':'font/ttf','.otf':'font/otf','.ogg':'audio/ogg','.mp3':'audio/mpeg'};

export function validateCommand(input) {
  if(Object.keys(input).some(key=>!['commandId','expectedRevision','type','args','sourceCity'].includes(key)))throw new GameError('CLIENT_SNAPSHOT_FORBIDDEN','共享操作不能替换存档、身份或服务器时间');
  validateInput(input);
  if(localBattleActions.has(input.type)||!gameActions.has(input.type)&&!namespaces.test(input.type)&&!sharedActions.has(input.type))throw new GameError('COMMAND_NOT_ALLOWED','共享演练仅支持共享出征及城市经营，此操作尚未接入');
  if(input.commandId.startsWith('scenario_')||input.commandId.startsWith('settlement_'))throw new GameError('BAD_COMMAND_ID','操作编号使用保留前缀');
  if(input.sourceCity!==undefined&&(typeof input.sourceCity!=='string'||input.sourceCity.length>100))throw new GameError('BAD_CITY','出发城市格式无效');
  const walk=(value,depth=0)=>{
    if(depth>10)throw new GameError('BAD_INPUT','操作参数嵌套过深');
    if(Array.isArray(value)){for(const part of value)walk(part,depth+1);return;}
    if(object(value))for(const [key,part]of Object.entries(value)){if(protectedFields.has(key)||['__proto__','constructor','prototype'].includes(key))throw new GameError('CLIENT_AUTHORITY_FORBIDDEN','操作不能指定身份、结果或服务器时间');walk(part,depth+1);}
  };walk(input.args);
}
export function requireUnusedEntityId(store,actor,input,realm=SHARED_REALM) {
  // Receipts are actor-scoped, while canonical marches/orders/alliances/marks
  // use globally keyed IDs. Preserve exact retries, but reject a new colliding
  // entity before canonical rules can debit assets and select an older row.
  if(store.data.receipts.some(row=>row.actor===actor&&row.realm===realm&&row.id===input.commandId))return;
  const rows=marchCreators.has(input.type)?store.data.marches:input.type==='shared.marketCreate'?store.data.orders:input.type==='shared.createAlliance'?store.data.alliances:input.type==='shared.markOperation'?store.data.alliances.flatMap(alliance=>alliance.marks||[]):[];
  if(rows.some(row=>row.id===input.commandId))throw new GameError('ENTITY_ID_REUSED','操作编号已用于共享实体，请刷新后重新提交',409);
}
export async function readBody(request) {
  if(!/^application\/json(?:\s*;|$)/i.test(request.headers['content-type']||''))throw new GameError('CONTENT_TYPE','请求必须使用 application/json',415);
  if(Number(request.headers['content-length']||0)>MAX_BODY)throw new GameError('BODY_TOO_LARGE','请求过大',413);
  const chunks=[];let size=0;for await(const chunk of request){size+=chunk.length;if(size>MAX_BODY)throw new GameError('BODY_TOO_LARGE','请求过大',413);chunks.push(chunk);}
  try{const input=JSON.parse(Buffer.concat(chunks).toString('utf8'));if(!object(input))throw new Error();return input;}catch{throw new GameError('BAD_JSON','JSON 请求格式无效');}
}
export function safeNow(clock) {const now=clock();if(!Number.isSafeInteger(now)||now<0)throw new GameError('SERVER_CLOCK','服务器时间无效',500);return now;}

/** Loopback rehearsal only. Client accounts and time cannot be selected in an HTTP body. */
export async function startSharedBridge({dataDir,port=17342,host='127.0.0.1',clock=Date.now,webDir=null,settlementIntervalMs=1000,readyFile=null}={}) {
  if(!dataDir)throw new Error('dataDir is required');
  if(!['127.0.0.1','::1','localhost'].includes(host))throw new Error('Shared rehearsal must bind to loopback');
  if(!Number.isInteger(port)||port<0||port>65535)throw new Error('Invalid port');
  if(!Number.isInteger(settlementIntervalMs)||settlementIntervalMs<0||settlementIntervalMs>60000)throw new Error('Invalid settlement interval');
  dataDir=path.resolve(dataDir);await fs.mkdir(dataDir,{recursive:true,mode:0o700});dataDir=await fs.realpath(dataDir);
  if(readyFile){readyFile=path.resolve(readyFile);if(['credentials.json','shared-world.json','.shared-bridge.lock','.shared-bridge.reclaim.lock'].some(name=>readyFile===path.join(dataDir,name)))throw new Error('Ready file cannot replace private shared data');}
  if(webDir){webDir=await fs.realpath(path.resolve(webDir));if(within(webDir,dataDir)||within(dataDir,webDir)||readyFile&&within(webDir,readyFile))throw new Error('Web resources must be separate from private shared data and ready files');}
  const storage=await openSharedStore(dataDir,safeNow(clock)),credentials=storage.credentials;
  let pending=Promise.resolve(),pendingCount=0,closed=false,timer=null,assignedPort=port,settlementError=null;
  const serial=operation=>{
    if(pendingCount>=MAX_PENDING)return Promise.reject(new GameError('SERVICE_BUSY','共享服务繁忙，请稍后重试',503));
    pendingCount++;const task=pending.then(operation);pending=task.catch(()=>{}).finally(()=>{pendingCount--;});return task;
  };
  const actorFor=request=>{
    const raw=request.headers.authorization?.replace(/^Bearer\s+/i,'')||request.headers['x-bridge-token']||'';
    const supplied=Buffer.from(String(raw));
    return credentials.find(actor=>{const expected=Buffer.from(actor.token);return expected.length===supplied.length&&crypto.timingSafeEqual(expected,supplied);});
  };
  const context=(store,actor,now)=>store.context(actor,SHARED_REALM,null,now);
  const settleOperation=async()=>{
    const now=safeNow(clock),snapshot=storage.snapshot(),due=snapshot.marches.filter(march=>march.status==='march'&&march.arrive<=now||march.status==='return'&&march.returnAt<=now);
    if(!due.length)return {settled:0,serverTime:now};
    return storage.transaction(async store=>{
      let settled=0;
      // Canonical batches process eight arrivals. Bound the tick while draining all rehearsal jobs.
      for(let batch=0;batch<16;batch++){
        const next=store.data.marches.filter(march=>march.status==='march'&&march.arrive<=now||march.status==='return'&&march.returnAt<=now).sort((a,b)=>(a.status==='return'?a.returnAt:a.arrive)-(b.status==='return'?b.returnAt:b.arrive)||a.id.localeCompare(b.id))[0];
        if(!next)break;
        const row=store.data.players.find(player=>player.id===next.source);
        const response=await handleRequest(store,row.id,{op:'command',realm:SHARED_REALM,type:'shared.settle',args:[{}],expectedRevision:row.revision,commandId:`settlement_${crypto.randomUUID()}`},now);
        settled+=response.result.receipts.length;
      }
      return {settled,serverTime:now};
    });
  };
  const settle=()=>serial(settleOperation);
  const allowedOrigin=origin=>{
    try{const url=new URL(origin);return url.origin===origin&&url.protocol==='http:'&&['127.0.0.1','localhost','[::1]'].includes(url.hostname)&&Number(url.port||80)===assignedPort;}catch{return false;}
  };
  const server=http.createServer(async(request,response)=>{
    const reply=(status,value)=>{response.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});response.end(JSON.stringify(value));};
    let identity;
    try{
      if(closed)throw new GameError('SHUTTING_DOWN','共享服务正在关闭',503);
      const origin=request.headers.origin;if(origin&&!allowedOrigin(origin))throw new GameError('ORIGIN_DENIED','此网页不能访问共享演练',403);
      if(origin){response.setHeader('Access-Control-Allow-Origin',origin);response.setHeader('Vary','Origin');response.setHeader('Access-Control-Allow-Headers','Authorization, X-Bridge-Token, Content-Type');response.setHeader('Access-Control-Allow-Methods','GET, POST, OPTIONS');}
      if(request.method==='OPTIONS'){response.writeHead(204);response.end();return;}
      const url=new URL(request.url,`http://${request.headers.host||'127.0.0.1'}`),route=url.pathname.startsWith('/api/')?url.pathname.slice(4):url.pathname;
      const api=['/health','/state','/world','/node','/command','/import','/export','/shutdown'];
      if(api.includes(route)||url.pathname.startsWith('/api/')){identity=actorFor(request);if(!identity)throw new GameError('UNAUTHORIZED','请选择有效的演练身份连接密钥',401);}
      if(request.method==='GET'&&route==='/health'){
        if([...url.searchParams.keys()].length)throw new GameError('BAD_INPUT','健康检查不接受身份或时间参数');
        reply(200,{ok:true,protocol:1,mode:'shared',runtimeHash,authentication:true,authorityId:storage.authorityId(identity.id),actor:{id:identity.id,name:identity.name},scenario:storage.scenario(),settlement:{ok:!settlementError,error:settlementError}});return;
      }
      if(request.method==='GET'&&['/state','/world','/node'].includes(route)){
        if([...url.searchParams.keys()].some(key=>route!=='/node'||key!=='id'))throw new GameError('BAD_INPUT','读取请求不能指定身份或服务器时间');
        const result=await serial(async()=>{
          const now=safeNow(clock),current=await context(storage.readStore(),identity.id,now),authority=storage.authorityId(identity.id);
          if(route==='/world')return sharedWorldView(current,identity.id,authority,identity);
          if(route==='/node')return sharedNodeView(current,identity.id,url.searchParams.get('id')||'',authority,identity);
          return sharedEnvelope(current,identity.id,authority,identity);
        });reply(200,result);return;
      }
      if(request.method==='POST'&&route==='/command'){
        if([...url.searchParams.keys()].length)throw new GameError('BAD_INPUT','操作请求不接受查询参数');
        const input=await readBody(request);validateCommand(input);
        const result=await serial(async()=>{
          const now=safeNow(clock);
          return storage.transaction(async store=>{
            requireUnusedEntityId(store,identity.id,input);
            const responseValue=await handleRequest(store,identity.id,{op:'command',realm:SHARED_REALM,...input},now);
            const receipt=store.data.receipts.find(row=>row.actor===identity.id&&row.realm===SHARED_REALM&&row.id===input.commandId);
            // Keep the private state and public world from one confirmation generation.
            // Rebuilding an old actor revision beside today's marches would resurrect stale UI escrow.
            if(responseValue.replayed&&receipt.bridgeResponse)return {...copy(receipt.bridgeResponse),replayed:true};
            if(responseValue.replayed){
              // An early rehearsal snapshot may predate presentation receipts. A fresh
              // authoritative view is coherent; pairing old private state with it is not.
              const current=await context(store,identity.id,now);
              const acknowledgement=sharedEnvelope(current,identity.id,storage.authorityId(identity.id),identity,responseValue.result,true);
              receipt.bridgeResponse=copy(acknowledgement);return acknowledgement;
            }
            const current=await context(store,identity.id,responseValue.serverTime);
            const responseContext={...current,players:current.players.map(row=>row.id===identity.id?{...row,revision:responseValue.revision,state:responseValue.state}:row)};
            const acknowledgement=sharedEnvelope(responseContext,identity.id,storage.authorityId(identity.id),identity,responseValue.result,responseValue.replayed===true);
            receipt.bridgeResponse=copy(acknowledgement);return acknowledgement;
          });
        });reply(200,result);return;
      }
      if(api.includes(route))throw new GameError('COMMAND_NOT_ALLOWED','共享演练不支持导入、导出、上传状态或管理接口',405);
      if(webDir&&['GET','HEAD'].includes(request.method)&&!url.pathname.startsWith('/api/')){
        let pathname;try{pathname=decodeURIComponent(url.pathname);}catch{throw new GameError('BAD_PATH','资源路径无效');}
        if(pathname.includes('\\')||pathname.split('/').some(segment=>segment.startsWith('.')||['credentials.json','shared-world.json'].includes(segment)))throw new GameError('NOT_FOUND','资源不存在',404);
        const requested=path.resolve(webDir,'.'+(pathname==='/'?'/index.html':pathname));
        if(!within(webDir,requested)||!mime[path.extname(requested).toLowerCase()])throw new GameError('NOT_FOUND','资源不存在',404);
        let resolved,stat;try{resolved=await fs.realpath(requested);stat=await fs.stat(resolved);}catch{throw new GameError('NOT_FOUND','资源不存在',404);}
        if(!within(webDir,resolved)||!stat.isFile())throw new GameError('NOT_FOUND','资源不存在',404);
        response.writeHead(200,{'Content-Type':mime[path.extname(resolved).toLowerCase()],'Cache-Control':'no-cache','X-Content-Type-Options':'nosniff','Cross-Origin-Opener-Policy':'same-origin','Cross-Origin-Embedder-Policy':'require-corp'});
        response.end(request.method==='HEAD'?undefined:await fs.readFile(resolved));return;
      }
      throw new GameError('NOT_FOUND','接口不存在',404);
    }catch(error){const known=error instanceof GameError;reply(known?error.status:500,{error:{code:known?error.code:'INTERNAL_ERROR',message:known?error.message:'共享服务发生错误，操作未确认写入'}});}
  });
  server.requestTimeout=10000;server.headersTimeout=10000;
  const close=async()=>{if(closed)return;closed=true;clearInterval(timer);await pending;await new Promise(resolve=>server.close(resolve));await storage.close();if(readyFile)await fs.unlink(readyFile).catch(()=>{});};
  try{
    // Recover overdue canonical arrivals once before clients receive the ready boundary.
    await settle();
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,host,resolve);});assignedPort=server.address().port;
    if(settlementIntervalMs)timer=setInterval(()=>{settle().then(()=>{settlementError=null;}).catch(error=>{settlementError={code:error instanceof GameError?error.code:'SETTLEMENT_FAILED',message:'自动结算未确认，请检查本地共享服务'};});},settlementIntervalMs);timer?.unref();
    if(readyFile){await fs.mkdir(path.dirname(readyFile),{recursive:true,mode:0o700});await atomicSharedJSON(readyFile,{url:`http://${host==='::1'?'[::1]':host}:${assignedPort}`,pid:process.pid,protocol:1,mode:'shared'});}
  }catch(error){clearInterval(timer);await new Promise(resolve=>server.close(resolve));await storage.close();throw error;}
  return {server,port:assignedPort,host,url:`http://${host==='::1'?'[::1]':host}:${assignedPort}`,dataDir,credentials,credentialsFile:storage.credentialsFile,settle,snapshot:storage.snapshot,close};
}

export function parseSharedArguments(args) {
  const options={port:17342,dataDir:path.resolve('.local/shared-pvp')};
  for(let index=0;index<args.length;index++){
    const key=args[index],value=args[++index];if(!value)throw new Error(`Missing value for ${key}`);
    if(key==='--port')options.port=Number(value);else if(key==='--data-dir')options.dataDir=path.resolve(value);else if(key==='--web-dir')options.webDir=path.resolve(value);else if(key==='--ready-file')options.readyFile=path.resolve(value);else throw new Error(`Unknown option ${key}`);
  }return options;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{
    const bridge=await startSharedBridge(parseSharedArguments(process.argv.slice(2)));
    console.log(JSON.stringify({event:'ready',host:bridge.host,port:bridge.port,protocol:1,mode:'shared',scenario:'本机 4 城 PvP 演练'}));
    const stop=async()=>{await bridge.close();process.exit(0);};process.once('SIGINT',stop);process.once('SIGTERM',stop);
  }catch(error){console.error(JSON.stringify({error:error.code||'START_FAILED',message:error.message}));process.exitCode=1;}
}
