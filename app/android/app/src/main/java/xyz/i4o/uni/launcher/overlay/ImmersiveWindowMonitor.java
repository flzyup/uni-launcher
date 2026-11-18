package xyz.i4o.uni.launcher.overlay;

import android.content.Context;
import android.content.pm.PackageManager;
import android.os.*;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Bounded background reads of only the foreground package's windows.
 * No shell subprocess, full-system dump or UI-thread I/O. Poll only external
 * apps; foreground changes cancel stale results. Preserve last valid state on
 * transient read errors, but fail open after three misses.
 */
public final class ImmersiveWindowMonitor implements AutoCloseable {
    public interface Listener {void onState(String pkg,boolean immersive);}
    private final Context context;
    private final Listener listener;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final HandlerThread thread=new HandlerThread("uni-immersive-window");
    private final Handler worker;
    private String foreground="";
    private int epoch, misses;
    private boolean closed, reported, last;
    private final boolean granted;
    public ImmersiveWindowMonitor(Context context,Listener listener) {
        this.context=context;this.listener=listener;
        granted=context.checkSelfPermission("android.permission.DUMP")==PackageManager.PERMISSION_GRANTED;
        thread.start();worker=new Handler(thread.getLooper());
        if(!granted)UniLog.w(LogTags.DOCK,"沉浸式窗口读取不可用：缺少 DUMP 权限");
    }
    public void setForeground(String pkg) {
        if(closed)return;
        if(pkg==null||pkg.equals(context.getPackageName()))pkg="";
        if(pkg.equals(foreground))return;
        foreground=pkg;int sequence=++epoch;misses=0;reported=false;last=false;
        worker.removeCallbacksAndMessages(null);
        listener.onState(pkg,false);
        if(granted&&!pkg.isEmpty())readLater(pkg,sequence,0);
    }
    private void readLater(String pkg,int sequence,long delay) {
        worker.postDelayed(()->{
            ImmersiveWindowState state=read(pkg);
            main.post(()->{
                if(closed||sequence!=epoch)return;
                if(state.known){misses=0;
                    if(!reported||state.immersive!=last){reported=true;last=state.immersive;listener.onState(pkg,last);}
                }else if(++misses>=3&&last){last=false;listener.onState(pkg,false);}
                readLater(pkg,sequence,750);
            });
        },delay);
    }
    private ImmersiveWindowState read(String pkg) {
        ParcelFileDescriptor[] pipe=null;
        Runnable timeout=null;
        try {
            IBinder window=(IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,"window");
            if(window==null)return ImmersiveWindowState.unknown();
            pipe=ParcelFileDescriptor.createPipe();final ParcelFileDescriptor[] current=pipe;
            timeout=()->{try{current[0].close();}catch(Exception ignored){}try{current[1].close();}catch(Exception ignored){}};
            main.postDelayed(timeout,1000);
            window.dumpAsync(pipe[1].getFileDescriptor(),new String[]{"-a",pkg});
            pipe[1].close();
            try(InputStream in=new ParcelFileDescriptor.AutoCloseInputStream(pipe[0]);ByteArrayOutputStream out=new ByteArrayOutputStream()) {
                byte[] buffer=new byte[4096];int n;
                while((n=in.read(buffer))!=-1){if(out.size()+n>262144)return ImmersiveWindowState.unknown();out.write(buffer,0,n);}
                return ImmersiveWindowState.parse(new String(out.toByteArray(),StandardCharsets.UTF_8),pkg);
            }
        }catch(Exception e){return ImmersiveWindowState.unknown();}
        finally{if(timeout!=null)main.removeCallbacks(timeout);if(pipe!=null)for(ParcelFileDescriptor fd:pipe)try{fd.close();}catch(Exception ignored){}}
    }
    @Override public void close(){closed=true;epoch++;worker.removeCallbacksAndMessages(null);thread.quitSafely();}
}
