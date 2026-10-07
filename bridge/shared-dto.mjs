import {copy, scopedRuntime, GameError} from '../vendor/shared/runtime.mjs';
import {publicWorld} from '../vendor/shared/service.mjs';
import {attackPermission} from '../vendor/shared/realm-systems.mjs';
import {gameView, worldView, nodeView} from './dto.mjs';
import {reportEconomy} from './report-economy.mjs';

export const playerNodeId=(actor,city='capital')=>`player_city:${actor}:${city}`;
const point=p=>({x:p.x,y:p.y});
const count=army=>Object.values(army||{}).reduce((sum,value)=>sum+value,0);
function location(context,actor,city='capital') {
  const row=context.players.find(player=>player.id===actor);
  return city==='capital'?row?.home:row?.state.realm.cities[city]||row?.home;
}
function publicPlayerNode(context,actor,target,city='capital') {
  const row=context.players.find(player=>player.id===target),owner=context.players.find(player=>player.id===actor);
  if(!row||!row.state.realm.cities[city])return null;
  const at=location(context,target,city),owned=actor===target,membership=context.memberships.find(member=>member.user===target),ours=context.memberships.find(member=>member.user===actor);
  const raid=owned?'请选择其他玩家城池':attackPermission(copy(owner.state),copy(row.state),actor,target,context.alliances,context.memberships,context.serverTime);
  return {id:playerNodeId(target,city),...point(at),name:city==='capital'?`${row.name||row.state.ruler}主城`:row.state.realm.cities[city].name,
    terrain:'plain',tileType:'fort',kind:'city',level:city==='capital'?row.state.realm.cities.capital.data.buildings.hall:row.state.realm.cities[city].data.buildings.hall,
    owned,owner:target,relation:owned?'own':membership?.alliance&&membership.alliance===ours?.alliance?'allied':'enemy',hidden:false,selectable:true,player:true,shared:true,playerId:target,cityId:city,alliance:membership?.alliance||null,
    faction:owned?'我方':membership?.alliance&&membership.alliance===ours?.alliance?'同盟':'玩家',
    description:owned?'我的共享世界城池':'玩家城池；驻军和资源需通过游戏内情报判断。',army:{},intel:null,
    dispatch:{raid,occupy:city==='capital'?'主城是保底城市，不能被占领':raid,aid:owned?'请选择同盟城池':membership?.alliance&&membership.alliance===ours?.alliance?'':'只能向同盟城池派出援军'},
  };
}
function sharedMarches(context,actor,shared) {
  return shared.marches.map(march=>{
    const owned=march.source===actor,trade=march.kind==='trade';
    const source=location(context,march.source,march.sourceCity),target=march.kind==='hunt'?context.players.find(p=>p.id===march.source)?.state.wildGenerals.rumors.find(r=>r.line===march.line):location(context,march.target,march.targetCity);
    let destination=target;
    if(march.kind==='hunt'){const raw=context.marches.find(row=>row.id===march.id),g=scopedRuntime(context.players.find(p=>p.id===raw.source).state,context.serverTime,context.marches,raw.source).Game;destination=g.getNode(context.heroes.find(hero=>hero.line===march.line)?.node);}
    // Market escrow belongs to the buyer; the goods physically travel seller -> buyer.
    let from=trade?destination:source,to=trade?source:destination;
    if(march.status==='return')[from,to]=[to,from];
    if(march.status==='stationed')from=to;
    const clean={...copy(march),shared:true,incoming:!owned,from:point(from||source),to:point(to||source),origin:point(from||source),destination:point(to||source),
      node:playerNodeId(march.target||march.source,march.targetCity||'capital'),type:march.kind,
      label:`${march.kind==='aid'?'援军':march.kind==='trade'?'商队':march.kind==='hunt'?'寻将':'讨伐'} · ${owned?'我方':'来军'}`,
      start:march.status==='return'?march.returnAt-Math.max(1000,march.arrive-march.start):march.start,arrive:march.status==='return'?march.returnAt:march.status==='stationed'?null:march.arrive,
      count:owned?count(march.army):null,canStartBattle:false,
    };
    if(!owned){delete clean.army;delete clean.general;}
    if(owned&&march.kind==='aid'&&march.status==='stationed')clean.recallCommand={type:'shared.recallAid',args:[{id:march.id}],sourceCity:march.sourceCity};
    return clean;
  });
}

export function sharedProjection(context,actor) {
  const shared=publicWorld(context,actor);
  shared.marches=sharedMarches(context,actor,shared);
  shared.reports=shared.reports.map(report=>{
    const march=context.marches.find(row=>row.id===report.id);
    const delivered=!!march.lootDelivered||march.status==='done'&&Number.isFinite(march.returnAt);
    return {...report,shared:true,status:march.status,lootDelivered:delivered,
      // The canonical return transaction is the delivery proof, not the battle loot estimate.
      receivedResources:delivered&&march.source===actor?copy(march.loot||{}):{},
      lootStatus:delivered?'已入库':march.source===actor?'返程携带':'敌军携走'};
  });
  return shared;
}

export function sharedEnvelope(context,actor,authorityId,identity,result=undefined,replayed=false) {
  const row=context.players.find(player=>player.id===actor);
  if(!row)throw new GameError('NOT_JOINED','演练账号尚未创建',404);
  const runtime=scopedRuntime(row.state,context.serverTime,context.marches,actor),g=runtime.Game;
  const shared=sharedProjection(context,actor),view=gameView(g,context.serverTime,runtime,{shared:true});
  if(g.currentCityId()==='capital')view.city={...view.city,...point(row.home)};
  view.marches=[...view.marches,...shared.marches];
  view.reports=[...shared.reports.map(report=>({...report,economy:reportEconomy(runtime,report,{shared:true,actor})})),...view.reports];
  return {ok:true,protocol:1,mode:'shared',revision:row.revision,state:copy(g.state),view,serverTime:context.serverTime,authorityId,
    actor:{id:identity.id,name:identity.name},shared,...(result===undefined?{}:{result:copy(result),replayed})};
}

export function sharedWorldView(context,actor,authorityId,identity) {
  const row=context.players.find(player=>player.id===actor),runtime=scopedRuntime(row.state,context.serverTime,context.marches,actor),g=runtime.Game;
  const view=worldView(g,context.serverTime),shared=sharedProjection(context,actor);
  const home=g.currentCityId()==='capital'?row.home:g.cityMeta();view.home=point(home);
  // Canonical private capitals are always (32,32); shared home coordinates belong to the server map.
  const oldHome=view.tiles.findIndex(tile=>tile.id==='home');
  if(oldHome>=0){const tile=view.tiles[oldHome];view.tiles[oldHome]={id:`shared_terrain_${tile.x}_${tile.y}`,x:tile.x,y:tile.y,name:'平原',terrain:'plain',tileType:'plain',kind:'wild',level:0,owned:false,hidden:false,selectable:false};}
  for(const player of context.players)for(const city of Object.values(player.state.realm.cities)) {
    if(!city.capital&&player.id!==actor&&!shared.cities.some(visible=>visible.owner===player.id&&visible.cityId===city.id))continue;
    const node=publicPlayerNode(context,actor,player.id,city.id);
    const index=node.y*view.width+node.x;if(index>=0&&index<view.tiles.length)view.tiles[index]=node;
  }
  return {...view,marches:[...view.marches,...shared.marches],revision:row.revision,serverTime:context.serverTime,authorityId,
    protocol:1,mode:'shared',actor:{id:identity.id,name:identity.name},shared};
}

export function sharedNodeView(context,actor,id,authorityId,identity) {
  let node;
  if(id.startsWith('player_city:')){const parts=id.split(':');if(parts.length===3)node=publicPlayerNode(context,actor,parts[1],parts[2]);}
  else {
    const row=context.players.find(player=>player.id===actor),g=scopedRuntime(row.state,context.serverTime,context.marches,actor).Game;
    const raw=g.getNode(id);if(!raw)throw new GameError('NODE_NOT_FOUND','目标不存在',404);
    if(!g.landmarkVisible(raw.id))throw new GameError('NODE_HIDDEN','请先完成当前任务据点',403);
    node=nodeView(g,raw);
  }
  if(!node)throw new GameError('NODE_NOT_FOUND','目标不存在',404);
  return {node,revision:context.players.find(player=>player.id===actor).revision,serverTime:context.serverTime,authorityId,mode:'shared',actor:{id:identity.id,name:identity.name}};
}
