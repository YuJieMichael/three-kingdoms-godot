// Test-only loopback Auth provider. Never import from production launchers.
import http from 'node:http';
import crypto from 'node:crypto';
const secret=()=>crypto.randomBytes(32).toString('hex');
export const ALICE='11111111-1111-4111-8111-111111111111',BOB='22222222-2222-4222-8222-222222222222';

export async function startFakeSupabase(clock=Date.now) {
  const users=new Map([['alice@test.invalid',{id:ALICE,email:'alice@test.invalid',email_confirmed_at:'2026-01-01T00:00:00Z',user_metadata:{accountId:BOB,isAdmin:true}}],
    ['bob@test.invalid',{id:BOB,email:'bob@test.invalid',email_confirmed_at:'2026-01-01T00:00:00Z'}]]),access=new Map(),refresh=new Map();
  const info={users,access,refresh,calls:[],unavailable:false,expiresIn:60,identityOverride:null,tokenUserOverride:null};
  const tokens=user=>{
    const result={access_token:'supabase-access-'+secret(),refresh_token:'supabase-refresh-'+secret(),expires_in:info.expiresIn,token_type:'bearer',user:info.tokenUserOverride||user},
      record={user,session:secret(),expires:clock()+info.expiresIn*1000};
    access.set(result.access_token,record);refresh.set(result.refresh_token,record);return result;
  };
  const server=http.createServer(async(req,res)=>{
    const url=new URL(req.url,'http://local'),parts=[];for await(const part of req)parts.push(part);
    let body={};try{if(parts.length)body=JSON.parse(Buffer.concat(parts).toString());}catch{}
    info.calls.push({path:url.pathname,grant:url.searchParams.get('grant_type'),method:req.method,apikey:req.headers.apikey});
    const send=(status,value)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(value));};
    if(info.unavailable){send(503,{error:'provider detail must never reach a client'});return;}
    if(req.headers.apikey!=='sb_publishable_local_test_key'){send(401,{});return;}
    if(url.pathname==='/auth/v1/token'&&url.searchParams.get('grant_type')==='password'){
      const user=users.get(body.email);if(!user||body.password!=='correct-test-password'){send(400,{error:'invalid_grant'});return;}
      send(200,tokens(user));return;
    }
    if(url.pathname==='/auth/v1/token'&&url.searchParams.get('grant_type')==='refresh_token'){
      const record=refresh.get(body.refresh_token);if(!record){send(400,{});return;}
      refresh.delete(body.refresh_token);send(200,tokens(record.user));return;
    }
    const token=String(req.headers.authorization||'').replace(/^Bearer /,''),record=access.get(token);
    if(!record||record.expires<=clock()||!users.has(record.user.email)){send(401,{});return;}
    if(url.pathname==='/auth/v1/user'){send(200,info.identityOverride||record.user);return;}
    if(url.pathname==='/auth/v1/logout'&&url.searchParams.get('scope')==='local'){
      for(const [key,value]of refresh)if(value.session===record.session)refresh.delete(key);
      res.writeHead(204);res.end();return;
    }
    send(404,{});
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  return {...info,get unavailable(){return info.unavailable;},set unavailable(value){info.unavailable=value;},
    get identityOverride(){return info.identityOverride;},set identityOverride(value){info.identityOverride=value;},
    get tokenUserOverride(){return info.tokenUserOverride;},set tokenUserOverride(value){info.tokenUserOverride=value;},
    url:'http://127.0.0.1:'+server.address().port,close:()=>new Promise(resolve=>server.close(resolve))};
}
