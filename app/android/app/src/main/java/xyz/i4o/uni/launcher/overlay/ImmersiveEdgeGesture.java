package xyz.i4o.uni.launcher.overlay;

import android.content.Context;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.os.Build;
import android.util.DisplayMetrics;
import android.view.*;

/** A thin non-focusable edge only while an external app hides navigation.
 * The app keeps the rest of the screen and the full-screen task bounds.
 */
public final class ImmersiveEdgeGesture implements AutoCloseable {
    private final WindowManager windows;
    private final View edge;
    private final WindowManager.LayoutParams bounds;
    private boolean attached, fired;
    private float startX,startY;
    private final float threshold;
    public ImmersiveEdgeGesture(Context context,boolean internalWindow,Runnable reveal) {
        windows=(WindowManager)context.getSystemService(Context.WINDOW_SERVICE);
        threshold=24*context.getResources().getDisplayMetrics().density;
        edge=new View(context);edge.setBackgroundColor(Color.TRANSPARENT);
        edge.setOnApplyWindowInsetsListener((v,i)->i.consumeSystemWindowInsets().consumeStableInsets());
        bounds=new WindowManager.LayoutParams();
        bounds.type=internalWindow?2024:Build.VERSION.SDK_INT>=26?WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY:WindowManager.LayoutParams.TYPE_PHONE;
        bounds.format=PixelFormat.TRANSLUCENT;bounds.gravity=Gravity.TOP|Gravity.LEFT;
        bounds.setTitle("UNI Immersive Edge");
        bounds.flags=WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE|WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
            |WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN|WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS;
        edge.setOnTouchListener((v,e)->{
            if(e.getActionMasked()==MotionEvent.ACTION_DOWN){startX=e.getRawX();startY=e.getRawY();fired=false;return true;}
            if(e.getActionMasked()==MotionEvent.ACTION_MOVE&&!fired){
                float up=startY-e.getRawY(),horizontal=Math.abs(startX-e.getRawX());
                if(up>threshold&&up>horizontal*1.2f){fired=true;reveal.run();}
            }
            return true;
        });
    }
    public void show(boolean show) {
        if(!show){if(attached){windows.removeViewImmediate(edge);attached=false;}return;}
        DisplayMetrics real=new DisplayMetrics();windows.getDefaultDisplay().getRealMetrics(real);
        int height=Math.max(6,Math.round(real.widthPixels*8f/1920f));
        boolean changed=bounds.width!=real.widthPixels||bounds.height!=height||bounds.y!=real.heightPixels-height;
        bounds.width=real.widthPixels;bounds.height=height;bounds.x=0;bounds.y=real.heightPixels-height;
        if(!attached){windows.addView(edge,bounds);attached=true;}
        else if(changed)windows.updateViewLayout(edge,bounds);
    }
    @Override public void close(){show(false);}
}
