package xyz.i4o.uni.launcher.integration;

import android.app.*;
import android.appwidget.*;
import android.content.*;
import android.content.pm.*;
import android.os.*;
import android.test.mock.MockPackageManager;
import android.widget.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.*;

/** Isolated harness package, real Android binder/JSON; package-manager doubles only where stated. */
public final class OfficialEntryInstrumentation extends Instrumentation {
    private int assertions;
    private String phase;
    private Context context;
    private AppWidgetHost host;
    @Override public void onCreate(Bundle args) { phase=args.getString("phase","granted");start(); }
    private void check(boolean ok,String description) {
        assertions++;
        if(!ok)throw new AssertionError(description);
    }
    @Override public void onStart() {
        Bundle result=new Bundle();
        try {
            context=getTargetContext();host=new AppWidgetHost(context,75301);
            catalogAndPackageTests();
            host.deleteHost();context.getSharedPreferences("widgets",0).edit().clear().commit();
            if("denied".equals(phase)) deniedBinding();else hostTests();
            result.putString("stream","PASS "+assertions+" assertions ("+phase+"). Synthetic fixtures only; no OEM fields verified.\n");
            result.putBoolean("passed",true);finish(Activity.RESULT_OK,result);
        } catch(Throwable e) {
            result.putString("stream","FAIL "+android.util.Log.getStackTraceString(e));
            result.putBoolean("passed",false);finish(Activity.RESULT_CANCELED,result);
        }
    }
    private static class FakePm extends MockPackageManager {
        ApplicationInfo app=new ApplicationInfo();
        ActivityInfo activity=new ActivityInfo();
        Intent launcher; boolean missing,throwsLookup; Set<String> packages;
        FakePm() {
            app.enabled=true;activity.applicationInfo=app;activity.enabled=true;activity.exported=true;
            activity.packageName="ecarx.membercenter";activity.name="ecarx.membercenter.Entry";
            launcher=new Intent(Intent.ACTION_MAIN).setComponent(new ComponentName(activity.packageName,activity.name));
        }
        public ApplicationInfo getApplicationInfo(String pkg,int flags)throws NameNotFoundException {
            if(missing||(packages!=null&&!packages.contains(pkg)))throw new NameNotFoundException();if(throwsLookup)throw new SecurityException();return app;
        }
        public Intent getLaunchIntentForPackage(String pkg){if(throwsLookup)throw new SecurityException();return launcher;}
        public ResolveInfo resolveActivity(Intent i,int flags){ResolveInfo r=new ResolveInfo();r.activityInfo=activity;return r;}
        public ActivityInfo getActivityInfo(ComponentName c,int flags){return activity;}
    }
    private static class FakeContext extends ContextWrapper {
        FakePm pm=new FakePm();int launches;Intent last;boolean deny,failStart;
        FakeContext(Context c){super(c);}
        public PackageManager getPackageManager(){return pm;}
        public int checkSelfPermission(String permission){return deny?PackageManager.PERMISSION_DENIED:PackageManager.PERMISSION_GRANTED;}
        public void startActivity(Intent i){if(failStart)throw new SecurityException();launches++;last=i;}
    }
    private AppWidgetProviderInfo provider(String pkg,String cls) {
        AppWidgetProviderInfo i=new AppWidgetProviderInfo();i.provider=new ComponentName(pkg,cls);return i;
    }
    private void catalogAndPackageTests() {
        OfficialCatalog catalog=new OfficialCatalog(context);
        check(catalog.providers(null).isEmpty(),"null type is safe");
        check(catalog.providers("unknown").isEmpty(),"unknown type is closed");
        check(catalog.providers("music").equals(catalog.providers("media")),"music alias");
        check(catalog.providers("nav").equals(catalog.providers("navigation")),"navigation alias");
        check(catalog.applicationPackages("settings").equals(Arrays.asList("com.ecarx.settings","ecarx.settings")),"DCY11 settings before Utilities variant");
        check(catalog.applicationPackages("weather").equals(Arrays.asList("com.ecarx.smartcloud","ecarx.weather")),"DCY11 weather before Utilities variant");
        check(catalog.applicationPackages("member").equals(Arrays.asList("ecarx.membercenter")),"account exact package");
        check(catalog.applicationPackages("cleanup").equals(Arrays.asList("ecarx.autosecure")),"cleanup exact package");
        int count=0;for(String type:Arrays.asList("media","navigation","weather","calendar","member","cleanup","tpms","air","ride"))count+=catalog.providers(type).size();
        check(count==14,"all 14 catalog components retained");
        List<ComponentName> weather=catalog.providers("weather");
        AppWidgetProviderInfo first=provider(weather.get(0).getPackageName(),weather.get(0).getClassName());
        AppWidgetProviderInfo second=provider(weather.get(1).getPackageName(),weather.get(1).getClassName());
        AppWidgetProviderInfo spoof=provider("ecarx.home",first.provider.getClassName());
        check(OfficialEntryAdapter.select(weather,Arrays.asList(spoof),null)==null,"same class wrong package rejected");
        check(OfficialEntryAdapter.select(weather,Arrays.asList(provider("com.ecarx.smartcloud","unknown.Provider")),null)==null,"right package wrong class rejected");
        check(OfficialEntryAdapter.select(weather,Arrays.asList(second,first),null)==first,"catalog order wins over installed order");
        check(OfficialEntryAdapter.select(weather,Arrays.asList(second,first),second.provider)==second,"persisted supported variant retained");
        check(OfficialEntryAdapter.select(weather,null,null)==null,"provider service empty");
        FakeContext fake=new FakeContext(context);AppRepository apps=new AppRepository(fake);
        check(!apps.launchPackage(null)&&!apps.launchPackage(""),"null/empty package rejected");
        fake.pm.missing=true;check("not-installed".equals(apps.packageStatus("ecarx.membercenter"))&&!apps.launchPackage("ecarx.membercenter"),"missing package fallback");fake.pm.missing=false;
        fake.pm.app.enabled=false;check("disabled".equals(apps.packageStatus("ecarx.membercenter"))&&!apps.launchPackage("ecarx.membercenter"),"disabled app");fake.pm.app.enabled=true;
        fake.pm.launcher=null;check(!apps.launchPackage("ecarx.membercenter"),"no launch activity");fake.pm.launcher=new Intent(Intent.ACTION_MAIN);
        fake.pm.activity.exported=false;check(!apps.launchPackage("ecarx.membercenter"),"nonexported activity");fake.pm.activity.exported=true;
        fake.pm.activity.enabled=false;check(!apps.launchPackage("ecarx.membercenter"),"disabled activity");fake.pm.activity.enabled=true;
        fake.pm.activity.permission="fixture.signature";fake.deny=true;check(!apps.launchPackage("ecarx.membercenter"),"protected activity");fake.deny=false;fake.pm.activity.permission=null;
        fake.pm.activity.packageName="ecarx.membercenter.fake";check(!apps.launchPackage("ecarx.membercenter"),"foreign resolved app rejected");fake.pm.activity.packageName="ecarx.membercenter";
        check(fake.launches==0,"all negative paths avoid starts");
        check(apps.launchPackage("ecarx.membercenter")&&fake.launches==1&&fake.last.getComponent().getPackageName().equals("ecarx.membercenter"),"launch pinned to checked package");
        check((fake.last.getFlags()&Intent.FLAG_ACTIVITY_NEW_TASK)!=0,"works with service context");
        fake.failStart=true;check(!apps.launchPackage("ecarx.membercenter"),"start permission race caught");fake.failStart=false;
        fake.pm.throwsLookup=true;check("unavailable".equals(apps.packageStatus("ecarx.membercenter"))&&!apps.launchPackage("ecarx.membercenter"),"lookup failures caught");
        fake.pm.throwsLookup=false;fake.pm.packages=new HashSet<String>(Arrays.asList("ecarx.settings"));
        fake.pm.activity.packageName="ecarx.settings";
        check(new OfficialCatalog(fake).packageFor("settings").equals("ecarx.settings"),"installed Utilities settings variant selected");
        fake.pm.packages=new HashSet<String>(Arrays.asList("ecarx.weather"));fake.pm.activity.packageName="ecarx.weather";
        check(new OfficialCatalog(fake).packageFor("weather").equals("ecarx.weather"),"installed weather variant selected");
        check(apps.launchOfficial("weather")&&fake.last.getComponent().getPackageName().equals("ecarx.weather"),"official fallback tries evidence-backed packages only");
    }
    private OfficialWidgetActivity launch(String type) {
        return (OfficialWidgetActivity)startActivitySync(new Intent(context,OfficialWidgetActivity.class).setAction(Intent.ACTION_MAIN).putExtra("type",type).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }
    private Object value(final Activity a,final String field) {
        final Object[] out=new Object[1];
        runOnMainSync(new Runnable(){public void run(){try{Field f=OfficialWidgetActivity.class.getDeclaredField(field);f.setAccessible(true);out[0]=f.get(a);}catch(Exception e){throw new RuntimeException(e);}}});
        return out[0];
    }
    private void settled(OfficialWidgetActivity a) {
        long end=SystemClock.uptimeMillis()+6000;
        do{waitForIdleSync();if(((Integer)value(a,"pendingRequest"))==0)return;SystemClock.sleep(50);}while(SystemClock.uptimeMillis()<end);
        throw new AssertionError("widget flow did not settle");
    }
    private void close(final Activity a) {runOnMainSync(new Runnable(){public void run(){a.finish();}});waitForIdleSync();}
    private void mode(String mode)throws Exception {
        final CountDownLatch done=new CountDownLatch(1);
        context.sendOrderedBroadcast(new Intent().setComponent(new ComponentName("ecarx.calendar","ecarx.calendar.ModeReceiver")).putExtra("mode",mode),null,
            new BroadcastReceiver(){public void onReceive(Context c,Intent i){done.countDown();}},new Handler(Looper.getMainLooper()),Activity.RESULT_OK,null,null);
        check(done.await(3,TimeUnit.SECONDS),"fixture mode configured");
    }
    private void hostTests()throws Exception {
        OfficialWidgetActivity missing=launch("member");settled(missing);
        check(!(Boolean)value(missing,"committed")&&host.getAppWidgetIds().length==0,"absent widget allocates no ID");
        check(!((Button)value(missing,"openApp")).isEnabled(),"absent app entry disabled");close(missing);
        mode("ok");OfficialWidgetActivity calendar=launch("calendar");settled(calendar);
        check((Boolean)value(calendar,"committed"),"real binder bind/config completes");
        int id=(Integer)value(calendar,"widgetId");
        check(host.getAppWidgetIds().length==1,"one owned widget allocation");
        check(((Button)value(calendar,"openApp")).isEnabled(),"app entry independent of widget grant");
        Bundle size=AppWidgetManager.getInstance(context).getAppWidgetOptions(id);
        check(size.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)>0&&size.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)>0,"widget receives measured dp dimensions");
        close(calendar);calendar=launch("calendar");settled(calendar);
        check((Integer)value(calendar,"widgetId")==id&&host.getAppWidgetIds().length==1,"completed binding survives reopen without duplicate");close(calendar);
        host.deleteHost();context.getSharedPreferences("widgets",0).edit().clear().commit();
        mode("cancel");calendar=launch("calendar");settled(calendar);
        check(!(Boolean)value(calendar,"committed")&&host.getAppWidgetIds().length==0,"cancelled configuration releases bound ID");
        check(!context.getSharedPreferences("widgets",0).contains("calendar")&&!context.getSharedPreferences("widgets",0).contains("calendar.pending"),"cancel does not persist incomplete binding");
        check(((Button)value(calendar,"openApp")).isEnabled(),"cancel retains application fallback");close(calendar);
        AppWidgetHost foreign=new AppWidgetHost(context,75302);int foreignId=foreign.allocateAppWidgetId();
        context.getSharedPreferences("widgets",0).edit().putInt("calendar",foreignId).commit();mode("ok");
        calendar=launch("calendar");settled(calendar);
        check((Boolean)value(calendar,"committed")&&(Integer)value(calendar,"widgetId")!=foreignId,"foreign host preference not reused");
        check(foreign.getAppWidgetIds().length==1&&foreign.getAppWidgetIds()[0]==foreignId,"foreign host ID never deleted");close(calendar);foreign.deleteHost();host.deleteHost();
        context.getSharedPreferences("widgets",0).edit().clear().commit();
        int abandoned=host.allocateAppWidgetId();context.getSharedPreferences("widgets",0).edit().putInt("calendar.pending",abandoned).commit();
        calendar=launch("calendar");settled(calendar);
        check((Boolean)value(calendar,"committed")&&host.getAppWidgetIds().length==1,"abandoned pending allocation recovered on reopen");
        check((Integer)value(calendar,"widgetId")!=abandoned&&!context.getSharedPreferences("widgets",0).contains("calendar.pending"),"recovery deletes old pending ID and journal");close(calendar);host.deleteHost();
        int aliasId=foreign.allocateAppWidgetId();
        context.getSharedPreferences("widgets",0).edit().putInt("nav",aliasId).commit();
        OfficialWidgetActivity nav=launch("nav");settled(nav);
        check(!context.getSharedPreferences("widgets",0).contains("nav"),"legacy alias preference migrated");
        check(foreign.getAppWidgetIds().length==1&&foreign.getAppWidgetIds()[0]==aliasId,"alias migration never deletes another host ID");close(nav);foreign.deleteHost();
    }
    private void deniedBinding() {
        ActivityMonitor monitor=addMonitor(new IntentFilter(AppWidgetManager.ACTION_APPWIDGET_BIND),new ActivityResult(Activity.RESULT_CANCELED,null),true);
        OfficialWidgetActivity calendar=launch("calendar");settled(calendar);
        check(monitor.getHits()==1,"system authorization requested");
        check(!(Boolean)value(calendar,"committed")&&host.getAppWidgetIds().length==0,"denied bind releases allocation");
        check(((Button)value(calendar,"openApp")).isEnabled(),"denied bind retains app fallback");
        removeMonitor(monitor);close(calendar);
    }
}
