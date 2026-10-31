package xyz.i4o.uni.launcher.platform;

import android.app.Activity;
import android.app.ActivityOptions;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.MotionEvent;
import android.view.Surface;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import xyz.i4o.uni.launcher.integration.NavigationApps;

/** Android 9 navigation rendered directly into Flutter's live texture.
 * The display and producer Surface survive page/modal visibility changes.
 * No ActivityView/SurfaceView, screenshot, PixelCopy or Canvas buffer queue.
 */
public final class LiveNavigationHost {
    private final Activity activity;
    private final BinaryMessenger messenger;
    private final TextureRegistry textures;
    private final MethodChannel host;
    private final Handler main=new Handler(Looper.getMainLooper());
    private LiveMap map;
    private int nextId;
    private boolean closed,hostVisible=true;
    public LiveNavigationHost(Activity activity,BinaryMessenger messenger,TextureRegistry textures){
        this.activity=activity;this.messenger=messenger;this.textures=textures;
        host=new MethodChannel(messenger,"xyz.i4o.uni.launcher/navigation");
        host.setMethodCallHandler((call,result)->{
            try{
                if("create".equals(call.method)){
                    if(closed)throw new IllegalStateException("Navigation host closed");
                    String pkg=apps().selected();
                    if(map!=null&&!map.disposed&&map.requestedVisible&&hostVisible)
                        throw new IllegalStateException("Navigation already visible in another card");
                    if(map!=null){map.close();map=null;}
                    map=new LiveMap(nextId++,pkg,dimension(call.argument("width"),1920),dimension(call.argument("height"),1080),scale(call.argument("scale")));
                    result.success(map.status());
                    LiveMap created=map;main.post(()->{if(map==created&&!created.disposed)created.activate();});
                }else if("dispose".equals(call.method)){
                    Object id=call.arguments;
                    if(id instanceof Map)id=((Map<?,?>)id).get("id");
                    if(map!=null&&id instanceof Number&&((Number)id).intValue()==map.id){map.close();map=null;}
                    result.success(null);
                }else result.notImplemented();
            }catch(Exception|LinkageError error){result.error("navigation_unavailable","地图实时容器无法启动",null);}
        });
    }
    private NavigationApps apps(){return new NavigationApps(activity,activity.getSharedPreferences("launcher",0));}
    /** 纹理缩放系数，只接受 (0.3, 1] 以免误配出无法使用的画面。 */
    private static float scale(Object raw){
        if(!(raw instanceof Number))return 1f;
        double value=((Number)raw).doubleValue();
        return Double.isFinite(value)&&value>0.3&&value<=1?((float)value):1f;
    }

    private int dimension(Object raw,int maximum){
        if(!(raw instanceof Number))throw new IllegalArgumentException("Missing map dimensions");
        double value=((Number)raw).doubleValue();
        if(!Double.isFinite(value)||value<1)throw new IllegalArgumentException("Invalid map dimensions");
        return Math.max(64,Math.min(maximum,(int)Math.round(value)));
    }
    public void setVisible(boolean visible){
        boolean changed=hostVisible!=visible;hostVisible=visible;
        if(map!=null){if(!visible)map.cancelTouch();if(changed&&visible&&map.requestedVisible)map.activate();else map.publish();}
    }
    // Texture composition moves with Flutter. There is no independent Android
    // layer to hide and no Surface recreation fence during page animations.
    public void preparePageChange(){}
    public void trimMemory(int level){
        // A live producer has no disposable preview/cache. Keep its display
        // stable; the engines' image caches handle their own pressure callback.
    }
    public org.json.JSONArray snapshot(){
        org.json.JSONArray result=new org.json.JSONArray();if(map!=null)result.put(new org.json.JSONObject(map.status()));return result;
    }
    public void close(){if(closed)return;closed=true;main.removeCallbacksAndMessages(null);host.setMethodCallHandler(null);if(map!=null){map.close();map=null;}}

    private final class LiveMap {
        final int id;
        final String pkg;
        final MethodChannel channel;
        final AtomicBoolean awaitingFrame=new AtomicBoolean(true);
        final AtomicLong consumedFrames=new AtomicLong();
        TextureRegistry.SurfaceTextureEntry texture;
        Surface surface;
        VirtualDisplay display;
        Object inputForwarder;
        java.lang.reflect.Method forwardEvent;
        int width,height,activationCount,launchCount,taskMoves,resizeCount,placementAttempts,generation;
        /** 纹理像素缩放：只降分辨率，密度同比降，保证导航 App 看到的 dp 尺寸不变。 */
        final float scale;
        boolean disposed,requestedVisible=true,ready,pointerDown;
        long downTime;
        String phase="loading",reason="正在载入实时地图";
        final Runnable timeout=()->{if(!disposed&&!ready){phase="unavailable";reason="地图未输出画面，请重试或全屏打开";publish();}};
        LiveMap(int id,String pkg,int logicalWidth,int logicalHeight,float scale)throws Exception{
            this.id=id;this.pkg=pkg;this.scale=scale;
            this.width=pixels(logicalWidth);this.height=pixels(logicalHeight);
            channel=new MethodChannel(messenger,"xyz.i4o.uni.launcher/map/"+id);
            channel.setMethodCallHandler((call,result)->{
                try{
                    if("status".equals(call.method))result.success(status());
                    else if("visible".equals(call.method)){
                        boolean next=Boolean.TRUE.equals(call.arguments),changed=requestedVisible!=next;
                        requestedVisible=next;if(!next)cancelTouch();if(changed&&next&&hostVisible)activate();else publish();result.success(null);
                    }else if("resize".equals(call.method)){
                        resize(dimension(call.argument("width"),1920),dimension(call.argument("height"),1080));result.success(null);
                    }else if("touch".equals(call.method)){touch(call.arguments);result.success(null);}
                    else if("retry".equals(call.method)){ready=false;awaitingFrame.set(true);activate();result.success(null);}
                    else if("dispose".equals(call.method)){close();if(map==this)map=null;result.success(null);}
                    else result.notImplemented();
                }catch(Exception|LinkageError error){result.error("navigation_unavailable","地图操作暂不可用",null);}
            });
            try{createDisplay();}
            catch(Exception|LinkageError error){close();throw error;}
        }
        Map<String,Object> status(){
            Map<String,Object> status=new HashMap<>();
            status.put("id",id);status.put("viewId",id);status.put("renderMode","realtime");
            status.put("phase",phase);status.put("reason",reason);status.put("ready",ready);
            status.put("displayId",display==null?-1:display.getDisplay().getDisplayId());
            if(texture!=null)status.put("textureId",texture.id());
            status.put("width",width);status.put("height",height);
            status.put("hostVisible",hostVisible);status.put("cardVisible",requestedVisible);
            status.put("activationCount",activationCount);status.put("resizeCount",resizeCount);
            status.put("launchCount",launchCount);status.put("taskMoves",taskMoves);
            status.put("consumedFrames",consumedFrames.get());
            return status;
        }
        void publish(){if(!disposed)channel.invokeMethod("status",status());}
        void createDisplay()throws Exception{
            if(!apps().snapshot().optBoolean("canEmbed"))throw new IllegalStateException("Embedding permission unavailable");
            texture=textures.createSurfaceTexture();
            texture.surfaceTexture().setDefaultBufferSize(width,height);
            texture.setOnFrameConsumedListener(()->{
                consumedFrames.incrementAndGet();
                if(awaitingFrame.compareAndSet(true,false))main.post(()->{
                    if(disposed)return;ready=true;phase="ready";reason="实时地图已连接";main.removeCallbacks(timeout);publish();
                });
            });
            surface=new Surface(texture.surfaceTexture());
            DisplayManager manager=(DisplayManager)activity.getSystemService(Context.DISPLAY_SERVICE);
            display=manager.createVirtualDisplay("UNI Live Navigation "+id,width,height,textureDensity(),surface,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC|DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY);
            if(display==null)throw new IllegalStateException("Virtual display unavailable");
            // Match ActivityView's Android 9 contract without its SurfaceView.
            Object wm=Class.forName("android.view.WindowManagerGlobal").getMethod("getWindowManagerService").invoke(null);
            java.lang.reflect.Method override=wm.getClass().getMethod("dontOverrideDisplayInfo",int.class);override.setAccessible(true);
            override.invoke(wm,display.getDisplay().getDisplayId());
            Object input=Class.forName("android.hardware.input.InputManager").getMethod("getInstance").invoke(null);
            java.lang.reflect.Method create=input.getClass().getMethod("createInputForwarder",int.class);create.setAccessible(true);
            inputForwarder=create.invoke(input,display.getDisplay().getDisplayId());
            forwardEvent=inputForwarder.getClass().getMethod("forwardEvent",InputEvent.class);forwardEvent.setAccessible(true);
        }
        int pixels(int logical){return Math.max(64,Math.min(1920,Math.round(logical*scale)));}

        /** 密度同比缩放，导航 App 的 dp 逻辑尺寸保持不变，因此它自己的界面不会重排。 */
        int textureDensity(){
            int base=activity.getResources().getDisplayMetrics().densityDpi;
            return Math.max(72,Math.round(base*scale));
        }

        void resize(int logicalWidth,int logicalHeight){
            int nextWidth=pixels(logicalWidth),nextHeight=pixels(logicalHeight);
            if(disposed||width==nextWidth&&height==nextHeight)return;
            cancelTouch();width=nextWidth;height=nextHeight;resizeCount++;
            texture.surfaceTexture().setDefaultBufferSize(width,height);
            display.resize(width,height,textureDensity());
            ready=false;awaitingFrame.set(true);phase="loading";reason="正在调整实时地图";publish();
            main.removeCallbacks(timeout);main.postDelayed(timeout,10000);
        }
        void activate(){
            if(disposed||!hostVisible||!requestedVisible||display==null)return;
            try{
                if(!pkg.equals(apps().selected()))return;
                Intent intent=apps().displayIntent();if(intent==null)throw new IllegalStateException("Navigation app removed");
                ComponentName existing=placeExistingTask();
                // The texture's producer never detaches on hide. An existing
                // map needs only task placement, not another singleTask intent.
                // Android 9 devices lacking the secondary-activities feature
                // can ignore launchDisplayId and send that intent back to 0.
                if(existing==null){
                    ActivityOptions options=ActivityOptions.makeBasic();options.setLaunchDisplayId(display.getDisplay().getDisplayId());
                    activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),options.toBundle());launchCount++;
                }
                activationCount++;placementAttempts=0;int epoch=++generation;
                main.postDelayed(()->verifyPlacement(epoch),200);
                if(!ready){phase="loading";reason="正在载入实时地图";main.removeCallbacks(timeout);main.postDelayed(timeout,10000);}
                publish();
            }catch(Exception|LinkageError error){phase="unavailable";reason="地图实时接入失败，请使用全屏入口";android.util.Log.w("UniMap","Live display launch",error);publish();}
        }
        ComponentName placeExistingTask()throws Exception{
            Object manager=Class.forName("android.app.ActivityManager").getMethod("getService").invoke(null);
            java.lang.reflect.Method all=manager.getClass().getMethod("getAllStackInfos");all.setAccessible(true);
            for(Object stack:(List<?>)all.invoke(manager)){
                Class<?> type=stack.getClass();String[] names=(String[])type.getField("taskNames").get(stack);
                if(names==null||names.length!=1||names[0]==null||!names[0].startsWith(pkg+"/"))continue;
                if(type.getField("displayId").getInt(stack)!=display.getDisplay().getDisplayId()){
                    java.lang.reflect.Method move=manager.getClass().getMethod("moveStackToDisplay",int.class,int.class);move.setAccessible(true);
                    move.invoke(manager,type.getField("stackId").getInt(stack),display.getDisplay().getDisplayId());
                    taskMoves++;
                    // AMap keeps full-screen Activity bounds after moving back.
                    // Resize the stack before it draws, so the existing view tree
                    // relayouts without clearing the live texture.
                    java.lang.reflect.Method resizeStack=manager.getClass().getMethod("resizeStack",int.class,android.graphics.Rect.class,boolean.class,boolean.class,boolean.class,int.class);
                    resizeStack.setAccessible(true);
                    resizeStack.invoke(manager,type.getField("stackId").getInt(stack),new android.graphics.Rect(0,0,width,height),true,true,false,-1);
                }
                return ComponentName.unflattenFromString(names[0]);
            }return null;
        }
        void verifyPlacement(int epoch){
            if(disposed||epoch!=generation||!hostVisible||!requestedVisible)return;
            try{
                if(placeExistingTask()!=null)return;
                if(++placementAttempts<20)main.postDelayed(()->verifyPlacement(epoch),250);
            }catch(Exception|LinkageError error){android.util.Log.w("UniMap","Live map placement",error);}
        }
        void touch(Object raw)throws Exception{
            if(disposed||!hostVisible||!requestedVisible||!(raw instanceof Map))return;
            Map<?,?> values=(Map<?,?>)raw;Object actionValue=values.get("action"),rawPointers=values.get("pointers");
            if(!(actionValue instanceof Number)||!(rawPointers instanceof List))throw new IllegalArgumentException("Invalid pointer event");
            int action=((Number)actionValue).intValue();
            if(action!=0&&action!=1&&action!=2&&action!=3&&action!=5&&action!=6)throw new IllegalArgumentException("Invalid pointer action");
            List<?> pointers=(List<?>)rawPointers;int count=pointers.size();
            if(count<1||count>10)throw new IllegalArgumentException("Invalid pointer count");
            int index=values.get("actionIndex") instanceof Number?((Number)values.get("actionIndex")).intValue():0;
            if(index<0||index>=count)throw new IllegalArgumentException("Invalid action index");
            MotionEvent.PointerProperties[] properties=new MotionEvent.PointerProperties[count];
            MotionEvent.PointerCoords[] coords=new MotionEvent.PointerCoords[count];HashSet<Integer> ids=new HashSet<>();
            for(int i=0;i<count;i++){
                if(!(pointers.get(i) instanceof Map))throw new IllegalArgumentException("Invalid pointer");
                Map<?,?> pointer=(Map<?,?>)pointers.get(i);Object identifier=pointer.get("id"),x=pointer.get("x"),y=pointer.get("y");
                if(!(identifier instanceof Number)||!(x instanceof Number)||!(y instanceof Number))throw new IllegalArgumentException("Invalid pointer coordinates");
                int pid=((Number)identifier).intValue();double px=((Number)x).doubleValue(),py=((Number)y).doubleValue();
                if(pid<0||pid>31||!ids.add(pid)||!Double.isFinite(px)||!Double.isFinite(py))throw new IllegalArgumentException("Invalid pointer coordinates");
                properties[i]=new MotionEvent.PointerProperties();properties[i].id=pid;properties[i].toolType=MotionEvent.TOOL_TYPE_FINGER;
                coords[i]=new MotionEvent.PointerCoords();coords[i].x=(float)(Math.max(0,Math.min(1,px))*width);coords[i].y=(float)(Math.max(0,Math.min(1,py))*height);coords[i].pressure=1;coords[i].size=1;
            }
            long now=SystemClock.uptimeMillis();if(action==0){downTime=now;pointerDown=true;}
            if(!pointerDown&&action!=0)return;
            MotionEvent event=MotionEvent.obtain(downTime,now,action|((action==5||action==6)?index<<MotionEvent.ACTION_POINTER_INDEX_SHIFT:0),count,properties,coords,0,0,1,1,0,0,InputDevice.SOURCE_TOUCHSCREEN,0);
            try{forwardEvent.invoke(inputForwarder,event);}finally{event.recycle();}
            if(action==1||action==3)pointerDown=false;
        }
        void cancelTouch(){
            if(!pointerDown||forwardEvent==null)return;
            MotionEvent event=MotionEvent.obtain(downTime,SystemClock.uptimeMillis(),MotionEvent.ACTION_CANCEL,0,0,0);event.setSource(InputDevice.SOURCE_TOUCHSCREEN);
            try{forwardEvent.invoke(inputForwarder,event);}catch(Exception ignored){}finally{event.recycle();pointerDown=false;}
        }
        void close(){
            if(disposed)return;cancelTouch();disposed=true;generation++;main.removeCallbacks(timeout);channel.setMethodCallHandler(null);
            if(display!=null){display.release();display=null;}
            if(surface!=null){surface.release();surface=null;}
            if(texture!=null){texture.setOnFrameConsumedListener(null);texture.release();texture=null;}
            inputForwarder=null;forwardEvent=null;
        }
    }
}
