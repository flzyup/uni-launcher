package xyz.i4o.uni.spectrumfixture;
import android.app.Activity;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.AudioFormat;
import android.os.Bundle;
import android.os.Handler;
import android.widget.TextView;
/** Test-only known audible output; no microphone, never installed on the car. */
public final class ToneActivity extends Activity {
    private AudioTrack tone;
    private final Handler main = new Handler();
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        if (!android.os.Build.FINGERPRINT.contains("generic") && !android.os.Build.MODEL.contains("sdk")) { finish(); return; }
        TextView label=new TextView(this);label.setText("UNI test tone · emulator only · auto-stop 10min");setContentView(label);
        AudioManager audio=(AudioManager)getSystemService(AUDIO_SERVICE);
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, Math.max(1,audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)/2),0);
        int rate=48000;
        short[] samples=new short[rate];
        for(int i=0;i<rate;i++)samples[i]=(short)(8000*Math.sin(2*Math.PI*660*i/rate)+6000*Math.sin(2*Math.PI*1320*i/rate));
        tone=new AudioTrack(AudioManager.STREAM_MUSIC,rate,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT,samples.length*2,AudioTrack.MODE_STATIC);
        tone.write(samples,0,samples.length);tone.setLoopPoints(0,samples.length,-1);tone.play();
        main.postDelayed(new Runnable(){public void run(){finish();}},600000);
    }
    @Override public void onDestroy(){main.removeCallbacksAndMessages(null);if(tone!=null){tone.stop();tone.release();tone=null;}super.onDestroy();}
}
