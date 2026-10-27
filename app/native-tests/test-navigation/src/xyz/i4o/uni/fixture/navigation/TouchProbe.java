package xyz.i4o.uni.fixture.navigation;

import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.MotionEvent;

/** Shell-side two-finger test on the emulator's physical display only. */
public final class TouchProbe {
    public static void main(String[] args)throws Exception{
        Object properties=Class.forName("android.os.SystemProperties").getMethod("get",String.class).invoke(null,"ro.kernel.qemu");
        if(!"1".equals(properties))throw new SecurityException("Emulator required");
        Object manager=Class.forName("android.hardware.input.InputManager").getMethod("getInstance").invoke(null);
        java.lang.reflect.Method inject=manager.getClass().getMethod("injectInputEvent",InputEvent.class,int.class);inject.setAccessible(true);
        long start=SystemClock.uptimeMillis();
        int[] actions={0,5|(1<<8),2,6|(1<<8),1};
        for(int step=0;step<actions.length;step++){
            int count=step==0||step==4?1:2;
            MotionEvent.PointerProperties[] pp=new MotionEvent.PointerProperties[count];
            MotionEvent.PointerCoords[] pc=new MotionEvent.PointerCoords[count];
            for(int i=0;i<count;i++){
                pp[i]=new MotionEvent.PointerProperties();pp[i].id=i;pp[i].toolType=MotionEvent.TOOL_TYPE_FINGER;
                pc[i]=new MotionEvent.PointerCoords();pc[i].x=450+i*200+(step==2?(i==0?-50:50):0);pc[i].y=450;pc[i].pressure=1;pc[i].size=1;
            }
            MotionEvent event=MotionEvent.obtain(start,SystemClock.uptimeMillis(),actions[step],count,pp,pc,0,0,1,1,0,0,InputDevice.SOURCE_TOUCHSCREEN,0);
            try{if(!Boolean.TRUE.equals(inject.invoke(manager,event,2)))throw new IllegalStateException("Injection failed");}
            finally{event.recycle();}
            Thread.sleep(80);
        }
        System.out.println("EMULATOR_TWO_FINGER_INJECTED");
    }
}
