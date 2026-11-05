package xyz.i4o.uni.launcher.overlay;

import android.app.PendingIntent;
import android.content.*;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.os.*;
import java.io.*;
import java.lang.reflect.Method;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Code-free resource adapter bundled only in the platform-signed car APK.
 * Native navigation insets keep system confirmation controls above the dock.
 * No framework file is replaced; disabling the dock restores the overlay state. */
public final class NavigationInsets {
    public static final String PACKAGE="xyz.i4o.uni.launcher.insets";
    private static final String SAVED="uniNativeInsetsOriginal",APPLIED="uniNativeInsetsApplied";
    private NavigationInsets(){}
    public static boolean applied(Context c){return c.getSharedPreferences("launcher",0).getBoolean(APPLIED,false);}
    public static boolean supported(Context c){
        if(c.checkSelfPermission("android.permission.CHANGE_OVERLAY_PACKAGES")!=PackageManager.PERMISSION_GRANTED
            ||c.checkSelfPermission("android.permission.STATUS_BAR_SERVICE")!=PackageManager.PERMISSION_GRANTED)return false;
        try{c.getPackageManager().getPackageInfo(PACKAGE,0);return true;}catch(PackageManager.NameNotFoundException e){return false;}
    }
    private static Object manager()throws Exception{
        android.os.IBinder binder=(android.os.IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,"overlay");
        return Class.forName("android.content.om.IOverlayManager$Stub").getMethod("asInterface",android.os.IBinder.class).invoke(null,binder);
    }
    private static Object invoke(Object manager,String name,Class<?>[] types,Object...args)throws Exception{
        return Class.forName("android.content.om.IOverlayManager").getMethod(name,types).invoke(manager,args);
    }
    public static boolean activate(Context c,SharedPreferences p){
        if(c.checkSelfPermission("android.permission.CHANGE_OVERLAY_PACKAGES")!=PackageManager.PERMISSION_GRANTED)return false;
        UniLog.enter(LogTags.SYS,"sys/insets","action","activate");
        try{
            Object manager=manager();int user=android.os.Process.myUid()/100000;
            Object info=invoke(manager,"getOverlayInfo",new Class<?>[]{String.class,int.class},PACKAGE,user);
            if(info==null){UniLog.skip(LogTags.SYS,"sys/insets","action","activate","reason","overlay-not-installed");return false;}
            boolean was=(Boolean)info.getClass().getMethod("isEnabled").invoke(info);
            if(!p.contains(SAVED))p.edit().putBoolean(SAVED,was).commit();
            invoke(manager,"setHighestPriority",new Class<?>[]{String.class,int.class},PACKAGE,user);
            boolean ok=Boolean.TRUE.equals(invoke(manager,"setEnabled",new Class<?>[]{String.class,boolean.class,int.class},PACKAGE,true,user));
            if(ok){p.edit().putBoolean(APPLIED,true).commit();refreshPolicy(c);}
            if(ok)UniLog.done(LogTags.SYS,"sys/insets","action","activate","wasEnabled",was);
            else UniLog.fail(LogTags.SYS,"sys/insets","action","activate","reason","set-enabled-rejected");
            return ok;
        }catch(Exception e){UniLog.w(LogTags.SYS,"Native navigation resources unavailable",e,"tag","UniInsets");UniLog.fail(LogTags.SYS,"sys/insets","action","activate","error",e.getClass().getSimpleName());return false;}
    }
    public static void restore(Context c,SharedPreferences p){
        if(!p.contains(SAVED)){UniLog.skip(LogTags.SYS,"sys/insets","action","restore","reason","nothing-saved");return;}
        UniLog.enter(LogTags.SYS,"sys/insets","action","restore");
        try{
            Object manager=manager();int user=android.os.Process.myUid()/100000;
            boolean previous=p.getBoolean(SAVED,false);
            invoke(manager,"setEnabled",new Class<?>[]{String.class,boolean.class,int.class},PACKAGE,previous,user);
            p.edit().remove(SAVED).remove(APPLIED).commit();
            refreshPolicy(c);
            UniLog.done(LogTags.SYS,"sys/insets","action","restore","restored",previous);
        }catch(Exception e){UniLog.w(LogTags.SYS,"Unable to restore native navigation resources",e,"tag","UniInsets");UniLog.fail(LogTags.SYS,"sys/insets","action","restore","error",e.getClass().getSimpleName());}
    }
    private static void refreshPolicy(Context c){
        // Android 9 caches policy dimensions independently of app resources.
        // Reconfigure with the existing density; never change its actual value
        // or introduce a forced-density preference where there was none.
        new Handler(Looper.getMainLooper()).postDelayed(()->{
            try{
                Object binder=Class.forName("android.view.WindowManagerGlobal").getMethod("getWindowManagerService").invoke(null);
                Class<?> type=Class.forName("android.view.IWindowManager");int user=android.os.Process.myUid()/100000;
                String forced=android.provider.Settings.Secure.getString(c.getContentResolver(),"display_density_forced");
                if(forced==null||forced.isEmpty())type.getMethod("clearForcedDisplayDensityForUser",int.class,int.class).invoke(binder,0,user);
                else{
                    int density=((Number)type.getMethod("getBaseDisplayDensity",int.class).invoke(binder,0)).intValue();
                    type.getMethod("setForcedDisplayDensityForUser",int.class,int.class,int.class).invoke(binder,0,density,user);
                }
            }catch(Exception e){UniLog.w(LogTags.SYS,"Navigation policy refresh unavailable",e,"tag","UniInsets");UniLog.fail(LogTags.SYS,"sys/insets","action","policy-refresh","error",e.getClass().getSimpleName());}
        },250);
    }
    public static void prepare(Context c,Runnable done){
        UniLog.enter(LogTags.SYS,"sys/insets","action","prepare");
        try{c.getPackageManager().getPackageInfo(PACKAGE,0);UniLog.skip(LogTags.SYS,"sys/insets","action","prepare","reason","already-installed");done.run();return;}catch(PackageManager.NameNotFoundException ignored){}
        if(c.checkSelfPermission("android.permission.INSTALL_PACKAGES")!=PackageManager.PERMISSION_GRANTED){UniLog.skip(LogTags.SYS,"sys/insets","action","prepare","reason","no-install-permission");done.run();return;}
        InputStream asset;
        try{asset=c.getAssets().open("uni-nav-insets.apk");}catch(IOException e){UniLog.skip(LogTags.SYS,"sys/insets","action","prepare","reason","asset-missing");done.run();return;}
        Handler main=new Handler(Looper.getMainLooper());String action=c.getPackageName()+".NATIVE_INSETS_INSTALLED";
        BroadcastReceiver receiver=new BroadcastReceiver(){public void onReceive(Context context,Intent intent){
            try{context.unregisterReceiver(this);}catch(RuntimeException ignored){}
            UniLog.done(LogTags.SYS,"sys/insets","action","prepare");
            done.run();
        }};
        c.registerReceiver(receiver,new IntentFilter(action));
        new Thread(()->{
            int id=-1;PackageInstaller installer=c.getPackageManager().getPackageInstaller();
            try(InputStream in=asset){
                PackageInstaller.SessionParams params=new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
                params.setAppPackageName(PACKAGE);id=installer.createSession(params);
                try(PackageInstaller.Session session=installer.openSession(id)){
                    try(OutputStream out=session.openWrite("base.apk",0,-1)){byte[] buffer=new byte[16384];int size;while((size=in.read(buffer))>=0)out.write(buffer,0,size);session.fsync(out);}
                    PendingIntent result=PendingIntent.getBroadcast(c,753,new Intent(action).setPackage(c.getPackageName()),PendingIntent.FLAG_UPDATE_CURRENT);
                    session.commit(result.getIntentSender());
                }
            }catch(Exception e){
                if(id>=0)try{installer.abandonSession(id);}catch(RuntimeException ignored){}
                UniLog.w(LogTags.SYS,"Resource adapter installation unavailable",e,"tag","UniInsets");
                UniLog.fail(LogTags.SYS,"sys/insets","action","prepare","error",e.getClass().getSimpleName());
                main.post(()->{try{c.unregisterReceiver(receiver);}catch(RuntimeException ignored){}done.run();});
            }
        },"uni-native-insets").start();
    }
}
