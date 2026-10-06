#!/usr/bin/env python3
"""Reproducible Godot client exports and local rule-service packages."""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.6.0-dev.1'
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
    for name in ('bridge', 'vendor/legacy', 'vendor/shared'):
        shutil.copytree(ROOT / name, destination / name, dirs_exist_ok=True)
    (destination/'scripts').mkdir(exist_ok=True)
    for name in ('start-pvp.mjs','join-pvp.mjs','start-rooms.mjs'):
        shutil.copy2(ROOT/'scripts'/name,destination/'scripts'/name)

def notices(destination):
    folder = destination / 'licenses'; folder.mkdir(exist_ok=True)
    for source in [ROOT/'docs/GODOT-LICENSE.txt',ROOT/'docs/GODOT-COPYRIGHT.txt',ROOT/'assets/fonts/OFL.txt']:
        if source.exists(): shutil.copy2(source, folder/source.name)
    for source in (ROOT/'docs/licenses').glob('*.txt'):
        shutil.copy2(source, folder/source.name)
    shutil.copy2(ROOT/'THIRD_PARTY_NOTICES.md',destination/'THIRD_PARTY_NOTICES.md')

def zip_folder(folder, target):
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for file in sorted(folder.rglob('*')):
            if file.is_file(): archive.write(file, file.relative_to(folder))

parser = argparse.ArgumentParser()
parser.add_argument('--godot', default=os.environ.get('GODOT_BIN','godot'))
parser.add_argument('--node-win-zip', type=Path, required=True)
parser.add_argument('--skip-export', action='store_true')
parser.add_argument('--output-dir', type=Path, default=ROOT/'build')
args = parser.parse_args()
actual = subprocess.check_output([args.godot,'--version'], text=True).strip()
if not actual.startswith(GODOT_VERSION+'.stable'): raise SystemExit('Requires Godot '+GODOT_VERSION+' stable')
if digest(args.node_win_zip) != NODE_WINDOWS_SHA256: raise SystemExit('Node Windows archive checksum mismatch')
build = args.output_dir.resolve(); build.mkdir(exist_ok=True)
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
    (package/'试玩说明.txt').write_text(f'山河策 Godot {VERSION}\n\nWindows 客户端：双击 ThreeKingdoms.exe，规则服务与进度会自动启动。请完整解压，不要只复制 exe。\n网页试玩包：双击 StartWeb.cmd，看到服务就绪后在浏览器打开 http://127.0.0.1:17338/ 。\n已有原网页版存档可在“存档”导入 JSON。\n电脑默认快捷键：1–5 切换页面，H 回城，T 打开事务，O 打开存档，K 打开按键设置。地图支持键盘移动与缩放，按键可在设置中重新绑定并保存在本机。Tab、Enter、Esc 保留原生界面的焦点、确认和关闭操作。\n市场交易、城守与税率管理、客栈招募的费用和收益仍由原规则结算。\n新版是独立迁移试玩；原网页和原 GitHub 保持不变。Steamworks 和公网多人服务尚未接入。\n',encoding='utf-8-sig')
(web_package/'StartWeb.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\necho Open http://127.0.0.1:17338/ after the service is ready.\r\nruntime\\node.exe rule-service\\bridge\\server.mjs --port 17338 --data-dir "%LOCALAPPDATA%\\ThreeKingdomsGodot\\Web" --web-dir web\r\n',encoding='ascii')
(web_package/'start-web.sh').write_text('#!/bin/sh\nset -eu\ncd "$(dirname "$0")"\nnode rule-service/bridge/server.mjs --port 17338 --data-dir "${XDG_DATA_HOME:-$HOME/.local/share}/three-kingdoms-godot-web" --web-dir web\n')
(web_package/'start-web.sh').chmod(0o755)
for package in [windows,web_package]:
    if package == windows:
        (package/'StartPvP.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\necho Keep this window open. Then run PlayPvP1.cmd through PlayPvP4.cmd.\r\nruntime\\node.exe rule-service\\bridge\\shared-server.mjs --port 17342 --data-dir "%LOCALAPPDATA%\\ThreeKingdomsGodot\\SharedPvP"\r\n',encoding='ascii')
    else:
        (package/'StartPvP.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\nruntime\\node.exe rule-service\\scripts\\start-pvp.mjs --port 17342 --data-dir "%LOCALAPPDATA%\\ThreeKingdomsGodot\\SharedPvPWeb" --web-dir web\r\n',encoding='ascii')
        (package/'start-pvp.sh').write_text('#!/bin/sh\nset -eu\ncd "$(dirname "$0")"\nnode rule-service/scripts/start-pvp.mjs --port 17342 --data-dir "${XDG_DATA_HOME:-$HOME/.local/share}/three-kingdoms-godot-shared-pvp" --web-dir web\n')
        (package/'start-pvp.sh').chmod(0o755)
    for slot in range(1,5):
        if package == windows:
            (package/f'PlayPvP{slot}.cmd').write_text(f'@echo off\r\ncd /d "%~dp0"\r\nruntime\\node.exe rule-service\\scripts\\join-pvp.mjs --native --slot {slot} --data-dir "%LOCALAPPDATA%\\ThreeKingdomsGodot\\SharedPvP"\r\n',encoding='ascii')
    (package/'共享演练说明.txt').write_text('共享攻防演练（本机四账号）\n\n先启动 StartPvP.cmd，并保持服务窗口运行。Windows 包再分别打开 PlayPvP1.cmd～PlayPvP4.cmd；网页包从自动打开的本地邀请页面选择账号。\n账号 1、2 同盟，账号 3、4 同盟。兵力和战争状态为虚构演练预置，不是正式新手礼包。\n先从账号 4 向账号 3 派遣援军，再由账号 1 掠夺账号 3；抵达后服务器自动结算，返程后物资入库。可在共享战争和战报查看结果。\n四份共享进度各自保存，私人进度保持独立。共享世界不能导入私人存档。\n服务器只接受本机连接；跨电脑账号、公网服务、Steamworks 和百人负载尚未接入。\n',encoding='utf-8-sig')
    if package == windows:
        (package/'StartRooms.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\necho Keep this window open. Then run PlayRooms.cmd.\r\nruntime\\node.exe rule-service\\scripts\\start-rooms.mjs --native-only --port 17343 --data-dir "%LOCALAPPDATA%\\ThreeKingdomsGodot\\Rooms"\r\n',encoding='ascii')
        (package/'PlayRooms.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\nThreeKingdoms.exe -- --lobby=http://127.0.0.1:17343\r\n',encoding='ascii')
    else:
        (package/'StartRooms.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\nruntime\\node.exe rule-service\\scripts\\start-rooms.mjs --port 17343 --data-dir "%LOCALAPPDATA%\\ThreeKingdomsGodot\\RoomsWeb" --web-dir web\r\n',encoding='ascii')
        (package/'start-rooms.sh').write_text('#!/bin/sh\nset -eu\ncd "$(dirname "$0")"\nnode rule-service/scripts/start-rooms.mjs --port 17343 --data-dir "${XDG_DATA_HOME:-$HOME/.local/share}/three-kingdoms-godot-rooms" --web-dir web\n')
        (package/'start-rooms.sh').chmod(0o755)
    (package/'房间试玩说明.txt').write_text('山河策 1–8人房间演练\n\nWindows 桌面包：先运行 StartRooms.cmd 并保持窗口开启，再运行 PlayRooms.cmd 打开联机大厅。\n网页包：运行 StartRooms.cmd / start-rooms.sh，在自动打开的大厅创建或加入房间。\n创建时选择人数上限1–8。邀请码只能申请空席位；自己的恢复密钥才可回到已有城池，请自行保存。未确认请求请保持窗口开启并使用原请求重试；关闭或刷新会丢失本次重试信息。\n每位成员使用同样的备战资源与兵力，加入时按席位交替分入青、赤两盟，后续以当前游戏联盟关系为准。抵达自动交战，返程后物资入库。\n房间、四账号演练与私人试玩各有独立存档，不要将已有进度目录用于另一种启动入口。\n当前房间服务仅接受本机连接，尚未部署外网账号、跨电脑服务或Steamworks。\n',encoding='utf-8-sig')
manifest = {'version':VERSION,'godot':actual,'nodeWindows':'24.21.0','legacyCommit':'c7674df45b9595405e57907524e737e633b0ff63','runtimeHash':re.search(r'export const runtimeHash="([a-f0-9]+)"', (ROOT/'vendor/legacy/supabase/functions/_shared/game-runtime.mjs').read_text()).group(1),'artifacts':[]}
for folder,label in [(windows,'Windows-x64'),(web_package,'Web-preview')]:
    archive = build/('ThreeKingdoms-Godot-v'+VERSION+'-'+label+'.zip')
    zip_folder(folder,archive)
    manifest['artifacts'].append({'file':archive.name,'bytes':archive.stat().st_size,'sha256':digest(archive)})
(build/'build-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(build/'SHA256SUMS.txt').write_text(''.join(item['sha256']+'  '+item['file']+'\n' for item in manifest['artifacts']))
print(json.dumps(manifest,ensure_ascii=False,indent=2))
