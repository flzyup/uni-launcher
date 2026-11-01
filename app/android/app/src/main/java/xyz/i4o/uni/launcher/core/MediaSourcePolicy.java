package xyz.i4o.uni.launcher.core;

/** An explicit player never silently falls back to another application's session. */
public final class MediaSourcePolicy {
    /** Session-level selection: never merge two tokens merely because their package matches. */
    public static int selectSessions(String preferred, String last, String[] packages,
            boolean[] playing, boolean[] hasMetadata, boolean[] current) {
        int n=packages.length;
        if(playing.length!=n||hasMetadata.length!=n||current.length!=n)return -1;
        boolean locked=preferred!=null&&!preferred.isEmpty()&&!"auto".equals(preferred);
        if(locked){
            for(int i=0;i<n;i++)if(preferred.equals(packages[i])&&playing[i])return i;
            for(int i=0;i<n;i++)if(preferred.equals(packages[i])&&hasMetadata[i]&&current[i])return i;
            for(int i=0;i<n;i++)if(preferred.equals(packages[i])&&hasMetadata[i])return i;
            for(int i=0;i<n;i++)if(preferred.equals(packages[i]))return i;
            return -1;
        }
        for(int i=0;i<n;i++)if(playing[i]&&!"ecarx.xsf.mediacenter".equals(packages[i]))return i;
        for(int i=0;i<n;i++)if(current[i]&&hasMetadata[i])return i;
        for(int i=0;i<n;i++)if(current[i]&&!"ecarx.xsf.mediacenter".equals(packages[i]))return i;
        if(last!=null&&!last.isEmpty())for(int i=0;i<n;i++)if(last.equals(packages[i])&&hasMetadata[i])return i;
        for(int i=0;i<n;i++)if(playing[i])return i;
        for(int i=0;i<n;i++)if(hasMetadata[i]&&!"ecarx.xsf.mediacenter".equals(packages[i]))return i;
        for(int i=0;i<n;i++)if(current[i])return i;
        if(last!=null&&!last.isEmpty()&&!"ecarx.xsf.mediacenter".equals(last)){
            boolean onlyEmptyProxy=n>0;
            for(int i=0;i<n;i++)if(!"ecarx.xsf.mediacenter".equals(packages[i])||playing[i]||hasMetadata[i])onlyEmptyProxy=false;
            if(onlyEmptyProxy)return -1;
        }
        return n==0?-1:0;
    }
    public static int select(String preferred,String[] packages,boolean[] playing){
        return select(preferred, "", packages, playing);
    }
    public static int select(String preferred,String last,String[] packages,boolean[] playing){
        if(packages.length!=playing.length)return -1;
        if(preferred!=null&&!preferred.isEmpty()&&!"auto".equals(preferred)){
            int first=-1;for(int i=0;i<packages.length;i++)if(preferred.equals(packages[i])){if(playing[i])return i;if(first<0)first=i;}
            return first;
        }
        for(int i=0;i<packages.length;i++)if(playing[i]&&!"ecarx.xsf.mediacenter".equals(packages[i]))return i;
        if(last!=null&&!last.isEmpty())for(int i=0;i<packages.length;i++)if(last.equals(packages[i]))return i;
        for(int i=0;i<packages.length;i++)if(playing[i])return i;
        for(int i=0;i<packages.length;i++)if("ecarx.xsf.mediacenter".equals(packages[i]))return i;
        return packages.length==0?-1:0;
    }
}
