package com.max2idea.android.limbo.ui;

import android.app.Activity;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowManager;

import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;

import com.max2idea.android.limbo.toast.ToastUtils;

/**
 * Idle "screensaver": after a configurable timeout of no user input the
 * activity hides its chrome (and, for VNC, shows the bouncing DVD logo) until
 * the next tap.
 *
 * The timeout comes from the immersive-mode settings screen
 * ({@code screensaverTimeout}, seconds, 0 = off, default 30).
 */
public class ScreenSaver {

    public interface Callbacks {
        /** Enter the screensaver (show overlay, hide system bars...). */
        void onEnter();

        /** Leave the screensaver (restore the normal UI). */
        void onExit();
    }

    /** Lets the host veto entering, e.g. when no VM is running. */
    public interface Gate {
        boolean allow();
    }

    private final Activity activity;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Callbacks callbacks;
    private final Runnable timeoutTask = new Runnable() {
        @Override
        public void run() {
            enter();
        }
    };

    private Gate gate;
    private boolean showToast;
    private int timeoutMs = 30000;
    private boolean running;
    private boolean active;

    public ScreenSaver(Activity activity, Callbacks callbacks) {
        this.activity = activity;
        this.callbacks = callbacks;
    }

    /** Show the "screen saver on" toast when it kicks in (VNC view only). */
    public void setShowToast(boolean showToast) {
        this.showToast = showToast;
    }

    public void setGate(Gate gate) {
        this.gate = gate;
    }

    /** Seconds, 0 disables the screensaver. */
    public void setTimeoutSeconds(int seconds) {
        timeoutMs = Math.max(0, seconds) * 1000;
    }

    public int getTimeoutMs() {
        return timeoutMs;
    }

    public boolean isActive() {
        return active;
    }

    /** Start (or restart) the idle timer; call from onResume(). */
    public void begin() {
        running = true;
        schedule();
    }

    /** Stop the timer and restore the UI; call from onPause(). */
    public void end() {
        running = false;
        handler.removeCallbacks(timeoutTask);
        dismiss();
    }

    /**
     * Report user activity.
     *
     * @return true if the event was swallowed because it dismissed the
     *         screensaver (the caller should not pass it on to the guest)
     */
    public boolean onUserInput() {
        if (active) {
            dismiss();
            return true;
        }
        schedule();
        return false;
    }

    private void schedule() {
        handler.removeCallbacks(timeoutTask);
        if (running && timeoutMs > 0 && !active) {
            handler.postDelayed(timeoutTask, timeoutMs);
        }
    }

    private void enter() {
        if (!running || active || timeoutMs <= 0) {
            return;
        }
        if (gate != null && !gate.allow()) {
            schedule();
            return;
        }
        active = true;
        callbacks.onEnter();
        if (showToast) {
            ToastUtils.toastShort(activity, activity.getString(
                    com.limbo.emu.lib.R.string.ScreenSaverEntered));
        }
    }

    private void dismiss() {
        if (!active) {
            return;
        }
        active = false;
        callbacks.onExit();
        schedule();
    }

    /**
     * True while the soft keyboard is on screen. The screensaver must stay
     * away then: it would swallow the IME key events.
     */
    public static boolean isImeVisible(Activity activity) {
        View decor = activity.getWindow().getDecorView();
        WindowInsets insets = decor.getRootWindowInsets();
        if (insets == null) {
            return false;
        }
        return WindowInsetsCompat.toWindowInsetsCompat(insets, decor)
                .isVisible(WindowInsetsCompat.Type.ime());
    }

    /**
     * Hide or show the status/navigation bars. Works on API 21+ through the
     * androidx compat layer (WindowInsetsControllerCompat falls back to the
     * legacy systemUiVisibility flags on old releases).
     */
    public static void setImmersive(Activity activity, boolean immersive) {
        Window window = activity.getWindow();
        WindowInsetsControllerCompat controller =
                WindowCompat.getInsetsController(window, window.getDecorView());
        if (immersive) {
            controller.hide(WindowInsetsCompat.Type.systemBars());
            controller.setSystemBarsBehavior(
                    WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            /* A burn-in screen is pointless if the panel turns itself off. */
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        } else {
            controller.show(WindowInsetsCompat.Type.systemBars());
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }
    }
}
