package xyz.i4o.uni.launcher;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.view.Gravity;
import android.view.View;
import android.widget.ArrayAdapter;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;
import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Locale;

/** Small built-in file browser for head units without a documents provider. */
public final class WallpaperPickerActivity extends Activity {
    private static final int REQUEST_READ=4207;
    private final ArrayList<File> entries=new ArrayList<>();
    private File directory;
    private TextView heading;
    private ListView list;
    private int generation;
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(Color.rgb(9,20,35));
        LinearLayout layout=new LinearLayout(this);layout.setOrientation(LinearLayout.VERTICAL);
        layout.setBackgroundColor(Color.rgb(12,25,41));
        heading=new TextView(this);heading.setTextColor(Color.WHITE);heading.setTextSize(20);
        heading.setPadding(32,20,32,20);heading.setGravity(Gravity.CENTER_VERTICAL);
        layout.addView(heading);
        list=new ListView(this);list.setDividerHeight(1);layout.addView(list,new LinearLayout.LayoutParams(-1,0,1));
        setContentView(layout);
        String permission=Build.VERSION.SDK_INT>=33?"android.permission.READ_MEDIA_IMAGES":android.Manifest.permission.READ_EXTERNAL_STORAGE;
        if(Build.VERSION.SDK_INT>=23&&checkSelfPermission(permission)!=PackageManager.PERMISSION_GRANTED)requestPermissions(new String[]{permission},REQUEST_READ);
        else open(Environment.getExternalStorageDirectory());
    }
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] grants){
        super.onRequestPermissionsResult(request,permissions,grants);
        if(request!=REQUEST_READ)return;
        if(grants.length>0&&grants[0]==PackageManager.PERMISSION_GRANTED)open(Environment.getExternalStorageDirectory());
        else {heading.setText("需要存储访问权限才能选择本地图片");}
    }
    private void open(File folder) {
        directory=folder;heading.setText("选择壁纸图片   ·   "+folder.getAbsolutePath());
        final int ticket=++generation;
        new Thread(()->{
            File[] found=folder.listFiles(file->{
                if(file.isHidden())return false;
                if(file.isDirectory())return true;
                String n=file.getName().toLowerCase(Locale.ROOT);
                return file.isFile()&&(n.endsWith(".jpg")||n.endsWith(".jpeg")||n.endsWith(".png")||n.endsWith(".webp"));
            });
            if(found==null)found=new File[0];
            Arrays.sort(found,Comparator.comparing((File f)->!f.isDirectory()).thenComparing(File::getName,String.CASE_INSENSITIVE_ORDER));
            final File[] files=found;
            runOnUiThread(()->{
                if(isFinishing()||ticket!=generation)return;
                entries.clear();ArrayList<String> names=new ArrayList<>();
                if(folder.getParentFile()!=null&&!"/".equals(folder.getAbsolutePath())){entries.add(folder.getParentFile());names.add("‹   返回上级目录");}
                for(File f:files){entries.add(f);names.add((f.isDirectory()?"▸   ":"▧   ")+f.getName());}
                if(names.isEmpty())names.add("此目录没有图片或文件夹");
                list.setAdapter(new ArrayAdapter<String>(this,android.R.layout.simple_list_item_1,names){
                    @Override public View getView(int position,View convert,android.view.ViewGroup parent){TextView row=(TextView)super.getView(position,convert,parent);row.setTextColor(Color.rgb(223,233,245));row.setTextSize(18);row.setPadding(36,16,24,16);return row;}
                });
                list.setOnItemClickListener((parent,view,index,id)->{
                    if(index>=entries.size())return;
                    File selected=entries.get(index);
                    if(selected.isDirectory())open(selected);
                    else {setResult(RESULT_OK,new Intent().putExtra("wallpaperPath",selected.getAbsolutePath()));finish();}
                });
            });
        },"uni-wallpaper-list").start();
    }
    @Override public void onBackPressed(){
        if(directory!=null&&directory.getParentFile()!=null&&!"/".equals(directory.getAbsolutePath()))open(directory.getParentFile());
        else super.onBackPressed();
    }
}
