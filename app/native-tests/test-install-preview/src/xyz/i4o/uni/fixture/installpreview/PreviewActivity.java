package xyz.i4o.uni.fixture.installpreview;
import android.app.Activity;
import android.os.Bundle;
import android.content.Intent;
import android.net.Uri;
import android.widget.TextView;
import java.io.*;
public final class PreviewActivity extends Activity {
    private TextView text;
    @Override public void onCreate(Bundle state){
        super.onCreate(state);text=new TextView(this);text.setTextSize(32);text.setText("等待安装确认页");setContentView(text);
        if(state!=null)return;
        try(InputStream in=getAssets().open("candidate.apk");OutputStream out=new FileOutputStream(new File(getFilesDir(),"candidate.apk"))){
            byte[] buffer=new byte[8192];int n;while((n=in.read(buffer))>=0)out.write(buffer,0,n);
        }catch(IOException e){text.setText("ERROR");return;}
        Intent preview=new Intent(Intent.ACTION_INSTALL_PACKAGE,Uri.parse("content://xyz.i4o.uni.fixture.installpreview.apk/package.apk"))
            .setPackage("com.android.packageinstaller").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION).putExtra(Intent.EXTRA_RETURN_RESULT,true);
        startActivityForResult(preview,41);
    }
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);text.setText("RESULT:"+result);}
}
