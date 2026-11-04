package xyz.i4o.uni.launcher.integration;

import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Permission boundary only; notifications are neither read nor stored. */
public final class MediaAccessService extends android.service.notification.NotificationListenerService {
    public MediaAccessService(){
        // This component is what the media session lookup is bound to, so its
        // lifetime is the permission boundary the launcher depends on.
        UniLog.i(LogTags.MEDIA,"媒体访问服务已创建","component",getClass().getName());
    }

    @Override public void onDestroy(){
        super.onDestroy();
        UniLog.i(LogTags.MEDIA,"媒体访问服务已销毁","component",getClass().getName());
    }
}
