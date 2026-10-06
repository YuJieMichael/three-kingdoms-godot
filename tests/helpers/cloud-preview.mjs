import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {startPostgresFixture} from './postgres-fixture.mjs';
import {startFakeSupabase} from './fake-supabase.mjs';
import {createSupabaseAuth} from '../../bridge/supabase-auth.mjs';
import {openPostgresRoomStore} from '../../bridge/postgres-room-store.mjs';
import {startRoomsServer} from '../../bridge/room-server.mjs';

// Test-only launch: fake Auth provider and real temporary local PostgreSQL.
// This file is excluded from production/client bundles and never uses a cloud account.
let db,provider,service,directory;
try {
  const options={port:17344,webDir:path.resolve('build/online/web'),readyFile:null};
  for(let i=2;i<process.argv.length;i+=2){const key=process.argv[i],value=process.argv[i+1];
    if(!value)throw new Error('Missing preview option');
    if(key==='--web-dir')options.webDir=path.resolve(value);else if(key==='--port')options.port=Number(value);
    else if(key==='--ready-file')options.readyFile=path.resolve(value);else throw new Error('Unknown preview option');
  }
  directory=await fs.mkdtemp(path.join(os.tmpdir(),'tk-cloud-preview-'));await fs.chmod(directory,0o700);
  db=await startPostgresFixture();provider=await startFakeSupabase();
  const auth=createSupabaseAuth({url:provider.url,publishableKey:'sb_publishable_local_test_key',
    allowedEmails:['alice@test.invalid','bob@test.invalid'],allowInsecureLocal:true});
  service=await startRoomsServer({dataDir:directory,port:options.port,webDir:options.webDir,
    cloudAccount:{auth,publicOrigin:'http://127.0.0.1:'+options.port,allowInsecureLocal:true},
    storageFactory:({now})=>openPostgresRoomStore({connectionString:db.connectionString,namespace:'cloud-ui-fixture',requireTLS:false,now})});
  if(options.readyFile)await fs.writeFile(options.readyFile,JSON.stringify({url:service.url,pid:process.pid,testOnly:true}),{mode:0o600});
  console.log(JSON.stringify({event:'local-test-only-preview',url:service.url+'/lobby',auth:'fake provider',database:'temporary PostgreSQL'}));
  let stopping=false;
  const stop=async()=>{if(stopping)return;stopping=true;await service.close();await provider.close();await db.close();await fs.rm(directory,{recursive:true,force:true});process.exit(0);};
  process.once('SIGINT',stop);process.once('SIGTERM',stop);
} catch {
  await service?.close().catch(()=>{});await provider?.close().catch(()=>{});await db?.close().catch(()=>{});
  if(directory)await fs.rm(directory,{recursive:true,force:true});console.error('Local fixture preview failed; no cloud project used.');process.exitCode=1;
}
