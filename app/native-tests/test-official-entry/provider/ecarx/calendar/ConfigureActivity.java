package ecarx.calendar;
import android.app.*;
import android.appwidget.*;
import android.content.*;
import android.os.*;
public final class ConfigureActivity extends Activity {
    public void onCreate(Bundle b) {
        super.onCreate(b);
        int id=getIntent().getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID,-1);
        String mode=getSharedPreferences("fixture",0).getString("mode","ok");
        if("hold".equals(mode)) return;
        if(!"cancel".equals(mode)) {
            android.widget.RemoteViews views=new android.widget.RemoteViews(getPackageName(),android.R.layout.simple_list_item_1);
            views.setTextViewText(android.R.id.text1,"SYNTHETIC OEM FIXTURE - NOT REAL DATA");
            AppWidgetManager.getInstance(this).updateAppWidget(id,views);
            setResult(RESULT_OK,new Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID,id));
        }
        finish();
    }
}
