#!/usr/bin/env python3
"""Local NetEase contract tests with JVM doubles; never connects to a device."""
from pathlib import Path
import subprocess, tempfile
temporary=tempfile.TemporaryDirectory(prefix='uni-netease-contract-');r=Path(temporary.name);s=r/'stubs'
files={
'android/os/Bundle.java':'''package android.os; import java.util.*; public class Bundle { public Map<String,Object> m=new HashMap<>(); public String getString(String k){return (String)m.get(k);} public int getInt(String k,int d){Object o=m.get(k);return o==null?d:(Integer)o;} public String[] getStringArray(String k){return (String[])m.get(k);} public void putString(String k,String v){m.put(k,v);} public void putInt(String k,int v){m.put(k,v);} public void putStringArray(String k,String[] v){m.put(k,v);} }''',
'android/os/Looper.java':'''package android.os; public class Looper { public static Looper getMainLooper(){return new Looper();} }''',
'android/os/Handler.java':'''package android.os; public class Handler { public Handler(Looper l){} }''',
'android/os/SystemClock.java':'''package android.os; public class SystemClock { public static long uptimeMillis(){return 1234;} }''',
'android/view/KeyEvent.java':'''package android.view; public class KeyEvent { public static final int ACTION_DOWN=0,ACTION_UP=1,KEYCODE_MEDIA_PLAY_PAUSE=85,KEYCODE_MEDIA_NEXT=87,KEYCODE_MEDIA_PREVIOUS=88,KEYCODE_MEDIA_PLAY=126,KEYCODE_MEDIA_PAUSE=127; public int action,key; public KeyEvent(long d,long t,int a,int k,int repeat){action=a;key=k;} }''',
'android/media/MediaMetadata.java':'''package android.media; import java.util.*; public class MediaMetadata { public static final String METADATA_KEY_MEDIA_ID="android.media.metadata.MEDIA_ID",METADATA_KEY_TITLE="android.media.metadata.TITLE",METADATA_KEY_ARTIST="android.media.metadata.ARTIST",METADATA_KEY_DURATION="android.media.metadata.DURATION"; public Map<String,Object> m=new HashMap<>(); public String getString(String k){return (String)m.get(k);} public long getLong(String k){Object o=m.get(k);return o==null?0:((Number)o).longValue();} }''',
'android/media/session/MediaSession.java':'''package android.media.session; public class MediaSession { public static final int FLAG_HANDLES_MEDIA_BUTTONS=1; }''',
'android/media/session/PlaybackState.java':'''package android.media.session; public class PlaybackState { public static final int STATE_PLAYING=3; public int state=3; public int getState(){return state;} public long getActions(){return 0;} }''',
'android/media/session/MediaController.java':'''package android.media.session; import android.media.*; import android.os.*; import android.view.*; import java.util.*; public class MediaController { public String pkg; public long flags=3; public MediaMetadata metadata; public PlaybackState state=new PlaybackState(); public Callback callback; public List<KeyEvent> keys=new ArrayList<>(); public TransportControls controls=new TransportControls(); public boolean fail=false; public MediaController(String p){pkg=p;} public String getPackageName(){return pkg;} public void registerCallback(Callback c,Handler h){callback=c;} public void unregisterCallback(Callback c){if(callback==c)callback=null;} public MediaMetadata getMetadata(){return metadata;} public long getFlags(){return flags;} public PlaybackState getPlaybackState(){return state;} public TransportControls getTransportControls(){return controls;} public boolean dispatchMediaButtonEvent(KeyEvent e){if(fail)throw new IllegalStateException(); keys.add(e);return e.action==1;} public static class Callback {public void onMetadataChanged(MediaMetadata m){} public void onSessionEvent(String e,Bundle b){} public void onSessionDestroyed(){}} public static class TransportControls {public long last=-1;public int calls=0; public void seekTo(long p){last=p;calls++;}} }''',
'org/json/JSONObject.java':'''package org.json; import java.util.*; public class JSONObject { public Map<String,Object> m=new HashMap<>(); public JSONObject put(String k,Object v){m.put(k,v);return this;} public String optString(String k){Object v=m.get(k);return v==null?"":v.toString();} public boolean optBoolean(String k){return Boolean.TRUE.equals(m.get(k));} }''',
'AdapterContractTest.java':'''import android.media.*; import android.media.session.*; import android.os.*; import android.view.*; import org.json.*; import xyz.i4o.uni.launcher.integration.NeteaseMediaAdapter;
public class AdapterContractTest {
 static int count; static void ok(boolean b,String m){count++;if(!b)throw new AssertionError(m);}
 static MediaMetadata meta(String id,String lyric){MediaMetadata m=new MediaMetadata();m.m.put(MediaMetadata.METADATA_KEY_MEDIA_ID,id);m.m.put(MediaMetadata.METADATA_KEY_TITLE,"Track "+id);m.m.put(MediaMetadata.METADATA_KEY_DURATION,180000L);if(lyric!=null)m.m.put(NeteaseMediaAdapter.LYRIC_KEY,lyric);return m;}
 static JSONObject snapshot(NeteaseMediaAdapter a){JSONObject j=new JSONObject();a.augmentSnapshot(j);return j;}
 static Bundle lyric(String id,String value,int state){Bundle b=new Bundle();b.putString(MediaMetadata.METADATA_KEY_MEDIA_ID,id);b.putString("wt_music_lyric_obj",value);b.putInt("wt_music_lyric_state",state);return b;}
 public static void main(String[] args){
  NeteaseMediaAdapter a=new NeteaseMediaAdapter(null); MediaController n=new MediaController(NeteaseMediaAdapter.PACKAGE);n.metadata=meta("1",null);a.setController(n);
  ok(n.keys.isEmpty()&&n.controls.calls==0,"attach is read only");ok(snapshot(a).optBoolean("canNext")&&snapshot(a).optBoolean("canSeek"),"zero actions capability");
  String[] actions={"next","previous","play","pause","toggle-play"};int[] codes={87,88,126,127,127};
  for(int i=0;i<actions.length;i++){int k=n.keys.size();ok(a.command(actions[i]),"button accepted");ok(n.keys.size()==k+2&&n.keys.get(k).action==0&&n.keys.get(k+1).action==1&&n.keys.get(k+1).key==codes[i],"targeted down/up mapping");}
  n.state.state=2;ok(a.command("toggle-play")&&n.keys.get(n.keys.size()-1).key==126,"paused toggle plays");n.state=null;ok(a.command("toggle-play")&&n.keys.get(n.keys.size()-1).key==85,"unknown toggle");
  ok(a.command("seek",65432)&&n.controls.last==65432,"seek milliseconds unchanged");ok(a.command("seek",999999)&&n.controls.last==180000,"seek duration clamp");int calls=n.controls.calls;ok(!a.command("seek",-1)&&n.controls.calls==calls,"negative seek rejected");ok(!a.command("unknown"),"unknown command rejected");
  n.metadata.m.put(MediaMetadata.METADATA_KEY_DURATION,0L);ok(a.command("seek",Long.MAX_VALUE)&&n.controls.last==(long)Integer.MAX_VALUE*1000L,"seek integer seconds overflow bounded");n.flags=0;int keys=n.keys.size();ok(!a.command("next")&&n.keys.size()==keys,"missing button flag no dispatch");n.flags=3;
  MediaController.Callback old=n.callback;n.callback.onSessionEvent("wt_music_lyric",lyric("1","[00:01]line",1));ok(snapshot(a).optString("lyrics").equals("[00:01]line"),"full event lyric");
  n.callback.onSessionEvent("wt_music_lyric",lyric("other","wrong",1));ok(snapshot(a).optString("lyrics").equals("[00:01]line"),"foreign song event ignored");
  Bundle line=new Bundle();line.putStringArray("lyric",new String[]{"previous","current","next"});n.callback.onSessionEvent("get_lyric_action",line);ok(snapshot(a).optString("lyricLine").equals("current"),"sentence separate from full lyrics");ok(snapshot(a).optString("lyricPrevious").equals("previous")&&snapshot(a).optString("lyricNext").equals("next"),"real neighboring lyric lines preserved");
  n.metadata=meta("2",null);n.callback.onMetadataChanged(n.metadata);ok(snapshot(a).optString("lyrics").isEmpty()&&snapshot(a).optString("lyricLine").isEmpty(),"song change clears lyrics");ok(snapshot(a).optString("lyricPrevious").isEmpty()&&snapshot(a).optString("lyricNext").isEmpty(),"song change clears neighboring lines");
  n.metadata=meta("2","[00:02]metadata");n.callback.onMetadataChanged(n.metadata);ok(snapshot(a).optString("lyrics").equals("[00:02]metadata"),"metadata lyric");n.metadata=meta("2",null);n.callback.onMetadataChanged(n.metadata);ok(snapshot(a).optString("lyrics").isEmpty(),"metadata removal clears cached metadata lyric");
  n.callback.onSessionEvent("wt_music_lyric",lyric("2","no lyric",2));ok(snapshot(a).optString("lyrics").isEmpty(),"error is not lyric text");
  MediaController q=new MediaController("com.tencent.qqmusiccar");a.setController(q);ok(q.callback==null&&!a.command("next")&&q.keys.isEmpty(),"QQ session untouched");ok(!snapshot(a).optBoolean("canNext"),"QQ snapshot untouched");
  a.setController(n);old.onSessionEvent("wt_music_lyric",lyric("2","stale",1));ok(snapshot(a).optString("lyrics").isEmpty(),"old callback ignored after same controller reattach");
  n.fail=true;ok(!a.command("next"),"dispatch exception no global retry");a.stop();ok(n.callback==null&&!a.command("next"),"stop detaches");
  System.out.println("PASS "+count+" contract assertions; JVM doubles only; no adb/control calls");
 }
}'''}
for name,body in files.items():
 p=s/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(body)
jvm=Path('/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64/bin');out=r/'jvm-classes';out.mkdir(exist_ok=True)
source=Path(__file__).resolve().parents[3]/'app/android/app/src/main/java/xyz/i4o/uni/launcher/integration/NeteaseMediaAdapter.java'
subprocess.run([str(jvm/'javac'),'-encoding','UTF-8','-d',str(out),*[str(p) for p in s.rglob('*.java')],str(source)],check=True)
subprocess.run([str(jvm/'java'),'-cp',str(out),'AdapterContractTest'],check=True)

temporary.cleanup()
