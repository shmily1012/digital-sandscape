"""Build a local Windows engine-and-project bundle; no tests or app launch."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[1]
engine=ROOT/'.tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe'
console=engine.with_name('Godot_v4.7.2-stable_win64_console.exe')
env=os.environ.copy()
for key,folder in [('APPDATA','roaming'),('LOCALAPPDATA','local')]:
    path=ROOT/'.tools/runtime'/folder
    path.mkdir(parents=True,exist_ok=True);env[key]=str(path)
subprocess.run([str(console),'--headless','--path',str(ROOT),'--script','res://tools/package_licenses.gd'],cwd=ROOT,env=env,check=True)
name='Digital-Sandscape-Windows-Prototype-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
destination=ROOT/'dist'/name
destination.mkdir(parents=True,exist_ok=False)
(destination/'engine').mkdir();(destination/'app').mkdir();(destination/'licenses').mkdir()
shutil.copy2(engine,destination/'engine/Godot.exe')
for name in ('project.godot','sandscape.tscn','main.tscn'):
    shutil.copy2(ROOT/name,destination/'app'/name)
for folder in ('src','shaders'):
    for source in (ROOT/folder).rglob('*'):
        if source.is_file() and source.suffix in ('.gd','.gdshader','.glsl','.uid'):
            target=destination/'app'/source.relative_to(ROOT)
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
for source in (ROOT/'.tools/package-licenses').iterdir():
    if source.is_file():shutil.copy2(source,destination/'licenses'/source.name)
launcher=r'''@echo off
setlocal
cd /d "%~dp0"
set "APPDATA=%~dp0user-data\roaming"
set "LOCALAPPDATA=%~dp0user-data\local"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
if not exist "%~dp0logs" mkdir "%~dp0logs"
start "" "%~dp0engine\Godot.exe" --path "%~dp0app" --rendering-method mobile --rendering-driver vulkan --log-file "%~dp0logs\sandscape.log"
'''
(destination/'Start Digital Sandscape.cmd').write_text(launcher,encoding='ascii')
(destination/'README.txt').write_text('''Digital Sandscape — Windows 开发原型

解压到可写文件夹，双击 Start Digital Sandscape.cmd。无需Python或另装Godot。
鼠标拖动/滑块旋转，空格暂停，Ctrl+S保存。
A开关定时自动翻转，M开关慢速模式；手动旋转退出自动模式。启动默认为手动。
F10切换无边框摆件，右键拖动窗口，F9置顶，Esc恢复边框（未运行验证）。正常退出及120秒周期也会保存。
存档放在本文件夹user-data内，日志在logs内。移动整个文件夹可保留作品。
请勿直接在压缩包内部运行。

此包包含Godot标准引擎和项目源码，不是已签名的正式发行导出。
按用户要求未运行新的测试或启动验证。GPU需支持Vulkan compute。
已知缺陷：气泡/沙帽可能滞留，自然沙诱导分裂未实现，视觉仍粗糙。
macOS、动态壁纸、屏保尚未交付。引擎许可证及第三方声明见licenses。
''',encoding='utf-8-sig')
manifest=[]
for source in sorted(destination.rglob('*')):
    if source.is_file():
        manifest.append({'path':source.relative_to(destination).as_posix(),'bytes':source.stat().st_size,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
(destination/'MANIFEST.json').write_text(json.dumps({'runtime_validation':'not run at user request','files':manifest},ensure_ascii=False,indent=2),encoding='utf-8')
archive=destination.with_suffix('.zip')
with zipfile.ZipFile(archive,'x',zipfile.ZIP_DEFLATED,compresslevel=6) as bundle:
    for source in sorted(destination.rglob('*')):
        if source.is_file():bundle.write(source,source.relative_to(destination.parent))
receipt={'folder':str(destination),'archive':str(archive),'archive_bytes':archive.stat().st_size,'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'file_count':len(manifest)+1,'tests_run':False,'application_launched':False}
(ROOT/'reports/PORTABLE_DELIVERY.json').write_text(json.dumps(receipt,indent=2),encoding='utf-8')
print(json.dumps(receipt,indent=2))
