package com.gathin.tvhome;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.PowerManager;
import android.util.Log;

import java.util.Calendar;
import java.util.Locale;

/**
 * Azan at the namaz times (config.xml: azan, azan_prayers). One exact alarm is pending at a time, for the next
 * azan; when it fires, AzanActivity opens over whatever is on (only while the TV is on, never in standby) and
 * the next one is scheduled. After the day's last azan, an alarm just after midnight fetches the new day's
 * times and schedules its first. Boot, a clock or time zone change and an app update reschedule too.
 *
 * The times are Prayer's: the saved day, fetched from Aladhan when it is missing. Offline, the last saved day
 * stands in; neighbouring days differ by a minute or two.
 */
public final class Azan extends BroadcastReceiver {
    private static final String TAG = "TvHome.Azan";
    static final String ACTION_ALARM = "com.gathin.tvhome.action.AZAN_ALARM";
    /** Index in Prayer.KEYS of the namaz the alarm is for; -1 for the after-midnight refresh. */
    static final String EXTRA_PRAYER = "prayer";
    /** When the alarm was meant to go off; an alarm delivered much later (the TV was asleep) stays silent. */
    static final String EXTRA_AT = "at";
    private static final long LATE_MS = 5 * 60_000L;
    /** Prayer.KEYS indices that can have an azan (not sunrise), with their config.xml names. */
    private static final int[] PRAYERS = {0, 2, 3, 4, 5};
    private static final String[] NAMES = {"fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"};

    @Override
    public void onReceive(Context context, Intent intent) {
        Context ctx = context.getApplicationContext();
        if (ACTION_ALARM.equals(intent.getAction())) {
            int prayer = intent.getIntExtra(EXTRA_PRAYER, -1);
            long at = intent.getLongExtra(EXTRA_AT, 0);
            boolean onTime = Math.abs(System.currentTimeMillis() - at) < LATE_MS;
            PowerManager pm = (PowerManager) ctx.getSystemService(Context.POWER_SERVICE);
            if (prayer >= 0 && onTime && pm != null && pm.isInteractive()) {
                ctx.startActivity(new Intent(ctx, AzanActivity.class)
                        .putExtra(EXTRA_PRAYER, prayer)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION));
            } else if (prayer >= 0) {
                Log.i(TAG, "azan for " + NAMES[prayer] + " skipped: " + (onTime ? "TV in standby" : "alarm late"));
            }
        }
        // Boot, time change, app update, or the alarm itself: schedule the next one, off the main thread
        // (it may have to fetch the day's times).
        PendingResult result = goAsync();
        new Thread(() -> {
            try {
                schedule(ctx);
            } finally {
                result.finish();
            }
        }).start();
    }

    /** Reschedules from a background thread; for the launcher (start, Settings switch). */
    static void scheduleAsync(Context context) {
        Context ctx = context.getApplicationContext();
        new Thread(() -> schedule(ctx)).start();
    }

    /** Sets the alarm for the next azan, or cancels it when the azan is off. Background thread only. */
    static void schedule(Context ctx) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        Config cfg = Config.load(ctx);
        if (!cfg.azan || cfg.prayerLatitude.isEmpty() || cfg.prayerLongitude.isEmpty()) {
            am.cancel(pending(ctx, -1, 0));
            return;
        }
        String key = Prayer.key(cfg.prayerLatitude, cfg.prayerLongitude, cfg.prayerMethod, cfg.prayerSchool);
        Prayer.Day day = Prayer.cached(ctx, key);
        if (day == null) day = Prayer.fetch(ctx, cfg.prayerLatitude, cfg.prayerLongitude, cfg.prayerMethod, cfg.prayerSchool);
        if (day == null) day = Prayer.lastSaved(ctx);
        long now = System.currentTimeMillis();
        if (day == null) {
            // Never had any times (offline since install): try again in half an hour.
            set(am, ctx, -1, now + 30 * 60_000L);
            return;
        }
        Calendar midnight = Calendar.getInstance();
        midnight.set(Calendar.HOUR_OF_DAY, 0);
        midnight.set(Calendar.MINUTE, 0);
        midnight.set(Calendar.SECOND, 0);
        midnight.set(Calendar.MILLISECOND, 0);
        long dayStart = midnight.getTimeInMillis();
        for (int i : PRAYERS) {
            if (!cfg.azanPrayers.contains(NAMES[i])) continue;
            long at = dayStart + day.minutes[i] * 60_000L;
            if (at > now + 1000) {
                set(am, ctx, i, at);
                return;
            }
        }
        // The day's azans are over: just after midnight, fetch the new day and schedule its first.
        midnight.add(Calendar.DAY_OF_MONTH, 1);
        set(am, ctx, -1, midnight.getTimeInMillis() + 60_000L);
    }

    private static void set(AlarmManager am, Context ctx, int prayer, long at) {
        PendingIntent pi = pending(ctx, prayer, at);
        boolean exact = Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms();
        if (exact) am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi);
        else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi);
        Log.i(TAG, "next: " + (prayer >= 0 ? NAMES[prayer] : "refresh") + " at "
                + String.format(Locale.ROOT, "%tF %<tR", at) + (exact ? "" : " (inexact)"));
    }

    /** The one alarm (same request code, so a new one replaces the old). */
    private static PendingIntent pending(Context ctx, int prayer, long at) {
        Intent i = new Intent(ctx, Azan.class).setAction(ACTION_ALARM)
                .putExtra(EXTRA_PRAYER, prayer).putExtra(EXTRA_AT, at);
        return PendingIntent.getBroadcast(ctx, 0, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
}
