package xyz.i4o.uni.launcher;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

/** Original launcher batch broadcasts are sent once per Android boot. */
public final class OtaBootReceiver extends BroadcastReceiver {
    private static final String PREFIX="com.ecarx.intent.action.EAS_LAUNCH_BAT_";
    @Override public void onReceive(Context context, Intent intent) {
        if (intent == null || !(PREFIX+"3RD").equals(intent.getAction())) return;
        try { context.startService(new Intent(context, OtaBootService.class)); }
        catch (RuntimeException e) { android.util.Log.w("UniOta", "Boot check service unavailable", e); }
    }
    static void scheduleLauncherBroadcasts(Context context) {
        Context app=context.getApplicationContext();
        int boot=Settings.Global.getInt(app.getContentResolver(), "boot_count", -1);
        if(boot<0)return; // The launcher's delayed startup check is the fallback.
        android.content.SharedPreferences prefs=app.getSharedPreferences("uni_boot",0);
        if(prefs.getInt("broadcastBoot",-1)==boot)return;
        if(!prefs.edit().putInt("broadcastBoot",boot).commit())return;
        Handler handler=new Handler(Looper.getMainLooper());
        String[] batches={"0ST","1ST","2ND","3RD"};
        long[] delays={0,1000,6000,11000};
        for(int i=0;i<batches.length;i++) {
            final String action=PREFIX+batches[i];
            handler.postDelayed(()->app.sendBroadcast(new Intent(action)),delays[i]);
        }
    }
}
