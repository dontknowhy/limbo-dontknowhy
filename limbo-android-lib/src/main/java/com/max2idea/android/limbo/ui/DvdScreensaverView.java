package com.max2idea.android.limbo.ui;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.drawable.Drawable;
import android.util.AttributeSet;
import android.view.View;

import com.limbo.emu.lib.R;

/**
 * The classic DVD player idle animation: the logo drifts across a black
 * screen, bounces off the edges and changes colour on every bounce.
 *
 * The logo is a VectorDrawable generated from dvd-logo.svg, so it stays sharp
 * at any size and can be tinted per bounce.
 */
public class DvdScreensaverView extends View {

    private final Drawable logo;

    private float x, y;
    private float speedX, speedY;
    private float logoWidth, logoHeight;
    private long lastFrameNs;
    private float hue;

    /* Only one frame callback may be in flight: onAttachedToWindow() and
     * onVisibilityChanged() both fire when the overlay is added. */
    private boolean framePosted;

    private final Runnable frame = new Runnable() {
        @Override
        public void run() {
            framePosted = false;
            long now = System.nanoTime();
            if (lastFrameNs != 0) {
                float dt = (now - lastFrameNs) / 1e9f;
                if (dt > 0.1f) {
                    dt = 0.1f;   /* first frame after a pause: do not jump */
                }
                step(dt);
            }
            lastFrameNs = now;
            invalidate();
            scheduleFrame();
        }
    };

    private void scheduleFrame() {
        if (!framePosted) {
            framePosted = true;
            postOnAnimation(frame);
        }
    }

    private void cancelFrame() {
        framePosted = false;
        removeCallbacks(frame);
    }

    public DvdScreensaverView(Context context) {
        this(context, null);
    }

    public DvdScreensaverView(Context context, AttributeSet attrs) {
        super(context, attrs);
        logo = context.getDrawable(R.drawable.dvd_logo);
        hue = 200f;
        if (logo != null) {
            logo.setTint(Color.HSVToColor(new float[]{hue, 0.75f, 1f}));
        }
        setBackgroundColor(Color.BLACK);
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        super.onSizeChanged(w, h, oldw, oldh);

        /* About a third of the screen wide; keep the 800x375 logo aspect. */
        logoWidth = w * 0.34f;
        if (logo != null) {
            int iw = Math.max(1, logo.getIntrinsicWidth());
            int ih = Math.max(1, logo.getIntrinsicHeight());
            logoHeight = logoWidth * ih / (float) iw;
        } else {
            logoHeight = logoWidth * 375f / 800f;
        }

        /* The same px/s on both axes: a 45-degree drift like the real player,
         * ~100 px/s on a 1080p screen (about ten seconds to cross the width,
         * longer vertically because the phone is taller than 4:3). */
        float speed = Math.min(w, h) * 0.09f;
        speedX = speed;
        speedY = speed;

        x = (w - logoWidth) / 2f;
        y = (h - logoHeight) / 2f;
        lastFrameNs = 0;
    }

    private void step(float dt) {
        float maxX = Math.max(0, getWidth() - logoWidth);
        float maxY = Math.max(0, getHeight() - logoHeight);

        x += speedX * dt;
        y += speedY * dt;

        if (x <= 0) {
            x = 0;
            speedX = Math.abs(speedX);
            nextColor();
        } else if (x >= maxX) {
            x = maxX;
            speedX = -Math.abs(speedX);
            nextColor();
        }
        if (y <= 0) {
            y = 0;
            speedY = Math.abs(speedY);
            nextColor();
        } else if (y >= maxY) {
            y = maxY;
            speedY = -Math.abs(speedY);
            nextColor();
        }
    }

    private void nextColor() {
        /* Golden-angle step: consecutive bounces look visibly different
         * without ever repeating the same hue twice in a row. */
        hue = (hue + 47f) % 360f;
        if (logo != null) {
            logo.setTint(Color.HSVToColor(new float[]{hue, 0.75f, 1f}));
        }
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        if (logo == null) {
            return;
        }
        logo.setBounds((int) x, (int) y,
                (int) (x + logoWidth), (int) (y + logoHeight));
        logo.draw(canvas);
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        lastFrameNs = 0;
        scheduleFrame();
    }

    @Override
    protected void onDetachedFromWindow() {
        cancelFrame();
        super.onDetachedFromWindow();
    }

    @Override
    protected void onVisibilityChanged(View changedView, int visibility) {
        super.onVisibilityChanged(changedView, visibility);
        if (visibility == VISIBLE) {
            lastFrameNs = 0;
            scheduleFrame();
        } else {
            cancelFrame();
        }
    }
}
