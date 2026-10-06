import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {spawn} from 'node:child_process';
import {startSharedBridge} from '../bridge/shared-server.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const escape=value=>String(value).replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
/** Invitations are private local files, never served from the web resource root. */
export async function writeInvitations(service) {
  const filename=path.join(service.dataDir,'join-world.html');
  const links=service.credentials.map(actor=>`<a href="${escape(service.url+'/#pvp-token='+encodeURIComponent(actor.token))}" target="_blank" rel="noopener noreferrer">${escape(actor.name)}<small>账号 ${actor.slot} · 独立进度</small></a>`).join('');
  await fs.writeFile(filename,`<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="referrer" content="no-referrer"><title>山河策 · 共享攻防演练</title><style>body{background:#142323;color:#e1dfcd;font:18px system-ui;max-width:720px;margin:48px auto;padding:20px}h1{color:#dec080}main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}a{display:block;color:#ead49e;border:1px solid #827754;border-radius:10px;padding:24px;text-decoration:none;background:#263633}small{display:block;color:#a8bfba;font-size:14px;margin-top:8px}p{line-height:1.7}@media(max-width:460px){main{grid-template-columns:1fr}}</style><h1>共享攻防演练</h1><p>四座城、两组联盟。每个账号各有兵力与进度，抵达自动交战，返程后物资入库。演练已准备兵力和战争状态。</p><main>${links}</main><p>账号 1、2 同盟，账号 3、4 同盟。建议先用账号 4 向账号 3 派援军，再用账号 1 掠夺账号 3。页面里的邀请仅供本机演练；关闭服务后可通过同一启动入口恢复进度。</p></html>`,{mode:0o600});
  await fs.chmod(filename,0o600);
  return filename;
}

export function openLocal(target) {
  const command=process.platform==='win32'?'explorer.exe':process.platform==='darwin'?'open':'xdg-open';
  const child=spawn(command,[target],{stdio:'ignore',detached:true});
  child.on('error',()=>{});child.unref();
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  let service;
  try {
    const options={port:17342,dataDir:path.resolve('.local/shared-pvp'),webDir:path.join(root,'build/web')};
    let open=true;
    for(let i=2;i<process.argv.length;i++) {
      const key=process.argv[i];if(key==='--no-open'){open=false;continue;}
      const value=process.argv[++i];if(!value)throw new Error('Missing value for '+key);
      if(key==='--port')options.port=Number(value);else if(key==='--data-dir')options.dataDir=path.resolve(value);else if(key==='--web-dir')options.webDir=path.resolve(value);else if(key==='--ready-file')options.readyFile=path.resolve(value);else throw new Error('Unknown option '+key);
    }
    service=await startSharedBridge(options);
    const invitations=await writeInvitations(service);
    console.log(JSON.stringify({event:'shared-ready',url:service.url,players:4,invitations,mode:'local-rehearsal'}));
    if(open)openLocal(process.platform==='win32'?invitations:pathToFileURL(invitations).href);
    const stop=async()=>{await service.close();process.exit(0);};
    process.once('SIGINT',stop);process.once('SIGTERM',stop);
  } catch(error) {await service?.close();console.error('共享演练未启动：'+error.message);process.exitCode=1;}
}
