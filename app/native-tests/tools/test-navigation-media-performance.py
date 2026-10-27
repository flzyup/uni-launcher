#!/usr/bin/env python3
"""Run production Java adapters with counting JVM doubles and compile against API 28.

No device, installation, playback control or Flutter build. Requires the existing
local JDK/Android SDK and org.json test dependency (or --json-jar).
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
JAVA = Path('/data/tools/linkco-android/java-runtime/usr/lib/jvm/java-17-openjdk-amd64/bin')
SDK = Path('/data/tools/linkco-android/sdk')
INTEGRATION = ROOT / 'app/android/app/src/main/java/xyz/i4o/uni/launcher/integration'
CORE = ROOT / 'app/android/app/src/main/java/xyz/i4o/uni/launcher/core/MediaSourcePolicy.java'
STUBS = {
'android/content/Context.java': '''package android.content;
import android.content.pm.*;import android.content.res.*;import android.media.session.*;import java.util.*;
public class Context {
 public static final String MEDIA_SESSION_SERVICE="media";
 public final Context app; public final PackageManager pm;public final SharedPreferences prefs;public final Resources resources;public final MediaSessionManager sessions;
 public int permission=0,registrations,launches;private final List<BroadcastReceiver> receivers=new ArrayList<>();private final List<IntentFilter> filters=new ArrayList<>();
 public Context(){app=this;pm=new PackageManager();prefs=new SharedPreferences();resources=new Resources();sessions=new MediaSessionManager();}
 public Context(Context a){app=a;pm=a.pm;prefs=a.prefs;resources=a.resources;sessions=a.sessions;}
 public Context getApplicationContext(){return app;}public PackageManager getPackageManager(){return pm;}public Resources getResources(){return resources;}
 public int checkSelfPermission(String p){return app.permission;}public String getPackageName(){return "xyz.i4o.uni.launcher";}public Object getSystemService(String s){return sessions;}
 public Intent registerReceiver(BroadcastReceiver r,IntentFilter f){registrations++;receivers.add(r);filters.add(f);return null;}
 public void broadcast(String action,String pkg){Intent i=new Intent(action);i.data=android.net.Uri.parse("package:"+pkg);for(int n=0;n<receivers.size();n++){IntentFilter f=filters.get(n);if(f.actions.contains(action)&&f.scheme.equals("package"))receivers.get(n).onReceive(this,i);}}
 public void startActivity(Intent i){launches++;}
}''',
'android/content/SharedPreferences.java': '''package android.content;import java.util.*;public class SharedPreferences {private final Map<String,Object> data=new HashMap<>();public void put(String k,Object v){data.put(k,v);}public String getString(String k,String d){return data.containsKey(k)?(String)data.get(k):d;}public boolean getBoolean(String k,boolean d){return data.containsKey(k)?(Boolean)data.get(k):d;}}''',
'android/content/Intent.java': '''package android.content;import android.net.Uri;public class Intent {
 public static final String ACTION_PACKAGE_ADDED="added",ACTION_PACKAGE_REMOVED="removed",ACTION_PACKAGE_CHANGED="changed",ACTION_PACKAGE_REPLACED="replaced",ACTION_VIEW="view";
 public static final int FLAG_ACTIVITY_NEW_TASK=0x10000000,FLAG_ACTIVITY_CLEAR_TOP=0x04000000,FLAG_ACTIVITY_SINGLE_TOP=0x20000000;
 public int flags;public String action,pkg;public ComponentName component;public Uri data;
 public Intent(){}public Intent(String a){action=a;}public Intent(String a,Uri u){action=a;data=u;}public Intent(Intent i){flags=i.flags;action=i.action;pkg=i.pkg;component=i.component;data=i.data;}
 public Intent setPackage(String p){pkg=p;return this;}public Intent setComponent(ComponentName c){component=c;return this;}public Intent addFlags(int f){flags|=f;return this;}
}''',
'android/content/IntentFilter.java': '''package android.content;import java.util.*;public class IntentFilter {public final List<String> actions=new ArrayList<>();public String scheme;public void addAction(String a){actions.add(a);}public void addDataScheme(String s){scheme=s;}}''',
'android/content/BroadcastReceiver.java': '''package android.content;public abstract class BroadcastReceiver {public abstract void onReceive(Context c,Intent i);}''',
'android/content/ComponentName.java': '''package android.content;public class ComponentName {private final String pkg,name;public ComponentName(String p,String n){pkg=p;name=n;}public ComponentName(Context c,Class<?> t){this(c.getPackageName(),t.getName());}public String getPackageName(){return pkg;}public String getClassName(){return name;}}''',
'android/content/pm/PackageManager.java': '''package android.content.pm;import java.util.*;import android.content.*;public class PackageManager {
 public static final int PERMISSION_GRANTED=0,MATCH_DEFAULT_ONLY=65536;public int launchQueries,labelQueries,infoQueries,resolveQueries;
 public final Map<String,String> labels=new LinkedHashMap<>();public final Set<String> disabled=new HashSet<>();public ActivityInfo directInfo;
 public void install(String p,String label){labels.put(p,label);}public void remove(String p){labels.remove(p);}public int totalQueries(){return launchQueries+labelQueries+infoQueries+resolveQueries;}
 public Intent getLaunchIntentForPackage(String p){launchQueries++;return labels.containsKey(p)&&!disabled.contains(p)?new Intent().setComponent(new ComponentName(p,"Main")):null;}
 public ApplicationInfo getApplicationInfo(String p,int f)throws Exception{infoQueries++;if(!labels.containsKey(p))throw new Exception("missing");ApplicationInfo i=new ApplicationInfo();i.packageName=p;return i;}
 public CharSequence getApplicationLabel(ApplicationInfo i){labelQueries++;return labels.get(i.packageName);}
 public ResolveInfo resolveActivity(Intent i,int flags){resolveQueries++;if(directInfo==null)return null;ResolveInfo r=new ResolveInfo();r.activityInfo=directInfo;return r;}
}''',
'android/content/pm/ApplicationInfo.java': '''package android.content.pm;public class ApplicationInfo {public boolean enabled=true;public String packageName;}''',
'android/content/pm/ActivityInfo.java': '''package android.content.pm;public class ActivityInfo {public String packageName,name,permission;public boolean exported=true,enabled=true;public ApplicationInfo applicationInfo=new ApplicationInfo();}''',
'android/content/pm/ResolveInfo.java': '''package android.content.pm;public class ResolveInfo {public ActivityInfo activityInfo;}''',
'android/content/res/Resources.java': '''package android.content.res;public class Resources {public final Configuration configuration=new Configuration();public Configuration getConfiguration(){return configuration;}}''',
'android/content/res/Configuration.java': '''package android.content.res;public class Configuration {public String locales="zh-CN";public android.os.LocaleList getLocales(){return new android.os.LocaleList(locales);}}''',
'android/os/LocaleList.java': '''package android.os;public class LocaleList {private final String tags;public LocaleList(String t){tags=t;}public String toLanguageTags(){return tags;}}''',
'android/net/Uri.java': '''package android.net;public class Uri {public static Uri parse(String s){return new Uri();}}''',
'android/os/Build.java': '''package android.os;public class Build {public static class VERSION {public static int SDK_INT=28;}}''',
'android/os/Handler.java': '''package android.os;public class Handler {public Handler(){}public Handler(Looper l){}}''',
'android/os/Looper.java': '''package android.os;public class Looper {public static Looper getMainLooper(){return new Looper();}}''',
'android/os/SystemClock.java': '''package android.os;public class SystemClock {public static long elapsedRealtime(){return System.nanoTime()/1000000;}public static long uptimeMillis(){return elapsedRealtime();}}''',
'android/os/Bundle.java': '''package android.os;import java.util.*;public class Bundle {private final Map<String,Object> values=new HashMap<>();public Object get(String k){return values.get(k);}public String getString(String k){return (String)get(k);}public int getInt(String k,int d){Object v=get(k);return v==null?d:(Integer)v;}public String[] getStringArray(String k){return (String[])get(k);}}''',
'android/app/PendingIntent.java': '''package android.app;import android.content.*;public class PendingIntent {public static final int FLAG_UPDATE_CURRENT=1;public static PendingIntent getActivity(Context c,int code,Intent i,int f){return new PendingIntent();}}''',
'android/graphics/Bitmap.java': '''package android.graphics;import java.io.*;public class Bitmap {public enum CompressFormat {JPEG}public boolean isRecycled(){return false;}public int getWidth(){return 128;}public int getHeight(){return 128;}public static Bitmap createScaledBitmap(Bitmap b,int w,int h,boolean f){return b;}public boolean compress(CompressFormat f,int q,OutputStream out){return true;}public void recycle(){}}''',
'android/util/Base64.java': '''package android.util;public class Base64 {public static final int NO_WRAP=2;public static String encodeToString(byte[] b,int flags){return java.util.Base64.getEncoder().encodeToString(b);}}''',
'android/util/Log.java': '''package android.util;public class Log {public static int w(String t,String s,Throwable e){return 0;}public static int i(String t,String s,Throwable e){return 0;}}''',
'android/view/KeyEvent.java': '''package android.view;public class KeyEvent {public static final int ACTION_DOWN=0,ACTION_UP=1,KEYCODE_MEDIA_NEXT=87,KEYCODE_MEDIA_PREVIOUS=88,KEYCODE_MEDIA_PLAY=126,KEYCODE_MEDIA_PAUSE=127,KEYCODE_MEDIA_PLAY_PAUSE=85;public final int key,action;public KeyEvent(long d,long t,int a,int k,int r){key=k;action=a;}}''',
'android/media/MediaMetadata.java': '''package android.media;import java.util.*;import android.graphics.Bitmap;public class MediaMetadata {
 public static final String METADATA_KEY_TITLE="title",METADATA_KEY_ARTIST="artist",METADATA_KEY_ALBUM="album",METADATA_KEY_DURATION="duration",METADATA_KEY_DISPLAY_TITLE="display-title",METADATA_KEY_DISPLAY_SUBTITLE="subtitle",METADATA_KEY_MEDIA_ID="id",METADATA_KEY_ALBUM_ART="album-art",METADATA_KEY_ART="art";
 private final Map<String,Object> values=new HashMap<>();public String getString(String k){return (String)values.get(k);}public CharSequence getText(String k){return (CharSequence)values.get(k);}public Bitmap getBitmap(String k){return (Bitmap)values.get(k);}public long getLong(String k){Object v=values.get(k);return v instanceof Number?((Number)v).longValue():0;}
 public static class Builder {private final MediaMetadata m=new MediaMetadata();public Builder putText(String k,CharSequence v){m.values.put(k,v);return this;}public Builder putLong(String k,long v){m.values.put(k,v);return this;}public Builder putBitmap(String k,Bitmap v){m.values.put(k,v);return this;}public MediaMetadata build(){return m;}}
}''',
'android/media/session/PlaybackState.java': '''package android.media.session;public class PlaybackState {
 public static final int STATE_NONE=0,STATE_PAUSED=2,STATE_PLAYING=3;public static final long ACTION_PLAY=1,ACTION_PAUSE=2,ACTION_PLAY_PAUSE=4,ACTION_SKIP_TO_NEXT=8,ACTION_SKIP_TO_PREVIOUS=16,ACTION_SEEK_TO=32;
 public int state=STATE_PLAYING;public long actions=63,position=5000;public int getState(){return state;}public long getActions(){return actions;}public long getPosition(){return position;}public float getPlaybackSpeed(){return 1;}public long getLastPositionUpdateTime(){return 0;}
 public static class Builder {private final PlaybackState p=new PlaybackState();public Builder setActions(long a){p.actions=a;return this;}public Builder setState(int s,long position,float speed,long t){p.state=s;p.position=position;return this;}public PlaybackState build(){return p;}}
}''',
'android/media/session/MediaSession.java': '''package android.media.session;import android.content.Context;import android.media.*;import android.os.*;public class MediaSession {
 public static final int FLAG_HANDLES_MEDIA_BUTTONS=1,FLAG_HANDLES_TRANSPORT_CONTROLS=2;public static MediaSession last;public int metadataWrites,stateWrites;public boolean active;public Callback callback;
 public MediaSession(Context c,String t){last=this;}public void setFlags(int f){}public void setCallback(Callback c,Handler h){callback=c;}public void setMetadata(MediaMetadata m){metadataWrites++;}public void setPlaybackState(PlaybackState p){stateWrites++;}public void setSessionActivity(android.app.PendingIntent p){}public void setActive(boolean a){active=a;}
 public static class Callback {public void onPlay(){}public void onPause(){}public void onSkipToNext(){}public void onSkipToPrevious(){}public void onSeekTo(long p){}}
}''',
'android/media/session/MediaController.java': '''package android.media.session;import java.util.*;import android.media.*;import android.os.*;import android.view.KeyEvent;public class MediaController {
 public final String pkg;public PlaybackState state=new PlaybackState();public MediaMetadata metadata;public final TransportControls controls=new TransportControls();public final List<Callback> callbacks=new ArrayList<>();public final List<KeyEvent> keys=new ArrayList<>();
 public MediaController(String p){pkg=p;metadata=new MediaMetadata.Builder().putText(MediaMetadata.METADATA_KEY_TITLE,"Track "+p).putText(MediaMetadata.METADATA_KEY_ARTIST,"Artist").putLong(MediaMetadata.METADATA_KEY_DURATION,180000).build();}
 public String getPackageName(){return pkg;}public PlaybackState getPlaybackState(){return state;}public MediaMetadata getMetadata(){return metadata;}public Bundle getExtras(){return new Bundle();}public long getFlags(){return 3;}public TransportControls getTransportControls(){return controls;}public boolean dispatchMediaButtonEvent(KeyEvent e){keys.add(e);return true;}
 public void registerCallback(Callback c,Handler h){callbacks.add(c);}public void unregisterCallback(Callback c){callbacks.remove(c);}public void emitPlayback(){for(Callback c:new ArrayList<>(callbacks))c.onPlaybackStateChanged(state);}public void emitMetadata(){for(Callback c:new ArrayList<>(callbacks))c.onMetadataChanged(metadata);}public void emitExtras(){for(Callback c:new ArrayList<>(callbacks))c.onExtrasChanged(new Bundle());}
 public static class Callback {public void onMetadataChanged(MediaMetadata m){}public void onPlaybackStateChanged(PlaybackState s){}public void onExtrasChanged(Bundle b){}public void onSessionDestroyed(){}public void onSessionEvent(String e,Bundle b){}}
 public static class TransportControls {public int next,previous,play,pause;public long seek=-1;public void skipToNext(){next++;}public void skipToPrevious(){previous++;}public void play(){play++;}public void pause(){pause++;}public void seekTo(long p){seek=p;}public int total(){return next+previous+play+pause+(seek<0?0:1);}}
}''',
'android/media/session/MediaSessionManager.java': '''package android.media.session;import android.content.*;import android.os.*;import java.util.*;public class MediaSessionManager {
 public boolean denied;public int adds;public List<MediaController> active=new ArrayList<>();public OnActiveSessionsChangedListener listener;
 public interface OnActiveSessionsChangedListener {void onActiveSessionsChanged(List<MediaController> list);}public void addOnActiveSessionsChangedListener(OnActiveSessionsChangedListener l,ComponentName c,Handler h){if(denied)throw new SecurityException();adds++;listener=l;}public List<MediaController> getActiveSessions(ComponentName c){if(denied)throw new SecurityException();return active;}public void removeOnActiveSessionsChangedListener(OnActiveSessionsChangedListener l){if(listener==l)listener=null;}
}''',
'xyz/i4o/uni/launcher/integration/OfficialMediaBridge.java': '''package xyz.i4o.uni.launcher.integration;import android.content.*;import android.media.session.*;import org.json.*;public class OfficialMediaBridge {
 public interface Commands {boolean send(String action,String source);}public static OfficialMediaBridge last;public int updates,starts,stops;public MediaController selected;public OfficialMediaBridge(Context c,Commands commands,Runnable changed){last=this;}public void update(MediaController c){updates++;selected=c;}public void start(){starts++;}public void stop(){stops++;}public JSONObject snapshot(){return new JSONObject();}
}''',
'xyz/i4o/uni/launcher/integration/MediaAccessService.java': '''package xyz.i4o.uni.launcher.integration;public final class MediaAccessService {}''',
}

def run(command, **kwargs):
    return subprocess.run(list(map(str, command)), check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json-jar', type=Path)
    parser.add_argument('--prove-regressions', action='store_true', help='also require pre-change HEAD adapters to fail the new behavioral tests')
    args = parser.parse_args()
    jars = sorted((Path.home()/'.gradle/caches/modules-2/files-2.1/org.json/json').glob('*/*/json-*.jar'))
    json_jar = args.json_jar or (jars[-1] if jars else None)
    if not json_jar or not json_jar.is_file():
        parser.error('org.json jar required; supply --json-jar')
    with tempfile.TemporaryDirectory(prefix='uni-navigation-media-') as directory:
        temp = Path(directory)
        doubles = temp/'doubles'
        for name, body in STUBS.items():
            path = doubles/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body)
        sources = [*doubles.rglob('*.java'), CORE, INTEGRATION/'NeteaseMediaAdapter.java']
        tests = ROOT/'app/native-tests/test-performance'
        adapters = [INTEGRATION/'NavigationApps.java', INTEGRATION/'MediaAdapter.java']
        out = temp/'classes';out.mkdir()
        run([JAVA/'javac', '-encoding', 'UTF-8', '-cp', json_jar, '-d', out, *sources, *adapters, *tests.glob('*.java')])
        for test in ['NavigationAppsCacheTest', 'MediaPlaybackSyncTest']:
            run([JAVA/'java', '-cp', f'{out}:{json_jar}', test])
        if args.prove_regressions:
            baseline = temp/'baseline';baseline.mkdir()
            for adapter, test in zip(adapters, ['NavigationAppsCacheTest', 'MediaPlaybackSyncTest']):
                original = baseline/adapter.name
                original.write_bytes(subprocess.check_output(['git', 'show', f'HEAD:{adapter.relative_to(ROOT)}'], cwd=ROOT))
                old_out = baseline/test;old_out.mkdir()
                other = [p for p in adapters if p != adapter]
                run([JAVA/'javac', '-encoding', 'UTF-8', '-cp', json_jar, '-d', old_out, *sources, *other, original, tests/f'{test}.java'])
                result = subprocess.run([str(JAVA/'java'), '-cp', f'{old_out}:{json_jar}', test], text=True, capture_output=True)
                expected = 'each candidate queried once' if test.startswith('Navigation') else '100 playback callbacks deliver exactly 100'
                if result.returncode == 0 or expected not in result.stderr:
                    raise AssertionError(f'Unexpected baseline result for {test}: {result.stdout}{result.stderr}')
                print(f'PASS regression sensitivity: HEAD {adapter.name} fails at "{expected}"', flush=True)
        # Verify real platform signatures independently of the doubles.
        platform = SDK/'platforms/android-9/android.jar'
        actual = temp/'android-classes';actual.mkdir()
        # API 28's android.jar intentionally lacks LambdaMetafactory bodies.
        # Use Java 8 bootstrap symbols for javac's lambdas, Android API 28 for
        # Android signatures, then let D8 desugar for the production min SDK.
        run([JAVA/'javac', '--release', '8', '-encoding', 'UTF-8', '-cp', platform, '-d', actual,
             *adapters, INTEGRATION/'NeteaseMediaAdapter.java', INTEGRATION/'OfficialMediaBridge.java', INTEGRATION/'MediaAccessService.java', CORE])
        dex = temp/'dex';dex.mkdir()
        run([JAVA/'java', '-cp', SDK/'cmdline-tools/latest/lib/r8.jar', 'com.android.tools.r8.D8', '--min-api', '24', '--lib', platform, '--output', dex, *actual.rglob('*.class')])
        print('PASS real Android API 28 compilation + D8 (min API 24); no device accessed', flush=True)

if __name__ == '__main__':
    main()
