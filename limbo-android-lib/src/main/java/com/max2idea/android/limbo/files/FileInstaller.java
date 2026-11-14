/*
Copyright (C) Max Kastanas 2012

 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 */
package com.max2idea.android.limbo.files;

import android.app.Activity;
import android.content.Context;
import android.content.res.AssetManager;
import android.net.Uri;
import android.content.pm.PackageInfo;
import android.os.Build;
import androidx.documentfile.provider.DocumentFile;
import android.util.Log;

import com.limbo.emu.lib.R;
import com.max2idea.android.limbo.dontknowhy.Config;
import com.max2idea.android.limbo.dontknowhy.LimboApplication;
import com.max2idea.android.limbo.toast.ToastUtils;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Locale;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.zip.CRC32;

/**
 *
 * @author dev
 */
public class FileInstaller {
    private static final String TAG = "FileInstaller";

    public static void installFiles(Activity activity, boolean force) {
        Log.d(TAG, "Installing files");
        File tmpDir = new File(LimboApplication.getBasefileDir());
        if (!tmpDir.exists()) {
            if(tmpDir.mkdirs()) {
                ToastUtils.toastShort(activity, activity.getString(R.string.CouldNotCreateBaseDir) + ": " + tmpDir.getPath());
                return;
            }
        }

        File tmpDir1 = new File(LimboApplication.getMachineDir());
        if (!tmpDir1.exists()) {
            if(tmpDir.mkdirs()) {
                ToastUtils.toastShort(activity, activity.getString(R.string.CouldNotCreateMachineDir) + ": " + tmpDir.getPath());
            }
        }

        //Install base dir
        File dir = new File(LimboApplication.getBasefileDir());
        if (dir.exists() && dir.isDirectory()) {
            //don't create again
        } else if (dir.exists() && !dir.isDirectory()) {
            Log.e(TAG, "Could not create Dir, file found: " + LimboApplication.getBasefileDir());
            return;
        } else if (!dir.exists()) {
            dir.mkdir();
        }

        String destDir = LimboApplication.getBasefileDir();

        // LIMBO: the assets are copied into the cache dir, which survives app
        // updates, so a rebuilt APK used to keep serving the previous roms and
        // firmware.  Remember which APK installed the current copy and do a
        // full verification pass whenever it changes.
        String assetsTag = assetsTag(activity);
        String installedTag = readAssetsTag(tmpDir);
        final boolean verifyAll = assetsTag != null && !assetsTag.equals(installedTag);
        if (verifyAll) {
            Log.w(TAG, "Roms were installed by another build (was " + installedTag
                    + ", now " + assetsTag + "); verifying all installed assets");
        }
        boolean installOk = true;

        //Get each file in assets under ./roms/ and install in SDCARD
        AssetManager am = activity.getResources().getAssets();
        String[] files = null;
        try {
            files = am.list("roms");
        } catch (IOException ex) {
            Logger.getLogger(FileInstaller.class.getName()).log(Level.SEVERE, null, ex);
            Log.e(TAG, "Could not install files: " + ex.getMessage());
            return;
        }

        for (int i = 0; i < files.length; i++) {
            String[] subfiles = null;
            try {
                subfiles = am.list("roms/" + files[i]);
            } catch (IOException ex) {
                Logger.getLogger(FileInstaller.class.getName()).log(Level.SEVERE, null, ex);
            }
            if (subfiles != null && subfiles.length > 0) {
                //Install base dir
                File dir1 = new File(LimboApplication.getBasefileDir() + files[i]);
                if (dir1.exists() && dir1.isDirectory()) {
                    //don't create again
                } else if (dir1.exists() && !dir1.isDirectory()) {
                    Log.e(TAG, "Could not create Dir, file found: " + LimboApplication.getBasefileDir() + files[i]);
                    return;
                } else if (!dir1.exists()) {
                    dir1.mkdir();
                }
                for (int k = 0; k < subfiles.length; k++) {

                    File file = new File(destDir, files[i] + "/" + subfiles[k]);
                    if(!file.exists() || force
                            || assetNeedsReinstall(am, files[i] + "/" + subfiles[k], file, verifyAll)) {
                        Log.d(TAG, "Installing file: " + file.getPath());
                        installOk &= installAssetFile(activity, files[i] + "/" + subfiles[k], destDir, "roms", null);
                    }
                }
            } else {
                File file = new File(destDir, files[i]);
                if(!file.exists() || force || assetNeedsReinstall(am, files[i], file, verifyAll)) {
                    Log.d(TAG, "Installing file: " + file.getPath());
                    installOk &= installAssetFile(activity, files[i], LimboApplication.getBasefileDir(), "roms", null);
                }
            }
        }

        if (installOk && assetsTag != null) {
            writeAssetsTag(tmpDir, assetsTag);
        }
    }

    private static final String ASSETS_TAG_FILE = ".assets-tag";

    private static String assetsTag(Activity activity) {
        try {
            PackageInfo pi = activity.getPackageManager()
                    .getPackageInfo(activity.getPackageName(), 0);
            long versionCode = (Build.VERSION.SDK_INT >= 28)
                    ? pi.getLongVersionCode() : pi.versionCode;
            return versionCode + "-" + pi.lastUpdateTime;
        } catch (Exception e) {
            Log.e(TAG, "Could not read package info: " + e.getMessage());
            return null;
        }
    }

    private static String readAssetsTag(File baseDir) {
        File f = new File(baseDir, ASSETS_TAG_FILE);
        if (!f.exists()) {
            return null;
        }
        InputStream is = null;
        try {
            is = new FileInputStream(f);
            byte[] buf = new byte[128];
            int n = is.read(buf);
            return n > 0 ? new String(buf, 0, n).trim() : "";
        } catch (Exception e) {
            Log.e(TAG, "Could not read " + ASSETS_TAG_FILE + ": " + e.getMessage());
            return null;
        } finally {
            if (is != null) {
                try {
                    is.close();
                } catch (IOException ignored) {
                }
            }
        }
    }

    private static void writeAssetsTag(File baseDir, String tag) {
        OutputStream os = null;
        try {
            os = new FileOutputStream(new File(baseDir, ASSETS_TAG_FILE));
            os.write(tag.getBytes());
        } catch (Exception e) {
            Log.e(TAG, "Could not write " + ASSETS_TAG_FILE + ": " + e.getMessage());
        } finally {
            if (os != null) {
                try {
                    os.close();
                } catch (IOException ignored) {
                }
            }
        }
    }

    private static final String[] VERIFIED_ASSET_EXTENSIONS = {".fd", ".bin", ".rom"};

    /**
     * LIMBO: the roms under assets/roms are copied to the base dir only when the
     * destination is missing, so an app update never refreshes them.  That let a
     * stale 4MiB firmware image survive a download of a newer 3.5MiB one, and
     * UEFI guests silently stopped booting (they hung in 16-bit real mode).
     * Verify firmware assets against the APK copy and reinstall on mismatch.
     * With allTypes (a different APK installed the current copy) every asset is
     * compared, not just firmware, so a renamed/rebuilt data file is refreshed
     * too.
     */
    private static boolean assetNeedsReinstall(AssetManager am, String assetPath, File dest,
                                               boolean allTypes) {
        String lower = assetPath.toLowerCase(Locale.US);
        boolean verified = false;
        for (String ext : VERIFIED_ASSET_EXTENSIONS) {
            if (lower.endsWith(ext)) {
                verified = true;
                break;
            }
        }
        // "xbzj" files are intentionally supplied/replaced by the user
        if ((!verified && !allTypes) || lower.contains("xbzj")) {
            return false;
        }
        try {
            long[] asset = assetSizeAndCrc(am, "roms/" + assetPath);
            if (asset == null) {
                return false;
            }
            if (dest.length() != asset[0]) {
                Log.w(TAG, "Asset stale: " + dest.getName() + " on disk "
                        + dest.length() + " bytes, in apk " + asset[0] + " bytes; reinstalling");
                return true;
            }
            // UEFI firmware is the pflash device: QEMU writes the NVRAM variable
            // store into it at boot, so its bytes legitimately differ from the
            // shipped image.  Size is still a reliable staleness check (the bug
            // this guards against shipped a 4MiB image where 3.5MiB was expected).
            if (lower.endsWith(".fd")) {
                return allTypes;
            }
            if (fileCrc(dest) != asset[1]) {
                Log.w(TAG, "Asset differs from apk: " + dest.getName()
                        + " checksum differs from apk; reinstalling");
                return true;
            }
        } catch (Exception e) {
            Log.e(TAG, "Could not verify " + dest.getName() + ": " + e.getMessage());
        }
        return false;
    }

    private static long[] assetSizeAndCrc(AssetManager am, String path) throws IOException {
        InputStream is = null;
        try {
            is = am.open(path);
            CRC32 crc = new CRC32();
            byte[] buf = new byte[65536];
            long total = 0;
            int n;
            while ((n = is.read(buf)) > 0) {
                crc.update(buf, 0, n);
                total += n;
            }
            return new long[]{total, crc.getValue()};
        } catch (IOException e) {
            Log.e(TAG, "Could not read asset " + path + ": " + e.getMessage());
            return null;
        } finally {
            if (is != null) {
                try {
                    is.close();
                } catch (IOException ignored) {
                }
            }
        }
    }

    private static long fileCrc(File f) throws IOException {
        InputStream is = new FileInputStream(f);
        try {
            CRC32 crc = new CRC32();
            byte[] buf = new byte[65536];
            int n;
            while ((n = is.read(buf)) > 0) {
                crc.update(buf, 0, n);
            }
            return crc.getValue();
        } finally {
            is.close();
        }
    }

    public static boolean installAssetFile(Activity activity, String srcFile,
                                           String destDir, String assetsDir, String destFile) {
        try {
            AssetManager am = activity.getResources().getAssets(); // get the local asset manager
            InputStream is = am.open(assetsDir + "/" + srcFile); // open the input stream for reading
            File destDirF = new File(destDir);
            if (!destDirF.exists()) {
                boolean res = destDirF.mkdirs();
                if(!res){
                	ToastUtils.toastShort(activity, activity.getString(R.string.CouldNotCreateDirForImage));
                }
            }
            
            if(destFile==null)
            	destFile=srcFile;
            OutputStream os = new FileOutputStream(destDir + "/" + destFile);
            byte[] buf = new byte[8092];
            int n;
            while ((n = is.read(buf)) > 0) {
                os.write(buf, 0, n);
            }
            os.close();
            is.close();
            return true;
        } catch (Exception ex) {
            Log.e(TAG, "failed to install file: " + destFile + ", Error:" + ex.getMessage());
            return false;
        }
    }

    public static Uri installImageTemplateToSDCard(Context context, String srcFile,
                                                   Uri destDir, String assetsDir, String destFile) {

        DocumentFile destFileF = null;
        OutputStream os = null;
        InputStream is = null;
        Uri uri = null;

        try {

            DocumentFile dir = DocumentFile.fromTreeUri(context, destDir);
            AssetManager am = context.getResources().getAssets(); // get the local asset manager
            is = am.open(assetsDir + "/" + srcFile); // open the input stream for reading

            if(destFile==null)
                destFile=srcFile;

            //Create the file if doesn't exist
            destFileF = dir.findFile(destFile);
            if(destFileF == null) {
                destFileF = dir.createFile("application/octet-stream", destFile);
            }
            else {
                    ToastUtils.toastShort(context, context.getString(R.string.FileExistsChooseAnotherFilename));
                    return null;
            }

            //Write to the dest
            os = context.getContentResolver().openOutputStream(destFileF.getUri());
            //OutputStream os = new FileOutputStream(destDir + "/" + destFile);
            byte[] buf = new byte[8092];
            int n;
            while ((n = is.read(buf)) > 0) {
                os.write(buf, 0, n);
            }

            //success
            uri = destFileF.getUri();

        } catch (Exception ex) {
            Log.e(TAG, "failed to install file: " + destFile + ", Error:" + ex.getMessage());
        } finally {
            if(os!=null) {
                try {
                    os.close();
                } catch (IOException e) {
                    e.printStackTrace();
                }
            }
            if(is!=null) {
                try {
                    is.close();
                } catch (IOException e) {
                    e.printStackTrace();
                }
            }

        }
        return uri;
    }


    public static String installImageTemplateToExternalStorage(Context context, String srcFile,
                                                               String destDir, String assetsDir, String destFile) {

        File file = new File(destDir, destFile);
        String filePath = null;
        OutputStream os = null;
        InputStream is = null;
        try {

            AssetManager am = context.getResources().getAssets(); // get the local asset manager
            is = am.open(assetsDir + "/" + srcFile); // open the input stream for reading

            if(destFile==null)
                destFile=srcFile;

            //Create the file if doesn't exist
            if(!file.exists()){
                file.createNewFile();
            }
            else {
                ToastUtils.toastShort(context, context.getString(R.string.FileExistsChooseAnotherFilename));
                return null;
            }

            //Write to the dest
            os = new FileOutputStream(file);

            //OutputStream os = new FileOutputStream(destDir + "/" + destFile);
            byte[] buf = new byte[8092];
            int n;
            while ((n = is.read(buf)) > 0) {
                os.write(buf, 0, n);
            }

            //success
            filePath = file.getAbsolutePath();

        } catch (Exception ex) {
            Log.e(TAG, "failed to install file: " + destFile + ", Error:" + ex.getMessage());
        } finally {
            if(os!=null) {
                try {
                    os.close();
                } catch (IOException e) {
                    e.printStackTrace();
                }
            }
            if(is!=null) {
                try {
                    is.close();
                } catch (IOException e) {
                    e.printStackTrace();
                }
            }

        }
        return filePath;
    }
}
