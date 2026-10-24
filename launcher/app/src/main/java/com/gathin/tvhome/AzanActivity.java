package com.gathin.tvhome;

import android.app.Activity;
import android.content.res.AssetFileDescriptor;
import android.content.res.ColorStateList;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;
import android.widget.TextView;

/**
 * The azan screen (Azan schedules it): the namaz name, its time and the Islamic date over black with a gold
 * glow, while res/raw/azan_madinah.ogg plays. It takes transient audio focus, so YouTube, Prime Video and other
 * well-behaved players pause, and gives it back when the azan ends, so they can carry on. Covering Live TV or an
 * HDMI input stops that picture and sound too, until this screen closes. OK or Back stops the azan early.
 * Runs in its own task, so closing it goes back to whatever was on, not to Home.
 */
public class AzanActivity extends Activity {
    private static final String TAG = "TvHome.Azan";
    /** A short pause on the last frame after the recording ends, then back to what was on. */
    private static final long CLOSE_AFTER_MS = 2500;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private MediaPlayer player;
    private AudioManager audio;
    private AudioFocusRequest focus;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        setContentView(R.layout.activity_azan);
        int prayer = getIntent().getIntExtra(Azan.EXTRA_PRAYER, -1);
        if (prayer < 0 || prayer >= Prayer.KEYS.length) {
            finish();
            return;
        }

        ((ImageView) findViewById(R.id.azanIcon)).setImageTintList(ColorStateList.valueOf(MainActivity.PRAYER_GOLD));
        ((TextView) findViewById(R.id.azanPrayer)).setText(Prayer.name(this, prayer));
        Config cfg = Config.load(this);
        Prayer.Day day = Prayer.cached(this, Prayer.key(cfg.prayerLatitude, cfg.prayerLongitude, cfg.prayerMethod, cfg.prayerSchool));
        if (day == null) day = Prayer.lastSaved(this);
        TextView when = findViewById(R.id.azanTime);
        TextView hijri = findViewById(R.id.azanHijri);
        if (day != null) {
            when.setText(getString(R.string.azan_at, Prayer.time(this, day.minutes[prayer])));
            String h = cfg.hijriDate ? Prayer.hijri(this, day, cfg.hijriAdjustment) : null;
            hijri.setText(h);
            hijri.setVisibility(h != null ? View.VISIBLE : View.GONE);
        } else {
            when.setText(R.string.azan_title);
            hijri.setVisibility(View.GONE);
        }
        play();
    }

    private void play() {
        AudioAttributes attrs = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build();
        audio = (AudioManager) getSystemService(AUDIO_SERVICE);
        if (audio != null) {
            focus = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(attrs)
                    .setOnAudioFocusChangeListener(change -> { })   // the azan plays through; OK or Back stops it
                    .build();
            audio.requestAudioFocus(focus);
        }
        try (AssetFileDescriptor afd = getResources().openRawResourceFd(R.raw.azan_madinah)) {
            player = new MediaPlayer();
            player.setAudioAttributes(attrs);
            player.setDataSource(afd.getFileDescriptor(), afd.getStartOffset(), afd.getLength());
            player.setOnPreparedListener(MediaPlayer::start);
            player.setOnCompletionListener(mp -> handler.postDelayed(this::finish, CLOSE_AFTER_MS));
            player.setOnErrorListener((mp, what, extra) -> {
                Log.w(TAG, "playback error " + what + "/" + extra);
                finish();
                return true;
            });
            player.prepareAsync();
        } catch (Exception e) {
            Log.w(TAG, "cannot play the azan: " + e);
            finish();
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_BACK:
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
                finish();
                return true;
            case KeyEvent.KEYCODE_VOLUME_UP:
            case KeyEvent.KEYCODE_VOLUME_DOWN:
            case KeyEvent.KEYCODE_VOLUME_MUTE:
                return super.onKeyDown(keyCode, event);
            default:
                return true;   // the arrows and the rest do nothing here
        }
    }

    @Override
    protected void onStop() {
        super.onStop();
        // Home pressed, or the screen closed: either way the azan stops with it.
        if (!isFinishing()) finish();
        release();
    }

    @Override
    protected void onDestroy() {
        release();
        super.onDestroy();
    }

    private void release() {
        handler.removeCallbacksAndMessages(null);
        if (player != null) {
            player.release();
            player = null;
        }
        if (audio != null && focus != null) {
            audio.abandonAudioFocusRequest(focus);
            focus = null;
        }
    }
}
