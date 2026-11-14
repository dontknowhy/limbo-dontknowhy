package com.max2idea.android.limbo.ui;

import android.app.Activity;
import android.graphics.Color;
import android.content.res.ColorStateList;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;

/**
 * A strip of special keys (modifiers, Esc/Tab/arrows/F1-F12...) that sits just
 * above the software keyboard, in the spirit of the key bar in RealVNC Viewer.
 *
 * Modifiers are sticky: tapping Ctrl presses and holds it in the guest
 * (highlighted), so the next key typed anywhere - on this bar, on the soft
 * keyboard or on a hardware keyboard - becomes Ctrl+that key.  Tapping it again
 * releases it.  Backends that cannot hold a key (QMP's sendkey is atomic) are
 * told so by {@link Sender#setHeld}; there the modifier is only borrowed for
 * the next bar key instead.
 *
 * The bar never takes focus, so tapping it does not dismiss the keyboard.
 */
public class SpecialKeysBar {

    /** Sends key codes to the guest. */
    public interface Sender {
        /** Press and release these keys together. */
        void send(int[] keyCodes);

        /**
         * Press (down=true) or release a single key and keep that state.
         * Returns false when the backend cannot hold keys.
         */
        boolean setHeld(int keyCode, boolean down);
    }

    private static final int BAR_BG = 0xF2141414;
    private static final int KEY_BG = 0x33FFFFFF;
    private static final int KEY_BG_LATCHED = 0xFF3D7EBB;
    private static final int KEY_BG_RIPPLE = 0x66FFFFFF;

    private final Activity activity;
    private final Sender sender;
    /** Sticky modifier buttons: key code -> button. */
    private final LinkedHashMap<Integer, TextView> latched = new LinkedHashMap<Integer, TextView>();
    /** Modifiers that are really held down in the guest. */
    private final List<Integer> heldCodes = new ArrayList<Integer>();

    private HorizontalScrollView bar;
    private boolean visible;
    private boolean suppressed;

    private SpecialKeysBar(Activity activity, Sender sender) {
        this.activity = activity;
        this.sender = sender;
    }

    /**
     * Builds the bar and docks it at the bottom of the activity content.  The
     * IME is asked to resize the window, so "bottom of the content" is exactly
     * "just above the software keyboard" on every Android version: this app
     * targets a legacy SDK and therefore never receives IME window insets.
     */
    public static SpecialKeysBar attach(Activity activity, Sender sender) {
        SpecialKeysBar bar = new SpecialKeysBar(activity, sender);
        bar.install();
        return bar;
    }

    private void install() {
        View content = activity.findViewById(android.R.id.content);
        if (!(content instanceof ViewGroup)) {
            return;
        }
        ViewGroup root = (ViewGroup) content;

        activity.getWindow().setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
                        | WindowManager.LayoutParams.SOFT_INPUT_STATE_UNCHANGED);

        bar = new HorizontalScrollView(activity);
        bar.setHorizontalScrollBarEnabled(false);
        bar.setFillViewport(true);
        bar.setBackgroundColor(BAR_BG);
        bar.setElevation(dp(6));
        bar.setVisibility(View.GONE);

        LinearLayout row = new LinearLayout(activity);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setPadding(dp(4), dp(4), dp(4), dp(5));
        bar.addView(row, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        addModifier(row, "Ctrl", KeyEvent.KEYCODE_CTRL_LEFT);
        addModifier(row, "Alt", KeyEvent.KEYCODE_ALT_LEFT);
        addModifier(row, "Shift", KeyEvent.KEYCODE_SHIFT_LEFT);
        addModifier(row, "Win", KeyEvent.KEYCODE_META_LEFT);

        addKey(row, "Esc", KeyEvent.KEYCODE_ESCAPE);
        addKey(row, "Tab", KeyEvent.KEYCODE_TAB);
        addKey(row, "Enter", KeyEvent.KEYCODE_ENTER);
        addKey(row, "Backsp", KeyEvent.KEYCODE_DEL);
        addKey(row, "Del", KeyEvent.KEYCODE_FORWARD_DEL);
        addKey(row, "Ins", KeyEvent.KEYCODE_INSERT);
        addKey(row, "Home", KeyEvent.KEYCODE_MOVE_HOME);
        addKey(row, "End", KeyEvent.KEYCODE_MOVE_END);
        addKey(row, "PgUp", KeyEvent.KEYCODE_PAGE_UP);
        addKey(row, "PgDn", KeyEvent.KEYCODE_PAGE_DOWN);
        addKey(row, "\u2190", KeyEvent.KEYCODE_DPAD_LEFT);
        addKey(row, "\u2191", KeyEvent.KEYCODE_DPAD_UP);
        addKey(row, "\u2193", KeyEvent.KEYCODE_DPAD_DOWN);
        addKey(row, "\u2192", KeyEvent.KEYCODE_DPAD_RIGHT);
        addKey(row, "PrtSc", KeyEvent.KEYCODE_SYSRQ);
        addKey(row, "C+A+Del", KeyEvent.KEYCODE_CTRL_LEFT,
                KeyEvent.KEYCODE_ALT_LEFT, KeyEvent.KEYCODE_FORWARD_DEL);

        for (int i = 1; i <= 12; i++) {
            addKey(row, "F" + i, KeyEvent.KEYCODE_F1 + (i - 1));
        }

        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.gravity = Gravity.BOTTOM;
        root.addView(bar, lp);
    }

    public void setVisible(boolean visible) {
        this.visible = visible;
        update();
    }

    public boolean isVisible() {
        return bar != null && bar.getVisibility() == View.VISIBLE;
    }

    /** Temporarily force the bar out of the way (e.g. screensaver). */
    public void setSuppressed(boolean suppressed) {
        this.suppressed = suppressed;
        update();
    }

    public void show() {
        setVisible(true);
    }

    public void hide() {
        setVisible(false);
    }

    /** Release every modifier we may have left pressed in the guest. */
    public void releaseModifiers() {
        clearModifiers();
    }

    /**
     * A key was just pushed to the guest: a sticky modifier is one-shot, so
     * drop it (and its highlight) now that the combination went out.
     */
    public void onKeySent(int keyCode) {
        if (heldCodes.contains(keyCode) || latched.containsKey(keyCode)) {
            /* The modifier press itself (or its release). */
            return;
        }
        if (!latched.isEmpty()) {
            clearModifiers();
        }
    }

    private void update() {
        if (bar == null) {
            return;
        }
        boolean show = visible && !suppressed;
        if (!show) {
            /* Never leave a modifier stuck down in the guest. */
            clearModifiers();
        }
        bar.setVisibility(show ? View.VISIBLE : View.GONE);
    }

    private void addModifier(LinearLayout row, String label, final int code) {
        final TextView v = addKey(row, label);
        v.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                toggleModifier(v, code);
            }
        });
    }

    private TextView addKey(LinearLayout row, String label, final int... codes) {
        final TextView v = newKey(label);
        v.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                sendCombo(codes);
            }
        });
        row.addView(v);
        return v;
    }

    private TextView newKey(String label) {
        TextView v = new TextView(activity);
        v.setText(label);
        v.setTextColor(Color.WHITE);
        v.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        v.setGravity(Gravity.CENTER);
        v.setPadding(dp(11), dp(8), dp(11), dp(8));
        v.setBackground(keyBackground(KEY_BG));
        /* Keep the focus on the view that owns the keyboard. */
        v.setFocusable(false);
        v.setFocusableInTouchMode(false);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.rightMargin = dp(4);
        v.setLayoutParams(lp);
        addPressFeedback(v);
        return v;
    }

    private RippleDrawable keyBackground(int color) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(color);
        shape.setCornerRadius(dp(6));
        /* The system ripple (bounded by the rounded shape) is the touch
         * feedback the rest of the platform uses. */
        return new RippleDrawable(
                ColorStateList.valueOf(KEY_BG_RIPPLE), shape, null);
    }

    /** Press animation: a short shrink/grow plus the keyboard tap haptic. */
    private void addPressFeedback(final TextView v) {
        v.setOnTouchListener(new View.OnTouchListener() {
            @Override
            public boolean onTouch(View view, MotionEvent event) {
                switch (event.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        v.animate().cancel();
                        v.animate().scaleX(0.92f).scaleY(0.92f).setDuration(60).start();
                        v.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
                        break;
                    case MotionEvent.ACTION_UP:
                    case MotionEvent.ACTION_CANCEL:
                        v.animate().cancel();
                        v.animate().scaleX(1f).scaleY(1f).setDuration(90).start();
                        break;
                    default:
                        break;
                }
                /* Not consumed: the click listener still fires. */
                return false;
            }
        });
    }

    private void toggleModifier(TextView v, int code) {
        if (latched.containsKey(code)) {
            latched.remove(code);
            v.setBackground(keyBackground(KEY_BG));
            if (heldCodes.contains(code)) {
                heldCodes.remove(Integer.valueOf(code));
                sender.setHeld(code, false);
            }
            return;
        }
        latched.put(code, v);
        v.setBackground(keyBackground(KEY_BG_LATCHED));
        if (sender.setHeld(code, true)) {
            heldCodes.add(code);
        }
    }

    private void clearModifiers() {
        for (TextView v : latched.values()) {
            v.setBackground(keyBackground(KEY_BG));
        }
        latched.clear();
        for (int code : new ArrayList<Integer>(heldCodes)) {
            sender.setHeld(code, false);
        }
        heldCodes.clear();
    }

    private void sendCombo(int[] codes) {
        List<Integer> combo = new ArrayList<Integer>();
        List<Integer> consumedLatches = new ArrayList<Integer>();
        for (int code : latched.keySet()) {
            if (heldCodes.contains(code)) {
                /* Already down in the guest; the key alone completes the combo. */
                continue;
            }
            combo.add(code);
            consumedLatches.add(code);
        }
        for (int code : codes) {
            if (!heldCodes.contains(code) && !combo.contains(code)) {
                combo.add(code);
            }
        }
        /* Borrowed modifiers are released with the combination; held ones stay
         * down until tapped again. */
        for (int code : consumedLatches) {
            TextView v = latched.remove(code);
            if (v != null) {
                v.setBackground(keyBackground(KEY_BG));
            }
        }
        if (combo.isEmpty()) {
            return;
        }
        int[] result = new int[combo.size()];
        for (int i = 0; i < result.length; i++) {
            result[i] = combo.get(i);
        }
        sender.send(result);
    }

    private int dp(int value) {
        return Math.round(value * activity.getResources().getDisplayMetrics().density);
    }
}
