#!/usr/bin/env python3
"""Real Android installer bounds/touch regression. Only cancels confirmation.
Creates two temporary, explicitly named test packages and removes them afterwards.
Never confirms an installation through UI or touches an owner's app package.
"""
import argparse,json,re,subprocess,tempfile,time,zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
FIXTURE='xyz.i4o.uni.fixture.installpreview'
TARGET=FIXTURE+'.target'
SDK=Path('/data/tools/linkco-android/sdk')
JAVA=Path('/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64/bin')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--serial',required=True);p.add_argument('--out',type=Path,required=True);args=p.parse_args()
    adb=['adb','-s',args.serial];args.out.mkdir(parents=True,exist_ok=True);checks=[];installed=[]
    def call(*a):return subprocess.check_output([str(v) for v in a],timeout=45)
    def sh(*a):return call(*adb,'shell',*a).decode().strip()
    def check(name,passed):
        checks.append({'name':name,'passed':bool(passed)})
        if not passed:raise AssertionError(name)
    for name in [FIXTURE,TARGET]:
        if 'package:' in sh('pm','list','packages',name):raise SystemExit('Refusing existing package '+name)
    def sign(source,target):
        call(JAVA/'java','-jar',SDK/'build-tools/36.0.0/lib/apksigner.jar','sign','--ks',SDK.parent/'uni-debug.keystore',
            '--ks-pass','pass:android','--ks-key-alias','uni-debug','--v4-signing-enabled','false','--out',target,source)
    def dump():
        path='/sdcard/uni-install-preview.xml';sh('uiautomator','dump',path)
        return ET.fromstring(sh('cat',path))
    try:
        with tempfile.TemporaryDirectory(prefix='uni-install-preview-') as temp:
            temp=Path(temp);platform=SDK/'platforms/android-9/android.jar';aapt=SDK/'build-tools/36.0.0/aapt2'
            for version in [1,2]:
                manifest=temp/f'target-{version}.xml'
                manifest.write_text(f'<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{TARGET}" android:versionCode="{version}"><uses-sdk android:minSdkVersion="24" android:targetSdkVersion="28"/><application android:hasCode="false" android:label="UNI 安装验证"/></manifest>')
                call(aapt,'link','-I',platform,'--manifest',manifest,'-o',temp/'target-unsigned.apk')
                sign(temp/'target-unsigned.apk',temp/f'target-{version}.apk')
            classes=temp/'classes';classes.mkdir();assets=temp/'assets';assets.mkdir()
            (assets/'candidate.apk').write_bytes((temp/'target-2.apk').read_bytes())
            source=ROOT/'app/native-tests/test-install-preview'
            call(JAVA/'javac','-source','8','-target','8','-Xlint:-options','-encoding','UTF-8','-bootclasspath',platform,'-d',classes,*source.joinpath('src').rglob('*.java'))
            call(JAVA/'java','-cp',SDK/'cmdline-tools/latest/lib/r8.jar','com.android.tools.r8.D8','--min-api','24','--lib',platform,'--output',temp,*classes.rglob('*.class'))
            call(aapt,'link','-I',platform,'--manifest',source/'AndroidManifest.xml','-A',assets,'-o',temp/'preview-unsigned.apk')
            with zipfile.ZipFile(temp/'preview-unsigned.apk','a',zipfile.ZIP_DEFLATED) as z:z.write(temp/'classes.dex','classes.dex')
            sign(temp/'preview-unsigned.apk',temp/'preview.apk')
            for name,file in [(TARGET,temp/'target-1.apk'),(FIXTURE,temp/'preview.apk')]:
                call(*adb,'install',file);installed.append(name)
            sh('appops','set',FIXTURE,'REQUEST_INSTALL_PACKAGES','allow')
            sh('am','start','-n',FIXTURE+'/.PreviewActivity')
            buttons=None
            for _ in range(12):
                tree=dump();items=list(tree.iter('node'))
                ok=next((n for n in items if n.get('resource-id','').endswith('/ok_button') or n.get('text') in ['安装','Install','INSTALL']),None)
                cancel=next((n for n in items if n.get('resource-id','').endswith('/cancel_button') or n.get('text') in ['取消','Cancel','CANCEL']),None)
                if ok is not None and cancel is not None:buttons=(ok,cancel);break
                time.sleep(.3)
            check('real installer shows update confirmation for disposable target',buttons is not None)
            (args.out/'installer-confirm.png').write_bytes(call(*adb,'exec-out','screencap','-p'))
            (args.out/'installer-windows.txt').write_text(sh('dumpsys','window','windows'))
            for label,node in zip(['install','cancel'],buttons):
                bounds=list(map(int,re.findall(r'\d+',node.get('bounds'))))
                check(label+' button fully above 984px dock edge',bounds[3]<=984 and bounds[3]>bounds[1])
            cancel=buttons[1];l,t,r,b=map(int,re.findall(r'\d+',cancel.get('bounds')));sh('input','tap',str((l+r)//2),str((t+b)//2))
            result=False
            for _ in range(8):
                if any(n.get('text')=='RESULT:0' for n in dump().iter('node')):result=True;break
                time.sleep(.3)
            check('Cancel receives touch and returns RESULT_CANCELED',result)
            check('candidate update was never installed','versionCode=1 ' in sh('dumpsys','package',TARGET))
    finally:
        if installed:
            (args.out/'installer-final.png').write_bytes(call(*adb,'exec-out','screencap','-p'))
            (args.out/'installer-final-windows.txt').write_text(sh('dumpsys','window','windows'))
        for name in reversed(installed):call(*adb,'uninstall',name)
        if installed:sh('am','start','-n','xyz.i4o.uni.launcher/.MainActivity')
        (args.out/'installer-report.json').write_text(json.dumps({'checks':checks,'temporaryPackagesRemoved':installed},ensure_ascii=False,indent=2)+'\n')
    print('PASS',len(checks),'installer confirmation checks; temporary packages removed')

if __name__=='__main__':main()
