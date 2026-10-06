import crypto from 'node:crypto';
import {Client} from 'pg';
import {copy,GameError} from '../vendor/shared/runtime.mjs';
import {validateStored,validSecret,memberSession} from './room-store.mjs';
import {ROOM_PROFILE} from './room-scenario.mjs';

export const ROOM_WORLD_TABLE='game_private.room_worlds';
export const MAX_SNAPSHOT_BYTES=64*1024*1024;
const namespacePattern=/^[a-z0-9][a-z0-9_-]{0,63}$/;
const sameSecret=(a,b)=>validSecret(a)&&validSecret(b)&&crypto.timingSafeEqual(Buffer.from(a),Buffer.from(b));
const unavailable=()=>new GameError('PERSISTENCE_FAILED','数据库连接或独占锁已失效，请重启服务后用原编号核对',503);

export function advisoryLockKey(namespace) {
  if(!namespacePattern.test(namespace))throw new GameError('BAD_NAMESPACE','数据库世界名称无效',400);
  return crypto.createHash('sha256').update('three-kingdoms-room-store:'+namespace).digest().readBigInt64BE().toString();
}
export function databaseConnectionOptions(connectionString,requireTLS=true) {
  let url;try{url=new URL(connectionString);}catch{throw new GameError('BAD_DATABASE_CONFIG','请提供有效的后台数据库连接地址',500);}
  if(!['postgres:','postgresql:'].includes(url.protocol)||!url.hostname||url.port==='6543'||url.searchParams.get('pgbouncer')==='true'||url.searchParams.get('pool_mode')==='transaction')throw new GameError('BAD_DATABASE_CONFIG','数据库必须使用直连或会话连接池，不能使用事务连接池',500);
  if(requireTLS&&['disable','allow','prefer','no-verify'].includes(url.searchParams.get('sslmode')))throw new GameError('BAD_DATABASE_CONFIG','公网数据库必须验证 TLS 证书',500);
  // pg connection-string SSL flags can override its explicit TLS object. Strip
  // them after checking; production always verifies the peer certificate.
  for(const key of ['sslmode','sslcert','sslkey','sslrootcert'])url.searchParams.delete(key);
  return {connectionString:url.href,...(requireTLS?{ssl:{rejectUnauthorized:true}}:{}),connectionTimeoutMillis:10000,query_timeout:15000,statement_timeout:15000,application_name:'three-kingdoms-room-server',keepAlive:true};
}
function validatedSnapshot(value,now) {
  validateStored(value,now);
  if(Buffer.byteLength(JSON.stringify(value))>MAX_SNAPSHOT_BYTES)throw new GameError('SNAPSHOT_TOO_LARGE','数据库房间快照超过当前试玩容量，请先备份',503);
  return copy(value);
}
function rowVersion(row) {
  let value;try{value=BigInt(row.version);}catch{throw new GameError('ROOM_SAVE_CORRUPT','数据库版本无效，未覆盖原记录',500);}
  if(value<1n||value>=BigInt(Number.MAX_SAFE_INTEGER))throw new GameError('ROOM_SAVE_CORRUPT','数据库版本无效，未覆盖原记录',500);
  return value;
}
const emptySnapshot=()=>({schema:1,profile:ROOM_PROFILE.id,rooms:[],requests:[]});
export async function acquireRoomLock(client,namespace) {
  const key=advisoryLockKey(namespace),result=await client.query('select pg_try_advisory_lock($1::bigint) as acquired, pg_backend_pid() as pid',[key]);
  if(!result.rows[0]?.acquired)throw new GameError('SAVE_LOCKED','该数据库世界已有规则服务运行，请先停止旧服务',409);
  return {key,pid:Number(result.rows[0].pid)};
}
async function verifyLock(client,lock) {
  const unsigned=BigInt.asUintN(64,BigInt(lock.key));
  const result=await client.query("select pg_backend_pid() as pid, exists(select 1 from pg_locks where locktype='advisory' and pid=pg_backend_pid() and granted and objsubid=1 and classid=$1::oid and objid=$2::oid) as held",[(unsigned>>32n).toString(),(unsigned&0xffffffffn).toString()]);
  if(Number(result.rows[0]?.pid)!==lock.pid||!result.rows[0]?.held)throw unavailable();
}
const clientFor=async options=>options.clientFactory?await options.clientFactory(databaseConnectionOptions(options.connectionString,options.requireTLS!==false)):new Client(databaseConnectionOptions(options.connectionString,options.requireTLS!==false));

/** One dedicated session owns one namespace. Never reconnect around stale cache. */
export async function openPostgresRoomStore({connectionString,namespace='three-kingdoms',now=Date.now(),requireTLS=true,clientFactory,heartbeatMs=1000}={}) {
  advisoryLockKey(namespace);
  const client=await clientFor({connectionString,requireTLS,clientFactory});
  let stored,version,lock,failed=false,closed=false,timer=null,pending=Promise.resolve();
  const fail=()=>{failed=true;};
  client.on('error',fail);client.on('end',()=>{if(!closed)fail();});
  const healthy=()=>!failed&&!closed;
  const ensure=()=>{if(!healthy())throw unavailable();};
  const serial=operation=>{const task=pending.then(operation);pending=task.catch(()=>{});return task;};
  try {
    await client.connect();lock=await acquireRoomLock(client,namespace);
    const current=await client.query(`select version,snapshot from ${ROOM_WORLD_TABLE} where namespace=$1`,[namespace]);
    if(current.rows.length){version=rowVersion(current.rows[0]);stored=validatedSnapshot(current.rows[0].snapshot,now);}
    else{
      stored=emptySnapshot();version=1n;
      await client.query(`insert into ${ROOM_WORLD_TABLE}(namespace,version,snapshot) values($1,$2,$3::jsonb)`,[namespace,version.toString(),JSON.stringify(stored)]);
    }
    await verifyLock(client,lock);ensure();
  }catch(error){failed=true;closed=true;await client.end().catch(()=>{});throw error instanceof GameError?error:new GameError('DATABASE_START_FAILED','数据库连接或迁移未就绪，原记录未覆盖',503);}
  const close=async()=>{if(closed)return;closed=true;clearInterval(timer);await pending;await client.end().catch(()=>{});};
  if(heartbeatMs){
    if(!Number.isInteger(heartbeatMs)||heartbeatMs<20||heartbeatMs>60000){await close();throw new GameError('BAD_DATABASE_CONFIG','数据库检测间隔无效',500);}
    timer=setInterval(()=>{if(healthy())serial(async()=>{try{ensure();await verifyLock(client,lock);}catch{fail();}});},heartbeatMs);timer.unref();
  }
  return {
    healthy,health:()=>({ok:healthy()}),namespace,
    snapshot(){ensure();return copy(stored);},
    room(id){ensure();return copy(stored.rooms.find(room=>room.id===id)||null);},
    identityForToken(token){ensure();if(!validSecret(token))return null;for(const room of stored.rooms)for(const member of room.members)if(sameSecret(member.accessToken,token))return {roomId:room.id,actorId:member.id};return null;},
    recover(id,key){ensure();const room=stored.rooms.find(row=>row.id===id),member=room?.members.find(row=>sameSecret(row.recoveryKey,key));return member?memberSession(room,member):null;},
    transaction(operation){return serial(async()=>{
      ensure();const candidate=copy(stored),result=await operation(candidate);
      validatedSnapshot(candidate,Date.now());ensure();
      let began=false,committing=false;
      try{
        await client.query('begin');began=true;await verifyLock(client,lock);
        const update=await client.query(`update ${ROOM_WORLD_TABLE} set snapshot=$1::jsonb,version=version+1,updated_at=now() where namespace=$2 and version=$3 returning version`,[JSON.stringify(candidate),namespace,version.toString()]);
        if(update.rowCount!==1)throw new GameError('REVISION_CONFLICT','数据库已由另一版本更新，请重启服务读取最新世界',409);
        const nextVersion=rowVersion(update.rows[0]);committing=true;await client.query('commit');began=false;
        ensure();stored=candidate;version=nextVersion;return result;
      }catch(error){
        fail();if(began&&!committing)await client.query('rollback').catch(()=>{});
        // COMMIT may have succeeded although its acknowledgement was lost.
        // Stop every read/write; restart re-loads durable canonical receipts.
        throw error instanceof GameError?error:unavailable();
      }
    });},close,
  };
}

/** Backups read one complete committed JSONB row; they contain private secrets. */
export async function readPostgresBackup({connectionString,namespace='three-kingdoms',requireTLS=true,clientFactory,now=Date.now()}={}) {
  advisoryLockKey(namespace);const client=await clientFor({connectionString,requireTLS,clientFactory});client.on('error',()=>{});
  try{await client.connect();const result=await client.query(`select version,snapshot from ${ROOM_WORLD_TABLE} where namespace=$1`,[namespace]);
    if(!result.rows.length)throw new GameError('WORLD_NOT_FOUND','数据库没有该世界，未生成备份',404);
    return {schema:1,namespace,version:rowVersion(result.rows[0]).toString(),snapshot:validatedSnapshot(result.rows[0].snapshot,now)};
  }finally{await client.end().catch(()=>{});}
}

export async function restorePostgresBackup({connectionString,namespace='three-kingdoms',snapshot,replace=false,requireTLS=true,clientFactory,now=Date.now()}={}) {
  advisoryLockKey(namespace);const candidate=validatedSnapshot(snapshot,now),client=await clientFor({connectionString,requireTLS,clientFactory});client.on('error',()=>{});let began=false;
  try{await client.connect();const lock=await acquireRoomLock(client,namespace);await client.query('begin');began=true;await verifyLock(client,lock);
    const existing=await client.query(`select version from ${ROOM_WORLD_TABLE} where namespace=$1 for update`,[namespace]);
    if(existing.rows.length&&!replace)throw new GameError('RESTORE_TARGET_EXISTS','目标世界已存在；恢复前请明确选择替换并保留备份',409);
    const version=existing.rows.length?rowVersion(existing.rows[0])+1n:1n;
    await client.query(`insert into ${ROOM_WORLD_TABLE}(namespace,version,snapshot) values($1,$2,$3::jsonb) on conflict(namespace) do update set snapshot=excluded.snapshot,version=excluded.version,updated_at=now()`,[namespace,version.toString(),JSON.stringify(candidate)]);
    await client.query('commit');began=false;return {ok:true,namespace,version:version.toString()};
  }catch(error){if(began)await client.query('rollback').catch(()=>{});throw error;}finally{await client.end().catch(()=>{});}
}
