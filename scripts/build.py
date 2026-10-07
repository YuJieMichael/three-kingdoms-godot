#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Reproducible Godot client exports and local rule-service packages."""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.6.0-dev.12'
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
    (package/'试玩说明.txt').write_text(f'山河策 Godot {VERSION}\n\nWindows 客户端：双击 ThreeKingdoms.exe，规则服务与进度会自动启动。请完整解压，不要只复制 exe。\n网页试玩包：双击 StartWeb.cmd，看到服务就绪后在浏览器打开 http://127.0.0.1:17338/ 。\n已有原网页版存档可在“存档”导入 JSON。\n电脑默认快捷键：1–5 切换页面，H 回城，T 打开事务，O 打开存档，K 打开按键设置。地图支持键盘移动与缩放，按键可在设置中重新绑定并保存在本机。Tab、Enter、Esc 保留原生界面的焦点、确认和关闭操作。\n本版大地图采用六类山川林地和城池贴图，名城按真实县郡州都分级，缩放分层，筛选与缩放操作可用，行军方向和实际抵达时间明确。仍为64×64试玩世界，分区不是全国州郡版图，道路不增加规则效果。\n本版城内采用16种写实斜俯视建筑及独立门楼贴图，瓦顶、木架、石基和院落统一材质。贴图等比绘制，空地、0级地基、施工进度和实际地块身份保留。官府与军营1–3/4–7/8–10级有三阶外观，按已完成等级呈现；城墙、南门、官署庭院与主街材质统一。\n本版内城为36格自选建设，电脑6列、手机3列，点空地打开按用途分组的建筑目录，查看费用和工期后确认建设；固定工具栏可定位官府。新建目录提供用途标签与当前可建筛选，同窗查看详情再返回会保留浏览位置；费用与确认按钮固定可见。民房与军营可比较新建和升级的原规则费用、工期与完成后容量变化；军营容量是可排队训练订单数，不是并行训练速度。官署留地不可建设，已有城池和真实地块身份继续兼容。城外田庄改为水渠、田地和山林的可选场景；点选后管理该地块，城务与建设样板可展开。\n本版地图优先：任务栏可收起、选中目标显示详情；资源一行，点击看精确数量、容量与产量。手机底部导航，军情有活动时保持可见，空闲城池可收起并突出施工入口。出征与侦察使用同一战前准备窗口，报价和确认按钮固定可见；深灰铜金界面、连续地形与城池旗帜。\n本版接通城外目标定时侦察：地图或配兵窗口查看军情，先预览粮耗、往返时间、精度和预计斥候损失，再确认派遣。无斥候时在军队训练；行军列表显示各城侦察与返程，原规则不能途中取消。过期情报不显示旧兵力，玩家共享城池侦察尚未开放。\n本版成长路线显示真实缺口和已拥有加速建议；战报分别展示实际入库与补兵、治疗预算。占领黄巾营寨后，可在黄巾史诗的铜钱兑换中用80铜钱兑换1枚县城筹备珊瑚，全存档共限5枚。\n本版事务按成长、经营、军务、物资分组，窄屏保留当前目标；菜单的显示页可启用减少动态效果。战斗分阶段展示移动、攻击与伤亡，操作后显示明确回执。\n本版补齐任务、每日任务、黄巾史诗、官爵珠宝晋升、俸禄、野地画像抓将、将领成长与装备、伤兵俘虏、城防与黄巾来袭、多城运输调遣、城外样板、挂机保留、宝物开箱和商城。\n任务册可切换主线、日常、史诗、官爵、章节和十阶礼包；未达成任务点击前往目标。宝物可以选择目标或装备部位。运输、调遣和建城先预览费用再确认。原规则与存档格式继续兼容。\n新版是独立迁移试玩；原网页和原 GitHub 保持不变。Steamworks 和公网多人服务尚未接入。\n',encoding='utf-8-sig')
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
manifest = {'version':VERSION,'godot':actual,'nodeWindows':'24.21.0','legacyCommit':'c7674df45b9595405e57907524e737e633b0ff63','editionRules':{'countyPreparation':{'costCopper':80,'limitPerSave':5,'unlock':'camp','shared':False}},'runtimeHash':re.search(r'export const runtimeHash="([a-f0-9]+)"', (ROOT/'vendor/legacy/supabase/functions/_shared/game-runtime.mjs').read_text()).group(1),'artifacts':[]}
art_metadata = json.loads((ROOT/'data/city-rts-art-atlas.json').read_text())
manifest['cityArt'] = {'metadataSha256':digest(ROOT/'data/city-rts-art-atlas.json'), 'spriteCount':len(art_metadata.get('regions',{}))+len(art_metadata.get('sprites',[])), 'sources':[{'path':row['texture'],'bytes':(ROOT/row['texture'].removeprefix('res://')).stat().st_size,'sha256':digest(ROOT/row['texture'].removeprefix('res://'))} for row in art_metadata['sources']]}
ground = art_metadata['ground']
ground_path = ROOT/ground['texture'].removeprefix('res://')
manifest['cityArt']['ground'] = {'path':ground['texture'],'bytes':ground_path.stat().st_size,'sha256':digest(ground_path)}
manifest['cityArt']['tierCount'] = sum(len(rows) for rows in art_metadata.get('tiers', {}).values())
manifest['cityArt']['tierSources'] = [{'path':row['texture'],'bytes':(ROOT/row['texture'].removeprefix('res://')).stat().st_size,'sha256':digest(ROOT/row['texture'].removeprefix('res://'))} for row in art_metadata.get('tierSources', [])]
environment = art_metadata.get('environment', {})
if environment:
    environment_path = ROOT/environment['texture'].removeprefix('res://')
    manifest['cityArt']['environment'] = {'path':environment['texture'],'spriteCount':len(environment.get('regions',{})),'bytes':environment_path.stat().st_size,'sha256':digest(environment_path)}
map_metadata = json.loads((ROOT/'data/world-map-art-atlas.json').read_text())
map_source = ROOT/map_metadata['texture'].removeprefix('res://')
manifest['worldMapArt'] = {'metadataSha256':digest(ROOT/'data/world-map-art-atlas.json'), 'spriteCount':len(map_metadata['regions']), 'source':{'path':map_metadata['texture'],'bytes':map_source.stat().st_size,'sha256':digest(map_source)}}
for folder,label in [(windows,'Windows-x64'),(web_package,'Web-preview')]:
    archive = build/('ThreeKingdoms-Godot-v'+VERSION+'-'+label+'.zip')
    zip_folder(folder,archive)
    manifest['artifacts'].append({'file':archive.name,'bytes':archive.stat().st_size,'sha256':digest(archive)})
(build/'build-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
(build/'SHA256SUMS.txt').write_text(''.join(item['sha256']+'  '+item['file']+'\n' for item in manifest['artifacts']))
print(json.dumps(manifest,ensure_ascii=False,indent=2))
