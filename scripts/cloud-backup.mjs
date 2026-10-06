import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {readPostgresBackup,restorePostgresBackup,MAX_SNAPSHOT_BYTES} from '../bridge/postgres-room-store.mjs';

export const BACKUP_FORMAT='three-kingdoms-postgres-backup-1';
const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const hash=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
async function resolvedTarget(filename) {
  let ancestor=path.resolve(filename);const missing=[];
  for(;;){try{return path.join(await fs.realpath(ancestor),...missing.reverse());}catch(error){
    if(error.code!=='ENOENT')throw error;const parent=path.dirname(ancestor);if(parent===ancestor)throw error;
    missing.push(path.basename(ancestor));ancestor=parent;
  }}
}
export async function privateBackupOutput(filename,env=process.env,root=ROOT) {
  const output=await resolvedTarget(filename);
  const publicRoots=await Promise.all([path.resolve(root,'build'),path.resolve(root,env.TK_WEB_DIR?.trim()||'build/web-online')].map(resolvedTarget));
  if(publicRoots.some(value=>output===value||output.startsWith(value+path.sep)))throw new Error('Backup cannot be written inside Web or build resources');
  return output;
}
export function encodeBackup(value,now=Date.now()) {
  const body={format:BACKUP_FORMAT,createdAt:now,...value};
  return JSON.stringify({...body,digest:hash(body)})+'\n';
}
export function decodeBackup(text,namespace) {
  if(Buffer.byteLength(text)>MAX_SNAPSHOT_BYTES+1024*1024)throw new Error('Backup exceeds current capacity');
  let value;try{value=JSON.parse(text);}catch{throw new Error('Invalid backup JSON');}
  if(!value||value.format!==BACKUP_FORMAT||value.schema!==1||value.namespace!==namespace||
    !Number.isSafeInteger(value.createdAt)||value.createdAt<0||typeof value.version!=='string'||!/^[1-9][0-9]*$/.test(value.version)||
    typeof value.digest!=='string'||!/^[a-f0-9]{64}$/.test(value.digest))throw new Error('Invalid backup or namespace mismatch');
  const {digest,...body}=value;
  if(hash(body)!==digest)throw new Error('Backup checksum mismatch');
  return value;
}
export async function main(args=process.argv.slice(2),env=process.env) {
  const namespace=env.TK_DB_NAMESPACE?.trim()||'three-kingdoms',connectionString=env.DATABASE_URL;
  if(!connectionString)throw new Error('DATABASE_URL is required');
  if(args.length===2&&args[0]==='--out') {
    const output=await privateBackupOutput(args[1],env);
    const value=await readPostgresBackup({connectionString,namespace,requireTLS:true});
    await fs.mkdir(path.dirname(output),{recursive:true,mode:0o700});
    const file=await fs.open(output,'wx',0o600);
    try{await file.writeFile(encodeBackup(value));await file.sync();}finally{await file.close();}
    console.log(JSON.stringify({event:'backup-written',file:output,namespace,version:value.version}));return;
  }
  if((args.length===2||args.length===3&&args[2]==='--replace')&&args[0]==='--restore') {
    const input=path.resolve(args[1]);const stat=await fs.stat(input);
    if(stat.size>MAX_SNAPSHOT_BYTES+1024*1024)throw new Error('Backup exceeds current capacity');
    const value=decodeBackup(await fs.readFile(input,'utf8'),namespace);
    const result=await restorePostgresBackup({connectionString,namespace,snapshot:value.snapshot,replace:args.length===3,requireTLS:true});
    console.log(JSON.stringify({event:'backup-restored',namespace,version:result.version}));return;
  }
  throw new Error('Use --out FILE or --restore FILE [--replace]');
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try{await main();}catch(error){console.error('Backup operation failed'+(typeof error?.code==='string'&&/^[A-Z_]+$/.test(error.code)?' ('+error.code+')':'')+'. Check private configuration, file checksum, namespace and whether the game server is stopped before restore.');process.exitCode=1;}
}
