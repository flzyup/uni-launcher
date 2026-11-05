package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import android.os.SystemClock;
import android.view.InputEvent;
import android.view.KeyEvent;
import java.io.IOException;
import java.lang.reflect.Method;
import org.json.JSONObject;

/**
 * 媒体键注入：传输控制拿不到时的最后一级。
 *
 * <p>部分车机播放器（酷狗车机版这类）既不发布可用的 {@code TransportControls}，
 * 又把方控键拦在自己手里，于是桌面这一侧看到的按键就是死键。它们只在「焦点窗口
 * 收到按键」时才动作，所以唯一的执行器只能是按键注入。
 *
 * <p>两级通道：{@code InputManager.injectInputEvent} 优先——车机包已声明
 * {@code INJECT_EVENTS} 并随平台签名授予，亚毫秒级、没有进程开销；
 * {@code input keyevent} 命令只作为系统权限没拿到时的兜底（每键一次进程 fork，
 * 二十毫秒起步）。
 *
 * <p>注入下去的键会从原车输入回调 / 标准会话再回来一次，回环要在调用方挡掉
 * （见 {@code MediaAdapter#injectedEcho}），否则一次按键会走两步。
 */
public final class SteeringKeyInjector {
    /** INJECT_INPUT_EVENT_MODE_ASYNC：方控要的是即时响应，不等派发结果。 */
    private static final int MODE_ASYNC=0;
    private final Context context;
    private Object input;
    private Method injectInputEvent;
    private volatile String mode="未启动",reason="";
    private volatile int injected,executed,failed,lastKey=-1;

    public SteeringKeyInjector(Context context){this.context=context.getApplicationContext();}

    /**
     * 注入一个媒体键。
     *
     * @return 通道确实把事件送出去了。播放器有没有反应是另一回事，别把它当成功判据。
     */
    public boolean inject(int keyCode){
        if(keyCode<0)return false;
        if(reflect()){
            long now=SystemClock.uptimeMillis();
            try{
                injectInputEvent.invoke(input,new KeyEvent(now,now,KeyEvent.ACTION_DOWN,keyCode,0),MODE_ASYNC);
                injectInputEvent.invoke(input,new KeyEvent(now,now+1,KeyEvent.ACTION_UP,keyCode,0),MODE_ASYNC);
                injected++;lastKey=keyCode;
                return true;
            }catch(Throwable e){
                // 通常是权限被回收或注入服务拒绝：别再每键重试反射，直接落到命令通道。
                reason="注入失败："+name(e);
                injectInputEvent=null;
                input=null;
            }
        }
        return command(keyCode);
    }

    /** 反射一次并缓存；失败时记住原因，后续直接走命令通道。 */
    private boolean reflect(){
        if(injectInputEvent!=null)return true;
        try{
            input=context.getSystemService("input");
            if(input==null){reason="没有输入服务";return false;}
            Method method=input.getClass().getMethod("injectInputEvent",InputEvent.class,int.class);
            method.setAccessible(true);
            injectInputEvent=method;mode="injectInputEvent";reason="";
            return true;
        }catch(Throwable e){
            reason="injectInputEvent 不可用："+name(e);
            mode="";
            return false;
        }
    }

    private boolean command(int keyCode){
        try{
            Runtime.getRuntime().exec(new String[]{"input","keyevent",String.valueOf(keyCode)});
            executed++;lastKey=keyCode;mode="input 命令";
            return true;
        }catch(IOException|RuntimeException e){
            failed++;reason="input 命令失败："+name(e);
            return false;
        }
    }

    /** 诊断：当前生效通道、两条通道各送出多少、最后一个键。 */
    public JSONObject snapshot(){
        JSONObject out=new JSONObject();
        try{out.put("mode",mode).put("injected",injected).put("executed",executed)
            .put("failed",failed).put("lastKey",lastKey).put("reason",reason);}catch(Exception ignored){}
        return out;
    }

    private static String name(Throwable e){
        while(e.getCause()!=null&&e.getCause()!=e)e=e.getCause();
        return e.getClass().getSimpleName();
    }
}
