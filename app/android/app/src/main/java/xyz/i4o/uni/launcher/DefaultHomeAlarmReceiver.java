package xyz.i4o.uni.launcher;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Internal alarm entry point. Unexported: only UNI's own PendingIntent can send it. */
public final class DefaultHomeAlarmReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        android.util.Log.i("UniHome", "delayed check");
        if (DefaultHomeGuard.restoreIfNeeded(context)) {
            DefaultHomeGuard.dismissResolver(context);
        }
    }
}
