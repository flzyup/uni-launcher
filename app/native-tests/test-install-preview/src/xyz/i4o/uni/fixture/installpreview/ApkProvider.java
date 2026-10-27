package xyz.i4o.uni.fixture.installpreview;
import android.content.*;
import android.database.*;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import java.io.*;
public final class ApkProvider extends ContentProvider {
    public boolean onCreate(){return true;}
    public String getType(Uri uri){return "application/vnd.android.package-archive";}
    public ParcelFileDescriptor openFile(Uri uri,String mode)throws FileNotFoundException{
        if(!"/package.apk".equals(uri.getPath())||!"r".equals(mode))throw new FileNotFoundException();
        return ParcelFileDescriptor.open(new File(getContext().getFilesDir(),"candidate.apk"),ParcelFileDescriptor.MODE_READ_ONLY);
    }
    public Cursor query(Uri uri,String[] projection,String selection,String[] args,String order){
        MatrixCursor c=new MatrixCursor(new String[]{"_display_name","_size"});
        c.addRow(new Object[]{"UNI 安装验证.apk",new File(getContext().getFilesDir(),"candidate.apk").length()});return c;
    }
    public Uri insert(Uri u,ContentValues v){throw new UnsupportedOperationException();}
    public int update(Uri u,ContentValues v,String s,String[] a){throw new UnsupportedOperationException();}
    public int delete(Uri u,String s,String[] a){throw new UnsupportedOperationException();}
}
