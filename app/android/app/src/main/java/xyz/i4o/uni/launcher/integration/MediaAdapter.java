package xyz.i4o.uni.launcher.integration;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSession;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.os.Handler;
import android.os.Bundle;
import android.os.SystemClock;
import org.json.JSONObject;
import org.json.JSONArray;
import xyz.i4o.uni.launcher.core.MediaSourcePolicy;
import xyz.i4o.uni.launcher.core.MediaTextRetention;
import android.graphics.Bitmap;
import android.util.Base64;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.util.List;
import java.util.ArrayList;

/** Standard MediaSession is explicitly labeled; OEM source parity still needs car verification. */
public final class MediaAdapter {
    private final Context context;
    private final MediaSessionManager manager;
    private final MediaSession steeringSession;
    private final OfficialMediaBridge officialBridge;
    private final ComponentName listener;
    private final Runnable changed;
    private final NeteaseMediaAdapter netease;
    private final LyricsResolver lyrics;
    private final Handler handler=new Handler();
    private MediaController controller;
    private boolean authorized;
    private String preferred="auto";
    private String lastSource="";
    private final android.content.SharedPreferences lastTrackPrefs;
    private String savedTrackKey="";
    private long lastTrackWriteAt;
    private final MediaTextRetention retainedTrack=new MediaTextRetention();
    private Bitmap lastCover;
    private String coverData="";
    private boolean artworkDirty=true;
    private JSONArray activeSources=new JSONArray();
    private final List<MediaController> observed=new ArrayList<>();
    /** Resolved once per source package: an OEM player can publish a session
     *  without a launcher entry, and then the UI has no app row to read a label
     *  from. Cached so a position tick never costs an IPC. */
    private String labelPackage,labelValue="";
    /** A transport callback can be accepted then ignored by a background player.
     * Remember only a play request; pause cancels the wake check. */
    private static final long PLAY_CONFIRM_MS=800;
    private Object pendingPlayToken;
    private String pendingPlaySource="";
    private int pendingPlayStage;
    private final Runnable playFallback=new Runnable(){
        public void run(){
            Object token=pendingPlayToken;if(token==null)return;
            PlaybackState state=controller==null?null:controller.getPlaybackState();
            if(state!=null&&state.getState()==PlaybackState.STATE_PLAYING){clearPlayFallback();return;}
            // Buffering/connecting is genuine progress from a live receiver.
            if(state!=null&&(state.getState()==6||state.getState()==8)){
                handler.postDelayed(this,PLAY_CONFIRM_MS);return;
            }
            boolean sameSession=controller!=null&&token.equals(controller.getSessionToken())
                    &&pendingPlaySource.equals(controller.getPackageName());
            if(pendingPlayStage==0){
                pendingPlayStage=1;launchSource(pendingPlaySource);
                handler.postDelayed(this,PLAY_CONFIRM_MS);return;
            }
            clearPlayFallback();
            if(sameSession)sendPlay(controller);
        }
    };
    private String sourceLabel(String pkg){
        if(pkg==null)return "";
        if(pkg.equals(labelPackage))return labelValue;
        labelPackage=pkg;labelValue="";
        try{
            android.content.pm.PackageManager pm=context.getPackageManager();
            CharSequence label=pm.getApplicationLabel(pm.getApplicationInfo(pkg,0));
            if(label!=null)labelValue=label.toString();
        }catch(Exception ignored){}
        return labelValue;
    }
    public void setPreferredPackage(String value){preferred=value==null||value.isEmpty()?"auto":value;start();}
    private final MediaController.Callback callback=new MediaController.Callback(){
        public void onMetadataChanged(MediaMetadata m){artworkDirty=true;choose();changed.run();}
        // choose() already synchronizes the selected source, including switches.
        public void onPlaybackStateChanged(PlaybackState s){choose();changed.run();}
        public void onExtrasChanged(Bundle extras){syncSteeringSession();changed.run();}
        public void onSessionDestroyed(){
            try{select(manager.getActiveSessions(listener));}catch(SecurityException e){authorized=false;select(null);}
            changed.run();
        }
    };
    private final MediaSessionManager.OnActiveSessionsChangedListener sessions=new MediaSessionManager.OnActiveSessionsChangedListener(){
        public void onActiveSessionsChanged(List<MediaController> list){select(list);changed.run();}
    };
    public MediaAdapter(Context context,Runnable changed){
        this.context=context;this.changed=changed;netease=new NeteaseMediaAdapter(changed);manager=(MediaSessionManager)context.getSystemService(Context.MEDIA_SESSION_SERVICE);
        lastTrackPrefs=context.getSharedPreferences("uni_last_track",Context.MODE_PRIVATE);
        lastSource=lastTrackPrefs.getString("source", "");
        lyrics=new LyricsResolver(new File(context.getFilesDir(),"media-lyrics"),changed);
        listener=new ComponentName(context,MediaAccessService.class);
        officialBridge=new OfficialMediaBridge(context,(action,source)->{
            if(controller==null||!source.equals(controller.getPackageName()))return false;
            if("play".equals(action)){setPlaying(true);return true;}
            if("pause".equals(action)){setPlaying(false);return true;}
            return command(action);
        },changed);
        steeringSession=new MediaSession(context,"UNI steering media bridge");
        steeringSession.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS|MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS);
        steeringSession.setCallback(new MediaSession.Callback(){
            @Override public void onPlay(){setPlaying(true);}
            @Override public void onPause(){setPlaying(false);}
            @Override public void onSkipToNext(){command("next");}
            @Override public void onSkipToPrevious(){command("previous");}
            @Override public void onSeekTo(long position){command("seek",position);}
        },handler);
    }
    public void start(){
        stop();
        try{manager.addOnActiveSessionsChangedListener(sessions,listener,handler);select(manager.getActiveSessions(listener));authorized=true;}
        catch(SecurityException e){authorized=false;select(null);}
        officialBridge.start();
    }
    private void select(List<MediaController> list){
        for(MediaController c:observed)c.unregisterCallback(callback);
        observed.clear();
        activeSources=new JSONArray();
        if(list!=null)for(MediaController c:list)if(!context.getPackageName().equals(c.getPackageName()))observed.add(c);
        choose();
        // Observe every session: a player's state can change without the
        // active-session list changing, including paused -> playing.
        for(MediaController c:observed)c.registerCallback(callback,handler);
    }
    private void choose(){
            activeSources=new JSONArray();
            String[] packages=new String[observed.size()];boolean[] playing=new boolean[observed.size()];
            boolean[] metadata=new boolean[observed.size()],current=new boolean[observed.size()];
            for(int i=0;i<observed.size();i++){
                MediaController c=observed.get(i);PlaybackState p=c.getPlaybackState();
                packages[i]=c.getPackageName();playing[i]=p!=null&&p.getState()==PlaybackState.STATE_PLAYING;
                MediaMetadata m=c.getMetadata();String title=m==null?null:m.getString(MediaMetadata.METADATA_KEY_TITLE);
                metadata[i]=title!=null&&!title.trim().isEmpty();
                current[i]=controller!=null&&controller.getSessionToken().equals(c.getSessionToken());
                try{activeSources.put(new JSONObject().put("package",packages[i]).put("playing",playing[i]));}catch(Exception ignored){}
            }
            int selected=MediaSourcePolicy.selectSessions(preferred,lastSource,packages,playing,metadata,current);
            MediaController next=selected>=0?observed.get(selected):null;
            if(next!=null)lastSource=next.getPackageName();
            if(next==null||controller==null||!next.getSessionToken().equals(controller.getSessionToken())){lastCover=null;coverData="";artworkDirty=true;}
            controller=next;
            netease.setController(controller);
            syncSteeringSession();
    }
    private void setPlaying(boolean play){
        PlaybackState state=controller==null?null:controller.getPlaybackState();
        boolean playing=state!=null&&state.getState()==PlaybackState.STATE_PLAYING;
        if(play!=playing)command("toggle-play");
    }
    /** Mirror the selected source into a standard active MediaSession. The
     * steering-wheel dispatcher can now target transport callbacks and the
     * instrument cluster can consume the same title/artist/playback state. */
    private void syncSteeringSession(){
        officialBridge.update(controller);
        if(controller==null){steeringSession.setActive(false);return;}
        try{
            MediaMetadata source=controller.getMetadata();
            MediaMetadata.Builder metadata=new MediaMetadata.Builder();
            if(source!=null){
                copyText(source,metadata,MediaMetadata.METADATA_KEY_TITLE);
                copyText(source,metadata,MediaMetadata.METADATA_KEY_ARTIST);
                copyText(source,metadata,MediaMetadata.METADATA_KEY_ALBUM);
                copyText(source,metadata,MediaMetadata.METADATA_KEY_DISPLAY_TITLE);
                copyText(source,metadata,MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE);
                copyText(source,metadata,MediaMetadata.METADATA_KEY_MEDIA_ID);
                long duration=source.getLong(MediaMetadata.METADATA_KEY_DURATION);if(duration>0)metadata.putLong(MediaMetadata.METADATA_KEY_DURATION,duration);
                Bitmap art=source.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART);if(art==null)art=source.getBitmap(MediaMetadata.METADATA_KEY_ART);
                if(art!=null&&!art.isRecycled())metadata.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART,art);
            }
            steeringSession.setMetadata(metadata.build());
            PlaybackState p=controller.getPlaybackState();
            long actions=PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PAUSE|PlaybackState.ACTION_PLAY_PAUSE;
            if(p!=null)actions|=p.getActions()&(PlaybackState.ACTION_SKIP_TO_NEXT|PlaybackState.ACTION_SKIP_TO_PREVIOUS|PlaybackState.ACTION_SEEK_TO);
            if(NeteaseMediaAdapter.supports(controller))actions|=PlaybackState.ACTION_SKIP_TO_NEXT|PlaybackState.ACTION_SKIP_TO_PREVIOUS|PlaybackState.ACTION_SEEK_TO;
            steeringSession.setPlaybackState(new PlaybackState.Builder().setActions(actions)
                .setState(p==null?PlaybackState.STATE_NONE:p.getState(),p==null?0:Math.max(0,p.getPosition()),p==null?0:p.getPlaybackSpeed(),SystemClock.elapsedRealtime()).build());
            Intent launch=context.getPackageManager().getLaunchIntentForPackage(controller.getPackageName());
            if(launch!=null)steeringSession.setSessionActivity(android.app.PendingIntent.getActivity(context,0,launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),android.app.PendingIntent.FLAG_UPDATE_CURRENT));
            steeringSession.setActive(true);
        }catch(Exception|LinkageError e){android.util.Log.w("UniMedia","Unable to synchronize steering media session",e);steeringSession.setActive(false);}
    }
    private static void copyText(MediaMetadata source,MediaMetadata.Builder target,String key){
        CharSequence value=source.getText(key);if(value!=null&&value.length()>0)target.putText(key,value);
    }
    public JSONObject snapshot(){
        JSONObject j=new JSONObject();try{
            j.put("authorized",authorized).put("available",controller!=null).put("playing",false).put("preferredPackage",preferred).put("sessions",activeSources)
                .put("steeringControlReady",officialBridge.snapshot().optBoolean("registered"))
                .put("instrumentMetadataReady",officialBridge.snapshot().optBoolean("playbackAccepted"))
                .put("officialMedia",officialBridge.snapshot())
                .put("reason",!authorized?"请授权媒体访问":controller==null?"所选播放器尚未建立媒体会话":"");
            if(controller!=null){
                MediaMetadata m=controller.getMetadata();PlaybackState p=controller.getPlaybackState();
                String title=m==null?"":m.getString(MediaMetadata.METADATA_KEY_TITLE);
                String artist=m==null?"":m.getString(MediaMetadata.METADATA_KEY_ARTIST);
                long duration=m==null?0:Math.max(0,m.getLong(MediaMetadata.METADATA_KEY_DURATION));
                boolean missingTitle=title==null||title.trim().isEmpty();
                MediaTextRetention.Track track=retainedTrack.update(controller.getSessionToken(),
                    p!=null&&p.getState()==PlaybackState.STATE_PAUSED,
                    new MediaTextRetention.Track(title,artist,m==null?"":m.getString(MediaMetadata.METADATA_KEY_ALBUM),duration));
                boolean restored=false;
                if(!track.known()&&missingTitle&&p!=null&&p.getState()==PlaybackState.STATE_PAUSED
                        &&controller.getPackageName().equals(lastTrackPrefs.getString("source", ""))){
                    MediaTextRetention.Track saved=new MediaTextRetention.Track(lastTrackPrefs.getString("title", ""),
                        lastTrackPrefs.getString("artist", ""),lastTrackPrefs.getString("album", ""),lastTrackPrefs.getLong("duration",0));
                    if(saved.known()){track=saved;restored=true;}
                }
                title=track.title;artist=track.artist;duration=track.durationMs;
                if(track.known()&&!missingTitle)saveTrack(controller.getPackageName(),track,position(p));
                j.put("source",controller.getPackageName()).put("sourceLabel",sourceLabel(controller.getPackageName())).put("title",title).put("artist",artist)
                    .put("collection",track.album)
                    .put("cached",restored)
                    .put("playing",p!=null&&p.getState()==PlaybackState.STATE_PLAYING);
                long actions=p==null?0:p.getActions();
                j.put("canNext",(actions&PlaybackState.ACTION_SKIP_TO_NEXT)!=0)
                    .put("canSeek",(actions&PlaybackState.ACTION_SEEK_TO)!=0)
                    .put("canPrevious",(actions&PlaybackState.ACTION_SKIP_TO_PREVIOUS)!=0)
                    .put("canToggle",p!=null&&(actions&(p.getState()==PlaybackState.STATE_PLAYING?(PlaybackState.ACTION_PAUSE|PlaybackState.ACTION_PLAY_PAUSE):(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PLAY_PAUSE)))!=0)
                    .put("artwork",missingTitle&&track.known()&&!coverData.isEmpty()?coverData:artwork(m));
                // Android has no universal lyrics contract. Take an explicit text payload
                // when the source publishes one; otherwise identify the recording from the
                // session metadata. An unmatched track stays empty, it is never guessed.
                String text=readLyrics(m,controller.getExtras());
                String source=text.isEmpty()?"":"media-session";
                if(text.isEmpty()){
                    text=lyrics.cached(title,artist,duration);
                    source=text.isEmpty()?"":"lyrics-resolver";
                    if(text.isEmpty())lyrics.request(title,artist,duration);
                }
                j.put("lyrics",text).put("lyricsSource",source)
                    .put("durationMs",duration)
                    .put("positionMs",position(p)).put("positionKnown",p!=null&&p.getPosition()>=0)
                    .put("sampledAtMs",System.currentTimeMillis())
                    .put("speed",p==null?0:p.getPlaybackSpeed());
                netease.augmentSnapshot(j);
                if(!text.isEmpty())j.put("lyricsReason","");
            } else {
                String savedSource=lastTrackPrefs.getString("source", "");
                String savedTitle=lastTrackPrefs.getString("title", "");
                boolean accepts="auto".equals(preferred)||preferred.equals(savedSource);
                if(accepts&&!savedSource.isEmpty()&&!savedTitle.isEmpty()){
                    j.put("source",savedSource).put("sourceLabel",sourceLabel(savedSource))
                        .put("title",savedTitle).put("artist",lastTrackPrefs.getString("artist", ""))
                        .put("collection",lastTrackPrefs.getString("album", ""))
                        .put("durationMs",lastTrackPrefs.getLong("duration",0))
                        .put("positionMs",lastTrackPrefs.getLong("position",0))
                        .put("positionKnown",false).put("cached",true)
                        .put("reason","播放器未连接，显示上次播放");
                }
            }
        }catch(Exception ignored){}return j;
    }
    private void saveTrack(String source,MediaTextRetention.Track track,long position){
        String key=source+"\u0000"+track.title+"\u0000"+track.artist;
        long now=SystemClock.elapsedRealtime();
        if(key.equals(savedTrackKey)&&now-lastTrackWriteAt<30_000)return;
        savedTrackKey=key;lastTrackWriteAt=now;
        lastTrackPrefs.edit().putString("source",source).putString("title",track.title)
            .putString("artist",track.artist).putString("album",track.album)
            .putLong("duration",track.durationMs).putLong("position",Math.max(0,position)).apply();
    }
    private String artwork(MediaMetadata m){
        if(!artworkDirty)return coverData;artworkDirty=false;
        if(m==null){lastCover=null;coverData="";return "";}
        Bitmap bitmap=m.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART);
        if(bitmap==null)bitmap=m.getBitmap(MediaMetadata.METADATA_KEY_ART);
        if(bitmap==lastCover)return coverData;
        lastCover=bitmap;coverData="";
        if(bitmap!=null&&!bitmap.isRecycled())try{
            float scale=Math.min(1f,256f/Math.max(bitmap.getWidth(),bitmap.getHeight()));
            Bitmap small=Bitmap.createScaledBitmap(bitmap,Math.max(1,(int)(bitmap.getWidth()*scale)),Math.max(1,(int)(bitmap.getHeight()*scale)),true);
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();small.compress(Bitmap.CompressFormat.JPEG,80,bytes);
            coverData=Base64.encodeToString(bytes.toByteArray(),Base64.NO_WRAP);
            if(small!=bitmap)small.recycle();
        }catch(RuntimeException ignored){}
        return coverData;
    }
    private static String readLyrics(MediaMetadata metadata,Bundle extras){
        String[] keys={"android.media.metadata.LYRICS","android.media.metadata.LYRIC","lyrics","lyric","lrc"};
        for(String key:keys){
            try{CharSequence value=metadata==null?null:metadata.getText(key);
                if(value!=null&&value.length()>0&&value.length()<=131072)return value.toString();
            }catch(RuntimeException ignored){}
            try{Object value=extras==null?null:extras.get(key);
                if(value instanceof CharSequence&&((CharSequence)value).length()>0&&((CharSequence)value).length()<=131072)return value.toString();
            }catch(RuntimeException ignored){}
        }
        return "";
    }
    private static long position(PlaybackState p){
        if(p==null||p.getPosition()<0)return 0;
        long value=p.getPosition();
        if(p.getState()==PlaybackState.STATE_PLAYING&&p.getLastPositionUpdateTime()>0)
            value+=(long)(Math.max(0,SystemClock.elapsedRealtime()-p.getLastPositionUpdateTime())*p.getPlaybackSpeed());
        return Math.max(0,value);
    }
    public boolean command(String action){
        return command(action,-1);
    }
    public boolean command(String action,long positionMs){
        clearPlayFallback();
        boolean wantsPlay="play".equals(action)||("toggle-play".equals(action)
                &&(controller==null||controller.getPlaybackState()==null
                    ||controller.getPlaybackState().getState()!=PlaybackState.STATE_PLAYING));
        if(controller==null){
            // A paused player may destroy its MediaSession while the launcher
            // keeps the last track visible. Play is the one command that can
            // restore the application; transport controls cannot target a
            // disconnected session.
            if("toggle-play".equals(action)||"play".equals(action))return launchSavedSource();
            return false;
        }
        if(NeteaseMediaAdapter.supports(controller)){
            boolean accepted=netease.command(action,positionMs);
            if(accepted&&wantsPlay)schedulePlayFallback(controller);
            return accepted;
        }
        PlaybackState p=controller.getPlaybackState();if(p==null)return false;
        long actions=p.getActions();MediaController.TransportControls t=controller.getTransportControls();
        if("next".equals(action)&&(actions&PlaybackState.ACTION_SKIP_TO_NEXT)!=0)t.skipToNext();
        else if("previous".equals(action)&&(actions&PlaybackState.ACTION_SKIP_TO_PREVIOUS)!=0)t.skipToPrevious();
        else if("seek".equals(action)&&positionMs>=0&&(actions&PlaybackState.ACTION_SEEK_TO)!=0){
            MediaMetadata m=controller.getMetadata();long duration=m==null?0:m.getLong(MediaMetadata.METADATA_KEY_DURATION);
            t.seekTo(duration>0?Math.min(positionMs,duration):positionMs);
        }
        else if("toggle-play".equals(action)){
            if(p.getState()==PlaybackState.STATE_PLAYING&&(actions&(PlaybackState.ACTION_PAUSE|PlaybackState.ACTION_PLAY_PAUSE))!=0)t.pause();
            else if(p.getState()!=PlaybackState.STATE_PLAYING&&(actions&(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PLAY_PAUSE))!=0)t.play();
            else return false;
        }
        else if("play".equals(action)&&(actions&(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PLAY_PAUSE))!=0)t.play();
        else return false;
        if(wantsPlay)schedulePlayFallback(controller);
        return true;
    }
    private void schedulePlayFallback(MediaController target){
        pendingPlayToken=target.getSessionToken();pendingPlaySource=target.getPackageName();pendingPlayStage=0;
        handler.removeCallbacks(playFallback);handler.postDelayed(playFallback,PLAY_CONFIRM_MS);
    }
    private void clearPlayFallback(){
        handler.removeCallbacks(playFallback);pendingPlayToken=null;pendingPlaySource="";pendingPlayStage=0;
    }
    private boolean sendPlay(MediaController target){
        if(target==null)return false;
        if(NeteaseMediaAdapter.supports(target))return netease.command("play");
        PlaybackState state=target.getPlaybackState();
        if(state==null||(state.getActions()&(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PLAY_PAUSE))==0)return false;
        target.getTransportControls().play();return true;
    }
    private boolean launchSavedSource(){
        String saved=lastTrackPrefs.getString("source","");
        return launchSource("auto".equals(preferred)||preferred.isEmpty()?saved:preferred);
    }
    private boolean launchSource(String source){
        if(source==null||source.isEmpty())return false;
        try{
            Intent launch=context.getPackageManager().getLaunchIntentForPackage(source);
            if(launch==null)return false;
            context.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            return true;
        }catch(RuntimeException e){return false;}
    }
    public void stop(){clearPlayFallback();try{manager.removeOnActiveSessionsChangedListener(sessions);}catch(Exception ignored){}officialBridge.stop();select(null);steeringSession.setActive(false);}
}
