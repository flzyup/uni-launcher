package xyz.i4o.uni.launcher;

import android.app.IntentService;
import android.content.Intent;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Never opens a UI; the active launcher performs its single silent check. */
public final class OtaBootService extends IntentService {
    public OtaBootService() { super("UniOtaBoot"); }
    @Override protected void onHandleIntent(Intent intent) {
        UniLog.enter(LogTags.OTA,"ota/check","trigger","boot");
        long installed=installedVersionCode();
        UniLog.i(LogTags.OTA,"在线更新检查已触发","installedVersionCode",installed,"sdk",android.os.Build.VERSION.SDK_INT);
        MainActivity.requestBootUpdateCheck();
        UniLog.done(LogTags.OTA,"ota/check","trigger","boot","installedVersionCode",installed);
    }
    /** 当前装着的版本号：检查结果在 Flutter 侧判定，这里留个基线便于对照。 */
    private long installedVersionCode(){
        try{return getPackageManager().getPackageInfo(getPackageName(),0).versionCode;}
        catch(Exception e){return -1L;}
    }
}
