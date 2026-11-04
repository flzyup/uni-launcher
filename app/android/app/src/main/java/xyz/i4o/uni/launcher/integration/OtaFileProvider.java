package xyz.i4o.uni.launcher.integration;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import java.io.File;
import java.io.FileNotFoundException;
import xyz.i4o.uni.launcher.log.LogTags;
import xyz.i4o.uni.launcher.log.UniLog;

/** Exposes only the validated update file to the system package installer. */
public final class OtaFileProvider extends ContentProvider {
  @Override public boolean onCreate(){ return true; }
  @Override public ParcelFileDescriptor openFile(Uri uri,String mode) throws FileNotFoundException {
    String segment=uri.getLastPathSegment();
    if (!"r".equals(mode) || !"update.apk".equals(segment)) {
      UniLog.fail(LogTags.OTA,"ota/download","reason","not-allowed","mode",mode,"segment",segment);
      throw new FileNotFoundException("not allowed");
    }
    File dir=new File(getContext().getFilesDir(),"ota");
    File f=new File(dir,"update.apk");
    if(!f.isFile()) {
      UniLog.fail(LogTags.OTA,"ota/download","reason","not-found");
      throw new FileNotFoundException("not found");
    }
    UniLog.enter(LogTags.OTA,"ota/download","name",segment,"bytes",f.length());
    // 安装器真正拿到的是哪一个包、什么摘要：装不上时先确认它和下载器校验过的是同一个包。
    long actualBytes=f.length();
    String actualSha=sha256(f);
    long apkVersion=archiveVersionCode(f);
    long installedVersion=installedVersionCode();
    String identity=expectedIdentity(dir);
    String expectedSha=null;long expectedBytes=-1L;
    if(identity!=null){
      int sep=identity.indexOf(':');
      if(sep>0){
        expectedSha=identity.substring(0,sep);
        try{expectedBytes=Long.parseLong(identity.substring(sep+1));}catch(NumberFormatException ignored){}
      }
    }
    UniLog.done(LogTags.OTA,"ota/download","bytes",actualBytes,"sha256",actualSha);
    UniLog.enter(LogTags.OTA,"ota/install","apkVersionCode",apkVersion,"installedVersionCode",installedVersion);
    ParcelFileDescriptor descriptor=ParcelFileDescriptor.open(f,ParcelFileDescriptor.MODE_READ_ONLY);
    UniLog.done(LogTags.OTA,"ota/install","apkVersionCode",apkVersion,"installedVersionCode",installedVersion,
        "bytes",actualBytes,"sha256",actualSha,
        "expectedSha256",expectedSha,"expectedBytes",expectedBytes,
        "sha256Match",expectedSha==null?null:expectedSha.equalsIgnoreCase(actualSha),
        "bytesMatch",expectedBytes<0?null:expectedBytes==actualBytes);
    return descriptor;
  }
  /** 下载器写下的期望值（"<sha256>:<bytes>"）；装完就被删了，缺失时返回 null。 */
  private static String expectedIdentity(File dir){
    try{
      File identity=new File(dir,"update.identity");
      if(!identity.isFile())return null;
      java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream();
      try(java.io.InputStream in=new java.io.FileInputStream(identity)){
        byte[] buffer=new byte[256];int n;
        while((n=in.read(buffer))>=0)out.write(buffer,0,n);
      }
      String text=new String(out.toByteArray(),"UTF-8").trim();
      return text.isEmpty()?null:text;
    }catch(Exception e){return null;}
  }
  private static String sha256(File f){
    try(java.io.InputStream in=new java.io.FileInputStream(f)){
      java.security.MessageDigest md=java.security.MessageDigest.getInstance("SHA-256");
      byte[] buffer=new byte[65536];int n;
      while((n=in.read(buffer))>=0)md.update(buffer,0,n);
      StringBuilder hex=new StringBuilder();
      // 不用 String.format("%02x",b)：有符号字节的格式化规则容易踩坑，直接按位取十六进制。
      for(byte b:md.digest())hex.append(Character.forDigit((b>>4)&0xf,16)).append(Character.forDigit(b&0xf,16));
      return hex.toString();
    }catch(Exception e){return null;}
  }
  private long archiveVersionCode(File f){
    try{
      android.content.Context c=getContext();
      if(c==null)return -1L;
      android.content.pm.PackageInfo info=c.getPackageManager().getPackageArchiveInfo(f.getAbsolutePath(),0);
      return info==null?-1L:info.versionCode;
    }catch(Exception e){return -1L;}
  }
  private long installedVersionCode(){
    try{
      android.content.Context c=getContext();
      if(c==null)return -1L;
      return c.getPackageManager().getPackageInfo(c.getPackageName(),0).versionCode;
    }catch(Exception e){return -1L;}
  }
  @Override public String getType(Uri u){return "application/vnd.android.package-archive";}
  @Override public Cursor query(Uri u,String[] p,String s,String[] a,String o){return null;}
  @Override public Uri insert(Uri u,ContentValues v){return null;}
  @Override public int delete(Uri u,String s,String[] a){return 0;}
  @Override public int update(Uri u,ContentValues v,String s,String[] a){return 0;}
}
