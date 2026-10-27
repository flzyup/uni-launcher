package ecarx.xsf.mediacenter.widget;

import android.appwidget.AppWidgetProvider;
import android.appwidget.AppWidgetManager;
import android.content.Context;
import android.widget.RemoteViews;

public final class MediaWidgetProvider1x2 extends AppWidgetProvider {
    public void onUpdate(Context c,AppWidgetManager m,int[] ids){
        for(int id:ids){RemoteViews views=new RemoteViews(c.getPackageName(),c.getResources().getIdentifier("fixture_view","layout",c.getPackageName()));
            views.setTextViewText(android.R.id.text1,"UNI emulator fixture widget");views.setTextViewText(android.R.id.text2,"Synthetic RemoteViews / host ID "+id);m.updateAppWidget(id,views);}
    }
}
