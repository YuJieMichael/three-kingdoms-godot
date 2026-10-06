import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadCloudConfig} from './cloud-config.mjs';
import {startRoomsServer} from '../bridge/room-server.mjs';
import {createSupabaseAuth} from '../bridge/supabase-auth.mjs';
import {openPostgresRoomStore} from '../bridge/postgres-room-store.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let service,store;
try {
  if(process.argv.slice(2).some(value=>value!=='--check'))throw new Error('Only --check is supported; load secrets from a private environment file');
  const config=loadCloudConfig(process.env,root);
  await fs.access(path.join(config.webDir,'index.html'));
  const entries=await fs.readdir(config.webDir);
  if(!entries.some(value=>value.endsWith('.pck'))||!entries.some(value=>value.endsWith('.wasm')))throw new Error('TK_WEB_DIR requires a complete Godot Web export');
  if(process.argv.includes('--check')) {
    console.log(JSON.stringify({event:'cloud-config-valid',origin:config.publicOrigin,namespace:config.namespace,storage:'postgres',accounts:'supabase',networkVerified:false}));
  } else {
    const auth=createSupabaseAuth({url:config.supabaseUrl,publishableKey:config.publishableKey,allowedEmails:config.allowedEmails});
    service=await startRoomsServer({host:config.host,port:config.port,dataDir:config.dataDir,webDir:config.webDir,
      lobbyFile:path.join(root,'bridge/cloud-lobby.html'),
      storageFactory:async({now})=>{store=await openPostgresRoomStore({connectionString:config.connectionString,namespace:config.namespace,now,requireTLS:true});return store;},
      cloudAccount:{auth,publicOrigin:config.publicOrigin,limits:{maxRooms:config.maxRooms,maxRoomsPerAccount:config.maxRoomsPerAccount}}});
    console.log(JSON.stringify({event:'cloud-ready',origin:config.publicOrigin,lobby:config.publicOrigin+'/lobby',storage:'postgres',capacity:'1–8'}));
    let stopping=false;
    const stop=async(code=0)=>{if(stopping)return;stopping=true;clearInterval(watchdog);
      const deadline=setTimeout(()=>process.exit(1),25000);deadline.unref();
      await service.close();clearTimeout(deadline);process.exit(code);};
    // Container health status alone does not restart a process. Exit on loss of
    // the dedicated database session so the supervisor can reload committed state.
    const watchdog=setInterval(()=>{if(!store.healthy()){
      console.error('Cloud storage session lost; stopping to reload committed state.');
      stop(1).catch(()=>process.exit(1));
    }},1000);
    process.once('SIGTERM',()=>stop(0));process.once('SIGINT',()=>stop(0));
  }
} catch {
  await service?.close().catch(()=>{});if(!service)await store?.close().catch(()=>{});
  // Database/fetch error text can contain credentials. Keep diagnostics private.
  console.error('Cloud startup failed. Check required configuration, Web export, verified database TLS, migration, and exclusive world lock.');
  process.exitCode=1;
}
