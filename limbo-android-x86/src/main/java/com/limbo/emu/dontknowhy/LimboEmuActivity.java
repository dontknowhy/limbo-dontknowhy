package com.limbo.emu.dontknowhy;

import android.os.Bundle;

import com.max2idea.android.limbo.dontknowhy.Config;
import com.max2idea.android.limbo.dontknowhy.LimboActivity;
import com.max2idea.android.limbo.dontknowhy.LimboApplication;
import com.max2idea.android.limbo.log.Logger;

public class LimboEmuActivity extends LimboActivity {

    public void onCreate(Bundle bundle) {
        LimboApplication.arch = Config.Arch.x86_64;
        Config.clientClass = this.getClass();
        Config.enableKVM = true;
        //XXX; only for 64bit hosts, also make sure you have qemu 3.1.0 x86_64-softmmu and above compiled
        if(LimboApplication.isHost64Bit() && Config.enableMTTCG)
            Config.enableMTTCG = true;
        else
            Config.enableMTTCG = false;
        super.onCreate(bundle);
        //TODO: change location to something that the user will have access outside of limbo
        //  like internal storage
        Logger.setupLogFile("/limbo/limbo-x86-log.txt");
    }

    protected void loadQEMULib() {
        try {
            System.loadLibrary("qemu-system-i386");
        } catch (Error ex) {
            System.loadLibrary("qemu-system-x86_64");
        }

    }
}
