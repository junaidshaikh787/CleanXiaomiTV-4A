package com.gathin.tvhome;

import android.content.Context;
import android.text.format.DateFormat;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.Locale;

/**
 * Today's prayer times and Islamic (Hijri) date for the prayer coordinates, from Aladhan (free, no account or
 * key; only the coordinates, the date, the calculation method and the Asr school are sent), the same source as
 * the Prayer Times module. One request a day: the answer is kept in files/prayer.json, so a restart or a short
 * outage costs nothing.
 * Used by the pill under the clock (home_prayer) and by the screensaver (dream_prayer).
 */
final class Prayer {
    private static final String TAG = "TvHome.Prayer";
    private static final String FILE = "prayer.json";
    /** Aladhan's keys, in the order of the day. Sunrise is shown but is not a prayer. */
    static final String[] KEYS = {"Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"};
    static final int SUNRISE = 1;
    /** For this long after a prayer's time, it is still the one shown, as "now". */
    static final int NOW_MINUTES = 15;

    /** One day's times, minutes after midnight in KEYS order. */
    static final class Day {
        final String key;
        final int[] minutes;
        /** Aladhan's Hijri date for the day: day of month, month 1 to 12, year, days in that month; 0 if unknown. */
        final int hijriDay, hijriMonth, hijriYear, hijriMonthDays;

        Day(String key, int[] minutes, int hijriDay, int hijriMonth, int hijriYear, int hijriMonthDays) {
            this.key = key;
            this.minutes = minutes;
            this.hijriDay = hijriDay;
            this.hijriMonth = hijriMonth;
            this.hijriYear = hijriYear;
            this.hijriMonthDays = hijriMonthDays;
        }
    }

    /** What to show at a given minute: the prayer, and the minutes until it (negative while it is "now"). */
    static final class Next {
        final int index;
        final int minutesLeft;
        final boolean tomorrow;

        Next(int index, int minutesLeft, boolean tomorrow) {
            this.index = index;
            this.minutesLeft = minutesLeft;
            this.tomorrow = tomorrow;
        }
    }

    private Prayer() {}

    /** Which day and place a set of times is for; a different key means fetch again. */
    static String key(String latitude, String longitude, int method, int school) {
        return new SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(new Date())
                + '|' + latitude + '|' + longitude + '|' + method + '|' + school;
    }

    /** The saved times if they are for this key, else null. Cheap enough for the main thread. */
    static Day cached(Context ctx, String key) {
        return cached(ctx, key, false);
    }

    /**
     * The last saved times, whatever day and place they are for, or null. Days next to each other differ by a
     * minute or two, so the azan alarm uses them when the TV could not fetch today's (offline after midnight).
     */
    static Day lastSaved(Context ctx) {
        return cached(ctx, null, true);
    }

    private static Day cached(Context ctx, String key, boolean anyKey) {
        File f = new File(ctx.getFilesDir(), FILE);
        if (!f.isFile() || f.length() > 4096) return null;
        try (FileInputStream in = new FileInputStream(f)) {
            byte[] buf = new byte[(int) f.length()];
            int n = 0, r;
            while (n < buf.length && (r = in.read(buf, n, buf.length - n)) > 0) n += r;
            JSONObject o = new JSONObject(new String(buf, 0, n, StandardCharsets.UTF_8));
            if (!anyKey && !key.equals(o.optString("key"))) return null;
            if (anyKey) key = o.optString("key");
            JSONArray a = o.getJSONArray("minutes");
            if (a.length() != KEYS.length) return null;
            int[] m = new int[KEYS.length];
            for (int i = 0; i < m.length; i++) m[i] = a.getInt(i);
            JSONObject h = o.optJSONObject("hijri");
            if (h == null) return new Day(key, m, 0, 0, 0, 0);
            return new Day(key, m, h.optInt("day"), h.optInt("month"), h.optInt("year"), h.optInt("days"));
        } catch (Exception e) {
            return null;
        }
    }

    /** Fetches today's times and saves them; null when offline or the answer is unexpected. Background thread only. */
    static Day fetch(Context ctx, String latitude, String longitude, int method, int school) {
        String key = key(latitude, longitude, method, school);
        String url = "https://api.aladhan.com/v1/timings/"
                + new SimpleDateFormat("dd-MM-yyyy", Locale.ROOT).format(new Date())
                + "?latitude=" + latitude + "&longitude=" + longitude + "&method=" + method + "&school=" + school;
        try {
            JSONObject data = new JSONObject(new String(DailyPhoto.fetch(url), StandardCharsets.UTF_8))
                    .getJSONObject("data");
            JSONObject t = data.getJSONObject("timings");
            int[] m = new int[KEYS.length];
            JSONArray a = new JSONArray();
            for (int i = 0; i < KEYS.length; i++) {
                String v = t.getString(KEYS[i]).trim();   // "05:12", sometimes "05:12 (+01)"
                m[i] = Integer.parseInt(v.substring(0, 2)) * 60 + Integer.parseInt(v.substring(3, 5));
                if (m[i] < 0 || m[i] >= 24 * 60) throw new IllegalArgumentException("time " + v);
                a.put(m[i]);
            }
            // "date":{"hijri":{"day":"13","month":{"number":5,"days":30},"year":"1448"}}; optional, never fatal.
            JSONObject hijri = new JSONObject();
            JSONObject h = data.optJSONObject("date") != null ? data.getJSONObject("date").optJSONObject("hijri") : null;
            JSONObject hm = h != null ? h.optJSONObject("month") : null;
            if (h != null && hm != null) {
                hijri.put("day", Integer.parseInt(h.getString("day").trim()))
                        .put("month", hm.getInt("number"))
                        .put("year", Integer.parseInt(h.getString("year").trim()))
                        .put("days", hm.optInt("days", 30));
            }
            File tmp = new File(ctx.getFilesDir(), FILE + ".tmp");
            try (FileOutputStream out = new FileOutputStream(tmp)) {
                out.write(new JSONObject().put("key", key).put("minutes", a).put("hijri", hijri).toString().getBytes(StandardCharsets.UTF_8));
            }
            if (!tmp.renameTo(new File(ctx.getFilesDir(), FILE))) Log.w(TAG, "could not save " + FILE);
            return new Day(key, m, hijri.optInt("day"), hijri.optInt("month"), hijri.optInt("year"), hijri.optInt("days"));
        } catch (Exception e) {
            Log.w(TAG, "fetch: " + e);
            return null;
        }
    }

    /** The prayer to show now: the current one for NOW_MINUTES after its time, else the next; after Isha, tomorrow's Fajr. */
    static Next next(Day day) {
        Calendar c = Calendar.getInstance();
        int now = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE);
        int[] m = day.minutes;
        for (int i = 0; i < KEYS.length; i++) {
            if (i == SUNRISE) continue;
            if (now >= m[i] && now < m[i] + NOW_MINUTES) return new Next(i, m[i] - now, false);
            if (m[i] > now) return new Next(i, m[i] - now, false);
        }
        int fajr = m[0] + 24 * 60;   // today's Fajr stands in for tomorrow's, a minute out at most
        return new Next(0, fajr - now, true);
    }

    /**
     * The namaz whose time it is now, or -1 between sunrise and Dhuhr, when none is. Fajr lasts until sunrise,
     * each other one until the next begins, and Isha until Fajr (so also before Fajr, after midnight).
     */
    static int current(Day day) {
        int now = minuteOfDay();
        int[] m = day.minutes;
        if (now < m[0]) return 5;          // Isha, from the evening before
        if (now < m[SUNRISE]) return 0;    // Fajr
        if (now < m[2]) return -1;         // sunrise to Dhuhr: no namaz due
        for (int i = KEYS.length - 1; i >= 2; i--) {
            if (now >= m[i]) return i;
        }
        return -1;
    }

    /** The next namaz to begin (sunrise is skipped), with the minutes until it; after Isha, tomorrow's Fajr. */
    static Next upcoming(Day day) {
        int now = minuteOfDay();
        int[] m = day.minutes;
        for (int i = 0; i < KEYS.length; i++) {
            if (i != SUNRISE && m[i] > now) return new Next(i, m[i] - now, false);
        }
        return new Next(0, m[0] + 24 * 60 - now, true);
    }

    private static int minuteOfDay() {
        Calendar c = Calendar.getInstance();
        return c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE);
    }

    /**
     * "13 Jumada al-Awwal 1448 AH", moved by adjustment days (-2 to 2) for a local moon sighting; null when the
     * answer had no Hijri date. Going back past the 1st assumes the tabular calendar's month lengths (odd months
     * 30 days, even 29), which is right for the month before almost always.
     */
    static String hijri(Context ctx, Day day, int adjustment) {
        if (day.hijriDay < 1 || day.hijriMonth < 1 || day.hijriMonth > 12 || day.hijriYear < 1) return null;
        int d = day.hijriDay + adjustment, mo = day.hijriMonth, y = day.hijriYear;
        int length = day.hijriMonthDays >= 29 && day.hijriMonthDays <= 30 ? day.hijriMonthDays : 30;
        if (d > length) {
            d -= length;
            if (++mo > 12) { mo = 1; y++; }
        } else if (d < 1) {
            if (--mo < 1) { mo = 12; y--; }
            d += mo % 2 == 1 ? 30 : 29;
        }
        String[] months = ctx.getResources().getStringArray(R.array.hijri_months);
        return ctx.getString(R.string.hijri_date_format, d, months[mo - 1], y);
    }

    static String name(Context ctx, int index) {
        switch (index) {
            case 0: return ctx.getString(R.string.prayer_fajr);
            case 1: return ctx.getString(R.string.prayer_sunrise);
            case 2: return ctx.getString(R.string.prayer_dhuhr);
            case 3: return ctx.getString(R.string.prayer_asr);
            case 4: return ctx.getString(R.string.prayer_maghrib);
            default: return ctx.getString(R.string.prayer_isha);
        }
    }

    /** "17:55" or "5:55 PM", following the TV's 12/24 hour setting. */
    static String time(Context ctx, int minutes) {
        Calendar c = Calendar.getInstance();
        c.set(Calendar.HOUR_OF_DAY, minutes / 60);
        c.set(Calendar.MINUTE, minutes % 60);
        return DateFormat.format(DateFormat.is24HourFormat(ctx) ? "HH:mm" : "h:mm a", c).toString();
    }

    /** "in 2 h 24 min", "in 8 min" or "now". */
    static String countdown(Context ctx, Next n) {
        if (n.minutesLeft <= 0) return ctx.getString(R.string.prayer_now);
        String left = n.minutesLeft >= 60
                ? ctx.getString(R.string.prayer_hours_minutes, n.minutesLeft / 60, n.minutesLeft % 60)
                : ctx.getString(R.string.prayer_minutes, n.minutesLeft);
        return ctx.getString(R.string.prayer_in, left);
    }
}
