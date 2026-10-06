#!/usr/bin/env python3
"""Build a server deployment bundle without player data, secrets, or dev binaries."""
import argparse,hashlib,json,shutil,zipfile,tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--web-dir',type=Path,required=True)
parser.add_argument('--output-dir',type=Path,default=ROOT/'build/cloud')
args=parser.parse_args()
source=args.web_dir.resolve()
if not (source/'index.html').is_file() or not list(source.glob('*.pck')) or not list(source.glob('*.wasm')):
    raise SystemExit('A complete Godot Web export is required')
target=args.output_dir.resolve();target.mkdir(parents=True,exist_ok=True)
stage=Path(tempfile.mkdtemp(prefix='server-',dir=target))
allowed={'.html','.js','.wasm','.pck','.png','.svg','.ico','.webmanifest','.json','.css','.woff','.woff2','.ttf'}
web=stage/'build/web-online';web.mkdir(parents=True,exist_ok=True)
for item in source.iterdir():
    if item.is_file() and item.name.startswith(('index.','favicon.')) and item.suffix.lower() in allowed:
        shutil.copy2(item,web/item.name)
for name in ['bridge','vendor/legacy','vendor/shared']:
    shutil.copytree(ROOT/name,stage/name,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.*','*.env','*.tmp','node_modules'))
for name in ['scripts/start-cloud.mjs','scripts/cloud-config.mjs','scripts/cloud-backup.mjs','package.json','package-lock.json',
             'deploy/Dockerfile','deploy/Caddyfile','deploy/three-kingdoms.service','deploy/cloud.env.example',
             'docs/ONLINE-SERVICE.zh.md','THIRD_PARTY_NOTICES.md']:
    item=ROOT/name
    if not item.is_file(): raise SystemExit('Required deployment file missing: '+name)
    dest=stage/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(item,dest)
for item in (ROOT/'supabase/migrations').glob('*.sql'):
    dest=stage/'supabase/migrations'/item.name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(item,dest)
for item in (ROOT/'docs/licenses').glob('*.txt'):
    dest=stage/'docs/licenses'/item.name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(item,dest)
version=json.loads((ROOT/'package.json').read_text())['version']
archive=target/f'ThreeKingdoms-Server-v{version}.zip'
names=[]
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for file in sorted(stage.rglob('*')):
        if not file.is_file(): continue
        name=str(file.relative_to(stage))
        if any(part in ['node_modules','.local','.git','runtime','tools'] for part in file.relative_to(stage).parts) or file.name in ['rooms.json','credentials.json','shared-world.json'] or file.suffix=='.env':
            raise SystemExit('Private/development file in deployment bundle: '+name)
        z.write(file,name);names.append(name)
manifest={'version':version,'file':archive.name,'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
          'files':names,'deployment':'not deployed','requires':['Node 24','npm ci --omit=dev --ignore-scripts','dedicated Supabase Auth/Postgres','HTTPS proxy']}
(target/'server-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
shutil.rmtree(stage)
print(json.dumps({k:v for k,v in manifest.items() if k!='files'},ensure_ascii=False,indent=2))
