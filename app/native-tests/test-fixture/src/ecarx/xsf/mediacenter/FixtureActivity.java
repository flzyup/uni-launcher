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
    /** Heart rating published in the metadata: the launcher's capability probe reads it. */
    private static boolean favorited=false;
    /** Play mode in the NetEase car-side encoding: 1 = sequential, 2 = shuffle, 3 = repeat one. */
    private static int playMode=1;
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
                /** Standard favorite channel: the launcher sends a heart rating here. */
                public void onSetRating(android.media.Rating rating){
                    if(rating==null||rating.getRatingStyle()!=android.media.Rating.RATING_HEART)return;
                    favorited=rating.hasHeart();update();
                }
                /** Standard custom-action channel: play mode and the NetEase action names. */
                public void onCustomAction(String action,android.os.Bundle extras){
                    if(action==null||extras==null)return;
                    if("star_action".equals(action)){
                        favorited=extras.getBoolean("is_star",favorited);update();
                        android.os.Bundle reply=new android.os.Bundle();
                        reply.putInt("code",0);reply.putString("message","操作成功");
                        session.sendSessionEvent("star_action",reply);
                    }else if("play_mode_action".equals(action)){
                        playMode=extras.getInt("play_mode",playMode);update();
                    }else if("get_play_mode_action".equals(action)){
                        android.os.Bundle reply=new android.os.Bundle();
                        reply.putInt("play_mode",playMode);
                        session.sendSessionEvent("get_play_mode_action",reply);
                    }
                }
            });
        }
        session.setActive(true);update();
    }
    private static long position(){return positionMs+(playing?Math.max(0,android.os.SystemClock.elapsedRealtime()-sampledAt):0);}
    private static void update(){
        android.graphics.Bitmap cover=android.graphics.Bitmap.createBitmap(16,16,android.graphics.Bitmap.Config.ARGB_8888);cover.eraseColor(0xff4b92de);
        android.media.MediaMetadata.Builder metadata=new android.media.MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE,track==0?"<img src=x onerror=window.injected=true>":"Fixture track "+track)
            .putString(MediaMetadata.METADATA_KEY_ARTIST,"UNI test artist").putString(MediaMetadata.METADATA_KEY_ALBUM,"Synthetic media session")
            .putString("android.media.metadata.LYRICS","[00:00.00]Fixture lyric first\n[00:03.00]Fixture lyric second\n[00:06.00]Fixture lyric third")
            .putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART,cover).putLong(MediaMetadata.METADATA_KEY_DURATION,180000);
        // The heart rating is what the launcher's runtime probe looks for: a session that
        // publishes it speaks the standard favorite semantics.
        metadata.putRating(MediaMetadata.METADATA_KEY_USER_RATING,android.media.Rating.newHeartRating(favorited));
        session.setMetadata(metadata.build());
        session.setPlaybackState(new PlaybackState.Builder().setActions(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PAUSE|PlaybackState.ACTION_SKIP_TO_NEXT|PlaybackState.ACTION_SKIP_TO_PREVIOUS|PlaybackState.ACTION_SEEK_TO)
            .setState(playing?PlaybackState.STATE_PLAYING:PlaybackState.STATE_PAUSED,position(),1).build());
    }
}
