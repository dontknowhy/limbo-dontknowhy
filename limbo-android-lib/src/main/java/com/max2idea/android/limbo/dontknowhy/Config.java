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
package com.max2idea.android.limbo.dontknowhy;


import java.util.LinkedHashMap;

/**
 * Configuration
 */
public class Config {

    // Constants
    public static final int SDL_MOUSE_LEFT = 1;
    public static final int SDL_MOUSE_MIDDLE = 2;
    public static final int SDL_MOUSE_RIGHT = 3;
    public static final int SETTINGS_RETURN_CODE = 1000;
    public static final int FILEMAN_RETURN_CODE = 1002;

    public static final int SDL_REQUEST_CODE = 1007;
    public static final int SDL_QUIT_RESULT_CODE = 1009;

    public static final int OPEN_IMAGE_FILE_REQUEST_CODE = 2001;
    public static final int OPEN_IMAGE_FILE_ASF_REQUEST_CODE = 2002;

    public static final int OPEN_IMAGE_DIR_REQUEST_CODE = 2003;
    public static final int OPEN_IMAGE_DIR_ASF_REQUEST_CODE = 2004;

    public static final int OPEN_SHARED_DIR_REQUEST_CODE = 2005;
    public static final int OPEN_SHARED_DIR_ASF_REQUEST_CODE = 2006;

    public static final int OPEN_EXPORT_DIR_REQUEST_CODE = 2007;
    public static final int OPEN_EXPORT_DIR_ASF_REQUEST_CODE = 2008;

    public static final int OPEN_IMPORT_FILE_REQUEST_CODE = 2009;
    public static final int OPEN_IMPORT_FILE_ASF_REQUEST_CODE = 2010;

    public static final int OPEN_LOG_FILE_DIR_REQUEST_CODE = 2011;
    public static final int OPEN_LOG_FILE_DIR_ASF_REQUEST_CODE = 2012;

    public static final int OPEN_IMPORT_BIOS_FILE_REQUEST_CODE = 2013;
    public static final int OPEN_IMPORT_BIOS_FILE_ASF_REQUEST_CODE = 2014;

    public static final int STATUS_NULL = -1;
    public static final int STATUS_CREATED = 1000;
    public static final int STATUS_PAUSED = 1001;
    public static final String ACTION_START = "com.max2idea.android.limbo.action.STARTVM";

    // GUI Options
    public static final boolean enable_SDL = true;
    public static final int MAX_CPU_NUM = 8;

    // delay
    static int keyDelay = 100;
    static int mouseButtonDelay = 100;

    // App config
    public static final String APP_NAME = "Limbo xPro";

    public static final String defaultDNSServer = "114.114.114.114";
    // App Config
    public static final String downloadLink = "https://github.com/limboemu/limbo/wiki/Downloads";
    public static final String guidesLink = "https://ys.mihoyo.com/";

    public static final String srLink = "https://sr.mihoyo.com/";
    public static final String kvmLink = "https://baike.baidu.com/item/%E7%BB%9F%E4%B8%80%E5%8F%AF%E6%89%A9%E5%B1%95%E5%9B%BA%E4%BB%B6%E6%8E%A5%E5%8F%A3/22786233";
    public static final String faqLink = "https://github.com/limboemu/limbo/wiki/FAQ";
    public static final String toolsLink = "https://github.com/limboemu/limbo/wiki/Tools";
    public static final String newVersionLink = "https://raw.githubusercontents.com/limboemu/limbo/master/VERSION";
    public static final String otherOSLink = "https://github.com/limboemu/limbo/wiki/Other-Operating-Systems";

    public static final boolean enableKeyboardLayoutOption = true;
    public static final boolean enableMouseOption = true;

    // Debug
    public static final boolean debug = false;
    public static final boolean debugQmp = false;
    public static final boolean debugStrictMode = false;

    public static final int EXIT_SUCCESS = 1;
    public static final int EXIT_UNKNOWN = 2;


    public static boolean enableSDLSound = true;

    // stack size to remove an issue with SDL Audio
    public static long stackSize = 10 * 1024 * 1024;
    // native alternative to audio track
    public static String aaudioLibName = "libcompat-SDL2-addons.so";

    // if you don't want to enable software updates set to false
    public static boolean enableSoftwareUpdates = false;

    //TODO: enable immersive mode at some point in time
    public static boolean enableImmersiveMode = false;

    //TODO: add in settings
    public static boolean legacyDrives = false;
    public static boolean enableDefaultDevices = false;
    public static boolean syncFilesOnClose = true;

    public enum Arch {
        x86, x86_64, arm, arm64, ppc, ppc64, sparc, sparc64
    }

    //Enable if you build with KVM support, needes android-21 platform
    public static boolean enableKVM = false;
    public static String storagedir = null;
    //Some OSes don't like emulated multi cores for QEMU 2.9.1 you can disable here
    /// thought there is also the Disable TSC feature so you don't have to do it here
    public static boolean enableSMPOnlyOnKVM = false;
    //set to true if you need to debug native library loading
    public static boolean loadNativeLibsEarly = false;
    //XXX: QEMU 3.1.0 needs the libraries to be loaded from the main thread
    public static boolean loadNativeLibsMainThread = true;
    public static String wakeLockTag = "limbo:wakelock";
    public static String wifiLockTag = "limbo:wifilock";

    //XXX set scaling to linear it's a tad slower but it's worth it
    public static int SDLHintScale = 1;
    public static boolean viewLogInternally = true;
    //XXX some archs don't support floppy or sd card
    public static boolean enableEmulatedFloppy = false;
    public static boolean enableEmulatedSDCard;
    public static String destLogFilename = "limbolog.txt";
    public static String notificationChannelID = "limbo";
    public static String notificationChannelName = "limbo";
    public static boolean showToast = false;
    public static boolean closeFileDescriptors = true;
    //XXX: qemu vvfat is buggy so we disable
    public static boolean enableSharedFolder = false;

    public static String machineFolder = "machines/";
    public static String logFilePath = null;

    public static String stateFilename = "vm.state";
    //QMP
    public static String QMPServer = "127.0.0.1";
    public static int QMPPort = 4444;
    public static int MAX_DISPLAY_REFRESH_RATE = 120; //Hz
    // VNC Defaults
    public static String defaultVNCHost = "127.0.0.1";
    //It seems that new versions of qemu expect a relative number
    //  so we stop using absolute port numbers
    public static final int defaultVNCPort = 1;

    //Keyboard Layout
    public static String defaultKeyboardLayout = "zh-cn";

    //a little nicer ui
    public static boolean collapseSections = true;

    public static boolean enableToggleKeyboard = false;

    //override this at the app level it dependes on the host arch
    public static boolean enableMTTCG = true;

    public static boolean processMouseHistoricalEvents = false;

    //Change to true in prod if you want to be notified by default for new versions
    public static boolean defaultCheckNewVersion = false;

    //enable tracing
    // make sure you have access to the dir/files below
    public static boolean enableTracingLog = false;
    public static final String traceDir = "/sdcard/limbo/tmp/trace";
    public static final String traceEventsFile = "/sdcard/limbo/tmp/events";
    public static final String traceLogFile = "/sdcard/limbo/log.txt";

    // override translation block size
    public static boolean overrideTbSize;
    public static String tbSize = "32M";

    public static String VGAmem = "512";

    public static String VirtIO_VGA_mem = "512M"  ;

    // Class that starts when user presses notification
    public static Class<?> clientClass = null;

}
