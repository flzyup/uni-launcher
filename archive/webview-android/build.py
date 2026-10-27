#!/usr/bin/env python3
"""Dependency-light offline Android build. No automatic installation or vehicle access."""
import argparse
import hashlib
import re
import shutil
import subprocess
import zipfile
from pathlib import Path

project = Path(__file__).resolve().parent
repo = project.parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--toolchain', type=Path, default=Path('/tmp/linkco-build'))
parser.add_argument('--sdk', type=Path, default=Path('/data/tools/linkco-android/sdk'))
parser.add_argument('--test-only', action='store_true')
args = parser.parse_args()
toolchain = args.toolchain.resolve()
jvm = toolchain / 'root/usr/lib/jvm/java-17-openjdk-amd64/bin'
if not (jvm / 'javac').is_file():
    jvm = Path('/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64/bin')
android = args.sdk / 'platforms/android-9/android.jar'
if not android.exists():
    android = args.sdk / 'platforms/android-28/android.jar'
build = project / 'build'
build.mkdir(exist_ok=True)

def run(*command):
    subprocess.run([str(v) for v in command], check=True, cwd=project)

tests = build / 'tests'
tests.mkdir(exist_ok=True)
run(jvm / 'javac', '--release', '8', '-encoding', 'UTF-8', '-d', tests,
    *sorted((repo / 'app/android/app/src/main/java/xyz/i4o/uni/launcher/core').glob('*.java')),
    *sorted((repo / 'app/native-tests/test').rglob('*.java')))
run(jvm / 'java', '-cp', tests, 'xyz.i4o.uni.launcher.core.ClimateStateTest')
if args.test_only:
    raise SystemExit(0)
if not android.exists():
    raise SystemExit('Android API 28 platform android.jar required; pass --sdk.')
if not (project / 'node_modules/.bin/esbuild').exists():
    raise SystemExit('Run npm ci in archive/webview-android/ first.')
assets = build / 'assets'
ui = assets / 'ui'
ui.mkdir(parents=True, exist_ok=True)
for name in ['styles.css', 'glass.css', 'customize.css', 'oem-cards.css']:
    css_source=(repo / 'design' / name).read_text()
    # Android 9's bundled WebView 66 predates inset and the unprefixed grid gap alias.
    def expand_inset(match):
        values=match.group(1).strip().split()
        sides=values*4 if len(values)==1 else [values[0],values[1],values[0],values[1]] if len(values)==2 else values
        return ';'.join(side+':'+value for side,value in zip(['top','right','bottom','left'],sides))
    css_source=re.sub(r'\binset\s*:\s*([^;}]+)',expand_inset,css_source)
    css_source=re.sub(r'(?<![\w-])gap\s*:\s*([^;}]+)',lambda m:'grid-gap:'+m.group(1)+';gap:'+m.group(1),css_source)
    (ui / name).write_text(css_source)
shutil.copy2(project / 'ui/runtime.css', ui / 'runtime.css')
shutil.copy2(repo / 'analysis/official-widgets.json', assets / 'official-widgets.json')
reference = (repo / 'design/index.html').read_text()
symbols = re.search(r'<svg class="symbols".*?</svg>', reference, re.S).group()
css = ''.join('<link rel="stylesheet" href="' + n + '">' for n in ['styles.css','glass.css','customize.css','oem-cards.css','runtime.css'])
(ui / 'index.html').write_text('''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'none'; base-uri 'none'; form-action 'none'">
<title>UNI 桌面</title>''' + css + '</head><body class="single">' + symbols + '<div id="single-screen"></div><script src="app.js"></script></body></html>')
shared = '\n'.join((repo / 'design' / name).read_text() for name in ['oem-cards.js','customize.js'])
shared += '\n' + (repo / 'design/study.js').read_text().split('\nfunction render() {')[0]
# Metadata can come from another process. Escape at each shared HTML output boundary.
for field in ['title','artist','collection']:
    shared = shared.replace('${m.' + field + '}', '${safe(m.' + field + ')}')
bootstrap="""try { const saved=JSON.parse(UniNative.bootstrap()).savedDesign; if(saved) localStorage.setItem('lynk-design-v04',saved); } catch (_) {}\n"""
source = bootstrap + shared + '\n' + (project / 'ui/runtime.js').read_text()
(build / 'ui-source.js').write_text(source)
run(project / 'node_modules/.bin/esbuild', build / 'ui-source.js', '--target=chrome60', '--charset=utf8', '--outfile=' + str(ui / 'app.js'))
classes=build / 'classes'
if classes.exists():shutil.rmtree(classes)
classes.mkdir()
run(jvm / 'javac', '-source','8','-target','8','-Xlint:-options','-encoding','UTF-8','-bootclasspath',android,'-d',classes,*sorted((project/'src').rglob('*.java')),*sorted((repo/'app/android/app/src/main/java/xyz/i4o/uni/launcher/core').glob('*.java')),*sorted((repo/'app/android/app/src/main/java/xyz/i4o/uni/launcher/integration').glob('*.java')))
run(jvm / 'java','-cp',toolchain/'r8.jar','com.android.tools.r8.D8','--min-api','23','--lib',android,'--output',build,*sorted(classes.rglob('*.class')))
run(toolchain/'aapt2','compile','--dir',project/'res','-o',build/'res.zip')
run(toolchain/'aapt2','link','-I',android,'--manifest',project/'AndroidManifest.xml','-A',assets,'-R',build/'res.zip','-o',build/'unsigned.apk')
with zipfile.ZipFile(build/'unsigned.apk','a',zipfile.ZIP_DEFLATED) as apk:apk.write(build/'classes.dex','classes.dex')
signing = args.sdk.parent / 'uni-debug.keystore'
if not signing.exists():
    run(jvm/'keytool','-genkeypair','-keystore',signing,'-storepass','android','-keypass','android','-alias','uni-debug','-dname','CN=UNI Local Development','-keyalg','RSA','-keysize','2048','-validity','10000')
output=project/'dist/UNI-Launcher-0.1.0-debug.apk'
output.parent.mkdir(exist_ok=True)
signer=[jvm/'java','-cp',str(toolchain/'root/usr/share/java/apksigner.jar')+':'+str(toolchain/'root/usr/share/java/apksig.jar'),'com.android.apksigner.ApkSignerTool']
run(*signer,'sign','--ks',signing,'--ks-pass','pass:android','--key-pass','pass:android','--ks-key-alias','uni-debug','--v4-signing-enabled','false','--out',output,build/'unsigned.apk')
run(*signer,'verify','--verbose',output)
run(toolchain/'aapt2','dump','badging',output)
print('APK:',output)
print('SHA256:',hashlib.sha256(output.read_bytes()).hexdigest())
