import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {startRoomsServer} from '../bridge/room-server.mjs';
import {openLocal} from './start-pvp.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let service;
try {
  const options={port:17343,dataDir:path.resolve('.local/rooms'),webDir:path.join(root,'build/web')};
  let open=true;
  for(let i=2;i<process.argv.length;i++) {
    const key=process.argv[i];
    if(key==='--no-open'){open=false;continue;}
    if(key==='--native-only'){options.webDir=null;open=false;continue;}
    const value=process.argv[++i];if(!value)throw new Error('Missing value for '+key);
    if(key==='--port')options.port=Number(value);
    else if(key==='--data-dir')options.dataDir=path.resolve(value);
    else if(key==='--web-dir')options.webDir=path.resolve(value);
    else if(key==='--ready-file')options.readyFile=path.resolve(value);
    else throw new Error('Unknown option '+key);
  }
  service=await startRoomsServer(options);
  console.log(JSON.stringify({event:'rooms-ready',url:service.url,lobby:service.url+'/lobby',capacity:'1–8',mode:'local-room-rehearsal'}));
  if(open)openLocal(service.url+'/lobby');
  let stopping=false;
  const stop=async()=>{if(stopping)return;stopping=true;await service.close();process.exit(0);};
  process.once('SIGINT',stop);process.once('SIGTERM',stop);
} catch(error) {
  await service?.close();console.error('房间服务未启动：'+error.message);process.exitCode=1;
}
