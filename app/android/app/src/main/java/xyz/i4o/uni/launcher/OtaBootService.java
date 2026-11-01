package xyz.i4o.uni.launcher;

import android.app.IntentService;
import android.content.Intent;

/** Never opens a UI; the active launcher performs its single silent check. */
public final class OtaBootService extends IntentService {
    public OtaBootService() { super("UniOtaBoot"); }
    @Override protected void onHandleIntent(Intent intent) {
        MainActivity.requestBootUpdateCheck();
    }
}
