package xyz.i4o.uni.launcher.integration;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.database.ContentObserver;
import android.database.Cursor;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.provider.CalendarContract;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Locale;
import org.json.JSONObject;

/** System calendar source. Date fields are always available; agenda fields are
 * read only after Android grants READ_CALENDAR. */
public final class SystemCalendarAdapter {
    private final Context context;
    private final Runnable changed;
    private final Handler main=new Handler(Looper.getMainLooper());
    private HandlerThread thread;
    private Handler worker;
    private volatile boolean running;
    private volatile String state="{}";
    private final ContentObserver observer=new ContentObserver(main){
        @Override public void onChange(boolean selfChange){refresh();}
    };
    private final Runnable poll=new Runnable(){@Override public void run(){
        if(!running)return;
        String next=read().toString();
        if(!next.equals(state)){state=next;main.post(()->{if(running)changed.run();});}
        if(running)worker.postDelayed(this,60000);
    }};
    public SystemCalendarAdapter(Context context,Runnable changed){this.context=context;this.changed=changed;state=dateBase().toString();}
    public void start(){
        if(running)return;running=true;
        if(thread==null){thread=new HandlerThread("uni-calendar");thread.start();worker=new Handler(thread.getLooper());}
        try{context.getContentResolver().registerContentObserver(CalendarContract.Events.CONTENT_URI,true,observer);}catch(Exception ignored){}
        refresh();
    }
    public void stop(){
        if(!running)return;running=false;
        try{context.getContentResolver().unregisterContentObserver(observer);}catch(Exception ignored){}
        if(worker!=null)worker.removeCallbacksAndMessages(null);
    }
    public void refresh(){if(running&&worker!=null){worker.removeCallbacks(poll);worker.post(poll);}}
    public JSONObject snapshot(){try{return new JSONObject(state);}catch(Exception e){return dateBase();}}
    private JSONObject dateBase(){
        JSONObject result=new JSONObject();Calendar now=Calendar.getInstance();Locale locale=Locale.SIMPLIFIED_CHINESE;
        try{return result.put("available",true).put("day",now.get(Calendar.DAY_OF_MONTH))
            .put("weekday",new SimpleDateFormat("EEEE",locale).format(now.getTime()))
            .put("monthLabel",new SimpleDateFormat("yyyy 年 M 月",locale).format(now.getTime()))
            .put("todayStartMs",startOfDay(now).getTimeInMillis()).put("source","android-calendar");
        }catch(Exception ignored){return result;}
    }
    private JSONObject read(){
        JSONObject result=dateBase();boolean authorized=context.checkSelfPermission(Manifest.permission.READ_CALENDAR)==PackageManager.PERMISSION_GRANTED;
        try{result.put("authorized",authorized).put("eventAvailable",false);
            if(!authorized)return result.put("reason","点击授权后显示系统日程");
            Calendar now=Calendar.getInstance(),end=(Calendar)now.clone();end.add(Calendar.DAY_OF_YEAR,7);
            String[] projection={CalendarContract.Instances.TITLE,CalendarContract.Instances.EVENT_LOCATION,
                CalendarContract.Instances.BEGIN,CalendarContract.Instances.END,CalendarContract.Instances.ALL_DAY};
            try(Cursor cursor=CalendarContract.Instances.query(context.getContentResolver(),projection,now.getTimeInMillis(),end.getTimeInMillis())){
                if(cursor!=null&&cursor.moveToFirst()){
                    long begin=cursor.getLong(2),finish=cursor.getLong(3);String title=clean(cursor.getString(0)),location=clean(cursor.getString(1));
                    boolean today=begin<startOfNextDay(now).getTimeInMillis();
                    result.put("eventAvailable",true).put("title",title.isEmpty()?"未命名日程":title).put("location",location)
                        .put("beginMs",begin).put("endMs",finish).put("allDay",cursor.getInt(4)!=0).put("today",today).put("reason","");
                }else result.put("reason","未来七天没有日程");
            }
        }catch(Exception|LinkageError e){try{result.put("eventAvailable",false).put("reason","系统日历暂不可读取");}catch(Exception ignored){}}
        return result;
    }
    private static Calendar startOfDay(Calendar value){Calendar out=(Calendar)value.clone();out.set(Calendar.HOUR_OF_DAY,0);out.set(Calendar.MINUTE,0);out.set(Calendar.SECOND,0);out.set(Calendar.MILLISECOND,0);return out;}
    private static Calendar startOfNextDay(Calendar value){Calendar out=startOfDay(value);out.add(Calendar.DAY_OF_YEAR,1);return out;}
    private static String clean(String value){if(value==null)return "";value=value.replace('\n',' ').replace('\r',' ').trim();return value.substring(0,Math.min(120,value.length()));}
}
