import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {openLocal} from './start-pvp.mjs';

// Credentials remain in the private rehearsal directory. No token goes to stdout or a URL query.
try {
  const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
  const options={dataDir:path.resolve('.local/shared-pvp'),slot:1,url:'http://127.0.0.1:17342',native:false,godot:''};
  for(let i=2;i<process.argv.length;i++) {
    const key=process.argv[i];if(key==='--native'){options.native=true;continue;}
    const value=process.argv[++i];if(!value)throw new Error('Missing value for '+key);
    if(key==='--data-dir')options.dataDir=path.resolve(value);else if(key==='--slot')options.slot=Number(value);else if(key==='--url')options.url=value;else if(key==='--godot')options.godot=value;else throw new Error('Unknown option '+key);
  }
  const url=new URL(options.url);
  if(!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.protocol!=='http:'||url.username||url.password||url.search||url.hash||url.pathname!=='/')throw new Error('演练入口必须为本机服务地址');
  options.url=url.origin;
  const stored=JSON.parse(await fs.readFile(path.join(options.dataDir,'credentials.json'),'utf8'));
  const actor=stored.actors.find(value=>value.slot===options.slot);if(!actor)throw new Error('请选择账号 1～4');
  const health=await fetch(options.url+'/health',{headers:{Authorization:'Bearer '+actor.token}});
  const payload=await health.json();if(!health.ok||payload.mode!=='shared'||payload.actor?.id!==actor.id||payload.authorityId!==actor.authorityId)throw new Error('服务与演练账号不匹配，请先启动对应共享服务');
  if(options.native) {
    const executable=options.godot||path.resolve(root,'..','ThreeKingdoms.exe');
    const args=options.godot?['--path',root,'--','--api='+options.url]:['--','--api='+options.url];
    const child=spawn(executable,args,{stdio:'inherit',env:{...process.env,TK_BRIDGE_TOKEN:actor.token}});
    child.on('error',()=>{console.error('无法启动桌面客户端，请检查完整解压路径或 --godot');process.exitCode=1;});
  } else openLocal(options.url+'/#pvp-token='+encodeURIComponent(actor.token));
  console.log('已打开 '+actor.name+' · '+(options.native?'桌面端':'网页端'));
} catch(error) {console.error('无法加入演练：'+error.message);process.exitCode=1;}
