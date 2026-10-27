/* Production adapter. Shared V04 components are bundled locally, without review-board content. */
let nativeState=JSON.parse(UniNative.bootstrap());
const send=(action,extra={})=>UniNative.dispatch(JSON.stringify({action,...extra}));
const designAction=handleDesignAction;
const designCard=cardBody;
const designMedia=mediaState;
const designSheet=experienceSheet;
const designModal=modalMarkup;
const designAppearance=appearanceSettings;
const designDock=dock;
const designTheme=activeTheme;
const renderView=renderStandalone;
const browserPersist=persistDesign;
persistDesign=function(){
  browserPersist();
  if(!UniNative.saveDesign(JSON.stringify({version:4,preferences,cards,pageCount})))showToast('保存失败，请检查桌面布局');
};
const climateActions=['temp-up','temp-down','fan-up','fan-down','climate-power','climate-mode'];
const mediaActions=['toggle-play','previous','next'];

// Never show demonstration observations on a real car unless explicitly selected in settings.
statusBar=function(){
  const time=new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',hour12:false});
  return `<div class="oem-status"><div class="status-left"><b>${safe(time)}</b><span>UNI / LYNK & CO</span></div><div class="status-right"><span>${nativeState.demo?'模拟演示':'原车接入 · 待核对'}</span></div></div>`;
};
activeTheme=function(){return preferences.mode==='system'?(nativeState.dark?'dark':'light'):designTheme();};
temperature=function(zone){return nativeState.demo?Number(ui.climate[zone]).toFixed(1):'—';};
mediaState=function(){
  if(nativeState.demo)return designMedia();
  const m=nativeState.media||{};
  return {title:m.available?(m.title||'未知曲目'):'暂无播放',artist:m.artist||'等待媒体会话',collection:m.collection||'媒体访问可在设置中授权'};
};
function placeholder(card,text,detail){
  const small=card.h<=2,title=card.type==='weather'?'天气':card.title||cardCatalog[card.type].name;
  return `${oemHeading(title,cardCatalog[card.type].source||'原车应用',cardCatalog[card.type].icon)}<div class="live-placeholder">${small?'':icon(cardCatalog[card.type].icon)}<h3>${safe(text)}</h3>${small?'':`<p>${safe(detail)}</p>`}<button class="outline-button" data-action="official-widget" data-type="${safe(card.type)}">打开原厂卡片${icon('arrow-right')}</button>${small?'':`<button class="text-button" data-action="open-official" data-type="${safe(card.type)}">打开原车应用</button>`}</div>`;
}
dock=function(){
  const markup=designDock();
  return nativeState.demo?markup:markup.replace(/原车媒体中心/g,'媒体会话').replace(art,icon('music'));
};
cardBody=function(card){
  if(card.type==='clock'){
    const d=new Date();return `${oemHeading(card.title||'时钟','系统时间','clock')}<div class="clock-time">${safe(d.toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',hour12:false}))}</div><div class="clock-date">${safe(d.toLocaleDateString('zh-CN',{year:'numeric',month:'long',day:'numeric',weekday:'long'}))}</div>`;
  }
  if(nativeState.demo)return designCard(card);
  if(card.type==='music'){
    const m=mediaState();return `${oemHeading(card.title||'正在播放',nativeState.media?.source||'媒体会话','music')}<div class="listening"><div class="cover hero-cover">${icon('music')}</div><div class="song-copy"><h3>${safe(m.title)}</h3><p>${safe(m.artist)}</p></div><button class="outline-button" data-action="music-info">播放详情${icon('arrow-right')}</button></div>`;
  }
  if(card.type==='shortcuts')return `<div class="live-placeholder">${icon('apps')}<h3>全部应用</h3><button class="outline-button" data-action="apps">打开应用列表</button></div>`;
  return placeholder(card,'等待原车信息',card.type==='nav'?'打开原车导航，或查看原厂导航卡片':'连接原厂提供者后核对字段与状态');
};
appearanceSettings=function(theme){
  return designAppearance(theme).replace('</aside>',`<div class="native-options"><button data-action="hide-navigation" class="outline-button">${icon(nativeState.hideNavigation?'check':'apps')}系统导航栏：${nativeState.hideNavigation?'隐藏':'显示'}</button><button data-action="global-navigation" class="text-button">全局隐藏：${nativeState.globalNavigation?'开启':'关闭'}${nativeState.globalNavigationGranted?'':'（需系统授权）'}</button></div></aside>`);
};
sourceSettings=function(){
  return `<div class="source-settings native-sources"><section class="settings-block"><h3>原车通信</h3><p>${safe(nativeState.vehicle?.reason||'未连接')}</p><p>官方卡片保持原厂来源；统一样式的实时字段待实车核对。</p><button class="outline-button" data-action="refresh-native">${icon('check')}刷新连接</button></section><section class="settings-block"><h3>音乐</h3><p>${nativeState.media?.authorized?'媒体访问已授权':'尚未授权媒体访问'}</p><button class="outline-button" data-action="media-access">授权媒体访问</button></section><section class="settings-block"><h3>演示数据</h3><p>仅用于离线交互验证。关闭后显示真实接入状态。</p><button class="outline-button" data-action="demo-mode">${icon(nativeState.demo?'check':'close')}${nativeState.demo?'已开启':'已关闭'}</button></section><section class="settings-block"><h3>版本 0.1.0</h3><p>xyz.i4o.uni.launcher</p><button class="outline-button" data-action="open-official" data-type="settings">打开原车设置</button></section></div>`;
};
experienceSheet=function(){
  if(ui.modal==='oem-open')return '';
  const markup=designSheet();
  if(!markup)return '';
  const type={music:'music',climate:'climate',vehicle:'vehicle',camera:'camera'}[ui.modal];
  let updated=markup.replace(/操作预览 · 未连接车辆|原车媒体中心 · 样式示例|原车车辆信息 · 等待连接|原车全景影像入口/g,nativeState.demo?'模拟演示 · 不控制车辆':type==='music'?'标准媒体会话':'原车接入 · 待核对');
  if(!nativeState.demo&&ui.modal==='climate')updated=updated.replace(`<b>${ui.climate.fan}</b>`,'<b>—</b>');
  const extra=`<div class="native-sheet-actions"><button class="outline-button" data-action="open-official" data-type="${type}">打开${type==='camera'?'原车 360':'原车应用'}${icon('arrow-right')}</button>${['music','vehicle'].includes(type)?`<button class="text-button" data-action="official-widget" data-type="${type==='vehicle'?'tpms':type}">查看原厂卡片</button>`:''}</div>`;
  return updated.replace('</section></div>',extra+'</section></div>');
};
modalMarkup=function(theme){
  if(ui.modal!=='apps')return designModal(theme);
  return `<div class="modal-backdrop"><section class="modal-glass apps-sheet native-apps"><header><div><h2>全部应用</h2><p>${nativeState.apps.length} 个应用</p></div>${actionButton('close-modal','close','关闭全部应用','close-button')}</header><div class="app-drawer">${nativeState.apps.map(a=>`<button data-action="launch-app" data-id="${safe(a.id)}"><span><img src="${safe(a.icon)}" alt=""></span><b>${safe(a.label)}</b></button>`).join('')}</div></section></div>`;
};
handleDesignAction=function(button){
  const action=button.dataset.action;
  if((action==='new-page'||(action==='add-card'&&!findPlace(cardCatalog[button.dataset.type].w,cardCatalog[button.dataset.type].h,ui.page)))&&pageCount>=20){showToast('最多可建立 20 个桌面页');return;}
  if(climateActions.includes(action)){send(action,{zone:button.dataset.zone||'',value:button.dataset.value||''});return;}
  if(mediaActions.includes(action)){
    if(nativeState.demo){designAction(button);return;}send(action);return;
  }
  if(['hide-navigation','global-navigation','demo-mode'].includes(action)){
    const key={'hide-navigation':'hideNavigation','global-navigation':'globalNavigation','demo-mode':'demo'}[action];
    send(action,{enabled:!nativeState[key]});return;
  }
  if(action==='launch-app'){send(action,{value:button.dataset.id});return;}
  if(action==='media-access'){send(action);return;}
  if(action==='refresh-native'){send('refresh');return;}
  if(action==='official-widget'){send(action,{value:button.dataset.type});return;}
  if(action==='open-official'||action==='oem-open'){send('open-official',{value:button.dataset.type});return;}
  designAction(button);
};
resize=function(){
  const scale=Math.min(innerWidth/1920,innerHeight/1080);
  const root=document.getElementById('single-screen');
  root.style.width=`${innerWidth/scale}px`;
  root.style.height=`${innerHeight/scale}px`;
  root.style.transform=`scale(${scale})`;
  root.style.left='0px';root.style.top='0px';
  document.querySelectorAll('.mini-screen-wrap').forEach(el=>{if(el.firstElementChild)el.firstElementChild.style.transform=`scale(${el.clientWidth/1920})`;});
};
renderStandalone=function(){
  if(!nativeState.demo&&!nativeState.vehicle?.connected)Object.assign(ui.climate,{left:null,right:null,fan:null,power:false,auto:false,ac:false,sync:false,recirc:false});
  renderView();
  document.querySelector('#single-screen>.screen').classList.toggle('live-native',!nativeState.demo);
  document.querySelectorAll('svg use').forEach(el=>el.setAttributeNS('http://www.w3.org/1999/xlink','href',el.getAttribute('href')));
  if(!nativeState.demo){
    const disabled=nativeState.vehicle?.writable?[]:[...climateActions];
    if(!nativeState.media?.available)disabled.push(...mediaActions);
    document.querySelectorAll('#single-screen [data-action]').forEach(el=>{if(disabled.includes(el.dataset.action)){el.disabled=true;el.setAttribute('aria-disabled','true');}});
  }
};
window.Uni={
  receive(state){
    nativeState=state;Object.assign(ui.climate,state.climate);
    if(!state.demo)ui.playing=!!state.media?.playing;
    // Native callbacks must not interrupt an unfinished title, color or slider edit.
    if(!document.activeElement?.matches('input')&&!ui.editing)renderStandalone();
  },
  home(){if(!ui.editing){ui.view='home';ui.page=0;ui.modal=null;renderStandalone();}},
  back(){if(ui.modal){ui.modal=null;}else if(ui.editing){restoreSnapshot(ui.snapshot);ui.editing=false;}else if(ui.view==='settings'){ui.view='home';}renderStandalone();},
  inspect(){return {preferences,cards,pageCount,view:ui.view,page:ui.page,editing:ui.editing,modal:ui.modal,native:nativeState};}
};
initCustomization();Object.assign(ui.climate,nativeState.climate);if(!nativeState.demo)ui.playing=!!nativeState.media?.playing;renderStandalone();
window.addEventListener('resize',resize);
setInterval(()=>{document.querySelectorAll('.status-left b').forEach(el=>el.textContent=new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',hour12:false}));},30000);
