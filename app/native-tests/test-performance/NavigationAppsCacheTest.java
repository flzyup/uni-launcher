import android.content.*;
import android.content.pm.*;
import org.json.*;
import xyz.i4o.uni.launcher.integration.NavigationApps;

/** Executes the production resolver against counting PackageManager doubles. */
public final class NavigationAppsCacheTest {
    private static int checks;
    private static final String AMAP="com.autonavi.amapauto", BAIDU="com.baidu.BaiduMap";
    private static void check(boolean ok,String message){checks++;if(!ok)throw new AssertionError(message);}
    public static void main(String[] args)throws Exception{
        Context app=new Context();
        app.pm.install(AMAP,"高德地图");app.pm.install(BAIDU,"百度地图");
        NavigationApps nav=new NavigationApps(new Context(app),app.prefs);
        JSONObject first=nav.snapshot();
        check(first.getString("package").equals(AMAP),"first snapshot resolves auto immediately");
        check(first.getString("label").equals("高德地图")&&first.getBoolean("canEmbed"),"label and embedding capability");
        check(first.getJSONArray("options").length()==2,"installed navigation options only");
        check(app.pm.launchQueries==8&&app.pm.labelQueries==2&&app.pm.infoQueries==2,"each candidate queried once, labels only for installed apps");
        int warmQueries=app.pm.totalQueries();
        for(int i=0;i<1000;i++){
            NavigationApps helper=new NavigationApps(new Context(app),app.prefs);
            helper.snapshot();helper.selected();helper.launchIntent();
        }
        check(app.pm.totalQueries()==warmQueries,"1000 snapshots/helpers perform zero extra package queries");
        check(app.registrations==1,"one package receiver on Application, no Activity registrations");
        first.getJSONArray("options").getJSONObject(0).put("label","tampered");first.put("package","tampered");
        check(nav.snapshot().getJSONArray("options").getJSONObject(0).getString("label").equals("高德地图"),"mutable JSON cannot corrupt cache");
        Intent returned=nav.launchIntent();returned.addFlags(123).setComponent(new ComponentName("wrong","Wrong"));
        check(nav.launchIntent().flags==0&&nav.launchIntent().component.getPackageName().equals(AMAP),"launch Intent defensively copied");
        app.prefs.put("navigationPackage",BAIDU);
        JSONObject selected=nav.snapshot();
        check(selected.getString("package").equals(BAIDU)&&selected.getString("label").equals("百度地图"),"preference switch visible without package broadcast");
        check(selected.getJSONArray("options").getJSONObject(0).getString("package").equals(BAIDU),"selected option placed first");
        check(app.pm.totalQueries()==warmQueries,"known navigation switch needs no new queries");
        app.prefs.put("embedNavigation",false);check(!nav.snapshot().getBoolean("canEmbed"),"embedding toggle remains live");
        app.prefs.put("embedNavigation",true);app.permission=-1;
        check(!nav.snapshot().getBoolean("canEmbed")&&!nav.snapshot().getBoolean("injectGranted"),"permission revocation remains live");
        app.permission=0;check(nav.snapshot().getBoolean("canEmbed"),"permission restoration immediate");
        app.pm.install("custom.navigation","自定义导航");app.prefs.put("navigationPackage","custom.navigation");
        check(nav.snapshot().getString("label").equals("自定义导航"),"new arbitrary selected package resolved immediately");
        check(nav.snapshot().getJSONArray("options").getJSONObject(0).getString("package").equals("custom.navigation"),"custom selected navigation included first");
        app.prefs.put("navigationPackage","missing.navigation");
        check(!nav.snapshot().getBoolean("installed")&&nav.launchIntent()==null,"missing explicit package does not fall back");
        int missingQueries=app.pm.totalQueries();nav.snapshot();check(app.pm.totalQueries()==missingQueries,"negative query cached");
        app.pm.install("missing.navigation","新导航");app.broadcast(Intent.ACTION_PACKAGE_ADDED,"missing.navigation");
        check(nav.snapshot().getBoolean("installed")&&nav.snapshot().getString("label").equals("新导航"),"install invalidates negative result");
        app.prefs.put("navigationPackage","auto");app.pm.remove(AMAP);app.broadcast(Intent.ACTION_PACKAGE_REMOVED,AMAP);
        check(nav.snapshot().getString("package").equals(BAIDU),"uninstall updates auto selection immediately");
        app.pm.install(AMAP,"高德更新");app.broadcast(Intent.ACTION_PACKAGE_ADDED,AMAP);
        check(nav.snapshot().getString("package").equals(AMAP),"install updates auto priority");
        app.pm.labels.put(AMAP,"高德新版");app.broadcast(Intent.ACTION_PACKAGE_REPLACED,AMAP);
        check(nav.snapshot().getString("label").equals("高德新版"),"replacement invalidates label");
        app.pm.disabled.add(AMAP);app.broadcast(Intent.ACTION_PACKAGE_CHANGED,AMAP);
        check(nav.snapshot().getString("package").equals(BAIDU),"disable invalidates launchability");
        app.pm.disabled.remove(AMAP);app.broadcast(Intent.ACTION_PACKAGE_CHANGED,AMAP);
        check(nav.snapshot().getString("package").equals(AMAP),"enable restores auto immediately");
        app.pm.labels.put(AMAP,"AMap");app.resources.configuration.locales="en-US";
        check(nav.snapshot().getString("label").equals("AMap"),"locale change refreshes cached labels");
        int afterLocale=app.pm.totalQueries();nav.snapshot();check(app.pm.totalQueries()==afterLocale,"localized cache stays warm");
        ActivityInfo info=new ActivityInfo();info.packageName=AMAP;info.name="MapActivity";app.pm.directInfo=info;
        check(nav.displayIntent().component.getClassName().equals("MapActivity"),"declared AMap no-op entry still resolved");
        info.exported=false;
        check(nav.displayIntent().component.getClassName().equals("Main"),"non-exported entry still falls back safely");
        info.exported=true;info.permission="private.permission";app.permission=-1;
        check(nav.displayIntent().component.getClassName().equals("Main"),"cached launch cannot bypass direct-entry permission gate");
        check(app.launches==0,"discovery never launches navigation");
        System.out.println("PASS NavigationAppsCacheTest: "+checks+" checks; warm 1000 snapshots/helpers = 0 additional PackageManager queries");
    }
}
