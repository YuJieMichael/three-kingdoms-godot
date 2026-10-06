import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {GameError,runtimeHash,copy} from '../vendor/shared/runtime.mjs';
import {MemoryStore} from '../vendor/shared/memory-store.mjs';
import {handleRequest,digest} from '../vendor/shared/service.mjs';
import {validateCommand,requireUnusedEntityId,readBody,safeNow} from './shared-server.mjs';
import {atomicSharedJSON} from './shared-store.mjs';
import {openRoomStore,roomMetadata,validSecret,cleanName,createRoom,joinRoom} from './room-store.mjs';
import {ROOM_PROFILE} from './room-scenario.mjs';
import {sharedEnvelope,sharedWorldView,sharedNodeView} from './shared-dto.mjs';

const MAX_PENDING=64;
const within=(root,target)=>target===root||target.startsWith(root+path.sep);
const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8','.webmanifest':'application/manifest+json','.txt':'text/plain; charset=utf-8','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.svg':'image/svg+xml','.ico':'image/x-icon','.webp':'image/webp','.woff':'font/woff','.woff2':'font/woff2','.ttf':'font/ttf','.otf':'font/otf','.ogg':'audio/ogg','.mp3':'audio/mpeg'};
const privateNames=['rooms.json','credentials.json','shared-world.json','.shared-bridge.lock','.shared-bridge.reclaim.lock'];
const bodyKeys={create:['requestId','roomName','capacity','playerName'],join:['requestId','inviteCode','playerName'],resume:['roomId','recoveryKey']};

async function resolvedTarget(filename) {
  let ancestor=filename;const missing=[];
  for(;;){
    try{return path.join(await fs.realpath(ancestor),...missing.reverse());}catch(error){
      if(error.code!=='ENOENT')throw error;
      const parent=path.dirname(ancestor);if(parent===ancestor)throw error;
      missing.push(path.basename(ancestor));ancestor=parent;
    }
  }
}

function validateLobby(operation,input) {
  const keys=bodyKeys[operation];
  if(!keys||Object.keys(input).some(key=>!keys.includes(key))||keys.some(key=>!Object.hasOwn(input,key)))throw new GameError('BAD_INPUT','房间请求字段无效');
  if(operation==='resume'){
    if(typeof input.roomId!=='string'||!/^room_[a-f0-9]{32}$/.test(input.roomId)||!validSecret(input.recoveryKey))throw new GameError('BAD_RECOVERY','房间编号或恢复密钥格式无效');
    return input;
  }
  if(!validSecret(input.requestId))throw new GameError('BAD_REQUEST_ID','请使用新的 64 位随机操作密钥');
  const normalized={...input,playerName:cleanName(input.playerName,20,'城主名称')};
  if(operation==='create'){
    normalized.roomName=cleanName(input.roomName,40,'房间名称');
    if(!Number.isInteger(input.capacity)||input.capacity<1||input.capacity>8)throw new GameError('BAD_CAPACITY','房间人数需为 1–8 人');
  }else if(!validSecret(input.inviteCode))throw new GameError('BAD_INVITE','邀请密钥格式无效');
  return normalized;
}

/** Local rooms only: identity and room selection always come from a credential. */
export async function startRoomsServer({dataDir,port=17343,host='127.0.0.1',clock=Date.now,
  webDir=null,lobbyFile=path.join(path.dirname(fileURLToPath(import.meta.url)),'lobby.html'),
  settlementIntervalMs=1000,readyFile=null}={}) {
  if(!dataDir)throw new Error('dataDir is required');
  if(!['127.0.0.1','localhost','::1'].includes(host))throw new Error('Room rehearsal must bind to loopback');
  if(!Number.isInteger(port)||port<0||port>65535)throw new Error('Invalid port');
  if(!Number.isInteger(settlementIntervalMs)||settlementIntervalMs<0||settlementIntervalMs>60000)throw new Error('Invalid settlement interval');
  dataDir=path.resolve(dataDir);await fs.mkdir(dataDir,{recursive:true,mode:0o700});dataDir=await fs.realpath(dataDir);
  if(readyFile){readyFile=await resolvedTarget(path.resolve(readyFile));if(privateNames.some(name=>readyFile===path.join(dataDir,name)))throw new Error('Ready file cannot replace private room data');}
  if(webDir){webDir=await fs.realpath(path.resolve(webDir));if(within(webDir,dataDir)||within(dataDir,webDir)||readyFile&&within(webDir,readyFile))throw new Error('Web resources must be separate from private room data and ready files');}
  if(lobbyFile){lobbyFile=path.resolve(lobbyFile);if(within(dataDir,lobbyFile))throw new Error('Lobby resources must be separate from private room data');}
  const storage=await openRoomStore(dataDir,safeNow(clock));
  let pending=Promise.resolve(),pendingCount=0,closed=false,timer=null,assignedPort=port,settlementError=null;
  const serial=operation=>{
    if(pendingCount>=MAX_PENDING)return Promise.reject(new GameError('SERVICE_BUSY','房间服务繁忙，请稍后重试',503));
    pendingCount++;const task=pending.then(operation);pending=task.catch(()=>{}).finally(()=>{pendingCount--;});return task;
  };
  const identityFor=request=>storage.identityForToken(request.headers.authorization?.replace(/^Bearer\s+/i,'')||request.headers['x-bridge-token']||'');
  const currentRoom=identity=>{
    const room=storage.room(identity.roomId),member=room?.members.find(value=>value.id===identity.actorId);
    if(!room||!member)throw new GameError('UNAUTHORIZED','房间身份已失效，请使用恢复密钥重新加入',401);
    return {room,member};
  };
  const publicRoom=(room,member)=>({...roomMetadata(room),seat:member.seat});
  const dueAt=(data,now)=>data.marches.some(march=>march.status==='march'&&march.arrive<=now||march.status==='return'&&march.returnAt<=now);
  const settleOperation=async()=>{
    const now=safeNow(clock);
    if(!storage.snapshot().rooms.some(room=>dueAt(room.data,now)))return {settled:0,serverTime:now};
    return storage.transaction(async candidate=>{
      let settled=0;
      for(const room of candidate.rooms){
        if(!dueAt(room.data,now))continue;
        const store=new MemoryStore(room.data);
        // Canonical settle processes eight arrivals per command; preserve its own ordering.
        for(let batch=0;batch<16;batch++){
          const next=store.data.marches.filter(march=>march.status==='march'&&march.arrive<=now||march.status==='return'&&march.returnAt<=now)
            .sort((a,b)=>(a.status==='return'?a.returnAt:a.arrive)-(b.status==='return'?b.returnAt:b.arrive)||a.id.localeCompare(b.id))[0];
          if(!next)break;
          const row=store.data.players.find(player=>player.id===next.source);
          if(!row)throw new GameError('ROOM_SAVE_CORRUPT','行军所属城主不存在，自动结算已暂停',500);
          const response=await handleRequest(store,row.id,{op:'command',realm:room.id,type:'shared.settle',args:[{}],
            expectedRevision:row.revision,commandId:`settlement_${crypto.randomUUID()}`},now);
          settled+=response.result.receipts.length;
        }
        room.data=store.data;
      }
      return {settled,serverTime:now};
    });
  };
  const settle=()=>serial(settleOperation);
  const allowedOrigin=origin=>{
    try{const url=new URL(origin);return url.origin===origin&&url.protocol==='http:'&&['127.0.0.1','localhost','[::1]'].includes(url.hostname)&&Number(url.port||80)===assignedPort;}catch{return false;}
  };
  const staticFile=async(response,filename,method)=>{
    let stat;try{stat=await fs.stat(filename);}catch{throw new GameError('NOT_FOUND','资源不存在',404);}
    if(!stat.isFile())throw new GameError('NOT_FOUND','资源不存在',404);
    response.writeHead(200,{'Content-Type':mime[path.extname(filename).toLowerCase()]||'application/octet-stream',
      'Cache-Control':'no-cache','X-Content-Type-Options':'nosniff','Cross-Origin-Opener-Policy':'same-origin',
      'Cross-Origin-Embedder-Policy':'require-corp'});
    response.end(method==='HEAD'?undefined:await fs.readFile(filename));
  };
  const server=http.createServer(async(request,response)=>{
    const reply=(status,value)=>{response.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});response.end(JSON.stringify(value));};
    try{
      if(closed)throw new GameError('SHUTTING_DOWN','房间服务正在关闭',503);
      const origin=request.headers.origin;if(origin&&!allowedOrigin(origin))throw new GameError('ORIGIN_DENIED','此网页不能访问本机房间',403);
      if(origin){response.setHeader('Access-Control-Allow-Origin',origin);response.setHeader('Vary','Origin');
        response.setHeader('Access-Control-Allow-Headers','Authorization, X-Bridge-Token, Content-Type');response.setHeader('Access-Control-Allow-Methods','GET, POST, OPTIONS');}
      if(request.method==='OPTIONS'){response.writeHead(204);response.end();return;}
      const url=new URL(request.url,`http://${request.headers.host||'127.0.0.1'}`),route=url.pathname.startsWith('/api/')?url.pathname.slice(4):url.pathname;
      if(['/lobby/create','/lobby/join','/lobby/resume'].includes(route)){
        if(request.method!=='POST')throw new GameError('METHOD_NOT_ALLOWED','房间操作需要 POST 请求',405);
        if([...url.searchParams.keys()].length)throw new GameError('BAD_INPUT','房间操作不接受查询参数');
        const operation=route.split('/').pop(),raw=await readBody(request),input=validateLobby(operation,raw);
        const result=await serial(async()=>{
          if(operation==='resume'){
            const session=storage.recover(input.roomId,input.recoveryKey);
            if(!session)throw new GameError('RECOVERY_DENIED','房间编号或恢复密钥不匹配',401);
            return session;
          }
          const hash=await digest({operation,input:raw});
          const previous=storage.snapshot().requests.find(value=>value.id===input.requestId);
          if(previous){if(previous.operation!==operation||previous.hash!==hash)throw new GameError('ID_REUSED','房间操作密钥已用于不同请求',409);return copy(previous.response);}
          return storage.transaction(async candidate=>{
            let session;
            if(operation==='create')session=await createRoom(candidate,input,safeNow(clock));
            else{
              const room=candidate.rooms.find(value=>value.inviteCode===input.inviteCode);
              if(!room)throw new GameError('INVITE_DENIED','邀请密钥无效',401);
              session=await joinRoom(room,input.playerName,safeNow(clock));
            }
            candidate.requests.push({id:input.requestId,operation,hash,roomId:session.room.id,actorId:session.actor.id,response:copy(session)});
            return session;
          });
        });reply(200,result);return;
      }
      const api=['/health','/state','/world','/node','/command','/import','/export','/shutdown'];
      let identity;if(api.includes(route)||url.pathname.startsWith('/api/')){
        identity=identityFor(request);if(!identity)throw new GameError('UNAUTHORIZED','请从房间大厅加入，或使用自己的恢复密钥',401);
      }
      if(request.method==='GET'&&route==='/health'){
        if([...url.searchParams.keys()].length)throw new GameError('BAD_INPUT','健康检查不接受身份或时间参数');
        const {room,member}=currentRoom(identity);
        reply(200,{ok:true,protocol:1,mode:'shared',runtimeHash,authentication:true,authorityId:member.authorityId,
          actor:{id:member.id,name:member.name},room:publicRoom(room,member),scenario:{...ROOM_PROFILE,players:room.members.length},
          settlement:{ok:!settlementError,error:settlementError}});return;
      }
      if(request.method==='GET'&&['/state','/world','/node'].includes(route)){
        if([...url.searchParams.keys()].some(key=>route!=='/node'||key!=='id'))throw new GameError('BAD_INPUT','读取不能指定房间、身份或服务器时间');
        const result=await serial(async()=>{
          const {room,member}=currentRoom(identity),now=safeNow(clock),context=await new MemoryStore(room.data).context(member.id,room.id,null,now);
          const value=route==='/world'?sharedWorldView(context,member.id,member.authorityId,member):route==='/node'?
            sharedNodeView(context,member.id,url.searchParams.get('id')||'',member.authorityId,member):sharedEnvelope(context,member.id,member.authorityId,member);
          return {...value,room:publicRoom(room,member)};
        });reply(200,result);return;
      }
      if(request.method==='POST'&&route==='/command'){
        if([...url.searchParams.keys()].length)throw new GameError('BAD_INPUT','操作不能指定房间或查询参数');
        const input=await readBody(request);validateCommand(input);
        const result=await serial(()=>storage.transaction(async candidate=>{
          const room=candidate.rooms.find(value=>value.id===identity.roomId),member=room?.members.find(value=>value.id===identity.actorId);
          if(!member)throw new GameError('UNAUTHORIZED','房间身份已失效',401);
          const now=safeNow(clock),store=new MemoryStore(room.data);
          requireUnusedEntityId(store,member.id,input,room.id);
          const responseValue=await handleRequest(store,member.id,{op:'command',realm:room.id,...input},now),
            receipt=store.data.receipts.find(value=>value.actor===member.id&&value.realm===room.id&&value.id===input.commandId);
          if(responseValue.replayed&&receipt.bridgeResponse){room.data=store.data;return {...copy(receipt.bridgeResponse),replayed:true};}
          const context=await store.context(member.id,room.id,null,responseValue.replayed?now:responseValue.serverTime);
          const responseContext=responseValue.replayed?context:{...context,players:context.players.map(row=>row.id===member.id?
            {...row,revision:responseValue.revision,state:responseValue.state}:row)};
          const acknowledgement={...sharedEnvelope(responseContext,member.id,member.authorityId,member,responseValue.result,responseValue.replayed===true),room:publicRoom(room,member)};
          receipt.bridgeResponse=copy(acknowledgement);room.data=store.data;return acknowledgement;
        }));reply(200,result);return;
      }
      if(api.includes(route))throw new GameError('COMMAND_NOT_ALLOWED','房间不接受导入、导出、上传存档或管理请求',405);
      if(['GET','HEAD'].includes(request.method)&&route==='/lobby'&&lobbyFile){
        if([...url.searchParams.keys()].length)throw new GameError('BAD_INPUT','请使用邀请片段打开大厅');
        const resolved=await fs.realpath(lobbyFile).catch(()=>null);
        if(!resolved||within(dataDir,resolved))throw new GameError('NOT_FOUND','房间大厅资源不存在',404);
        await staticFile(response,resolved,request.method);return;
      }
      if(webDir&&['GET','HEAD'].includes(request.method)&&!url.pathname.startsWith('/api/')){
        let pathname;try{pathname=decodeURIComponent(url.pathname);}catch{throw new GameError('BAD_PATH','资源路径无效');}
        if(pathname.includes('\\')||pathname.split('/').some(segment=>segment.startsWith('.')||privateNames.includes(segment)))throw new GameError('NOT_FOUND','资源不存在',404);
        const requested=path.resolve(webDir,'.'+(pathname==='/'?'/index.html':pathname));
        if(!within(webDir,requested)||!mime[path.extname(requested).toLowerCase()])throw new GameError('NOT_FOUND','资源不存在',404);
        const resolved=await fs.realpath(requested).catch(()=>null);
        if(!resolved||!within(webDir,resolved))throw new GameError('NOT_FOUND','资源不存在',404);
        await staticFile(response,resolved,request.method);return;
      }
      throw new GameError('NOT_FOUND','接口不存在',404);
    }catch(error){const known=error instanceof GameError;reply(known?error.status:500,{error:{code:known?error.code:'INTERNAL_ERROR',message:known?error.message:'房间服务发生错误，操作未确认写入'}});}
  });
  server.requestTimeout=10000;server.headersTimeout=10000;
  const close=async()=>{if(closed)return;closed=true;clearInterval(timer);await pending;await new Promise(resolve=>server.close(resolve));await storage.close();if(readyFile)await fs.unlink(readyFile).catch(()=>{});};
  try{
    await settle();await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,host,resolve);});assignedPort=server.address().port;
    if(settlementIntervalMs)timer=setInterval(()=>{settle().then(()=>{settlementError=null;}).catch(error=>{
      settlementError={code:error instanceof GameError?error.code:'SETTLEMENT_FAILED',message:'自动结算未确认，请检查本机房间服务'};
    });},settlementIntervalMs);timer?.unref();
    if(readyFile){await fs.mkdir(path.dirname(readyFile),{recursive:true,mode:0o700});await atomicSharedJSON(readyFile,
      {url:`http://${host==='::1'?'[::1]':host}:${assignedPort}`,pid:process.pid,protocol:1,mode:'rooms'});}
  }catch(error){clearInterval(timer);await new Promise(resolve=>server.close(resolve));await storage.close();throw error;}
  return {server,port:assignedPort,host,url:`http://${host==='::1'?'[::1]':host}:${assignedPort}`,dataDir,
    snapshot:storage.snapshot,settle,close};
}

export function parseRoomArguments(args) {
  const options={port:17343,dataDir:path.resolve('.local/pvp-rooms')};
  for(let index=0;index<args.length;index++){
    const key=args[index],value=args[++index];if(!value)throw new Error('Missing value for '+key);
    if(key==='--port')options.port=Number(value);else if(key==='--data-dir')options.dataDir=path.resolve(value);
    else if(key==='--web-dir')options.webDir=path.resolve(value);else if(key==='--ready-file')options.readyFile=path.resolve(value);
    else if(key==='--lobby-file')options.lobbyFile=path.resolve(value);else throw new Error('Unknown option '+key);
  }return options;
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  try{
    const service=await startRoomsServer(parseRoomArguments(process.argv.slice(2)));
    console.log(JSON.stringify({event:'room-ready',url:service.url,protocol:1,mode:'local-rooms',profile:ROOM_PROFILE.id}));
    const stop=async()=>{await service.close();process.exit(0);};process.once('SIGINT',stop);process.once('SIGTERM',stop);
  }catch(error){console.error(JSON.stringify({error:error.code||'START_FAILED',message:error.message}));process.exitCode=1;}
}
