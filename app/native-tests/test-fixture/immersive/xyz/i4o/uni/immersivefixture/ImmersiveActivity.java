package xyz.i4o.uni.immersivefixture;
import android.app.Activity;
import android.os.Bundle;
import android.graphics.Color;
import android.view.*;
import android.widget.*;
/** Generic fixture: deliberately unrelated to any music app package. */
public final class ImmersiveActivity extends Activity {
    @Override public void onCreate(Bundle state){super.onCreate(state);
        FrameLayout root=new FrameLayout(this);root.setBackgroundColor(Color.rgb(24,39,57));
        LinearLayout actions=new LinearLayout(this);actions.setOrientation(LinearLayout.VERTICAL);
        String[] labels={"NORMAL", "IMMERSIVE STICKY", "IMMERSIVE", "STATUS FULLSCREEN ONLY", "LEGACY HIDE NAVIGATION", "STICKY WITHOUT HIDE NAV (0x1500)", "FULLSCREEN LAYOUT ONLY (0x500)"};
        int[] flags={0,5894,3846,1028,1798,5376,1280};
        for(int i=0;i<labels.length;i++){
            final int value=flags[i];Button button=new Button(this);button.setText(labels[i]);
            button.setOnClickListener(v->getWindow().getDecorView().setSystemUiVisibility(value));
            actions.addView(button,new LinearLayout.LayoutParams(480,72));
        }
        FrameLayout.LayoutParams a=new FrameLayout.LayoutParams(480,labels.length*72,Gravity.TOP|Gravity.CENTER_HORIZONTAL);a.topMargin=80;
        root.addView(actions,a);
        TextView text=new TextView(this);text.setText("BOTTOM CONTENT — should be above normal dock; at screen bottom while immersive");text.setTextSize(18);text.setTextColor(Color.WHITE);
        root.addView(text,new FrameLayout.LayoutParams(-1,64,Gravity.BOTTOM));setContentView(root);
    }
}
