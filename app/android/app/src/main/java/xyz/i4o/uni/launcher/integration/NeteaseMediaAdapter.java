package xyz.i4o.uni.launcher.integration;

import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.KeyEvent;
import org.json.JSONObject;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/**
 * NetEase IoT session compatibility, verified against 6.2.81 (6002081).
 * Its PlaybackState omits setActions(), although the callbacks are implemented.
 * Call setController after selecting a session, augmentSnapshot after the standard
 * snapshot, command before the standard actions-bit guard, and stop on shutdown.
 * Other packages (including QQ) are never registered or controlled here.
 * Use on the main thread. Attaching only observes; it sends no custom actions.
 */
public final class NeteaseMediaAdapter {
    public static final String PACKAGE = "com.netease.cloudmusic.iot";
    public static final String LYRIC_KEY = "android.media.metadata.LYRIC";
    private static final int MAX_LYRIC_LENGTH = 131072;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Runnable changed;
    private MediaController controller;
    private MediaController.Callback callback;
    private String track = "", mediaId = "", lyrics = "", lyricsSource = "", lyricLine = "", lyricPrevious = "", lyricNext = "";

    public NeteaseMediaAdapter(Runnable changed) { this.changed = changed; }

    public static boolean supports(MediaController candidate) {
        return candidate != null && PACKAGE.equals(candidate.getPackageName());
    }

    /** Does not start the player, change its UI, or enable its lyric preference. */
    public void setController(final MediaController candidate) {
        MediaController next = supports(candidate) ? candidate : null;
        if (controller == next) return;
        String previous = controller == null ? "" : controller.getPackageName();
        stop();
        if (next == null) {
            if (!previous.isEmpty()) UniLog.i(LogTags.MEDIA, "网易云会话已释放", "previous", previous);
            return;
        }
        controller = next;
        UniLog.i(LogTags.MEDIA, "网易云会话已接管", "source", next.getPackageName(), "previous", previous);
        callback = new MediaController.Callback() {
            @Override public void onMetadataChanged(MediaMetadata metadata) {
                if (controller != candidate || callback != this) return;
                readMetadata(metadata);
                notifyChanged();
            }
            @Override public void onSessionEvent(String event, Bundle extras) {
                if (controller != candidate || callback != this || extras == null) return;
                try {
                    if ("wt_music_lyric".equals(event)) {
                        String eventId = text(extras.getString(MediaMetadata.METADATA_KEY_MEDIA_ID));
                        if (!eventId.isEmpty() && !mediaId.isEmpty() && !eventId.equals(mediaId)) return;
                        // State 1 contains lyrics; other states are loading/error messages.
                        if (extras.getInt("wt_music_lyric_state", -1) == 1) {
                            setLyrics(extras.getString("wt_music_lyric_obj"), "netease-session-event");
                        } else {
                            clearLyrics();
                        }
                    } else if ("get_lyric_action".equals(event)) {
                        String[] lines = extras.getStringArray("lyric");
                        String nextLine = lines != null && lines.length > 1 ? text(lines[1]) : "";
                        String nextPrev = lines != null && lines.length > 0 ? text(lines[0]) : "";
                        String nextNext = lines != null && lines.length > 2 ? text(lines[2]) : "";
                        if (isLoadingOrEmpty(nextLine)) nextLine = "";
                        if (nextLine.equals(lyricLine) && nextPrev.equals(lyricPrevious) && nextNext.equals(lyricNext)) return;
                        lyricLine = nextLine;
                        lyricPrevious = nextPrev;
                        lyricNext = nextNext;
                    } else if ("lyric_loading_action".equals(event)
                            || "lyric_message_action".equals(event)) {
                        clearLyrics();
                    } else return;
                } catch (RuntimeException malformedPayload) { return; }
                notifyChanged();
            }
            @Override public void onSessionDestroyed() {
                if (controller != candidate || callback != this) return;
                stop();
                notifyChanged();
            }
        };
        try {
            controller.registerCallback(callback, handler);
            readMetadata(controller.getMetadata());
        } catch (RuntimeException unavailableSession) { stop(); }
    }

    /** Overlay only this player's compatibility capabilities and actual lyric text. */
    public void augmentSnapshot(JSONObject snapshot) {
        if (!supports(controller)) return;
        try {
            boolean buttons = (controller.getFlags() & MediaSession.FLAG_HANDLES_MEDIA_BUTTONS) != 0;
            snapshot.put("canNext", buttons).put("canPrevious", buttons)
                    .put("canToggle", buttons).put("canSeek", true)
                    .put("controlSource", "netease-targeted-session");
            if (!lyrics.isEmpty()) snapshot.put("lyrics", lyrics).put("lyricsSource", lyricsSource);
            // A current sentence is not fabricated into a complete timed LRC document.
            snapshot.put("lyricLine", lyricLine).put("lyricPrevious", lyricPrevious).put("lyricNext", lyricNext);
            snapshot.put("lyricsReason", lyrics.isEmpty() && lyricLine.isEmpty()
                    ? "网易云当前版本未向桌面共享歌词" : "");
        } catch (Exception unavailableSession) { /* Keep the standard snapshot. */ }
    }

    /**
     * Returns dispatch acceptance, not confirmation that playback changed.
     * Do not retry a false result through a global MEDIA_BUTTON broadcast.
     */
    public boolean command(String action, long positionMs) {
        if (!supports(controller)) return false;
        try {
            if ("seek".equals(action)) {
                if (positionMs < 0) {
                    UniLog.fail(LogTags.MEDIA, "media/transport", "action", action, "route", "netease", "reason", "negative-position");
                    return false;
                }
                MediaMetadata metadata = controller.getMetadata();
                long duration = metadata == null ? 0 : metadata.getLong(MediaMetadata.METADATA_KEY_DURATION);
                long position = Math.min(positionMs, (long) Integer.MAX_VALUE * 1000L);
                if (duration > 0) position = Math.min(position, duration);
                // NetEase onSeekTo accepts milliseconds, then converts to integer seconds
                // for seek_to_action -> IIotClient.seekReset { time: seconds }.
                controller.getTransportControls().seekTo(position);
                UniLog.done(LogTags.MEDIA, "media/transport", "action", action, "route", "netease", "positionMs", position, "durationMs", duration);
                return true;
            }
            int key;
            boolean wantsPlay=false;
            if ("next".equals(action)) key = KeyEvent.KEYCODE_MEDIA_NEXT;
            else if ("previous".equals(action)) key = KeyEvent.KEYCODE_MEDIA_PREVIOUS;
            else if ("play".equals(action)) {wantsPlay=true;key=KeyEvent.KEYCODE_MEDIA_PLAY;}
            else if ("pause".equals(action)) key = KeyEvent.KEYCODE_MEDIA_PAUSE;
            else if ("toggle-play".equals(action)) {
                PlaybackState state = controller.getPlaybackState();
                wantsPlay = state == null || state.getState() != PlaybackState.STATE_PLAYING;
                key = state == null ? KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                        : state.getState() == PlaybackState.STATE_PLAYING
                        ? KeyEvent.KEYCODE_MEDIA_PAUSE : KeyEvent.KEYCODE_MEDIA_PLAY;
} else {
                UniLog.fail(LogTags.MEDIA, "media/transport", "action", action, "route", "netease", "reason", "unknown-action");
                return false;
            }
            if ((controller.getFlags() & MediaSession.FLAG_HANDLES_MEDIA_BUTTONS) == 0) {
                UniLog.fail(LogTags.MEDIA, "media/transport", "action", action, "route", "netease", "reason", "no-media-button-flag", "flags", controller.getFlags());
                return false;
            }
            // Playing from a no-focus state is rejected by the broadcast receiver.
            // TransportControls reaches the app's onPlay callback, which requests focus.
            if (wantsPlay) {
                controller.getTransportControls().play();
                UniLog.done(LogTags.MEDIA, "media/transport", "action", action, "route", "netease", "reason", "play-requested");
                return true;
            }
            long now = SystemClock.uptimeMillis();
            // The actual NetEase receiver ignores DOWN and consumes only UP.
            controller.dispatchMediaButtonEvent(new KeyEvent(now, now, KeyEvent.ACTION_DOWN, key, 0));
            boolean accepted = controller.dispatchMediaButtonEvent(new KeyEvent(now, now, KeyEvent.ACTION_UP, key, 0));
            if (accepted) UniLog.done(LogTags.MEDIA, "media/transport", "action", action, "route", "netease", "keyCode", key);
            else UniLog.fail(LogTags.MEDIA, "media/transport", "action", action, "route", "netease", "reason", "event-not-consumed", "keyCode", key);
            return accepted;
        } catch (RuntimeException unavailableSession) {
            UniLog.w(LogTags.MEDIA, "网易云播放控制失败", "action", action, "route", "netease", "error", unavailableSession.getClass().getSimpleName(), "reason", String.valueOf(unavailableSession.getMessage()));
            return false;
        }
    }

    public boolean command(String action) { return command(action, -1); }

    public void stop() {
        MediaController previous = controller;
        MediaController.Callback previousCallback = callback;
        controller = null;
        callback = null;
        track = "";
        mediaId = "";
        clearLyrics();
        if (previous != null && previousCallback != null) {
            try { previous.unregisterCallback(previousCallback); }
            catch (RuntimeException unavailableSession) { /* Already destroyed. */ }
        }
    }

    public String getLyrics() { return lyrics; }
    public String getLyricsSource() { return lyricsSource; }
    public String getLyricLine() { return lyricLine; }
    public String getLyricPrevious() { return lyricPrevious; }
    public String getLyricNext() { return lyricNext; }
    public String getTrackIdentity() { return track; }

    private void readMetadata(MediaMetadata metadata) {
        if (metadata == null) { track = ""; mediaId = ""; clearLyrics(); return; }
        mediaId = text(metadata.getString(MediaMetadata.METADATA_KEY_MEDIA_ID));
        String title = text(metadata.getString(MediaMetadata.METADATA_KEY_TITLE));
        String artist = text(metadata.getString(MediaMetadata.METADATA_KEY_ARTIST));
        String identity = mediaId + "\n" + title + "\n" + artist;
        boolean trackChanged = !identity.equals(track);
        if (trackChanged) {
            track = identity;
            UniLog.done(LogTags.MEDIA, "media/metadata", "source", "netease", "mediaId", mediaId, "title", title, "artist", artist);
            clearLyrics();
            // NetEase Cloud Music IoT retains the previous track's LYRIC extra in the first metadata
            // callback right after a track switch. Never read LYRIC_KEY in the same transition turn.
            return;
        }
        String value = text(metadata.getString(LYRIC_KEY));
        if (isLoadingOrEmpty(value)) {
            clearLyrics();
            return;
        }
        if (!value.isEmpty()) setLyrics(value, "netease-media-metadata");
        else if ("netease-media-metadata".equals(lyricsSource)) clearLyrics();
    }

    private void setLyrics(String value, String source) {
        value = text(value);
        if (isLoadingOrEmpty(value)) {
            clearLyrics();
            return;
        }
        // The player republishes the same lyrics; log the change only.
        boolean changed = !value.equals(lyrics) || !source.equals(lyricsSource);
        lyrics = value;
        lyricsSource = value.isEmpty() ? "" : source;
        if (!changed) return;
        if (lyricsSource.isEmpty()) {
            UniLog.skip(LogTags.LYRIC, "lyric/resolve", "source", source, "reason", "empty-payload");
        } else {
            UniLog.done(LogTags.LYRIC, "lyric/resolve", "source", lyricsSource, "length", lyrics.length());
        }
    }

    private static boolean isLoadingOrEmpty(String value) {
        if (value == null || value.trim().isEmpty()) return true;
        String trimmed = value.trim();
        return "加载歌词中...".equals(trimmed)
                || "歌词加载中...".equals(trimmed)
                || "暂无歌词".equals(trimmed)
                || "纯音乐，请欣赏".equals(trimmed)
                || "纯音乐，无歌词".equals(trimmed);
    }

    private void clearLyrics() {
        boolean had = !lyrics.isEmpty() || !lyricsSource.isEmpty() || !lyricLine.isEmpty();
        lyrics = ""; lyricsSource = ""; lyricLine = ""; lyricPrevious = ""; lyricNext = "";
        if (had) UniLog.i(LogTags.LYRIC, "网易云歌词已清空", "reason", "player-cleared");
    }
    private static String text(String value) {
        return value != null && value.length() <= MAX_LYRIC_LENGTH ? value : "";
    }
    private void notifyChanged() { if (changed != null) changed.run(); }
}
