package ecarx.xsf.mediacenter;

import android.app.Service;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Intent;
import android.os.IBinder;

/** Keeps the synthetic session alive while screenshot-heavy emulator tests run. */
public final class FixtureMediaService extends Service {
    public void onCreate(){
        super.onCreate();
        NotificationManager manager=(NotificationManager)getSystemService(NOTIFICATION_SERVICE);
        manager.createNotificationChannel(new NotificationChannel("fixture","UNI synthetic media test",NotificationManager.IMPORTANCE_LOW));
        startForeground(1,new Notification.Builder(this,"fixture")
            .setContentTitle("UNI emulator test source — not OEM software")
            .setSmallIcon(android.R.drawable.ic_media_play).build());
        FixtureActivity.ensureSession(this);
    }
    public IBinder onBind(Intent intent){return null;}
}
