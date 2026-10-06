import path from 'node:path';

const required=(env,name)=>{const value=env[name]?.trim();if(!value)throw new Error(`Missing ${name}`);return value;};
const integer=(env,name,fallback,min,max)=>{const text=env[name]?.trim();const value=text?Number(text):fallback;if(!Number.isInteger(value)||value<min||value>max)throw new Error(`Invalid ${name}`);return value;};
const origin=(text,label)=>{let url;try{url=new URL(text);}catch{throw new Error(`Invalid ${label}`);}if(url.protocol!=='https:'||url.username||url.password||url.pathname!=='/'||url.search||url.hash)throw new Error(`${label} must be an HTTPS origin`);return url.origin;};

/** A production launch cannot silently fall back to local JSON or test accounts. */
export function loadCloudConfig(env=process.env,root=process.cwd()) {
  if(env.NODE_TLS_REJECT_UNAUTHORIZED==='0')throw new Error('Verified TLS cannot be disabled');
  const publicOrigin=origin(required(env,'TK_PUBLIC_ORIGIN'),'TK_PUBLIC_ORIGIN');
  const supabaseUrl=origin(required(env,'SUPABASE_URL'),'SUPABASE_URL');
  const publishableKey=required(env,'SUPABASE_PUBLISHABLE_KEY');
  if(!/^sb_publishable_[A-Za-z0-9_-]+$/.test(publishableKey))throw new Error('SUPABASE_PUBLISHABLE_KEY must be a publishable key');
  const connectionString=required(env,'DATABASE_URL');let db;
  try{db=new URL(connectionString);}catch{throw new Error('Invalid DATABASE_URL');}
  if(!['postgres:','postgresql:'].includes(db.protocol)||!db.hostname||!db.username||!db.password)throw new Error('DATABASE_URL requires a Postgres account');
  if(db.port==='6543'||db.searchParams.get('pgbouncer')==='true')throw new Error('DATABASE_URL must use direct or session pooling, not transaction pooling');
  if(['disable','allow','prefer','no-verify'].includes(db.searchParams.get('sslmode')))throw new Error('DATABASE_URL must require verified TLS');
  const allowedEmails=required(env,'TK_ALLOWED_EMAILS').split(',').map(value=>value.trim().toLowerCase());
  if(allowedEmails.length>128||allowedEmails.some(value=>!/^\S+@\S+\.\S+$/.test(value))||new Set(allowedEmails).size!==allowedEmails.length)throw new Error('Invalid TK_ALLOWED_EMAILS');
  const namespace=env.TK_DB_NAMESPACE?.trim()||'three-kingdoms';
  if(!/^[a-z0-9][a-z0-9_-]{0,63}$/.test(namespace))throw new Error('Invalid TK_DB_NAMESPACE');
  const host=env.TK_HOST?.trim()||'127.0.0.1';
  if(!['127.0.0.1','0.0.0.0','::1'].includes(host))throw new Error('Invalid TK_HOST');
  return {publicOrigin,supabaseUrl,publishableKey,connectionString,allowedEmails,namespace,host,
    port:integer(env,'PORT',3080,1,65535),maxRooms:integer(env,'TK_MAX_ROOMS',32,1,1000),
    maxRoomsPerAccount:integer(env,'TK_MAX_ROOMS_PER_ACCOUNT',4,1,32),
    webDir:path.resolve(root,env.TK_WEB_DIR?.trim()||'build/web-online'),
    dataDir:path.resolve(root,env.TK_DATA_DIR?.trim()||'.local/cloud-runtime')};
}
