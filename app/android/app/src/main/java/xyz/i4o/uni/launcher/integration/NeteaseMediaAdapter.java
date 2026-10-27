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
        stop();
        if (next == null) return;
        controller = next;
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
                        lyricLine = lines != null && lines.length > 1 ? text(lines[1]) : "";
                        lyricPrevious = lines != null && lines.length > 0 ? text(lines[0]) : "";
                        lyricNext = lines != null && lines.length > 2 ? text(lines[2]) : "";
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
                if (positionMs < 0) return false;
                MediaMetadata metadata = controller.getMetadata();
                long duration = metadata == null ? 0 : metadata.getLong(MediaMetadata.METADATA_KEY_DURATION);
                long position = Math.min(positionMs, (long) Integer.MAX_VALUE * 1000L);
                if (duration > 0) position = Math.min(position, duration);
                // NetEase onSeekTo accepts milliseconds, then converts to integer seconds
                // for seek_to_action -> IIotClient.seekReset { time: seconds }.
                controller.getTransportControls().seekTo(position);
                return true;
            }
            int key;
            if ("next".equals(action)) key = KeyEvent.KEYCODE_MEDIA_NEXT;
            else if ("previous".equals(action)) key = KeyEvent.KEYCODE_MEDIA_PREVIOUS;
            else if ("play".equals(action)) key = KeyEvent.KEYCODE_MEDIA_PLAY;
            else if ("pause".equals(action)) key = KeyEvent.KEYCODE_MEDIA_PAUSE;
            else if ("toggle-play".equals(action)) {
                PlaybackState state = controller.getPlaybackState();
                key = state == null ? KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                        : state.getState() == PlaybackState.STATE_PLAYING
                        ? KeyEvent.KEYCODE_MEDIA_PAUSE : KeyEvent.KEYCODE_MEDIA_PLAY;
            } else return false;
            if ((controller.getFlags() & MediaSession.FLAG_HANDLES_MEDIA_BUTTONS) == 0) return false;
            long now = SystemClock.uptimeMillis();
            // The actual NetEase receiver ignores DOWN and consumes only UP.
            controller.dispatchMediaButtonEvent(new KeyEvent(now, now, KeyEvent.ACTION_DOWN, key, 0));
            return controller.dispatchMediaButtonEvent(new KeyEvent(now, now, KeyEvent.ACTION_UP, key, 0));
        } catch (RuntimeException unavailableSession) { return false; }
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

    private void readMetadata(MediaMetadata metadata) {
        if (metadata == null) { track = ""; mediaId = ""; clearLyrics(); return; }
        mediaId = text(metadata.getString(MediaMetadata.METADATA_KEY_MEDIA_ID));
        String identity = mediaId + "\n"
                + text(metadata.getString(MediaMetadata.METADATA_KEY_TITLE)) + "\n"
                + text(metadata.getString(MediaMetadata.METADATA_KEY_ARTIST));
        if (!identity.equals(track)) { track = identity; clearLyrics(); }
        String value = text(metadata.getString(LYRIC_KEY));
        if (!value.isEmpty()) setLyrics(value, "netease-media-metadata");
        else if ("netease-media-metadata".equals(lyricsSource)) clearLyrics();
    }

    private void setLyrics(String value, String source) {
        value = text(value);
        lyrics = value;
        lyricsSource = value.isEmpty() ? "" : source;
    }

    private void clearLyrics() { lyrics = ""; lyricsSource = ""; lyricLine = ""; lyricPrevious = ""; lyricNext = ""; }
    private static String text(String value) {
        return value != null && value.length() <= MAX_LYRIC_LENGTH ? value : "";
    }
    private void notifyChanged() { if (changed != null) changed.run(); }
}
