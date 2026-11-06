package xyz.i4o.uni.launcher.integration;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.view.KeyEvent;
import org.json.JSONObject;

/**
 * 酷狗车机版专用媒体键旁路。
 *
 * <p>酷狗车机版不发布可用的传输控制，并且会抢走方控键；推动它只有它自己的
 * {@code byd.intent.action.MEDIA_BUTTON} 广播这一条路。纯广播，零权限，比按键注入
 * 更准（只有酷狗会收到，不影响焦点窗口）。
 *
 * <p>只在包真的装了、且当前音源就是它时才启用；其余情况交给
 * {@link SteeringKeyInjector}。
 */
public final class KugouKeyRelay {
    public static final String PACKAGE="com.kugou.android.auto";
    private static final String RECEIVER="com.kugou.android.auto.byd.broadcast.BYDBroadcastReceiver";
    private static final String ACTION="byd.intent.action.MEDIA_BUTTON";
    private final Context context;
    private Boolean present;
    private int sent,lastKey=-1;
    private String reason="";

    public KugouKeyRelay(Context context){this.context=context.getApplicationContext();}

    /** 只有这条通道真的能用时才接管，避免把按键投进不存在的接收器。 */
    public boolean send(String source,int keyCode){
        if(!PACKAGE.equals(source)||keyCode<0)return false;
        if(!installed())return false;
        try{
            context.sendBroadcast(intent(keyCode));
            sent++;lastKey=keyCode;
            android.util.Log.i("UniSteeringKeys","kugou relay key="+keyCode);
            return true;
        }catch(RuntimeException e){
            reason="广播失败："+e.getClass().getSimpleName();
            return false;
        }
    }

    private boolean installed(){
        Boolean cached=present;
        if(cached!=null)return cached;
        boolean found;
        try{context.getPackageManager().getPackageInfo(PACKAGE,0);found=true;}
        catch(PackageManager.NameNotFoundException absent){found=false;}
        catch(RuntimeException e){found=false;reason="查询安装状态失败："+e.getClass().getSimpleName();}
        present=found;
        return found;
    }

    private Intent intent(int keyCode){
        Intent intent=new Intent(ACTION).setComponent(new ComponentName(PACKAGE,RECEIVER)).putExtra("pkgName",PACKAGE);
        if(keyCode>=0)intent.putExtra("android.intent.extra.KEY_EVENT",new KeyEvent(KeyEvent.ACTION_DOWN,keyCode));
        return intent;
    }

    public JSONObject snapshot(){
        JSONObject out=new JSONObject();
        try{out.put("installed",present!=null&&present).put("sent",sent).put("lastKey",lastKey).put("reason",reason);}catch(Exception ignored){}
        return out;
    }
}
