package xyz.i4o.uni.launcher.integration;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import java.io.File;
import java.io.FileNotFoundException;

/** Exposes only the validated update file to the system package installer. */
public final class OtaFileProvider extends ContentProvider {
  @Override public boolean onCreate(){ return true; }
  @Override public ParcelFileDescriptor openFile(Uri uri,String mode) throws FileNotFoundException {
    if (!"r".equals(mode) || !"update.apk".equals(uri.getLastPathSegment())) throw new FileNotFoundException("not allowed");
    File f=new File(new File(getContext().getFilesDir(),"ota"),"update.apk");
    if(!f.isFile()) throw new FileNotFoundException("not found");
    return ParcelFileDescriptor.open(f,ParcelFileDescriptor.MODE_READ_ONLY);
  }
  @Override public String getType(Uri u){return "application/vnd.android.package-archive";}
  @Override public Cursor query(Uri u,String[] p,String s,String[] a,String o){return null;}
  @Override public Uri insert(Uri u,ContentValues v){return null;}
  @Override public int delete(Uri u,String s,String[] a){return 0;}
  @Override public int update(Uri u,ContentValues v,String s,String[] a){return 0;}
}
