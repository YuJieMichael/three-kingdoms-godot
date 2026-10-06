import crypto from 'node:crypto';
import {GameError} from '../vendor/shared/runtime.mjs';

const object=value=>!!value&&typeof value==='object'&&!Array.isArray(value);
const uuid=value=>typeof value==='string'&&/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value);
const opaque=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const email=value=>typeof value==='string'?value.trim().toLowerCase():'';
const safeToken=value=>typeof value==='string'&&value.length>=8&&value.length<=16384&&!/[\r\n\u0000]/.test(value);

/** Supabase tokens never leave this process. Clients receive only an opaque RAM session. */
export function createSupabaseAuth({url,publishableKey,allowedEmails,sessionTTL=12*3600000,
  clock=Date.now,fetchImpl=globalThis.fetch,timeoutMs=8000,maxSessions=256,allowInsecureLocal=false}={}) {
  let project;try{project=new URL(url);}catch{throw new Error('Supabase Auth URL is required');}
  if(project.username||project.password||project.search||project.hash||project.pathname!=='/'||
    project.protocol!=='https:'&&!(allowInsecureLocal&&project.protocol==='http:'&&['localhost','127.0.0.1','[::1]'].includes(project.hostname)))throw new Error('Supabase Auth requires an HTTPS project origin');
  if(!safeToken(publishableKey)||publishableKey.startsWith('sb_secret_'))throw new Error('Use a publishable Supabase Auth key');
  if(!publishableKey.startsWith('sb_publishable_')){
    let role;try{role=JSON.parse(Buffer.from(publishableKey.split('.')[1],'base64url').toString()).role;}catch{}
    if(role!=='anon')throw new Error('Use a publishable or legacy anon Supabase Auth key');
  }
  if(!Array.isArray(allowedEmails)||!allowedEmails.length||allowedEmails.some(value=>typeof value!=='string'||!value.includes('@')||value.length>254))throw new Error('Closed-test allowedEmails must be a nonempty email list');
  const allowed=new Set(allowedEmails.map(email));
  if(!Number.isSafeInteger(sessionTTL)||sessionTTL<60000||sessionTTL>7*86400000||!Number.isInteger(timeoutMs)||timeoutMs<100||timeoutMs>30000||!Number.isInteger(maxSessions)||maxSessions<1||maxSessions>10000)throw new Error('Invalid Auth session limits');
  const sessions=new Map(),now=()=>{const value=clock();if(!Number.isSafeInteger(value)||value<0)throw new GameError('SERVER_CLOCK','服务器时间无效',500);return value;};
  const denied=()=>new GameError('ACCOUNT_UNAUTHORIZED','账号会话已失效，请重新登录',401);
  const unavailable=()=>new GameError('AUTH_UNAVAILABLE','账号服务暂时不可用，操作未获授权，请稍后重试',503);
  const request=async(route,{method='GET',accessToken,body}={})=>{
    const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),timeoutMs);
    try{
      const response=await fetchImpl(project.origin+'/auth/v1'+route,{method,redirect:'error',signal:controller.signal,
        headers:{apikey:publishableKey,...(accessToken?{Authorization:'Bearer '+accessToken}:{}),...(body?{'Content-Type':'application/json'}:{})},
        ...(body?{body:JSON.stringify(body)}:{})});
      if(!response.ok){if([400,401,403,404,422].includes(response.status))throw denied();throw unavailable();}
      if(response.status===204)return null;
      const bytes=await response.arrayBuffer();if(bytes.byteLength>256*1024)throw unavailable();
      let value;try{value=JSON.parse(new TextDecoder().decode(bytes));}catch{throw unavailable();}
      if(!object(value))throw unavailable();return value;
    }catch(error){if(error instanceof GameError)throw error;throw unavailable();}finally{clearTimeout(timeout);}
  };
  const userFrom=value=>{
    const address=email(value?.email),banned=Date.parse(value?.banned_until||'');
    if(!object(value)||!uuid(value.id)||!allowed.has(address)||!value.email_confirmed_at||value.is_anonymous===true||Number.isFinite(banned)&&banned>now())throw new GameError('ACCOUNT_NOT_ALLOWED','此账号不在已确认的内测名单中',403);
    return {id:value.id.toLowerCase(),email:address};
  };
  const tokensFrom=value=>{
    if(!safeToken(value?.access_token)||!safeToken(value?.refresh_token)||!Number.isSafeInteger(value.expires_in)||value.expires_in<1||value.expires_in>7*86400)throw unavailable();
    return {accessToken:value.access_token,refreshToken:value.refresh_token,expiresAt:now()+value.expires_in*1000};
  };
  const ensureActive=(token,session)=>{
    if(sessions.get(token)!==session||now()>=session.until){sessions.delete(token);throw denied();}
  };
  const getUser=async accessToken=>userFrom(await request('/user',{accessToken}));
  return {
    enabled:true,
    async login(address,password){
      address=email(address);
      if(!allowed.has(address)||typeof password!=='string'||!password.length||password.length>1024)throw new GameError('LOGIN_DENIED','邮箱或密码不正确，或账号未获内测资格',401);
      for(const [token,session]of sessions)if(now()>=session.until)sessions.delete(token);
      if(sessions.size>=maxSessions)throw new GameError('AUTH_BUSY','账号会话数量已满，请稍后登录',503);
      const tokens=tokensFrom(await request('/token?grant_type=password',{method:'POST',body:{email:address,password}}));
      const user=await getUser(tokens.accessToken);
      if(user.email!==address)throw denied();
      if(sessions.size>=maxSessions)throw new GameError('AUTH_BUSY','账号会话数量已满，请稍后登录',503);
      // Login responses and user_metadata are never trusted as account identity.
      const token=crypto.randomBytes(32).toString('hex');
      sessions.set(token,{...tokens,user,until:now()+sessionTTL,pending:Promise.resolve()});
      return {ok:true,sessionToken:token,user};
    },
    async authenticate(token){
      if(!opaque(token)||!sessions.has(token))throw denied();
      const session=sessions.get(token);
      // Refresh is serialized per session so rotated refresh tokens are not raced.
      const operation=session.pending.then(async()=>{
        ensureActive(token,session);
        if(session.expiresAt-now()<=30000){
          try{Object.assign(session,tokensFrom(await request('/token?grant_type=refresh_token',{
            method:'POST',body:{refresh_token:session.refreshToken}})));}catch(error){if(error.status===401)sessions.delete(token);throw error;}
        }
        let user;
        try{user=await getUser(session.accessToken);}catch(error){if(error.status===401||error.status===403)sessions.delete(token);throw error;}
        ensureActive(token,session);
        if(user.id!==session.user.id){sessions.delete(token);throw denied();}
        session.user=user;return {user};
      });
      session.pending=operation.catch(()=>{});return operation;
    },
    assertActive(token){const session=sessions.get(token);if(!session)throw denied();ensureActive(token,session);},
    async logout(token,expectedAccountId){
      const session=sessions.get(token);
      if(session&&expectedAccountId!==undefined&&expectedAccountId!==session.user.id)throw new GameError('ACCOUNT_CHANGED','当前账号已切换，请重新登录并核对房间',401);
      sessions.delete(token);
      if(session){
        // Opaque game authorization is revoked immediately even if the provider is down.
        await session.pending;
        await request('/logout?scope=local',{method:'POST',accessToken:session.accessToken});
      }
      return {ok:true};
    },
    close(){sessions.clear();},
  };
}
