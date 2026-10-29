package xyz.i4o.uni.launcher.core;

/** Retains the last complete track only for the same paused session. */
public final class MediaTextRetention {
    public static final class Track {
        public final String title, artist, album;
        public final long durationMs;
        public Track(String title, String artist, String album, long durationMs) {
            this.title=title==null?"":title;
            this.artist=artist==null?"":artist;
            this.album=album==null?"":album;
            this.durationMs=Math.max(0,durationMs);
        }
        public boolean known(){return !title.trim().isEmpty();}
    }
    private Object token;
    private Track last;
    public Track update(Object nextToken, boolean paused, Track incoming) {
        if(nextToken==null || !nextToken.equals(token)) {
            token=nextToken;
            last=null;
        }
        if(incoming!=null && incoming.known()) {
            last=incoming;
            return incoming;
        }
        if(paused && last!=null) return last;
        if(!paused) last=null;
        return incoming==null?new Track("","","",0):incoming;
    }
    public void clear(){token=null;last=null;}
}
