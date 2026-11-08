package xyz.i4o.uni.launcher.integration;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import java.io.File;
import java.io.FileNotFoundException;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/**
 * 只读暴露 cache/artwork/ 下的封面 PNG。
 *
 * <p>原车 {@code IMusicPlaybackInfo.getArtwork()} 返回的是 {@link Uri}，不是位图：
 * 原车（可能还有仪表服务）拿到 URI 后自己开流读。所以封面必须落成一个它读得到的
 * {@code content://}，并对读的那一方 grant 读权限。
 *
 * <p>每次被读取都记一条日志 —— 「原车/仪表到底来不来取封面」这件事只有这样才有答案。
 */
public final class ArtworkFileProvider extends ContentProvider {
    public static final String AUTHORITY="xyz.i4o.uni.launcher.artwork";
    private static final String DIR="artwork";

    public static File dir(Context context){
        File dir=new File(context.getCacheDir(),DIR);
        if(!dir.isDirectory()&&!dir.mkdirs())UniLog.w(LogTags.MEDIA,"封面目录创建失败","path",dir.getAbsolutePath());
        return dir;
    }
    public static Uri uriFor(String name){return Uri.parse("content://"+AUTHORITY+"/"+name);}

    @Override public boolean onCreate(){return true;}

    @Override public ParcelFileDescriptor openFile(Uri uri,String mode)throws FileNotFoundException{
        String name=uri.getLastPathSegment();
        if(name==null)throw new FileNotFoundException("missing name");
        File dir=dir(getContext());
        File f=new File(dir,name);
        try{
            String root=dir.getCanonicalPath()+File.separator;
            if(!f.getCanonicalPath().startsWith(root))throw new FileNotFoundException("forbidden");
        }catch(FileNotFoundException e){throw e;
        }catch(Exception e){throw new FileNotFoundException("unreadable");}
        if(!f.isFile())throw new FileNotFoundException("not found");
        // 谁来看的封面（UID/包名）就记谁，用来确认原车那条链路是否真的在用这张图。
        String caller=null;
        try{
            String[] packages=getContext().getPackageManager().getPackagesForUid(android.os.Binder.getCallingUid());
            if(packages!=null&&packages.length>0)caller=packages[0];
        }catch(RuntimeException ignored){}
        UniLog.i(LogTags.MEDIA,"封面被读取","caller",caller==null?("uid="+android.os.Binder.getCallingUid()):caller,
            "name",name,"bytes",f.length());
        return ParcelFileDescriptor.open(f,ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override public String getType(Uri uri){
        String name=uri.getLastPathSegment();
        return name!=null&&name.endsWith(".lrc")?"text/plain":"image/png";
    }
    @Override public Cursor query(Uri uri,String[] p,String s,String[] a,String o){return null;}
    @Override public Uri insert(Uri uri,ContentValues values){return null;}
    @Override public int delete(Uri uri,String selection,String[] args){return 0;}
    @Override public int update(Uri uri,ContentValues values,String s,String[] a){return 0;}
}
