import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {copy,createGameRuntime,GameError} from '../vendor/shared/runtime.mjs';
import {MemoryStore} from '../vendor/shared/memory-store.mjs';
import {atomicSharedJSON,lockDirectory} from './shared-store.mjs';
import {ROOM_PROFILE,addPreparedMember} from './room-scenario.mjs';

const object=value=>!!value&&typeof value==='object'&&!Array.isArray(value);
export const validSecret=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const uuid=value=>typeof value==='string'&&/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);
const roomId=value=>typeof value==='string'&&/^room_[a-f0-9]{32}$/.test(value);
const memberId=value=>typeof value==='string'&&/^member_[a-f0-9]{32}$/.test(value);
const secret=()=>crypto.randomBytes(32).toString('hex');
const id=prefix=>prefix+crypto.randomUUID().replaceAll('-','');
const sameSecret=(left,right)=>validSecret(left)&&validSecret(right)&&crypto.timingSafeEqual(Buffer.from(left),Buffer.from(right));

export function roomMetadata(room) {
  return {id:room.id,name:room.name,capacity:room.capacity,
    members:room.members.map(member=>({id:member.id,name:member.name,seat:member.seat,team:member.team}))};
}
export function memberSession(room,member) {
  return {ok:true,protocol:1,room:roomMetadata(room),seat:member.seat,
    actor:{id:member.id,name:member.name},authorityId:member.authorityId,
    accessToken:member.accessToken,recoveryKey:member.recoveryKey,inviteCode:room.inviteCode};
}
export function cleanName(value,maximum,label) {
  if(typeof value!=='string')throw new GameError('BAD_NAME',`${label}格式无效`);
  const name=value.trim().normalize('NFC');
  if(!name.length||name.length>maximum||/[\u0000-\u001f\u007f]/.test(name))throw new GameError('BAD_NAME',`${label}需要 1–${maximum} 个字符`);
  return name;
}

export function validateStored(stored,now) {
  const corrupt=message=>{throw new GameError('ROOM_SAVE_CORRUPT',message+'，原文件已保留',500);};
  if(!object(stored)||stored.schema!==1||stored.profile!==ROOM_PROFILE.id||!Array.isArray(stored.rooms)||!Array.isArray(stored.requests))corrupt('房间存档结构无效');
  const seenRooms=new Set(),seenMembers=new Set(),seenAuthorities=new Set(),seenSecrets=new Set(),seenRequests=new Set();
  const takeSecret=value=>{if(!validSecret(value)||seenSecrets.has(value))corrupt('房间凭据无效');seenSecrets.add(value);};
  for(const room of stored.rooms){
    if(!object(room)||!roomId(room.id)||seenRooms.has(room.id)||!Number.isInteger(room.capacity)||room.capacity<1||room.capacity>8||!Array.isArray(room.members)||room.members.length<1||room.members.length>room.capacity||!Number.isSafeInteger(room.createdAt)||room.createdAt<0||room.profile!==ROOM_PROFILE.id)corrupt('房间资料无效');
    try{if(cleanName(room.name,40,'房间名称')!==room.name)corrupt('房间名称无效');}catch{corrupt('房间名称无效');}
    seenRooms.add(room.id);takeSecret(room.inviteCode);
    const seats=new Set(),members=new Set(),accounts=new Set();
    for(const member of room.members){
      if(!object(member)||!memberId(member.id)||seenMembers.has(member.id)||!uuid(member.authorityId)||seenAuthorities.has(member.authorityId)||!Number.isInteger(member.seat)||member.seat<1||member.seat>room.capacity||seats.has(member.seat)||member.team!==(member.seat%2?'blue':'red'))corrupt('房间成员无效');
      try{if(cleanName(member.name,20,'城主名称')!==member.name)corrupt('城主名称无效');}catch{corrupt('城主名称无效');}
      seenMembers.add(member.id);members.add(member.id);seenAuthorities.add(member.authorityId);seats.add(member.seat);
      if(member.accountId!==undefined){
        if(!uuid(member.accountId)||accounts.has(member.accountId.toLowerCase()))corrupt('房间账号绑定无效');
        accounts.add(member.accountId.toLowerCase());
      }
      takeSecret(member.accessToken);takeSecret(member.recoveryKey);
    }
    if(!object(room.data)||!object(room.data.allianceVersions))corrupt('房间世界结构无效');
    for(const key of ['players','heroes','cities','marches','orders','alliances','memberships','receipts','private'])if(!Array.isArray(room.data[key]))corrupt('房间世界数据表无效');
    if(room.data.private.length||room.data.players.length!==members.size)corrupt('房间成员与世界不匹配');
    const players=new Set(),homes=new Set();
    for(const row of room.data.players){
      const member=room.members.find(value=>value.id===row.id),home=row.home;
      if(!member||players.has(row.id)||row.realm!==room.id||!Number.isSafeInteger(row.revision)||row.revision<1||!Number.isInteger(home?.x)||!Number.isInteger(home?.y)||home.x<0||home.x>63||home.y<0||home.y>63||homes.has(`${home.x}:${home.y}`))corrupt('房间玩家数据无效');
      players.add(row.id);homes.add(`${home.x}:${home.y}`);
      try{createGameRuntime({snapshot:row.state,now});}catch{corrupt('房间存档未通过原作校验');}
    }
    for(const key of ['heroes','cities','marches','orders','alliances','memberships','receipts'])for(const row of room.data[key])if(!object(row)||row.realm!==room.id)corrupt('房间世界范围无效');
    for(const [key,column]of [['heroes','line'],['cities','id'],['marches','id'],['orders','id'],['alliances','id'],['memberships','user']]){
      const ids=new Set();for(const row of room.data[key]){
        if(typeof row[column]!=='string'||!row[column].length||ids.has(row[column]))corrupt('房间共享实体编号无效');
        ids.add(row[column]);
      }
    }
    const receiptIds=new Set();
    for(const row of room.data.receipts){
      const key=row.actor+':'+row.id;
      if(!members.has(row.actor)||typeof row.id!=='string'||!row.id.length||!validSecret(row.hash)||!object(row.response)||receiptIds.has(key))corrupt('房间操作回执无效');
      receiptIds.add(key);
    }
    for(const hero of room.data.heroes)if(hero.owner!==null&&!members.has(hero.owner)||!Number.isSafeInteger(hero.version)||hero.version<0)corrupt('房间名将数据无效');
    for(const city of room.data.cities)if(city.owner!==null&&!members.has(city.owner)||!Number.isInteger(city.x)||!Number.isInteger(city.y)||city.x<0||city.x>63||city.y<0||city.y>63||!Number.isSafeInteger(city.version)||city.version<0)corrupt('房间城市数据无效');
    for(const march of room.data.marches){
      if(!members.has(march.source)||march.target!==null&&!members.has(march.target)||!Number.isSafeInteger(march.version)||march.version<0||!['march','return','stationed','done'].includes(march.status)||!['pvp','aid','hunt','trade'].includes(march.kind)||!Number.isSafeInteger(march.start)||!Number.isSafeInteger(march.arrive)||march.start<0||march.arrive<march.start||march.returnAt!==null&&(!Number.isSafeInteger(march.returnAt)||march.returnAt<march.start)||!object(march.army))corrupt('房间行军数据无效');
    }
    for(const order of room.data.orders)if(!members.has(order.seller)||!Number.isSafeInteger(order.version)||order.version<0||!['open','filled','cancelled'].includes(order.status))corrupt('房间交易数据无效');
    for(const alliance of room.data.alliances)if(alliance.leader!==null&&!members.has(alliance.leader)||!object(alliance.relations)||!Array.isArray(alliance.marks))corrupt('房间联盟数据无效');
    for(const membership of room.data.memberships)if(!members.has(membership.user)||!['leader','member'].includes(membership.role)||!room.data.alliances.some(alliance=>alliance.id===membership.alliance))corrupt('房间联盟成员无效');
  }
  for(const request of stored.requests){
    if(!object(request)||!validSecret(request.id)||seenRequests.has(request.id)||!['create','join'].includes(request.operation)||!validSecret(request.hash)||!object(request.response))corrupt('房间加入回执无效');
    const room=stored.rooms.find(value=>value.id===request.roomId),member=room?.members.find(value=>value.id===request.actorId);
    if(!room||!member||request.response.room?.id!==room.id||request.response.actor?.id!==member.id||request.response.authorityId!==member.authorityId||request.response.accessToken!==member.accessToken||request.response.recoveryKey!==member.recoveryKey||request.response.inviteCode!==room.inviteCode)corrupt('房间加入身份回执无效');
    if(request.accountId!==undefined&&!uuid(request.accountId)||member.accountId!==undefined&&(typeof request.accountId!=='string'||request.accountId.toLowerCase()!==member.accountId.toLowerCase())||member.accountId===undefined&&request.accountId!==undefined)corrupt('房间加入账号回执无效');
    seenRequests.add(request.id);
  }
}

/** Membership, credentials, world state and receipts share one durable commit. */
export async function openRoomStore(dataDir,now) {
  await fs.mkdir(dataDir,{recursive:true,mode:0o700});dataDir=await fs.realpath(path.resolve(dataDir));
  const unlock=await lockDirectory(dataDir),filename=path.join(dataDir,'rooms.json');let stored,failed=false,missing=false;
  try{
    // Never turn an existing private or four-account save into rooms implicitly.
    for(const legacy of ['save.json','shared-world.json','credentials.json']){
      try{await fs.access(path.join(dataDir,legacy));throw new GameError('ROOM_DIRECTORY_CONFLICT','请选择独立房间目录；现有演练存档已保留',409);}catch(error){if(error.code!=='ENOENT')throw error;}
    }
    try{stored=JSON.parse(await fs.readFile(filename,'utf8'));}catch(error){if(error.code!=='ENOENT')throw new GameError('ROOM_SAVE_CORRUPT','房间存档无法读取，未覆盖原文件',500);missing=true;}
    if(missing){stored={schema:1,profile:ROOM_PROFILE.id,rooms:[],requests:[]};await atomicSharedJSON(filename,stored);}
    validateStored(stored,now);await fs.chmod(dataDir,0o700);await fs.chmod(filename,0o600);
  }catch(error){await unlock();throw error;}
  return {
    dataDir,filename,snapshot:()=>copy(stored),
    room:roomId=>copy(stored.rooms.find(room=>room.id===roomId)||null),
    identityForToken(token){
      if(!validSecret(token))return null;
      for(const room of stored.rooms)for(const member of room.members)if(sameSecret(member.accessToken,token))return {roomId:room.id,actorId:member.id};
      return null;
    },
    recover(roomId,key){const room=stored.rooms.find(value=>value.id===roomId),member=room?.members.find(value=>sameSecret(value.recoveryKey,key));return member?memberSession(room,member):null;},
    async transaction(operation){
      if(failed)throw new GameError('PERSISTENCE_FAILED','房间存档写入异常，请重启并检查房间目录',503);
      const candidate=copy(stored),result=await operation(candidate);
      try{await atomicSharedJSON(filename,candidate);}catch{
        // Rename may have completed before directory fsync fails; restore the previous commit.
        try{await atomicSharedJSON(filename,stored);}catch{failed=true;}
        throw new GameError('PERSISTENCE_FAILED','房间结果未确认写入，操作已撤销，请检查房间目录',503);
      }
      stored=candidate;return result;
    },close:unlock,
  };
}

export async function createRoom(candidate,input,now,accountId=undefined) {
  const room={id:id('room_'),name:input.roomName,capacity:input.capacity,createdAt:now,
    profile:ROOM_PROFILE.id,inviteCode:secret(),members:[],data:new MemoryStore().data};
  candidate.rooms.push(room);return joinRoom(room,input.playerName,now,accountId);
}
export async function joinRoom(room,name,now,accountId=undefined) {
  if(accountId!==undefined){
    if(!uuid(accountId))throw new GameError('BAD_ACCOUNT','账号绑定编号无效',400);
    accountId=accountId.toLowerCase();
    const existing=room.members.find(member=>member.accountId?.toLowerCase()===accountId);
    if(existing)return memberSession(room,existing);
  }
  if(room.members.length>=room.capacity)throw new GameError('ROOM_FULL','房间已满，请使用恢复密钥返回已有席位',409);
  const seat=Array.from({length:room.capacity},(_,index)=>index+1).find(value=>!room.members.some(member=>member.seat===value)),
    member={id:id('member_'),name,seat,team:seat%2?'blue':'red',authorityId:crypto.randomUUID(),accessToken:secret(),recoveryKey:secret(),...(accountId===undefined?{}:{accountId})};
  await addPreparedMember(room,member,now);room.members.push(member);return memberSession(room,member);
}
