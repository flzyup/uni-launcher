#!/usr/bin/env python3
"""Build synthetic media/Widget source and install only on an emulator, never a car."""
from pathlib import Path
import os,subprocess,zipfile
root=Path(__file__).resolve().parents[1]
serial=os.environ.get('UNI_EMULATOR_SERIAL','emulator-5580')
if not serial.startswith('emulator-') or not serial[9:].isdigit():raise SystemExit('Emulator serial required')
def run(*args):subprocess.run([str(x) for x in args],check=True)
check=subprocess.check_output(['adb','-s',serial,'shell','getprop','ro.kernel.qemu'],text=True).strip()
if check!='1':raise SystemExit('Refusing to install on non-emulator')
# SDK / JDK：默认是 Windows 侧的固定路径，本机（macOS）或 CI 用环境变量覆盖。
sdk=Path(os.environ.get('UNI_FIXTURE_SDK','/data/tools/linkco-android/sdk'));t=sdk/'build-tools/36.0.0';j=Path(os.environ.get('UNI_FIXTURE_JDK','/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64/bin'))
# 同一张 AOSP 测试签名证书（全项目只此一张，见 docs/BUILD_SIGNING.md）。
# 夹具装在同一台设备上，证书不一致会和主包互相顶掉。
keystore=Path(os.environ.get('UNI_FIXTURE_KEYSTORE')
              or os.environ.get('UNI_SIGNING_STORE')
              or next((p for p in [root.parent/'android'/'signing'/'uni-debug.keystore',
                                   root.parent/'android'/'uni-debug.keystore',
                                   sdk.parent/'uni-debug.keystore'] if p.is_file()), ''))
if not keystore.is_file():raise SystemExit('找不到 AOSP 测试签名 keystore：设置 UNI_SIGNING_STORE')
android=sdk/'platforms/android-9/android.jar'
src=root/'test-fixture';out=root/'build/fixture';classes=out/'classes';classes.mkdir(parents=True,exist_ok=True)
run(j/'javac','-source','8','-target','8','-Xlint:-options','-encoding','UTF-8','-bootclasspath',android,'-d',classes,*src.rglob('*.java'))
run(j/'java','-cp',sdk/'cmdline-tools/latest/lib/r8.jar','com.android.tools.r8.D8','--min-api','23','--lib',android,'--output',out,*classes.rglob('*.class'))
run(t/'aapt2','compile','--dir',src/'res','-o',out/'res.zip')

# 三个变体，共用同一份 dex，只换包名与类名前缀。
#
# 'netease' 带的是**真实网易云车机版的包名**，桌面按包名查能力表时它能命中，
# 于是「收藏」与「播放模式」两颗按钮都会亮 —— 收藏走 star_action，
# 播放模式走 play_mode_action / get_play_mode_action（见 FixtureActivity）。
# 'player' 是第二个独立会话，用来验证显式选源时不会串到别的音源。
# 'media' 用 ecarx.xsf.mediacenter 这个包名 —— 车机镜像上它是**原厂**媒体中心，
# 所以装到那种设备上时必须跳过，不能拿测试包把原厂的顶掉（见下面的已安装检查）。
VARIANTS=[
    ('media','ecarx.xsf.mediacenter','UNI 模拟器测试源','fixture.apk',
     'Synthetic source installed on {serial} ONLY; package ecarx.xsf.mediacenter is a test fixture, not an OEM APK.'),
    ('player','xyz.i4o.uni.fixture.player','UNI 备用测试播放器','fixture-alternate.apk',
     'Secondary synthetic player installed on {serial} ONLY.'),
    ('netease','com.netease.cloudmusic.iot','UNI 播放模式测试源','fixture-netease.apk',
     'NetEase-named synthetic player installed on {serial} ONLY; package com.netease.cloudmusic.iot is a test fixture, not the OEM APK.'),
]

def installed(pkg):
    """设备上是否已经有这个包名。"""
    out=subprocess.run(['adb','-s',serial,'shell','pm','list','packages',pkg],
                       capture_output=True,text=True).stdout
    return ('package:'+pkg) in out

# 只构建需要的变体：UNI_FIXTURE_VARIANTS=media,player,netease（默认全要）。
want=[v.strip() for v in os.environ.get('UNI_FIXTURE_VARIANTS','media,player,netease').split(',') if v.strip()]
known={v[0] for v in VARIANTS}
for name in want:
    if name not in known:raise SystemExit('未知变体：'+name+'（可选：'+','.join(sorted(known))+'）')

for name,pkg,label,apk,message in VARIANTS:
    if name not in want:continue
    if installed(pkg):
        # 车机镜像上 ecarx.xsf.mediacenter 是原厂媒体中心，别拿测试包顶掉它。
        print('跳过',name,'：设备上已有',pkg,'（不覆盖设备上已有的包）')
        continue
    work=out/name;work.mkdir(exist_ok=True)
    manifest=(src/'AndroidManifest.xml').read_text().replace('package="ecarx.xsf.mediacenter"','package="'+pkg+'"').replace('UNI 模拟器测试源',label)
    for cls in ['FixtureActivity','FixtureMediaService','widget.MediaWidgetProvider1x2']:
        manifest=manifest.replace('android:name=".'+cls+'"','android:name="ecarx.xsf.mediacenter.'+cls+'"')
    (work/'AndroidManifest.xml').write_text(manifest)
    run(t/'aapt2','link','-I',android,'--manifest',work/'AndroidManifest.xml','-R',out/'res.zip','-o',work/'unsigned.apk')
    with zipfile.ZipFile(work/'unsigned.apk','a',zipfile.ZIP_DEFLATED) as z:z.write(out/'classes.dex','classes.dex')
    run(j/'java','-cp',str(t/'lib/apksigner.jar'),'com.android.apksigner.ApkSignerTool','sign','--ks',str(keystore),'--ks-pass','pass:android','--ks-key-alias','uni-debug','--v4-signing-enabled','false','--out',out/apk,work/'unsigned.apk')
    run('adb','-s',serial,'install','-r',out/apk)
    print(message.format(serial=serial))
