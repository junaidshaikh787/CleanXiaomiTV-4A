package com.gathin.tvhome;

import android.app.Activity;
import android.content.res.Resources;
import android.content.res.TypedArray;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.style.RelativeSizeSpan;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.Calendar;
import java.util.Locale;
import java.util.Random;

/**
 * The namaz panel under the clock on Home (home_prayer): the next namaz with a countdown to the second and its
 * adhan time; the day's six times with the next one outlined in gold and the current one tagged; and under them
 * (home_quran) a random short surah from res/values/quran.xml, the Basmala and then one ayah at a time with
 * Pickthall's English, a new surah after the last ayah. MainActivity hands it the day's times; the ticks run
 * only between start() and stop() (Home on screen).
 */
final class NamazPanel {
    /** How long each ayah stays before the next fades in. */
    private static final long AYAH_MS = 9000;
    private static final int GOLD = MainActivity.PRAYER_GOLD;

    private final Activity activity;
    private final View panel, quranCard, quranAyah;
    private final TextView nextName, nextCountdown, nextAdhan, quranRef, quranArabic, quranEnglish;
    private final View[] cards = new View[Prayer.KEYS.length];
    private final TextView[] tags = new TextView[Prayer.KEYS.length];
    private final TextView[] names = new TextView[Prayer.KEYS.length];
    private final TextView[] times = new TextView[Prayer.KEYS.length];
    private final GradientDrawable goldEdge;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Random random = new Random();

    private String place = "";
    /** running: Home is on screen; ticking: the second tick (and the ayahs, with quranOn) are scheduled. */
    private boolean quranOn, running, ticking;
    /** When the next namaz begins, in System.currentTimeMillis() terms; 0 when nothing is shown. */
    private long nextAt;
    /** The nextAt onDue was last called for, so a stale day (offline after midnight) asks once, not every second. */
    private long dueFor;
    /** Callback for when the countdown reaches zero: the next namaz begins, so the times are shown afresh. */
    private Runnable onDue;

    /** The surah on the card (index into surah_numbers) and the step in it: 0 is the Basmala, n is ayah n. */
    private int surah = -1, step;
    private String[] surahAr, surahEn;

    private final Runnable secondTick = new Runnable() {
        @Override
        public void run() {
            long left = nextAt - System.currentTimeMillis();
            if (left <= 0 && onDue != null && dueFor != nextAt) {
                dueFor = nextAt;
                onDue.run();                     // shows the next namaz, which sets a new nextAt
                left = nextAt - System.currentTimeMillis();
            }
            nextCountdown.setText(countdown(left));
            // Wake again just after the next whole second, so the seconds turn over evenly.
            handler.postDelayed(this, 1000 - System.currentTimeMillis() % 1000 + 20);
        }
    };

    private final Runnable ayahTick = new Runnable() {
        @Override
        public void run() {
            if (++step > surahAr.length) pickSurah();
            quranAyah.animate().alpha(0f).setDuration(300).withEndAction(() -> {
                showAyah();
                quranAyah.animate().alpha(1f).setDuration(400).start();
            }).start();
            handler.postDelayed(this, AYAH_MS);
        }
    };

    NamazPanel(Activity activity, Backdrop backdrop, float density) {
        this.activity = activity;
        panel = activity.findViewById(R.id.namazPanel);
        View nextCard = activity.findViewById(R.id.nextPrayerCard);
        nextName = activity.findViewById(R.id.nextPrayerName);
        nextCountdown = activity.findViewById(R.id.nextPrayerCountdown);
        nextAdhan = activity.findViewById(R.id.nextPrayerAdhan);
        quranCard = activity.findViewById(R.id.quranCard);
        quranAyah = activity.findViewById(R.id.quranAyah);
        quranRef = activity.findViewById(R.id.quranRef);
        quranArabic = activity.findViewById(R.id.quranArabic);
        quranEnglish = activity.findViewById(R.id.quranEnglish);
        float radius = 14 * density;
        nextCard.setBackground(new GlassDrawable(nextCard, backdrop, radius, density));
        quranCard.setBackground(new GlassDrawable(quranCard, backdrop, radius, density));

        LinearLayout row = activity.findViewById(R.id.prayerRow);
        LayoutInflater inflater = LayoutInflater.from(activity);
        for (int i = 0; i < cards.length; i++) {
            View card = inflater.inflate(R.layout.item_prayer_card, row, false);
            if (i > 0) ((ViewGroup.MarginLayoutParams) card.getLayoutParams()).setMarginStart((int) (8 * density));
            card.setBackground(new GlassDrawable(card, backdrop, radius, density));
            tags[i] = card.findViewById(R.id.prayerTag);
            names[i] = card.findViewById(R.id.prayerCardName);
            names[i].setText(Prayer.name(activity, i));
            times[i] = card.findViewById(R.id.prayerCardTime);
            row.addView(card);
            cards[i] = card;
        }
        // The next namaz's card: a gold line over the glass edge.
        goldEdge = new GradientDrawable();
        goldEdge.setCornerRadius(radius);
        goldEdge.setStroke(Math.max(1, Math.round(1.5f * density)), GOLD);
    }

    void setOnDue(Runnable onDue) {
        this.onDue = onDue;
    }

    /** Shows the day's times; place goes after the adhan time ("" leaves it out). */
    void show(Prayer.Day day, String place, boolean quranOn) {
        this.place = place == null ? "" : place;
        if (quranOn && surah < 0) {
            pickSurah();
            showAyah();
        }
        if (this.quranOn != quranOn) {
            this.quranOn = quranOn;
            quranCard.setVisibility(quranOn ? View.VISIBLE : View.GONE);
            ticking = false;                     // the ayah tick starts or stops with the next restart below
        }
        int current = Prayer.current(day);
        Prayer.Next next = Prayer.upcoming(day);
        for (int i = 0; i < cards.length; i++) {
            boolean isNext = i == next.index;
            boolean isNow = i == current;
            times[i].setText(styledTime(Prayer.time(activity, day.minutes[i])));
            times[i].setTextColor(isNext ? GOLD : 0xFFFFFFFF);
            names[i].setTextColor(isNext ? GOLD : 0xE6FFFFFF);
            tags[i].setText(isNext ? R.string.prayer_next_label : R.string.prayer_now_label);
            tags[i].setTextColor(isNext ? GOLD : 0x8CFFFFFF);
            tags[i].setVisibility(isNext || isNow ? View.VISIBLE : View.INVISIBLE);
            cards[i].setForeground(isNext ? goldEdge : null);
        }
        nextName.setText(Prayer.name(activity, next.index));
        String at = Prayer.time(activity, day.minutes[next.index]);
        nextAdhan.setText(this.place.isEmpty()
                ? activity.getString(R.string.prayer_adhan_at, at)
                : activity.getString(R.string.prayer_adhan_at_place, at, this.place));
        Calendar c = Calendar.getInstance();
        c.set(Calendar.HOUR_OF_DAY, 0);
        c.set(Calendar.MINUTE, 0);
        c.set(Calendar.SECOND, 0);
        c.set(Calendar.MILLISECOND, 0);
        if (next.tomorrow) c.add(Calendar.DAY_OF_MONTH, 1);
        c.add(Calendar.MINUTE, day.minutes[next.index]);
        nextAt = c.getTimeInMillis();
        nextCountdown.setText(countdown(nextAt - System.currentTimeMillis()));
        if (panel.getVisibility() != View.VISIBLE) {
            panel.setAlpha(0f);
            panel.setVisibility(View.VISIBLE);
            panel.animate().alpha(1f).setDuration(400).start();
        }
        // Called every minute too: a tick already running carries on (the ayahs keep their pace).
        if (running && !ticking) restartTicks();
    }

    void hide() {
        panel.setVisibility(View.GONE);
        nextAt = 0;
        ticking = false;
        handler.removeCallbacksAndMessages(null);
    }

    /** Home is on screen: tick the countdown and turn the ayahs, from a new surah. */
    void start() {
        running = true;
        if (quranOn && surah >= 0) {
            pickSurah();
            showAyah();
        }
        restartTicks();
    }

    void stop() {
        running = false;
        ticking = false;
        handler.removeCallbacksAndMessages(null);
    }

    private void restartTicks() {
        handler.removeCallbacksAndMessages(null);
        ticking = false;
        if (panel.getVisibility() != View.VISIBLE || nextAt == 0) return;
        ticking = true;
        handler.post(secondTick);
        if (quranOn) handler.postDelayed(ayahTick, AYAH_MS);
    }

    /** A random surah other than the one just shown, from its Basmala. */
    private void pickSurah() {
        Resources res = activity.getResources();
        int count = res.getIntArray(R.array.surah_numbers).length;
        int pick = random.nextInt(count);
        if (count > 1 && pick == surah) pick = (pick + 1 + random.nextInt(count - 1)) % count;
        surah = pick;
        step = 0;
        surahAr = textsAt(res, R.array.surahs_ar, surah);
        surahEn = textsAt(res, R.array.surahs_en, surah);
    }

    private static String[] textsAt(Resources res, int arrays, int index) {
        TypedArray a = res.obtainTypedArray(arrays);
        try {
            return res.getStringArray(a.getResourceId(index, 0));
        } finally {
            a.recycle();
        }
    }

    private void showAyah() {
        Resources res = activity.getResources();
        String name = res.getStringArray(R.array.surah_names)[surah];
        int number = res.getIntArray(R.array.surah_numbers)[surah];
        String ref = step == 0
                ? activity.getString(R.string.quran_ref_basmala, name, number)
                : activity.getString(R.string.quran_ref, name, number, step);
        quranRef.setText(ref);
        quranArabic.setText(step == 0 ? activity.getString(R.string.basmala_ar) : surahAr[step - 1]);
        quranEnglish.setText(step == 0 ? activity.getString(R.string.basmala_en) : surahEn[step - 1]);
    }

    /** "5:22 AM" with a smaller "AM"; a 24 hour time is left as it is. */
    private static CharSequence styledTime(String time) {
        int space = time.indexOf(' ');
        if (space < 0) return time;
        SpannableString s = new SpannableString(time);
        s.setSpan(new RelativeSizeSpan(0.62f), space, time.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        return s;
    }

    /** "7:41:25", or "0:00:00" once it is due. */
    private static String countdown(long ms) {
        long s = Math.max(0, (ms + 999) / 1000);
        return String.format(Locale.ROOT, "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60);
    }
}
