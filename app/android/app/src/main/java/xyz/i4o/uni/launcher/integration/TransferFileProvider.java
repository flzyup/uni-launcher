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

/** 只读暴露 files/transfers/ 下的单个文件，供包安装器读取收到的 APK。 */
public final class TransferFileProvider extends ContentProvider {
    public static final String AUTHORITY = "xyz.i4o.uni.launcher.transfer";

    @Override public boolean onCreate() { return true; }

    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        String name = uri.getLastPathSegment();
        if (name == null) throw new FileNotFoundException("missing name");
        File dir = new File(getContext().getFilesDir(), "transfers");
        File f = new File(dir, name);
        try {
            String root = dir.getCanonicalPath() + File.separator;
            if (!f.getCanonicalPath().startsWith(root)) throw new FileNotFoundException("forbidden");
        } catch (FileNotFoundException e) {
            throw e;
        } catch (Exception e) {
            throw new FileNotFoundException("unreadable");
        }
        if (!f.isFile()) throw new FileNotFoundException("not found");
        // 安装器来取文件了：留一条记录，诊断时能对上「到底装的是哪个文件」。
        UniLog.i(LogTags.TRANSFER, "安装文件已提供给安装器", "name", name, "bytes", f.length());
        return ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override public String getType(Uri uri) { return "application/vnd.android.package-archive"; }
    @Override public Cursor query(Uri uri, String[] p, String s, String[] a, String o) { return null; }
    @Override public Uri insert(Uri uri, ContentValues values) { return null; }
    @Override public int delete(Uri uri, String selection, String[] args) { return 0; }
    @Override public int update(Uri uri, ContentValues values, String s, String[] a) { return 0; }
}
