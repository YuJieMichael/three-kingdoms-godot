import {createGameRuntime, copy, seededRandom, GameError} from '../vendor/shared/runtime.mjs';
import {MemoryStore} from '../vendor/shared/memory-store.mjs';
import {handleRequest} from '../vendor/shared/service.mjs';

export const ROOM_PROFILE = Object.freeze({
  id:'local-room-rehearsal-1',label:'本机房间攻防演练',prepared:true,
  production:false,publicServer:false,
  description:'1–8 名城主使用相同备战资源和兵力，席位交替分入青、赤两盟；演练已结束保护并进入交战，建设和攻防仍使用原作规则。',
});
export const ROOM_ARMY = Object.freeze({cavalry:600,archer:500,spear:300});
const desiredHomes=[{x:26,y:28},{x:30,y:28},{x:26,y:34},{x:30,y:34},
  {x:22,y:28},{x:34,y:28},{x:22,y:34},{x:34,y:34}];

/** No client save is accepted: every occupied seat starts from a canonical new save. */
export async function addPreparedMember(room,member,now) {
  const store=new MemoryStore(room.data);
  await handleRequest(store,member.id,{op:'create-realm',realm:room.id,
    commandId:`scenario_join_${member.id}`,expectedRevision:0},now);
  const row=store.data.players.find(player=>player.id===member.id),
    runtime=createGameRuntime({snapshot:row.state,now,random:seededRandom(member.seat)}),g=runtime.Game,s=g.state;
  s.ruler=member.name;s.realm.cities.capital.name=member.name+'城';
  const buildings=['drill','tavern','inn','barracks','market','academy','house','wall','warehouse'];
  for(const [site,id]of buildings.entries()){s.cityLayout[site]=id;s.cityLevels[site]=id==='wall'?1:5;s.buildings[id]=s.cityLevels[site];}
  const hall=s.cityLayout.indexOf('hall');s.cityLevels[hall]=5;s.buildings.hall=5;
  s.res={food:300000,wood:180000,stone:180000,iron:180000,gold:80000};s.population=1000;
  Object.assign(s.army,ROOM_ARMY);s.speed=1;s.autoUpgrade=false;s.autoResearch=false;
  s.onlineRealm={version:1,joinedAt:now,protectionUntil:now,peaceUntil:0,peaceCooldown:0,declarations:[],events:[]};
  g.save();if(!g.validSave(s))throw new GameError('SCENARIO_INVALID','房间演练未通过原作存档校验',500);
  row.state=copy(s);row.name=member.name;row.level=5;
  const wanted=desiredHomes[member.seat-1],occupied=new Set(store.data.cities.map(city=>`${city.x}:${city.y}`));
  for(const player of store.data.players)if(player.id!==member.id)occupied.add(`${player.home.x}:${player.home.y}`);
  const positions=[];for(let y=2;y<62;y++)for(let x=2;x<62;x++)positions.push({x,y});
  positions.sort((a,b)=>Math.hypot(a.x-wanted.x,a.y-wanted.y)-Math.hypot(b.x-wanted.x,b.y-wanted.y)||a.y-b.y||a.x-b.x);
  row.home=positions.find(point=>!occupied.has(`${point.x}:${point.y}`));
  if(!row.home)throw new GameError('WORLD_FULL','房间没有可用城址',409);
  if(!store.data.alliances.length)store.data.alliances=[
    {id:'room_blue',name:'演练青盟',leader:null,relations:{room_red:{status:'enemy',startsAt:now}},marks:[],realm:room.id},
    {id:'room_red',name:'演练赤盟',leader:null,relations:{room_blue:{status:'enemy',startsAt:now}},marks:[],realm:room.id},
  ];
  const alliance=store.data.alliances.find(value=>value.id==='room_'+member.team);
  // Joining a prepared seat respects any diplomacy changed by existing players.
  // If its original team was disbanded, recreate that team without altering the other alliance.
  if(!alliance)store.data.alliances.push({id:'room_'+member.team,name:member.team==='blue'?'演练青盟':'演练赤盟',
    leader:null,relations:{},marks:[],realm:room.id});
  const assigned=store.data.alliances.find(value=>value.id==='room_'+member.team),leader=!assigned.leader;
  if(leader)assigned.leader=member.id;
  store.data.memberships.push({user:member.id,alliance:assigned.id,role:leader?'leader':'member',realm:room.id});
  store.data.allianceVersions[room.id]=(store.data.allianceVersions[room.id]||0)+1;
  // Internal join receipt contains the save before preparation; it is never a public retry.
  store.data.receipts=store.data.receipts.filter(receipt=>receipt.actor!==member.id||!receipt.id.startsWith('scenario_join_'));
  room.data=store.data;
}
