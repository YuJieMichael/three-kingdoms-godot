import {createGameRuntime, copy, seededRandom, GameError} from '../vendor/shared/runtime.mjs';
import {MemoryStore} from '../vendor/shared/memory-store.mjs';
import {handleRequest} from '../vendor/shared/service.mjs';

export const SHARED_REALM = 'local-rehearsal';
export const REHEARSAL_ACTORS = Object.freeze([
  {id:'actor_1',slot:1,name:'演练·青龙',army:{cavalry:1200,archer:800,spear:400}},
  {id:'actor_2',slot:2,name:'演练·白虎',army:{cavalry:600,archer:500,spear:200}},
  {id:'actor_3',slot:3,name:'演练·朱雀',army:{cavalry:400,archer:500,spear:300}},
  {id:'actor_4',slot:4,name:'演练·玄武',army:{cavalry:600,archer:500,spear:300}},
]);
export const SCENARIO = Object.freeze({
  id:'pvp-rehearsal-1',label:'本机 4 城 PvP 演练',players:4,
  description:'四个虚构账号分属青、赤两盟，已备兵并进入交战；仅演练账号结束保护。行军、战斗、伤兵和返程使用原作规则。',
  production:false,publicServer:false,prepared:true,
});

/** Fresh rehearsal saves are created on the server, never supplied by a client. */
export async function createRehearsal(now) {
  const store = new MemoryStore();
  for (const actor of REHEARSAL_ACTORS) await handleRequest(store,actor.id,{
    op:'create-realm',realm:SHARED_REALM,commandId:`scenario_join_${actor.id}`,expectedRevision:0,
  },now);
  const desired = [{x:26,y:28},{x:30,y:28},{x:26,y:34},{x:30,y:34}], used = new Set();
  const occupied = new Set(store.data.cities.map(city=>`${city.x}:${city.y}`));
  for (const [index,actor] of REHEARSAL_ACTORS.entries()) {
    const row = store.data.players.find(player=>player.id===actor.id);
    const runtime = createGameRuntime({snapshot:row.state,now,random:seededRandom(index+1)}), g=runtime.Game,s=g.state;
    s.ruler=actor.name;s.realm.cities.capital.name=actor.name.replace('演练·','')+'城';
    const buildings=['drill','tavern','inn','barracks','market','academy','house','wall','warehouse'];
    for (const [site,id] of buildings.entries()) {s.cityLayout[site]=id;s.cityLevels[site]=id==='wall'?1:5;s.buildings[id]=s.cityLevels[site];}
    const hall=s.cityLayout.indexOf('hall');s.cityLevels[hall]=5;s.buildings.hall=5;
    s.res={food:300000,wood:180000,stone:180000,iron:180000,gold:80000};s.population=1000;
    Object.assign(s.army,actor.army);s.speed=1;s.autoUpgrade=false;s.autoResearch=false;
    s.onlineRealm={version:1,joinedAt:now,protectionUntil:now,peaceUntil:0,peaceCooldown:0,declarations:[],events:[]};
    g.save();if(!g.validSave(s))throw new GameError('SCENARIO_INVALID','演练场景未通过原作存档校验',500);
    row.state=copy(s);row.name=s.ruler;row.level=5;
    const wanted=desired[index],positions=[];
    for(let y=2;y<62;y++)for(let x=2;x<62;x++)positions.push({x,y});
    positions.sort((a,b)=>Math.hypot(a.x-wanted.x,a.y-wanted.y)-Math.hypot(b.x-wanted.x,b.y-wanted.y)||a.y-b.y||a.x-b.x);
    row.home=positions.find(point=>!occupied.has(`${point.x}:${point.y}`)&&!used.has(`${point.x}:${point.y}`));
    used.add(`${row.home.x}:${row.home.y}`);
  }
  store.data.alliances=[
    {id:'rehearsal_blue',name:'演练青盟',leader:'actor_1',relations:{rehearsal_red:{status:'enemy',startsAt:now}},marks:[],realm:SHARED_REALM},
    {id:'rehearsal_red',name:'演练赤盟',leader:'actor_3',relations:{rehearsal_blue:{status:'enemy',startsAt:now}},marks:[],realm:SHARED_REALM},
  ];
  store.data.memberships=REHEARSAL_ACTORS.map(actor=>({user:actor.id,alliance:actor.slot<3?'rehearsal_blue':'rehearsal_red',role:[1,3].includes(actor.slot)?'leader':'member',realm:SHARED_REALM}));
  store.data.allianceVersions[SHARED_REALM]=1;
  // Join receipts contain the pre-preparation saves; these internal IDs cannot be retried over HTTP.
  store.data.receipts=[];
  return store.data;
}
