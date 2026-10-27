/* End-to-end checks in an actual Android WebView. Only accepts emulator serials. */
import {execFileSync} from 'node:child_process';
import {mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const serial=process.env.UNI_EMULATOR_SERIAL||'emulator-5580';
if(!/^emulator-\d+$/.test(serial))throw new Error('Emulator serial required; refuses physical devices');
const adb=(...args)=>execFileSync('adb',['-s',serial,...args],{encoding:'utf8'}).trim();
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const out=path.join(root,'verification');mkdirSync(out,{recursive:true});
const checks=[],errors=[];let socket,id=0,pending=new Map();
async function connect(){
  const pid=adb('shell','pidof','xyz.i4o.uni.launcher').split(' ')[0];
  adb('forward','tcp:9226','localabstract:webview_devtools_remote_'+pid);
  let target;
  for(let n=0;n<60;n++){
    try{target=(await(await fetch('http://127.0.0.1:9226/json')).json()).find(t=>t.url.includes('uni.launcher.local'));if(target)break;}catch{}
    await pause(300);
  }
  if(!target)throw new Error('No launcher WebView');
  socket=new WebSocket(target.webSocketDebuggerUrl);await new Promise((resolve,reject)=>{socket.onopen=resolve;socket.onerror=reject;});
  socket.onmessage=e=>{
    const m=JSON.parse(e.data);
    if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.text);
    if(m.id){const p=pending.get(m.id);pending.delete(m.id);if(m.error)p?.reject(m.error);else p?.resolve(m.result);}
  };
  await cdp('Runtime.enable');
}
function cdp(method,params={}){return new Promise((resolve,reject)=>{const key=++id;pending.set(key,{resolve,reject});socket.send(JSON.stringify({id:key,method,params}));setTimeout(()=>{if(pending.has(key)){pending.delete(key);reject(new Error(method+' timed out'));}},10000).unref();});}
async function evaluate(expression){const r=await cdp('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw new Error(JSON.stringify(r.exceptionDetails));return r.result.value;}
async function check(name,expression){const ok=await evaluate(expression);if(!ok)throw new Error(name+' failed');checks.push(name);console.log('PASS',name);}
async function click(selector){await evaluate(`(()=>{const b=document.querySelector(${JSON.stringify(selector)});if(!b)throw new Error('Missing '+${JSON.stringify(selector)});b.click();})()`);await pause(180);}
async function capture(name){await pause(700);writeFileSync(path.join(out,name+'.png'),execFileSync('adb',['-s',serial,'exec-out','screencap','-p']));}
async function restart(){socket?.close();adb('shell','am','force-stop','xyz.i4o.uni.launcher');adb('shell','am','start','-W','-n','xyz.i4o.uni.launcher/.MainActivity');await connect();await pause(500);}
try{
  if(adb('shell','getprop','ro.build.version.sdk')!=='28')throw new Error('API 28 required');
  adb('shell','settings','put','secure','immersive_mode_confirmations','confirmed');
  // Start with a deterministic application sandbox; never clears system or car data.
  adb('shell','pm','clear','xyz.i4o.uni.launcher');adb('shell','am','start','-W','-n','xyz.i4o.uni.launcher/.MainActivity');await connect();
  await check('Android 9 bundled WebView renders shared UI','!!window.Uni && document.querySelectorAll(".widget-card").length===3');
  await check('Navigation has a visible map area','document.querySelector(".nav-card .map").getBoundingClientRect().height>500');
  await check('No left sidebar','!document.querySelector(".side-rail")');
  await check('Dock groups in requested order','[...document.querySelectorAll("[data-dock-group]")].map(e=>e.dataset.dockGroup).join(",")==="navigation,climate,transport,info,vehicle,camera"');
  // Actual touch long press, not a JS call to the settings function.
  const home=await evaluate('(()=>{const r=document.querySelector("[data-home-hold]").getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2};})()');
  adb('shell','input','swipe',String(Math.round(home.x)),String(Math.round(home.y)),String(Math.round(home.x)),String(Math.round(home.y)),'850');await pause(500);
  await check('Physical long press Home opens settings','Uni.inspect().view==="settings"');
  await click('[data-action="set-mode"][data-value="dark"]');
  await check('Dark theme applied','document.querySelector("#single-screen>.screen").classList.contains("dark")');
  await click('[data-action="set-palette"][data-value="blue"]');
  await evaluate('(()=>{const field=document.querySelector(".hex-input");field.value="#52A6C7";field.dispatchEvent(new Event("change",{bubbles:true}));})()');
  await check('Custom HEX accent updates theme','Uni.inspect().preferences.palette==="custom"&&Uni.inspect().preferences.custom==="#52A6C7"');
  await click('[data-action="set-palette"][data-value="blue"]');
  await evaluate('updateRadius(0)');
  await check('Zero radius reaches rendered surface','getComputedStyle(document.querySelector(".settings-block")).borderRadius==="0px"');
  await capture('settings-dark-square');
  await click('[data-action="set-mode"][data-value="light"]');
  await check('Light theme applied','document.querySelector("#single-screen>.screen").classList.contains("light")');
  await click('[data-action="hide-navigation"]');await pause(500);
  await check('Native navigation preference applied','Uni.inspect().native.hideNavigation===true');
  const flags=adb('shell','dumpsys','window','windows');
  if(!flags.includes('xyz.i4o.uni.launcher'))throw new Error('Window missing');
  await check('Full window fit after nav bar changes','Math.abs(document.querySelector("#single-screen>.screen").getBoundingClientRect().width-innerWidth)<2');
  await click('[data-action="home"]');await capture('home-light');
  await restart();
  await check('Theme, accent, radius and nav survive process restart','Uni.inspect().preferences.mode==="light"&&Uni.inspect().preferences.palette==="blue"&&Uni.inspect().preferences.radius===0&&Uni.inspect().native.hideNavigation');
  await evaluate('openDesktopSettings()');await click('[data-action="set-mode"][data-value="dark"]');await evaluate('updateRadius(28)');await click('[data-action="home"]');
  await capture('home-dark');
  await click('[data-action="temp-up"][data-zone="left"]');
  await check('Simulator command crosses native bridge and returns state','Uni.inspect().native.climate.left===23&&ui.climate.left===23');
  await click('[data-action="climate"]');await click('[data-action="climate-mode"][data-value="sync"]');
  await check('Dual-zone simulator sync confirmed from native state','Uni.inspect().native.climate.sync&&Uni.inspect().native.climate.right===23');await capture('climate');
  await click('[data-action="close-modal"]');
  await evaluate('beginEditing()');
  await click('[data-action="delete-card"][data-id="weather-1"]');
  await check('Card deletion changes editing draft','!Uni.inspect().cards.some(c=>c.id==="weather-1")');
  await click('[data-action="cancel-edit"]');await check('Cancel restores layout','Uni.inspect().cards.some(c=>c.id==="weather-1")');
  await evaluate('beginEditing()');await click('[data-action="open-library"]');
  await check('All IP753 card types available; other-model ride excluded','["nav","music","weather","calendar","member","cleanup","tpms","air"].every(t=>!!document.querySelector(`[data-action="add-card"][data-type="${t}"]`))&&!document.querySelector("[data-action=add-card][data-type=ride]")');
  await click('[data-action="add-card"][data-type="air"]');await click('[data-action="finish-edit"]');
  await check('Adding card creates a new page when full','Uni.inspect().cards.some(c=>c.type==="air")&&Uni.inspect().pageCount===3');
  await restart();await check('Card and new page survive process restart','Uni.inspect().cards.some(c=>c.type==="air")&&Uni.inspect().pageCount===3');
  await evaluate('ui.page=2;beginEditing()');
  const air=await evaluate('cards.find(c=>c.type==="air").id');
  await click(`[data-action="edit-card"][data-id="${air}"]`);await click('[data-action="choose-size"][data-w="8"]');await click('[data-action="save-card"]');await click('[data-action="finish-edit"]');
  await check('Card resize applies without overlap','cards.find(c=>c.type==="air").w===8&&cards.find(c=>c.type==="air").h===6');
  await evaluate('beginEditing()');
  const drag=await evaluate(`(()=>{const r=document.querySelector('.card-move').getBoundingClientRect(),g=document.querySelector('.card-grid').getBoundingClientRect();return {x:r.x+80,y:r.y+r.height/2,dx:(g.width+24)/12*2};})()`);
  adb('shell','input','swipe',String(Math.round(drag.x)),String(Math.round(drag.y)),String(Math.round(drag.x+drag.dx)),String(Math.round(drag.y)),'500');await pause(250);
  await check('Physical touch moves card on grid','cards.find(c=>c.type==="air").x===2');
  const handle=await evaluate(`(()=>{const r=document.querySelector('.resize-handle').getBoundingClientRect(),g=document.querySelector('.card-grid').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,dx:(g.width+24)/12,dy:(g.height+24)/6*2};})()`);
  adb('shell','input','swipe',String(Math.round(handle.x)),String(Math.round(handle.y)),String(Math.round(handle.x+handle.dx)),String(Math.round(handle.y-handle.dy)),'500');await pause(250);
  await check('Physical touch resizes card on grid','cards.find(c=>c.type==="air").w===9&&cards.find(c=>c.type==="air").h===4');
  await click('[data-action="finish-edit"]');await capture('card-edited');
  await evaluate('ui.page=0;renderStandalone()');await click('[data-action="apps"]');
  await check('App drawer comes from Android PackageManager','document.querySelectorAll("[data-action=launch-app]").length>0&&Uni.inspect().native.apps.length>0');await capture('apps');
  await click('[data-action="close-modal"]');
  await evaluate('openDesktopSettings();ui.tab="sources";renderStandalone()');await click('[data-action="demo-mode"]');
  await check('Live mode has no simulated observations','!Uni.inspect().native.demo');await click('[data-action="home"]');
  await check('Live mode removes demo route, weather and temperature','!document.querySelector(".map")&&document.querySelector(".dock-zone b").textContent.trim()==="—°"&&!document.querySelector(".weather-current")');
  await check('Live mode does not claim a demo city or OEM media source','!document.querySelector(".weather-card").textContent.includes("杭州")&&!document.querySelector(".dock-info").textContent.includes("原车媒体中心")');
  await click('[data-action="temp-up"][data-zone="left"]');await check('Unverified car control cannot mutate simulator state','Uni.inspect().native.climate.left===22.5');
  await capture('home-live-unavailable');
  await click('[data-action="official-widget"][data-type="nav"]');await pause(600);
  const foreground=adb('shell','dumpsys','activity','activities');if(!foreground.includes('OfficialWidgetActivity'))throw new Error('Widget activity not opened');checks.push('OEM Widget missing-provider path opens safely');
  adb('shell','input','keyevent','4');await pause(500);
  await check('Back from Widget returns to launcher','!!window.Uni&&Uni.inspect().view==="home"');
  await evaluate('openDesktopSettings()');await click('[data-action="settings-tab"][data-tab="appearance"]');await click('[data-action="hide-navigation"]');
  await check('Navigation bar can be restored','!Uni.inspect().native.hideNavigation');
  await check('Bridge origin cannot navigate externally','location.origin==="https://uni.launcher.local"');
  await evaluate('UniNative.dispatch(JSON.stringify({action:"launch-app",value:"not/an/allowed/component"}))');
  await check('Unknown app launch remains in launcher','location.origin==="https://uni.launcher.local"');
  await check('Malformed preference state is rejected','UniNative.saveDesign("{bad}")===false');
  if(process.argv.includes('--fixture')){
    adb('shell','cmd','notification','allow_listener','xyz.i4o.uni.launcher/xyz.i4o.uni.launcher.integration.MediaAccessService');
    adb('shell','am','start','-W','-n','ecarx.xsf.mediacenter/.FixtureActivity');
    adb('shell','am','start','-W','-n','xyz.i4o.uni.launcher/.MainActivity');await pause(500);
    await evaluate('Uni.home();send("refresh")');await pause(500);
    await check('Native MediaSession metadata arrives from synthetic source','Uni.inspect().native.media.available&&Uni.inspect().native.media.title.includes("<img")');
    await check('External media title is rendered as text, never markup','!window.injected&&!document.querySelector(".song-copy img")&&document.querySelector(".song-copy h3").textContent.includes("<img")');
    await click('.dock-transport [data-action="toggle-play"]');await pause(250);
    await check('Media pause command is confirmed by playback callback','!Uni.inspect().native.media.playing');
    await click('.dock-transport [data-action="next"]');await pause(250);
    await check('Media next command is confirmed by metadata callback','Uni.inspect().native.media.title==="Fixture track 1"');await capture('media-session-fixture');
    await click('[data-action="apps"]');await click('[data-action="launch-app"][data-id="ecarx.xsf.mediacenter/ecarx.xsf.mediacenter.FixtureActivity"]');
    if(!adb('shell','dumpsys','activity','activities').includes('mResumedActivity: ActivityRecord')||!adb('shell','dumpsys','activity','activities').match(/mResumedActivity:.*FixtureActivity/))throw new Error('Native app launch did not reach fixture');
    checks.push('App drawer launches an actual Android activity');
    adb('shell','am','start','-W','-n','xyz.i4o.uni.launcher/.MainActivity');await pause(300);
    adb('shell','appwidget','grantbind','--package','xyz.i4o.uni.launcher','--user','0');
    await evaluate('send("official-widget",{value:"music"})');await pause(800);
    adb('shell','uiautomator','dump','/sdcard/uni-fixture-ui.xml');
    const widgetUi=adb('shell','cat','/sdcard/uni-fixture-ui.xml');
    if(!widgetUi.includes('UNI emulator fixture widget'))throw new Error('RemoteViews not rendered');
    checks.push('Native WidgetHost binds and displays synthetic RemoteViews');await capture('widget-fixture');
    adb('shell','input','keyevent','4');await pause(300);
    await evaluate('openDesktopSettings();ui.tab="appearance";renderStandalone()');
    const priorPolicy=adb('shell','settings','get','global','policy_control');
    adb('shell','pm','grant','xyz.i4o.uni.launcher','android.permission.WRITE_SECURE_SETTINGS');
    await evaluate('send("refresh")');await pause(300);
    await click('[data-action="hide-navigation"]');await click('[data-action="global-navigation"]');
    if(adb('shell','settings','get','global','policy_control')!=='immersive.navigation=*')throw new Error('Global hide policy missing');
    checks.push('Authorized Dudu-style global navigation policy applied');
    await click('[data-action="global-navigation"]');
    if(adb('shell','settings','get','global','policy_control')!==priorPolicy)throw new Error('Prior global policy was not restored');
    checks.push('Global navigation policy restores its original value');
    await click('[data-action="hide-navigation"]');
  }
  const oldHome=adb('shell','cmd','package','resolve-activity','--brief','-a','android.intent.action.MAIN','-c','android.intent.category.HOME').split('\n').at(-1);
  try{
    adb('shell','cmd','package','set-home-activity','xyz.i4o.uni.launcher/.MainActivity');adb('shell','input','keyevent','3');await pause(300);
    if(!adb('shell','dumpsys','activity','activities').match(/mResumedActivity:.*xyz.i4o.uni.launcher\//))throw new Error('HOME did not resolve to UNI');
    checks.push('Android HOME role launches UNI');
  }finally{adb('shell','cmd','package','set-home-activity',oldHome.startsWith('android/')?'com.android.launcher3/.Launcher':oldHome);}
  const log=adb('logcat','-d','-s','AndroidRuntime:E','UniUI:D');
  if(log.includes('FATAL EXCEPTION')||errors.length)throw new Error('Runtime errors: '+JSON.stringify(errors)+' '+log);
  checks.push('No Android fatal exception or JavaScript exception');
  const apkSha256=createHash('sha256').update(readFileSync(path.join(root,'dist/UNI-Launcher-0.1.0-debug.apk'))).digest('hex');
  const report={date:new Date().toISOString(),serial,api:28,webview:await evaluate('navigator.userAgent'),checks,passed:checks.length,errors,package:'xyz.i4o.uni.launcher',apkSha256,syntheticIntegrationSource:process.argv.includes('--fixture'),carVerification:'pending'};
  writeFileSync(path.join(out,'emulator-report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(`Verified ${checks.length} emulator checks`);
}finally{socket?.close();}
