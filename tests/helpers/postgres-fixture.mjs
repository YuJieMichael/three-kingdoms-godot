import EmbeddedPostgres from 'embedded-postgres';
import {Client} from 'pg';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import {fileURLToPath} from 'node:url';

/** Real temporary PostgreSQL 17.10, TCP protocol and private local data only. */
export async function startPostgresFixture() {
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'tk-postgres-'));await fs.chmod(directory,0o700);
  const socket=net.createServer();await new Promise(resolve=>socket.listen(0,'127.0.0.1',resolve));
  const port=socket.address().port;await new Promise(resolve=>socket.close(resolve));
  const password=crypto.randomBytes(32).toString('hex');
  const cluster=new EmbeddedPostgres({databaseDir:path.join(directory,'db'),port,user:'postgres',password,
    persistent:false,postgresFlags:['-h','127.0.0.1',...(process.platform==='win32'?[]:['-k',directory])],onLog:()=>{},onError:()=>{}});
  const connectionString=`postgresql://postgres:${password}@127.0.0.1:${port}/postgres`;
  let db,closed=false;
  const close=async()=>{if(closed)return;closed=true;await db?.end().catch(()=>{});await cluster.stop();await fs.rm(directory,{recursive:true,force:true});};
  try{
    await cluster.initialise();await cluster.start();db=new Client({connectionString});
    // EmbeddedPostgres also handles process shutdown signals. The fixture's
    // setup session may therefore see its server stop before our async cleanup.
    // Queries still reject; production store sessions keep their own fail guard.
    db.on('error',()=>{});await db.connect();
    await db.query('create role anon;create role authenticated');
    const migrations=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../supabase/migrations');
    const migration=(await fs.readdir(migrations)).find(name=>name.endsWith('_private_room_state.sql'));
    await db.query(await fs.readFile(path.join(migrations,migration),'utf8'));
    return {connectionString,db,close};
  }catch(error){await close();throw error;}
}
