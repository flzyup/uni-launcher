package xyz.i4o.uni.launcher.core;

/** An explicit player never silently falls back to another application's session. */
public final class MediaSourcePolicy {
    public static int select(String preferred,String[] packages,boolean[] playing){
        if(packages.length!=playing.length)return -1;
        if(preferred!=null&&!preferred.isEmpty()&&!"auto".equals(preferred)){
            int first=-1;for(int i=0;i<packages.length;i++)if(preferred.equals(packages[i])){if(playing[i])return i;if(first<0)first=i;}
            return first;
        }
        for(int i=0;i<packages.length;i++)if(playing[i])return i;
        for(int i=0;i<packages.length;i++)if("ecarx.xsf.mediacenter".equals(packages[i]))return i;
        return packages.length==0?-1:0;
    }
}
