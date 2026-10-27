#!/usr/bin/env python3
"""Validate FFT math; optionally build an audible output fixture on an emulator."""
import argparse
import subprocess
import tempfile
import zipfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
sdk = Path('/data/tools/linkco-android/sdk')
java = Path('/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64/bin')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--install-fixture', action='store_true')
parser.add_argument('--serial', default='emulator-5580')
args = parser.parse_args()
def run(*command):
    subprocess.run([str(x) for x in command], check=True)
with tempfile.TemporaryDirectory(prefix='uni-spectrum-test-') as temp:
    out = Path(temp)
    test = out / 'SpectrumBandsTest.java'
    test.write_text('''import xyz.i4o.uni.launcher.audio.SpectrumBands;
public final class SpectrumBandsTest {
 public static void main(String[] args) {
  byte[] fft=new byte[512];
  for(double v:SpectrumBands.decode(fft,48000000))if(v!=0)throw new AssertionError("silence");
  fft[0]=127;fft[1]=127;
  for(double v:SpectrumBands.decode(fft,48000000))if(v!=0)throw new AssertionError("DC/Nyquist must not leak");
  fft[20]=100; // bin 10 at 937.5 Hz
  double[] bands=SpectrumBands.decode(fft,48000000);
  int count=0;
  for(int i=0;i<bands.length;i++){
   if(!Double.isFinite(bands[i])||bands[i]<0||bands[i]>1)throw new AssertionError("bounds");
   if(bands[i]>0){count++;if(i<10||i>13)throw new AssertionError("frequency mapping "+i);}
  }
  if(count==0)throw new AssertionError("missing tone");
  if(SpectrumBands.decode(null,0).length!=24)throw new AssertionError("fixed packet");
  System.out.println("SpectrumBands: silence, DC, log-frequency, bounds passed");
 }
}''')
    run(java/'javac', '-d', out, root/'app/android/app/src/main/java/xyz/i4o/uni/launcher/audio/SpectrumBands.java', test)
    run(java/'java', '-cp', out, 'SpectrumBandsTest')
if args.install_fixture:
    if not args.serial.startswith('emulator-') or not args.serial[9:].isdigit():
        parser.error('Emulator serial required')
    adb=['adb','-s',args.serial]
    if subprocess.check_output(adb+['shell','getprop','ro.kernel.qemu'],text=True).strip()!='1':
        raise SystemExit('Refusing physical device')
    out=root/'app/native-tests/build/spectrum-fixture'
    classes=out/'classes';classes.mkdir(parents=True,exist_ok=True)
    android=sdk/'platforms/android-9/android.jar';build=sdk/'build-tools/36.0.0'
    source=root/'app/native-tests/test-spectrum'
    run(java/'javac','-source','8','-target','8','-Xlint:-options','-bootclasspath',android,'-d',classes,*source.rglob('*.java'))
    run(java/'java','-cp',sdk/'cmdline-tools/latest/lib/r8.jar','com.android.tools.r8.D8','--min-api','26','--lib',android,'--output',out,*classes.rglob('*.class'))
    run(build/'aapt2','link','-I',android,'--manifest',source/'AndroidManifest.xml','-o',out/'unsigned.apk')
    with zipfile.ZipFile(out/'unsigned.apk','a',zipfile.ZIP_DEFLATED) as apk:apk.write(out/'classes.dex','classes.dex')
    run(java/'java','-jar',build/'lib/apksigner.jar','sign','--ks',sdk.parent/'uni-debug.keystore','--ks-pass','pass:android','--ks-key-alias','uni-debug','--out',out/'fixture.apk',out/'unsigned.apk')
    run(*adb,'install','-r',out/'fixture.apk')
