import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {MemoryStore} from '../vendor/shared/memory-store.mjs';
import {copy, createGameRuntime, GameError} from '../vendor/shared/runtime.mjs';
import {createRehearsal, REHEARSAL_ACTORS, SHARED_REALM, SCENARIO} from './shared-scenario.mjs';

const object=value=>!!value&&typeof value==='object'&&!Array.isArray(value);
const uuid=value=>typeof value==='string'&&/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);
export async function atomicSharedJSON(filename,value) {
  const temporary=`${filename}.${process.pid}.${crypto.randomUUID()}.tmp`;let handle;
  try {
    handle=await fs.open(temporary,'wx',0o600);await handle.writeFile(JSON.stringify(value),'utf8');
    await handle.sync();await handle.close();handle=null;await fs.rename(temporary,filename);
    if(process.platform!=='win32'){const directory=await fs.open(path.dirname(filename),'r');try{await directory.sync();}finally{await directory.close();}}
  } finally {await handle?.close().catch(()=>{});await fs.unlink(temporary).catch(()=>{});}
}

export async function lockDirectory(dataDir) {
  const filename=path.join(dataDir,'.shared-bridge.lock'),guardFile=path.join(dataDir,'.shared-bridge.reclaim.lock'),identity=crypto.randomUUID();
  let guard;
  // Every acquisition, including a fresh directory, holds this exclusive guard
  // until the owner lock exists. No contender can unlink a replacement owner.
  // Never reclaim the guard itself: after a crash its ambiguous ownership must
  // fail closed rather than repeat the stale-unlink race at another filename.
  try{guard=await fs.open(guardFile,'wx',0o600);}catch(error){
    if(error.code==='EEXIST')throw new GameError('SAVE_LOCKED','共享演练锁正在恢复或恢复曾中断；确认所有演练进程已退出后，检查并移除 .shared-bridge.reclaim.lock 再重启',409);
    throw error;
  }
  try {
    await guard.writeFile(JSON.stringify({pid:process.pid,identity}));await guard.sync();
    let existing;
    try{existing=JSON.parse(await fs.readFile(filename,'utf8'));}catch(error){
      if(error.code!=='ENOENT')throw new GameError('SAVE_LOCKED','共享演练锁无法读取，请检查现有进程',409);
    }
    if(existing){
      if(!Number.isSafeInteger(existing.pid)||existing.pid<1)throw new GameError('SAVE_LOCKED','共享演练锁无效',409);
      let stale=false;
      try{process.kill(existing.pid,0);}catch(error){if(error.code==='ESRCH')stale=true;else throw new GameError('SAVE_LOCKED','无法核对共享演练进程',409);}
      if(!stale)throw new GameError('SAVE_LOCKED','同一共享演练正在另一进程运行',409);
      await fs.unlink(filename);
    }
    const handle=await fs.open(filename,'wx',0o600);try{await handle.writeFile(JSON.stringify({pid:process.pid,identity}));await handle.sync();}finally{await handle.close();}
    return async()=>{try{const current=JSON.parse(await fs.readFile(filename,'utf8'));if(current.identity===identity)await fs.unlink(filename);}catch(error){if(error.code!=='ENOENT')throw error;}};
  } finally {
    await guard.close();await fs.unlink(guardFile);
  }
}

function validateData(stored,now) {
  if(!object(stored)||stored.schema!==1||stored.realm!==SHARED_REALM||stored.scenario?.id!==SCENARIO.id||!object(stored.data)||!object(stored.authorities))throw new GameError('SAVE_CORRUPT','共享演练文件无效，原文件已保留',500);
  for(const key of ['players','heroes','cities','marches','orders','alliances','memberships','receipts','private'])if(!Array.isArray(stored.data[key]))throw new GameError('SAVE_CORRUPT','共享演练数据表无效',500);
  if(stored.data.players.length!==4||stored.data.private.length||!object(stored.data.allianceVersions))throw new GameError('SAVE_CORRUPT','共享演练账号结构无效',500);
  const seen=new Set();
  for(const row of stored.data.players){
    if(!REHEARSAL_ACTORS.some(actor=>actor.id===row.id)||seen.has(row.id)||row.realm!==SHARED_REALM||!Number.isSafeInteger(row.revision)||row.revision<1||!uuid(stored.authorities[row.id])||!Number.isInteger(row.home?.x)||!Number.isInteger(row.home?.y)||row.home.x<0||row.home.y<0||row.home.x>63||row.home.y>63)throw new GameError('SAVE_CORRUPT','共享演练账号数据无效',500);
    seen.add(row.id);try{createGameRuntime({snapshot:row.state,now});}catch{throw new GameError('SAVE_CORRUPT','共享演练存档未通过原作校验',500);}
  }
  for(const row of stored.data.receipts)if(!seen.has(row.actor)||row.realm!==SHARED_REALM||typeof row.id!=='string'||typeof row.hash!=='string'||!object(row.response))throw new GameError('SAVE_CORRUPT','共享操作回执无效',500);
}

/** Every mutation works on a candidate MemoryStore. Disk and canonical receipts commit together. */
export async function openSharedStore(dataDir,now) {
  await fs.mkdir(dataDir,{recursive:true,mode:0o700});dataDir=await fs.realpath(path.resolve(dataDir));
  const unlock=await lockDirectory(dataDir),filename=path.join(dataDir,'shared-world.json'),credentialsFile=path.join(dataDir,'credentials.json');
  let stored,credentials,failed=false;
  try {
    try{stored=JSON.parse(await fs.readFile(filename,'utf8'));}catch(error){if(error.code!=='ENOENT')throw new GameError('SAVE_CORRUPT','共享演练文件无法读取，未覆盖原文件',500);}
    if(!stored){
      // Refuse to silently replace an orphaned credentials file after a partial/manual removal.
      try{await fs.access(credentialsFile);throw new GameError('SAVE_CORRUPT','存在账号密钥但世界文件缺失，请保留并检查演练目录',500);}catch(error){if(error.code!=='ENOENT')throw error;}
      credentials=REHEARSAL_ACTORS.map(actor=>({id:actor.id,name:actor.name,slot:actor.slot,token:crypto.randomBytes(32).toString('hex'),authorityId:crypto.randomUUID()}));
      stored={schema:1,realm:SHARED_REALM,scenario:{...SCENARIO,createdAt:now},authorities:Object.fromEntries(credentials.map(actor=>[actor.id,actor.authorityId])),data:await createRehearsal(now)};
      validateData(stored,now);await atomicSharedJSON(filename,stored);
      try{await atomicSharedJSON(credentialsFile,{schema:1,actors:credentials});}catch(error){await fs.unlink(filename).catch(()=>{});throw error;}
    }else{
      validateData(stored,now);let file;try{file=JSON.parse(await fs.readFile(credentialsFile,'utf8'));}catch{throw new GameError('CREDENTIALS_CORRUPT','演练账号密钥文件无法读取',500);}
      if(file.schema!==1||!Array.isArray(file.actors)||file.actors.length!==4)throw new GameError('CREDENTIALS_CORRUPT','演练账号密钥格式无效',500);
      credentials=file.actors;
      if(credentials.some((actor,index)=>actor.id!==REHEARSAL_ACTORS[index].id||actor.slot!==index+1||actor.name!==REHEARSAL_ACTORS[index].name||typeof actor.token!=='string'||!/^[a-f0-9]{64}$/.test(actor.token)||actor.authorityId!==stored.authorities[actor.id])||new Set(credentials.map(actor=>actor.token)).size!==4)throw new GameError('CREDENTIALS_CORRUPT','演练账号密钥与世界身份不匹配',500);
    }
    // Private data stays private even if a caller pre-created a permissive directory.
    await fs.chmod(dataDir,0o700);await fs.chmod(filename,0o600);await fs.chmod(credentialsFile,0o600);
  }catch(error){await unlock();throw error;}
  return {
    dataDir,credentialsFile,credentials:copy(credentials),
    authorityId:actor=>stored.authorities[actor],scenario:()=>copy(stored.scenario),
    snapshot:()=>copy(stored.data),readStore:()=>new MemoryStore(stored.data),
    async transaction(operation){
      if(failed)throw new GameError('PERSISTENCE_FAILED','共享存档写入异常，请重启并检查演练目录',503);
      const candidate=new MemoryStore(stored.data),result=await operation(candidate),next={...stored,data:candidate.data};
      try{await atomicSharedJSON(filename,next);}catch(error){
        // A directory fsync can fail after rename. Restore the previous durable snapshot.
        try{await atomicSharedJSON(filename,stored);}catch{failed=true;}
        throw new GameError('PERSISTENCE_FAILED','共享结果未确认写入，操作已撤销，请检查演练目录',503);
      }
      stored=next;return result;
    },close:unlock,
  };
}
