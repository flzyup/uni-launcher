import android.content.*;
import android.media.*;
import android.media.session.*;
import xyz.i4o.uni.launcher.integration.*;
import java.util.*;

/** Production MediaAdapter + NetEase adapter; bridge double counts deliveries. */
public final class MediaPlaybackSyncTest {
    private static int checks;
    private static void check(boolean ok,String message){checks++;if(!ok)throw new AssertionError(message);}
    private static void playback(MediaController source){source.emitPlayback();}
    public static void main(String[] args)throws Exception{
        Context app=new Context();int[] changes={0};
        MediaController qq=new MediaController("com.tencent.qqmusiccar"),netease=new MediaController(NeteaseMediaAdapter.PACKAGE);
        qq.state.state=PlaybackState.STATE_PLAYING;netease.state.state=PlaybackState.STATE_PAUSED;
        app.sessions.active=Arrays.asList(qq,netease,new MediaController(app.getPackageName()));
        MediaAdapter adapter=new MediaAdapter(app,()->changes[0]++);adapter.start();
        MediaSession mirror=MediaSession.last;OfficialMediaBridge bridge=OfficialMediaBridge.last;
        check(adapter.snapshot().getString("source").equals(qq.pkg),"playing QQ selected on attach");
        check(bridge.starts==1&&app.sessions.adds==1,"one normal registration on start");
        check(qq.controls.total()==0&&netease.keys.isEmpty(),"attach sends no transport commands");
        check(app.sessions.active.get(2).callbacks.isEmpty(),"own mirror excluded from observed sessions");
        int updates=bridge.updates,metadata=mirror.metadataWrites,states=mirror.stateWrites,notifications=changes[0];
        for(int i=0;i<100;i++)playback(qq);
        check(bridge.updates-updates==100,"100 playback callbacks deliver exactly 100 OEM updates, not 200");
        check(mirror.metadataWrites-metadata==100&&mirror.stateWrites-states==100,"one mirror synchronization per callback");
        check(changes[0]-notifications==100,"one change notification per playback callback");
        check(bridge.starts==1&&app.sessions.adds==1,"callbacks do not re-register media");
        updates=bridge.updates;qq.emitMetadata();check(bridge.updates==updates+1,"metadata still synchronizes once");
        updates=bridge.updates;qq.emitExtras();check(bridge.updates==updates+1,"extras still synchronize once");
        qq.state.state=PlaybackState.STATE_PAUSED;netease.state.state=PlaybackState.STATE_PLAYING;
        updates=bridge.updates;playback(netease);
        check(adapter.snapshot().getString("source").equals(netease.pkg)&&bridge.selected==netease,"playback callback reselects newly playing source before sync");
        check(bridge.updates==updates+1,"source switch synchronizes once");
        check(mirror.active,"steering session remains active");
        mirror.callback.onSkipToNext();
        check(netease.keys.size()==2&&netease.keys.get(1).key==87,"steering next retains targeted NetEase DOWN/UP");
        mirror.callback.onSeekTo(12345);check(netease.controls.seek==12345,"NetEase steering seek retains milliseconds");
        adapter.setPreferredPackage(qq.pkg);
        check(adapter.snapshot().getString("source").equals(qq.pkg),"explicit QQ selection preserved even paused");
        updates=bridge.updates;playback(netease);
        check(adapter.snapshot().getString("source").equals(qq.pkg)&&bridge.updates==updates+1,"other source callback cannot steal explicit selection");
        mirror.callback.onSkipToNext();mirror.callback.onSkipToPrevious();mirror.callback.onPlay();mirror.callback.onSeekTo(34567);
        check(qq.controls.next==1&&qq.controls.previous==1&&qq.controls.play==1&&qq.controls.seek==34567,"QQ steering controls still target selected session");
        check(adapter.snapshot().getString("title").equals("Track "+qq.pkg),"selected song metadata retained");
        app.sessions.active=Collections.emptyList();updates=bridge.updates;app.sessions.listener.onActiveSessionsChanged(app.sessions.active);
        check(!adapter.snapshot().getBoolean("available")&&!mirror.active&&bridge.selected==null,"session removal deactivates mirror");
        check(bridge.updates==updates+1,"empty selection synchronized once");
        check(qq.callbacks.isEmpty()&&netease.callbacks.isEmpty(),"removed sources detach callbacks");
        adapter.stop();check(app.sessions.listener==null&&!mirror.active,"stop removes active-session listener");
        Context denied=new Context();denied.sessions.denied=true;MediaAdapter unavailable=new MediaAdapter(denied,()->{});unavailable.start();
        check(!unavailable.snapshot().getBoolean("authorized")&&!MediaSession.last.active,"missing media permission fails closed");unavailable.stop();
        System.out.println("PASS MediaPlaybackSyncTest: "+checks+" checks; 100 playback callbacks = 100 synchronizations; QQ/NetEase steering regression passed");
    }
}
