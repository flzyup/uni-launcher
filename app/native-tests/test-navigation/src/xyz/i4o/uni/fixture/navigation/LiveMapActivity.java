package xyz.i4o.uni.fixture.navigation;

import android.app.Activity;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;

/** Synthetic moving picture + multi-touch probe. Emulator only, not AMap. */
public final class LiveMapActivity extends Activity {
    private MapView map;
    @Override public void onCreate(Bundle state){
        super.onCreate(state);getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
        map=new MapView(this);setContentView(map);
    }
    @Override public void dump(String prefix,java.io.FileDescriptor fd,java.io.PrintWriter writer,String[] args){
        writer.println("NAV_FIXTURE={\"frames\":"+map.frames+",\"touchEvents\":"+map.touches
            +",\"maxPointers\":"+map.maxPointers+",\"lastAction\":"+map.lastAction
            +",\"displayId\":"+getWindowManager().getDefaultDisplay().getDisplayId()
            +",\"width\":"+map.getWidth()+",\"height\":"+map.getHeight()+"}");
    }
    private static final class MapView extends View {
        final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
        int frames,touches,maxPointers,lastAction=-1;
        MapView(Context context){super(context);setBackgroundColor(Color.rgb(8,24,38));}
        @Override public void onDraw(Canvas canvas){
            super.onDraw(canvas);frames++;
            paint.setColor(Color.rgb(35,67,82));paint.setStrokeWidth(2);
            for(int x=0;x<getWidth();x+=64)canvas.drawLine(x,0,x,getHeight(),paint);
            for(int y=0;y<getHeight();y+=64)canvas.drawLine(0,y,getWidth(),y,paint);
            paint.setColor(Color.CYAN);canvas.drawCircle((frames*9)%Math.max(1,getWidth()),getHeight()*.55f,28,paint);
            paint.setTextSize(32);canvas.drawText("LIVE MAP / "+frames+" / TOUCH "+touches,32,64,paint);
            canvas.drawText(getWidth()+" x "+getHeight(),32,108,paint);
            postInvalidateDelayed(50);
        }
        @Override public boolean onTouchEvent(MotionEvent event){
            touches++;lastAction=event.getActionMasked();maxPointers=Math.max(maxPointers,event.getPointerCount());invalidate();return true;
        }
    }
}
