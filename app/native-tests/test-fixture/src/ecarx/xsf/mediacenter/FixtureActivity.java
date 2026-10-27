package ecarx.xsf.mediacenter;

import android.app.Activity;
import android.os.Bundle;
import android.media.MediaMetadata;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.widget.TextView;

/** Synthetic source. Installed ONLY by tools/build-fixture.py onto an emulator. */
public final class FixtureActivity extends Activity {
    private static MediaSession session;
    private static boolean playing=true;
    private static int track=0;
    private static long positionMs=1000,sampledAt=android.os.SystemClock.elapsedRealtime();
    public void onCreate(Bundle saved){
        super.onCreate(saved);TextView t=new TextView(this);t.setText("UNI emulator test source — not OEM software");t.setTextSize(24);setContentView(t);
        startService(new android.content.Intent(this,FixtureMediaService.class));
    }
    static void ensureSession(android.content.Context context){
        if(session==null){
            session=new MediaSession(context,"UniEmulatorFixture");
            session.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS|MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS);
            session.setCallback(new MediaSession.Callback(){
                public void onPlay(){positionMs=position();playing=true;sampledAt=android.os.SystemClock.elapsedRealtime();update();}
                public void onPause(){positionMs=position();playing=false;sampledAt=android.os.SystemClock.elapsedRealtime();update();}
                public void onSkipToNext(){track++;positionMs=1000;sampledAt=android.os.SystemClock.elapsedRealtime();update();}
                public void onSkipToPrevious(){track--;positionMs=1000;sampledAt=android.os.SystemClock.elapsedRealtime();update();}
                public void onSeekTo(long at){positionMs=Math.max(0,Math.min(180000,at));sampledAt=android.os.SystemClock.elapsedRealtime();update();}
            });
        }
        session.setActive(true);update();
    }
    private static long position(){return positionMs+(playing?Math.max(0,android.os.SystemClock.elapsedRealtime()-sampledAt):0);}
    private static void update(){
        android.graphics.Bitmap cover=android.graphics.Bitmap.createBitmap(16,16,android.graphics.Bitmap.Config.ARGB_8888);cover.eraseColor(0xff4b92de);
        session.setMetadata(new MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE,track==0?"<img src=x onerror=window.injected=true>":"Fixture track "+track)
            .putString(MediaMetadata.METADATA_KEY_ARTIST,"UNI test artist").putString(MediaMetadata.METADATA_KEY_ALBUM,"Synthetic media session")
            .putString("android.media.metadata.LYRICS","[00:00.00]Fixture lyric first\n[00:03.00]Fixture lyric second\n[00:06.00]Fixture lyric third")
            .putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART,cover).putLong(MediaMetadata.METADATA_KEY_DURATION,180000).build());
        session.setPlaybackState(new PlaybackState.Builder().setActions(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PAUSE|PlaybackState.ACTION_SKIP_TO_NEXT|PlaybackState.ACTION_SKIP_TO_PREVIOUS|PlaybackState.ACTION_SEEK_TO)
            .setState(playing?PlaybackState.STATE_PLAYING:PlaybackState.STATE_PAUSED,position(),1).build());
    }
}
