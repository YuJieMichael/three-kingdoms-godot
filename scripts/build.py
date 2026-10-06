#!/usr/bin/env python3
"""Reproducible Godot client exports and local rule-service packages."""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.2.0'
GODOT_VERSION = '4.7.2'
NODE_WINDOWS_SHA256 = '158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541'

def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''): value.update(block)
    return value.hexdigest()

def command(args, log):
    run = subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    log.write_text(run.stdout)
    if run.returncode or re.search(r'(^|\n)(SCRIPT ERROR:|ERROR:)', run.stdout):
        print(run.stdout[-8000:]); raise SystemExit('Godot build failed; see ' + str(log))

def service(destination):
    for name in ('bridge', 'vendor/legacy'):
        shutil.copytree(ROOT / name, destination / name, dirs_exist_ok=True)

def notices(destination):
    folder = destination / 'licenses'; folder.mkdir(exist_ok=True)
    for source in [ROOT/'docs/GODOT-LICENSE.txt',ROOT/'docs/GODOT-COPYRIGHT.txt',ROOT/'assets/fonts/OFL.txt']:
        if source.exists(): shutil.copy2(source, folder/source.name)
    shutil.copy2(ROOT/'THIRD_PARTY_NOTICES.md',destination/'THIRD_PARTY_NOTICES.md')

def zip_folder(folder, target):
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for file in sorted(folder.rglob('*')):
            if file.is_file(): archive.write(file, file.relative_to(folder))

parser = argparse.ArgumentParser()
parser.add_argument('--godot', default=os.environ.get('GODOT_BIN','godot'))
parser.add_argument('--node-win-zip', type=Path, required=True)
parser.add_argument('--skip-export', action='store_true')
args = parser.parse_args()
actual = subprocess.check_output([args.godot,'--version'], text=True).strip()
if not actual.startswith(GODOT_VERSION+'.stable'): raise SystemExit('Requires Godot '+GODOT_VERSION+' stable')
if digest(args.node_win_zip) != NODE_WINDOWS_SHA256: raise SystemExit('Node Windows archive checksum mismatch')
build = ROOT/'build'; build.mkdir(exist_ok=True)
(build/'.gdignore').touch()
windows = build/'windows'; web = build/'web'
windows.mkdir(exist_ok=True); web.mkdir(exist_ok=True)
if not args.skip_export:
    command([args.godot,'--headless','--path',str(ROOT),'--editor','--import'],build/'import.log')
    command([args.godot,'--headless','--path',str(ROOT),'--export-release','Windows Desktop',str(windows/'ThreeKingdoms.exe')],build/'windows-export.log')
    command([args.godot,'--headless','--path',str(ROOT),'--export-release','Web',str(web/'index.html')],build/'web-export.log')
if (windows/'ThreeKingdoms.exe').read_bytes()[:2] != b'MZ': raise SystemExit('Windows PE executable missing')
if not (windows/'ThreeKingdoms.pck').exists() or not list(web.glob('*.wasm')): raise SystemExit('Export resources missing')
web_package = build/'web-package'; web_package.mkdir(exist_ok=True)
shutil.copytree(web,web_package/'web',dirs_exist_ok=True)
for package in [windows,web_package]:
    service(package/'rule-service'); notices(package)
    runtime = package/'runtime'; runtime.mkdir(exist_ok=True)
    with zipfile.ZipFile(args.node_win_zip) as archive:
        for name in ['node.exe','LICENSE']:
            match = next(key for key in archive.namelist() if key.endswith('/'+name))
            (runtime/name).write_bytes(archive.read(match))
    (package/'试玩说明.txt').write_text(f'三国城志 Godot {VERSION}\n\nWindows 客户端：双击 ThreeKingdoms.exe，规则服务与进度会自动启动。请完整解压，不要只复制 exe。\n网页试玩包：双击 StartWeb.cmd，看到服务就绪后在浏览器打开 http://127.0.0.1:17338/ 。\n已有原网页版存档可在“存档”导入 JSON。\n城池事务新增市场交易、城守与税率管理、客栈招募；费用和收益仍由原规则结算。\n新版是独立迁移试玩；原网页和原 GitHub 保持不变。Steamworks 和公网多人服务尚未接入。\n',encoding='utf-8-sig')
(web_package/'StartWeb.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\necho Open http://127.0.0.1:17338/ after the service is ready.\r\nruntime\\node.exe rule-service\\bridge\\server.mjs --port 17338 --data-dir "%LOCALAPPDATA%\\ThreeKingdomsGodot\\Web" --web-dir web\r\n',encoding='ascii')
(web_package/'start-web.sh').write_text('#!/bin/sh\nset -eu\ncd "$(dirname "$0")"\nnode rule-service/bridge/server.mjs --port 17338 --data-dir "${XDG_DATA_HOME:-$HOME/.local/share}/three-kingdoms-godot-web" --web-dir web\n')
(web_package/'start-web.sh').chmod(0o755)
manifest = {'version':VERSION,'godot':actual,'nodeWindows':'24.21.0','legacyCommit':'c7674df45b9595405e57907524e737e633b0ff63','runtimeHash':re.search(r'export const runtimeHash="([a-f0-9]+)"', (ROOT/'vendor/legacy/supabase/functions/_shared/game-runtime.mjs').read_text()).group(1),'artifacts':[]}
for folder,label in [(windows,'Windows-x64'),(web_package,'Web-preview')]:
    archive = build/('ThreeKingdoms-Godot-v'+VERSION+'-'+label+'.zip')
    zip_folder(folder,archive)
    manifest['artifacts'].append({'file':archive.name,'bytes':archive.stat().st_size,'sha256':digest(archive)})
(build/'build-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(build/'SHA256SUMS.txt').write_text(''.join(item['sha256']+'  '+item['file']+'\n' for item in manifest['artifacts']))
print(json.dumps(manifest,ensure_ascii=False,indent=2))
