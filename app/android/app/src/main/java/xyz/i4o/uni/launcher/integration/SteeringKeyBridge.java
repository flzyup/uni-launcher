package xyz.i4o.uni.launcher.integration;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.LinkedHashMap;
import java.util.Map;
import org.json.JSONArray;
import org.json.JSONObject;
import xyz.i4o.uni.launcher.core.SteeringKeyPolicy;

/**
 * 方控与中控按键的原车输入通道。
 *
 * 方控不走 AOSP 媒体键，由系统 {@code EcarxInputDispatcherService} 派发 ECARX 自定义码，
 * 客户端只有两条注册路径（反编译见 car-reports/carcontrol/STEERING_KEYS.md）：
 * <ol>
 *   <li>适配层 {@code com.ecarx.xui.adaptapi.input.Input#requestKeysInterception}；</li>
 *   <li>底层 binder {@code android.cevt.dcy11.inputmanager.InputManager#setCallback}。</li>
 * </ol>
 * 两条路都只做被动监听：注册回调不改写原车按键路由，播放器自己照旧收到媒体键。
 * 接口全用反射，车机没有对应类时安静退回「未接入」，不影响桌面其他功能。
 */
public final class SteeringKeyBridge {
    /** 收到可映射按键时的回调，动作语义见 {@link SteeringKeyPolicy#action(int)}。 */
    public interface Sink { void onSteeringAction(String action,int keyCode); }

    private static final String ADAPT_INPUT="com.ecarx.xui.adaptapi.input.Input";
    private static final String ADAPT_CALLBACK="com.ecarx.xui.adaptapi.input.IKeyCallback";
    private static final String DISPATCH_MANAGER="android.cevt.dcy11.inputmanager.InputManager";
    private static final String DISPATCH_CALLBACK="android.cevt.dcy11.inputmanager.IInputCallback";
    private static final int SEEN_LIMIT=32;

    private final Context context;
    private final Sink sink;
    private final Handler main=new Handler(Looper.getMainLooper());
    /** 实车按下过的按键码与次数：用来核对中控那颗键到底派发的是哪个码。 */
    private final Map<Integer,Integer> seen=new LinkedHashMap<Integer,Integer>(){
        @Override protected boolean removeEldestEntry(Map.Entry<Integer,Integer> eldest){return size()>SEEN_LIMIT;}
    };
    private volatile boolean running;
    private Object input,dispatcher,callback;
    private Class<?> callbackType;
    private String mode="",reason="未启动";
    private int accepted,events,lastCode=-1;

    public SteeringKeyBridge(Context context,Sink sink){
        this.context=context;
        this.sink=sink;
    }

    /** 接入原车输入通道。重复调用无副作用，先适配层后 binder。 */
    public void start(){
        if(running)return;
        running=true;
        if(registerAdaptApi())return;
        if(registerDispatcher())return;
        if(reason.isEmpty()||"未启动".equals(reason))reason="未发现原车方控输入接口";
    }

    public void stop(){
        running=false;
        Object instance=input;
        Class<?> type=callbackType;
        Object handler=callback;
        input=null;dispatcher=null;callback=null;callbackType=null;
        if("adaptapi".equals(mode)&&instance!=null&&handler!=null&&type!=null){
            try{instance.getClass().getMethod("abandonKeysInterception",type).invoke(instance,handler);}
            catch(Throwable ignored){}
        }else if("dispatcher".equals(mode)&&instance!=null&&type!=null){
            // 底层 binder 没有反注册接口，交回空回调让服务端不再回送。
            try{instance.getClass().getMethod("setCallback",type).invoke(instance,new Object[]{null});}
            catch(Throwable ignored){}
        }
        mode="";
    }

    /** 是否已经接上原车输入通道。 */
    public boolean installed(){return ("adaptapi".equals(mode)&&accepted>0)||"dispatcher".equals(mode);}

    private boolean registerAdaptApi(){
        try{
            ClassLoader loader=loader(ADAPT_INPUT);
            Class<?> type=Class.forName(ADAPT_CALLBACK,true,loader);
            Object instance=Class.forName(ADAPT_INPUT,true,loader).getMethod("create",Context.class).invoke(null,context);
            if(instance==null){reason="原车输入适配层未创建实例";return false;}
            Object handler=Proxy.newProxyInstance(type.getClassLoader(),new Class<?>[]{type},(proxy,method,args)->adaptValue(proxy,method,args));
            int[] granted=(int[])instance.getClass().getMethod("requestKeysInterception",int[].class,type)
                .invoke(instance,SteeringKeyPolicy.interceptKeys(),handler);
            if(granted==null||granted.length==0){reason="原车未接受任何按键监听";return false;}
            input=instance;callback=handler;callbackType=type;accepted=granted.length;mode="adaptapi";
            reason="已接入原车方控输入（"+accepted+" 个键）";
            return true;
        }catch(Throwable e){
            reason="原车输入适配层不可用："+name(e);
            return false;
        }
    }

    private boolean registerDispatcher(){
        try{
            ClassLoader loader=context.getClassLoader();
            Class<?> type=Class.forName(DISPATCH_CALLBACK,true,loader);
            Object instance=Class.forName(DISPATCH_MANAGER,true,loader).getDeclaredConstructor().newInstance();
            Object handler=Proxy.newProxyInstance(type.getClassLoader(),new Class<?>[]{type},(proxy,method,args)->dispatcherValue(proxy,method,args));
            instance.getClass().getMethod("setCallback",type).invoke(instance,handler);
            dispatcher=instance;input=instance;callback=handler;callbackType=type;mode="dispatcher";
            reason="已接入原车按键派发回调";
            return true;
        }catch(Throwable e){
            if(reason.isEmpty()||"未启动".equals(reason))reason="原车按键派发回调不可用："+name(e);
            return false;
        }
    }

    /** 适配层回调：按下/抬起各一次，只认按下。 */
    private Object adaptValue(Object proxy,Method method,Object[] args){
        String function=method.getName();
        if("onKeyPressed".equals(function)){
            if(args!=null&&args.length>0&&args[0] instanceof Number)handle(((Number)args[0]).intValue());
            return Boolean.TRUE;
        }
        if("onKeyReleased".equals(function))return Boolean.FALSE;
        return objectValue(proxy,method,args);
    }

    /** 底层回调：onKeyEvent(键值, 0 按下 / 1 抬起)。 */
    private Object dispatcherValue(Object proxy,Method method,Object[] args){
        if("onKeyEvent".equals(method.getName())&&args!=null&&args.length>=2&&args[0] instanceof Number){
            int action=args[1] instanceof Number?((Number)args[1]).intValue():-1;
            if(action==0)handle(((Number)args[0]).intValue());
            return null;
        }
        return objectValue(proxy,method,args);
    }

    private void handle(int keyCode){
        events++;lastCode=keyCode;
        boolean first;
        synchronized(seen){Integer count=seen.get(keyCode);first=count==null;seen.put(keyCode,count==null?1:count+1);}
        String action=SteeringKeyPolicy.action(keyCode);
        // 每个键第一次出现记一条：实车核对中控那颗键派发的是哪个码，靠的就是这行。
        if(first)android.util.Log.i("UniSteeringKeys","key="+keyCode+" action="+(action.isEmpty()?"-":action));
        // 音量之类不归桌面管的键只进诊断计数，不打扰媒体适配层。
        if(action.isEmpty()||!running)return;
        main.post(()->{if(running&&sink!=null)sink.onSteeringAction(action,keyCode);});
    }

    private Object objectValue(Object proxy,Method method,Object[] args){
        String function=method.getName();
        if("hashCode".equals(function))return System.identityHashCode(proxy);
        if("equals".equals(function))return args!=null&&args.length>0&&proxy==args[0];
        if("toString".equals(function))return "UNI steering key bridge";
        Class<?> type=method.getReturnType();
        if(type==boolean.class)return Boolean.FALSE;
        if(type==int.class)return 0;
        if(type==long.class)return 0L;
        return null;
    }

    private ClassLoader loader(String name)throws Exception{
        ClassLoader loader=context.getClassLoader();
        try{Class.forName(name,true,loader);return loader;}
        catch(ClassNotFoundException absent){
            return context.createPackageContext("com.ecarx.systemui.plugin",
                Context.CONTEXT_INCLUDE_CODE|Context.CONTEXT_IGNORE_SECURITY).getClassLoader();
        }
    }

    private static String name(Throwable e){
        while(e.getCause()!=null&&e.getCause()!=e)e=e.getCause();
        return e.getClass().getSimpleName();
    }

    /** 诊断：接入方式、被接受的键、实车按下过的键码与次数。 */
    public JSONObject snapshot(){
        JSONObject out=new JSONObject();
        try{
            JSONArray requested=new JSONArray();
            for(int code:SteeringKeyPolicy.interceptKeys())requested.put(code);
            JSONObject counts=new JSONObject();
            synchronized(seen){for(Map.Entry<Integer,Integer> entry:seen.entrySet())counts.put(String.valueOf(entry.getKey()),entry.getValue());}
            out.put("installed",installed()).put("mode",mode).put("reason",reason)
                .put("requested",requested).put("accepted",accepted)
                .put("events",events).put("lastCode",lastCode).put("seen",counts);
        }catch(Exception ignored){}
        return out;
    }
}
