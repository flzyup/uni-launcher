package xyz.i4o.uni.launcher;
import android.content.*;
/** Restore only the owner's previously enabled dock after normal boot. */
public final class GlobalDockBootReceiver extends BroadcastReceiver {
    private static final String RESTORE_ACTION="xyz.i4o.uni.launcher.action.RESTORE_HOME";
    private static final long[] CHECK_DELAYS={1000,4000,8000,16000,32000};
    @Override public void onReceive(final Context c, Intent i){
        final String action=i==null?null:i.getAction();
        final boolean lockedBoot=Intent.ACTION_LOCKED_BOOT_COMPLETED.equals(action);
        final boolean boot=Intent.ACTION_BOOT_COMPLETED.equals(action);
        final boolean unlocked=Intent.ACTION_USER_UNLOCKED.equals(action);
        if(!(lockedBoot||boot||unlocked))return;
        scheduleDelayedChecks(c);
        runCheck(c,lockedBoot);
        if(boot)GlobalDockService.ensureStarted(c);
    }
    private static void scheduleDelayedChecks(Context c){
        android.app.AlarmManager alarms=(android.app.AlarmManager)
            c.getSystemService(Context.ALARM_SERVICE);
        if(alarms==null)return;
        long now=android.os.SystemClock.elapsedRealtime();
        for(int i=0;i<CHECK_DELAYS.length;i++){
            Intent intent=new Intent(RESTORE_ACTION)
                .setClass(c,DefaultHomeAlarmReceiver.class);
            android.app.PendingIntent pending=android.app.PendingIntent.getBroadcast(
                c,i+1,intent,android.app.PendingIntent.FLAG_UPDATE_CURRENT
                    |android.app.PendingIntent.FLAG_IMMUTABLE);
            alarms.setExactAndAllowWhileIdle(android.app.AlarmManager.ELAPSED_REALTIME_WAKEUP,
                now+CHECK_DELAYS[i],pending);
        }
    }
    private void runCheck(final Context c,final boolean lockedBoot){
        final PendingResult result=goAsync();
        new Thread(()->{
            try {
                boolean restored=DefaultHomeGuard.restoreIfNeeded(c);
                if(restored && !lockedBoot) DefaultHomeGuard.dismissResolver(c);
            } finally {
                result.finish();
            }
        },"uni-default-home").start();
    }
}
