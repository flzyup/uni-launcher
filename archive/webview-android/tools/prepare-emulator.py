#!/usr/bin/env python3
"""Prepare an isolated API 28 AVD from pinned Google archives, without starting it."""
import argparse, concurrent.futures, hashlib, shutil, urllib.request, zipfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path('/data/tools/linkco-android'));args=p.parse_args()
root=args.root.resolve();downloads=root/'downloads';downloads.mkdir(parents=True,exist_ok=True)
items=[
 ('https://dl.google.com/android/repository/emulator-linux_x64-16428233.zip','emulator.zip','cd7362ea55dfb86a418958138dc396e74165dd01',root/'sdk'),
 ('https://dl.google.com/android/repository/sys-img/android/x86_64-28_r04.zip','android28.zip','d47a85c8f4e9fd57df97814ad8884eeb0f3a0ef0',root/'sdk/system-images/android-28/default'),
 ('https://dl.google.com/android/repository/platform-28_r06.zip','platform28.zip','9a4e52b1d55bd2e24216b150aafae2503d3efba6',root/'sdk/platforms')]
def get(item):
    url,name,checksum,out=item;archive=downloads/name
    if not archive.exists():urllib.request.urlretrieve(url,archive)
    if hashlib.sha1(archive.read_bytes()).hexdigest()!=checksum:raise RuntimeError(name+' checksum mismatch')
    with zipfile.ZipFile(archive) as z:
        z.extractall(out)
        for f in z.infolist():
            mode=f.external_attr>>16
            if mode:(out/f.filename).chmod(mode)
    print(name,'verified',flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:list(executor.map(get,items))
adb=shutil.which('adb')
if not adb:raise SystemExit('System adb required')
platform=root/'sdk/platform-tools';platform.mkdir(exist_ok=True)
if not (platform/'adb').exists():(platform/'adb').symlink_to(adb)
avd=root/'avd/uni-api28.avd';avd.mkdir(parents=True,exist_ok=True)
(root/'avd/uni-api28.ini').write_text('avd.ini.encoding=UTF-8\npath='+str(avd)+'\ntarget=android-28\n')
config={'AvdId':'uni-api28','abi.type':'x86_64','avd.ini.displayname':'UNI Android 9','avd.ini.encoding':'UTF-8','disk.dataPartition.size':'2G',
 'hw.cpu.arch':'x86_64','hw.cpu.ncore':'4','hw.gpu.enabled':'yes','hw.gpu.mode':'swiftshader_indirect','hw.initialOrientation':'landscape','hw.keyboard':'yes',
 'hw.lcd.density':'160','hw.lcd.height':'1080','hw.lcd.width':'1920','hw.mainKeys':'no','hw.ramSize':'2048','hw.sdCard':'no','hw.audioInput':'no','hw.audioOutput':'no',
 'image.sysdir.1':str(root/'sdk/system-images/android-28/default/x86_64')+'/','showDeviceFrame':'no','skin.dynamic':'yes','skin.name':'1920x1080','skin.path':'_no_skin','vm.heapSize':'256'}
(avd/'config.ini').write_text(''.join(k+'='+v+'\n' for k,v in config.items()))
print('AVD ready at',avd)
