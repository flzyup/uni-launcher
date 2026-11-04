package xyz.i4o.uni.launcher;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Internal alarm entry point. Unexported: only UNI's own PendingIntent can send it. */
public final class DefaultHomeAlarmReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        UniLog.i(LogTags.SYS, "delayed check", "tag","UniHome");
        if (DefaultHomeGuard.restoreIfNeeded(context)) {
            DefaultHomeGuard.dismissResolver(context);
        }
    }
}
