package ecarx.calendar;
import android.content.*;
public final class ModeReceiver extends BroadcastReceiver {
    public void onReceive(Context c, Intent i) {
        c.getSharedPreferences("fixture",0).edit().putString("mode",i.getStringExtra("mode")).commit();
    }
}
