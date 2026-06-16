import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Application;
import Toybox.SensorHistory;
import Toybox.Position;
import Toybox.Math;
import Toybox.Weather;

//
// Autumn - a golden-hour fall foliage watch face.
//
//   - Center:  large digital time (Rounded) + elegant date line (Segoe UI)
//   - Left:    configurable complication (default heart rate)
//   - Right:   configurable complication (default device battery)
//   - Bottom:  steps progress bar, styled as a harvest gold bar
//   - Background: living autumn sky gradient, arcing sun/moon, drifting clouds,
//                 rolling hills, a leaf-litter forest floor, a swaying autumn grove,
//                 and maple leaves drifting + orbiting as the seconds hand
//
// The two bottom complications are chosen in the app settings (heart rate, Body
// Battery, device battery, steps, or calories) and each draws a matching icon.
// The sun, day/night, and sky track the REAL sunrise/sunset computed from the
// watch's location and today's date, falling back to a fixed autumn schedule when
// no location fix is available. The maple-leaf seconds marker is drawn last (on
// top of everything) with a black outline so it stays legible. Once in a while a
// little woodland visitor (squirrel, fox, hedgehog, a skein of geese, an owl, or
// a bat) crosses the scene.
//
// Everything scales cleanly relative to the screen dimensions (dc.getWidth()/getHeight()).
//
class AutumnView extends WatchUi.WatchFace {

    // --- Screen geometry (resolved in onLayout) ---
    private var mWidth as Number = 0;
    private var mHeight as Number = 0;
    private var mCenterX as Number = 0;
    private var mCenterY as Number = 0;

    // --- State ---
    private var mIsSleep as Boolean = false;
    private var mLowPower as Boolean = false;  // true only on AMOLED in Always-On (burn-in) mode
    private var mFlatGlobes as Boolean = false; // true on MIP: flat 2-tone fills (no banded gradient)
    private var mLastMin as Number = -1;       // throttles low-power partial updates

    // --- Complication option ids (must match resources/settings list values) ---
    private const COMP_OFF      = 0;
    private const COMP_HR       = 1;  // heart rate (BPM)
    private const COMP_BODY     = 2;  // Body Battery (%)
    private const COMP_BATTERY  = 3;  // device battery (%)
    private const COMP_STEPS    = 4;  // step count
    private const COMP_CALORIES = 5;  // calories (kcal)

    // --- Critter ids (the little woodland visitors that cross the scene) ---
    private const CR_SQUIRREL = 0;  // ground (day) - scampers across the forest floor
    private const CR_FOX      = 1;  // ground (day or night) - trots across
    private const CR_HEDGEHOG = 2;  // ground (day or night) - trundles along, foraging
    private const CR_GEESE    = 3;  // sky (day) - a small migrating V crosses overhead
    private const CR_OWL      = 4;  // sky (night) - glides silently across
    private const CR_BAT      = 5;  // sky (night) - flutters across
    // Seasonal-holiday critters (only join the rotation when their mode is on).
    private const CR_BLACKCAT = 6;  // Halloween, ground - arched back, glowing eyes
    private const CR_GHOST    = 7;  // Halloween, sky - a floaty sheet ghost
    private const CR_TURKEY   = 8;  // Thanksgiving, ground - struts with a fanned tail

    // --- Settings (see resources/settings) ---
    private var mShowDate as Boolean = true;
    private var mStepGoalOverride as Number = 0;  // 0 => use device step goal
    private var mLeftComp as Number = COMP_HR;       // bottom-left complication
    private var mRightComp as Number = COMP_BATTERY; // bottom-right complication
    private var mShowCritters as Boolean = true;     // the crossing woodland visitors
    private var mShowHalloween as Boolean = false;   // jack-o'-lantern + spooky visitors
    private var mShowThanksgiving as Boolean = false; // harvest pumpkins + a turkey

    // --- Heart-rate cache (sensor read throttled to once every ~10s) ---
    private var mCachedHr as Number or Null = null;
    private var mHrLastSec as Number = -100;

    // --- Sunrise/sunset cache (recomputed when the day or first fix changes) ---
    private var mSunDay as Number = -1;        // day-of-year the times were computed for
    private var mSunValid as Boolean = false;  // true once a real location fix was used
    private var mSunrise as Float = 6.5;       // local hours; defaults = fixed autumn schedule
    private var mSunset as Float = 18.5;
    private var mSunLastTry as Number = -10000; // epoch sec of last (not-yet-valid) sun retry

    // --- Per-frame cache of device settings (read once per redraw) ---
    private var mSettings as System.DeviceSettings or Null = null;

    // --- Fonts (vector fonts with safe fallbacks) ---
    private var mFontTime as Graphics.FontType or Null = null;
    private var mFontDate as Graphics.FontType or Null = null;
    private var mFontValue as Graphics.FontType or Null = null;
    private var mFontLabel as Graphics.FontType or Null = null;

    // --- Color Palettes ----------------------------------------------------
    // Body Battery = maple orange
    private const C_BODY_BRIGHT = 0xFF6A2E;
    private const C_BODY_DARK   = 0x3A1206;
    private const C_BODY_RIM    = 0xFF9E5A;
    private const C_BODY_GLOW   = 0x5A2410;

    // Device battery = golden amber
    private const C_BATT_BRIGHT = 0xFFB23A;
    private const C_BATT_DARK   = 0x3A2A0A;
    private const C_BATT_RIM    = 0xE0902A;
    private const C_BATT_GLOW   = 0x5A3A10;

    // Steps bar = harvest gold / burnt orange
    private const C_XP_TRACK    = 0x2A1C0E;
    private const C_XP_FILL     = 0xD4622A;
    private const C_XP_BRIGHT   = 0xFFC043;
    private const C_XP_GLOW     = 0x6A3810;
    private const C_XP_BORDER   = 0xFFE6B0;

    private const BG_COLOR = 0x000000;        // pitch black for AMOLED contrast/battery

    // --- Hoisted constants (avoid re-allocating these arrays every frame) ---
    // Star field positions, expressed against a 454x454 reference and scaled.
    private const STAR_X = [70, 120, 180, 240, 310, 380, 90, 150, 220, 290, 360, 130, 200, 270, 340, 110, 250, 330] as Array<Number>;
    private const STAR_Y = [50, 70, 45, 60, 55, 75, 110, 95, 120, 105, 115, 160, 150, 175, 155, 200, 210, 195] as Array<Number>;
    // Sky gradient keyframe colors (identical for the real-sun and fallback schedules).
    private const SKY_TOP    = [0x080814, 0x141029, 0x6E4A6A, 0x4E86A8, 0x5AA0C0, 0xB0743C, 0x9A3A28, 0x241834, 0x080814] as Array<Number>;
    private const SKY_BOTTOM = [0x10101F, 0x33243F, 0xFF955A, 0xE8C486, 0xCDE0DC, 0xFFB347, 0xFFC95A, 0x4A2C48, 0x10101F] as Array<Number>;
    // Fixed-autumn fallback keyframe hours, used when no real sun fix is available.
    private const SKY_HOURS_FALLBACK = [0.0, 5.0, 6.5, 9.0, 14.0, 17.0, 18.5, 20.5, 24.0] as Array<Float>;

    // Forest layout: base X (fraction of width) + canopy scale. Two large trees
    // frame the edges; two smaller ones sit further back toward the center.
    private const FOREST_TXF = [0.86, 0.10, 0.72, 0.27] as Array<Float>;
    private const FOREST_TSC = [1.00, 0.92, 0.60, 0.64] as Array<Float>;
    private const LEAF_COLORS = [0xE0651E, 0xE0A828, 0xC8501E, 0xB23A1E, 0xD4621E] as Array<Number>;
    private const LITTER_COLORS = [0xC8501E, 0xE0A828, 0xB23A1E] as Array<Number>;
    private const LITTER_X = [60, 150, 250, 350, 410] as Array<Number>;
    // Canopy foliage blobs: [dxFrac, dyFrac, rFrac, colorIndex].
    private const CANOPY_COLORS = [0xB23A1E, 0xD4621E, 0xE89A2A, 0xC8501E, 0xE0A828] as Array<Number>;
    private const CANOPY_BX = [ 0.00, -0.07,  0.07, -0.03,  0.05,  0.00, -0.09,  0.09,  0.03] as Array<Float>;
    private const CANOPY_BY = [-0.02,  0.01,  0.00, -0.06, -0.05,  0.05, -0.02, -0.03,  0.06] as Array<Float>;
    private const CANOPY_BR = [ 0.10,  0.085, 0.085, 0.075, 0.08,  0.075, 0.06,  0.06,  0.07] as Array<Float>;
    private const CANOPY_CI = [ 1,     0,     2,     3,     2,     4,     0,     3,     1] as Array<Number>;

    // Reusable polygon buffer for the rolling hills (filled in place each frame
    // instead of allocating a new array + point pairs on every redraw).
    private var mHillPts as Array or Null = null;

    // --- Per-frame caches (read once per redraw to avoid duplicate syscalls) ---
    private var mClock as System.ClockTime or Null = null;
    private var mActInfo as ActivityMonitor.Info or Null = null;

    // --- Cached AMOLED sky-gradient buffer ---------------------------------
    // The gradient colors depend only on hour+minute, so they change at most
    // once a minute. We render the per-row fill into a buffered bitmap once and
    // just blit it on subsequent (per-second) frames, re-rendering only when the
    // colors or dimensions change. Only used on AMOLED (MIP uses a flat fill).
    private var mSkyBufRef as Graphics.BufferedBitmapReference or Null = null;
    private var mSkyKeyTop as Number = -1;
    private var mSkyKeyBottom as Number = -1;
    private var mSkyKeyW as Number = -1;
    private var mSkyKeyH as Number = -1;

    // --- Adaptive render quality (auto-tunes to the device's frame budget) ---
    // onUpdate times itself and nudges mQuality up/down with hysteresis. Expensive
    // detail (text-outline passes, grove segments, sun rays) scales with it, so a
    // slow/large panel sheds just enough detail to stay smooth while the whole
    // scene keeps animating. 3 = full detail, 0 = leanest.
    private var mQuality as Number = 2;
    private var mFrameStart as Number = 0;
    private const Q_SLOW_MS = 220;  // frame slower than this -> drop a level
    private const Q_FAST_MS = 120;  // frame faster than this -> raise a level

    function initialize() {
        WatchFace.initialize();
        loadSettings();
    }

    // Read user settings; safe to call any time.
    function loadSettings() as Void {
        try {
            if (Application has :Properties) {
                var showDate = Application.Properties.getValue("ShowDate");
                var stepGoal = Application.Properties.getValue("StepGoalOverride");
                var leftComp = Application.Properties.getValue("LeftComplication");
                var rightComp = Application.Properties.getValue("RightComplication");
                var critters = Application.Properties.getValue("ShowCritters");
                var halloween = Application.Properties.getValue("ShowHalloween");
                var thanksgiving = Application.Properties.getValue("ShowThanksgiving");
                if (showDate != null) { mShowDate = showDate; }
                if (stepGoal != null) { mStepGoalOverride = stepGoal; }
                if (leftComp != null) { mLeftComp = leftComp; }
                if (rightComp != null) { mRightComp = rightComp; }
                if (critters != null) { mShowCritters = critters; }
                if (halloween != null) { mShowHalloween = halloween; }
                if (thanksgiving != null) { mShowThanksgiving = thanksgiving; }
            }
        } catch (e) {
            // keep defaults
        }
        if (mStepGoalOverride < 0) { mStepGoalOverride = 0; }
    }

    function onLayout(dc as Dc) as Void {
        mWidth = dc.getWidth();
        mHeight = dc.getHeight();
        mCenterX = mWidth / 2;
        mCenterY = mHeight / 2;
        initFonts();
    }

    // Custom fonts generated by gen_fonts.py are loaded here.
    function initFonts() as Void {
        try {
            mFontTime  = WatchUi.loadResource(Rez.Fonts.ExocetTime) as Graphics.FontType;
            mFontValue = WatchUi.loadResource(Rez.Fonts.ExocetValue) as Graphics.FontType;
            mFontLabel = WatchUi.loadResource(Rez.Fonts.ExocetLabel) as Graphics.FontType;
            mFontDate  = mFontLabel;
        } catch (e) {
            mFontTime = null;
            mFontValue = null;
            mFontLabel = null;
            mFontDate = null;
        }

        // Vector-font fallback for anything that didn't load.
        if (Graphics has :getVectorFont) {
            var bold = ["RobotoCondensedBold", "RobotoRegular", "sans-serif"] as Array<String>;
            if (mFontTime == null)  { mFontTime  = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.21).toNumber() }); }
            if (mFontDate == null)  { mFontDate  = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.058).toNumber() }); }
            if (mFontValue == null) { mFontValue = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.085).toNumber() }); }
            if (mFontLabel == null) { mFontLabel = Graphics.getVectorFont({ :face => bold, :size => (mWidth * 0.044).toNumber() }); }
        }

        // Built-in last resort.
        if (mFontTime == null)  { mFontTime  = Graphics.FONT_NUMBER_THAI_HOT; }
        if (mFontDate == null)  { mFontDate  = Graphics.FONT_TINY; }
        if (mFontValue == null) { mFontValue = Graphics.FONT_MEDIUM; }
        if (mFontLabel == null) { mFontLabel = Graphics.FONT_XTINY; }
    }

    function onShow() as Void {
        loadSettings();
    }

    // Single render entry point for both active and low-power frames.
    function onUpdate(dc as Dc) as Void {
        mFrameStart = System.getTimer();  // adaptive-quality frame timer
        var w = mWidth;
        var h = mHeight;

        var settings = System.getDeviceSettings();
        mSettings = settings;  // cache for drawTime / getWeatherString this frame
        var hasBurnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        var burnIn = hasBurnIn && mIsSleep;
        var dx = 0;
        var dy = 0;
        if (burnIn) {
            var shift = computeBurnInShift();
            dx = shift[0];
            dy = shift[1];
        }
        mLowPower = burnIn;
        mFlatGlobes = !hasBurnIn;

        var cx = mCenterX + dx;
        var cy = mCenterY + dy;

        // 1. Clear to pitch black
        dc.setColor(BG_COLOR, BG_COLOR);
        dc.clear();

        // Time values (cache the clock + activity info once for this redraw)
        var clockTime = System.getClockTime();
        mClock = clockTime;
        mActInfo = ActivityMonitor.getInfo();
        var hour = clockTime.hour;
        var min = clockTime.min;
        var secVal = clockTime.sec;

        if (!mLowPower) {
            // --- ACTIVE VISUAL LAYER ---

            // A. Resolve today's sunrise/sunset (cached), then get the living
            //    autumn-sky gradient colors for the current time.
            updateSunTimes();
            var tNow = hour.toFloat() + min.toFloat() / 60.0;
            var skyColors = getSkyColors(hour, min);
            var cTop = skyColors[0];
            var cBottom = skyColors[1];

            // B. Draw Sky
            var skyH = (h * 0.78).toNumber();
            if (mFlatGlobes) {
                // MIP: Solid fill to prevent ugly banding
                dc.setColor(cTop, cTop);
                dc.fillRectangle(0, 0, w, skyH);
            } else {
                // AMOLED: smooth gradient, cached in a buffer so the per-row fill
                // loop runs at most once a minute (when the colors change) rather
                // than on every per-second redraw.
                var skyBmp = getSkyBitmap(w, skyH, cTop, cBottom);
                if (skyBmp != null) {
                    dc.drawBitmap(0, 0, skyBmp);
                } else {
                    // Fallback: render the gradient directly (no buffered bitmap).
                    var step = 4;
                    for (var y = 0; y < skyH; y += step) {
                        var frac = y.toFloat() / skyH.toFloat();
                        var c = lerpColor(cTop, cBottom, frac);
                        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
                        dc.fillRectangle(0, y, w, step);
                    }
                }
            }

            var isNight = !(tNow >= mSunrise && tNow < mSunset);

            // C. Draw Stars at night
            if (isNight) {
                dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
                for (var i = 0; i < STAR_X.size(); i++) {
                    var sx = (STAR_X[i] * w / 454).toNumber();
                    var sy = (STAR_Y[i] * h / 454).toNumber();
                    dc.drawPoint(sx, sy);
                }
            }

            // D. Draw Arcing Sun / Moon along the real day arc
            var dayStart = mSunrise;
            var dayEnd = mSunset;
            var t = tNow;
            var isDay = !isNight;
            var arcR = (w * 0.38).toNumber();
            var arcCenterY = (h * 0.70).toNumber();

            var angle = 0.0;
            if (isDay) {
                angle = Math.PI - (Math.PI * (t - dayStart) / (dayEnd - dayStart));
            } else {
                var tNight = (t < dayStart) ? (t + (24.0 - dayEnd)) : (t - dayEnd);
                angle = Math.PI - (Math.PI * tNight / (24.0 - (dayEnd - dayStart)));
            }
            var sx = cx + (arcR * Math.cos(angle)).toNumber();
            var sy = arcCenterY - (arcR * Math.sin(angle)).toNumber();

            if (isDay) {
                var sunR = (w * 0.065).toNumber();
                var sunSkyFrac = sy.toFloat() / skyH.toFloat();
                if (sunSkyFrac < 0.0) { sunSkyFrac = 0.0; }
                if (sunSkyFrac > 1.0) { sunSkyFrac = 1.0; }
                var sunSkyColor = lerpColor(cTop, cBottom, sunSkyFrac);

                // Rays rotation based on seconds (skipped at low quality)
                if (mQuality >= 2) {
                    dc.setColor(0xFFB347, Graphics.COLOR_TRANSPARENT);
                    dc.setPenWidth(1);
                    var numRays = 8;
                    var secOffset = secVal.toFloat() * 0.02;
                    for (var i = 0; i < numRays; i++) {
                        var rayAngle = (i * (2.0 * Math.PI / numRays)) + secOffset;
                        var rx1 = (sx + (sunR + 2) * Math.cos(rayAngle)).toNumber();
                        var ry1 = (sy + (sunR + 2) * Math.sin(rayAngle)).toNumber();
                        var rx2 = (sx + (sunR + 8) * Math.cos(rayAngle)).toNumber();
                        var ry2 = (sy + (sunR + 8) * Math.sin(rayAngle)).toNumber();
                        dc.drawLine(rx1, ry1, rx2, ry2);
                    }
                }

                // Procedural bloom (warm amber harvest sun)
                dc.setColor(lerpColor(sunSkyColor, 0xFFA838, 0.25), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, sunR + 6);
                dc.setColor(lerpColor(sunSkyColor, 0xFFA838, 0.55), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, sunR + 3);

                // Core
                dc.setColor(0xFFB347, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, sunR);
                dc.setColor(0xFFE0A0, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, sunR - 4);
            } else {
                var moonR = (w * 0.055).toNumber();
                var moonSkyFrac = sy.toFloat() / skyH.toFloat();
                if (moonSkyFrac < 0.0) { moonSkyFrac = 0.0; }
                if (moonSkyFrac > 1.0) { moonSkyFrac = 1.0; }
                var moonSkyColor = lerpColor(cTop, cBottom, moonSkyFrac);

                // Pale harvest-moon base circle
                dc.setColor(0xF0E2C0, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, moonR);
                // Offset circle of sky color to mask crescent
                dc.setColor(moonSkyColor, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(sx + 5, sy - 2, moonR);
            }

            // E. Draw Drifting Clouds (muted autumn overcast)
            var cloudOffset = (min * 60 + secVal).toFloat();
            var span = w + 80;
            // Positive modulo: Monkey C's % keeps the sign of the dividend, so a
            // negative drift (cloud 2) would otherwise wrap off-screen.
            var cx1 = (((((w * 0.1 + (cloudOffset * 0.08)).toNumber()) % span) + span) % span) - 40;
            var cx2 = (((((w * 0.7 - (cloudOffset * 0.05)).toNumber()) % span) + span) % span) - 40;
            drawCloud(dc, cx1, (h * 0.18).toNumber());
            drawCloud(dc, cx2, (h * 0.26).toNumber());

            // Resolve which little visitor (if any) is crossing right now, so a
            // flying one can be drawn up in the sky (behind the grove) and a
            // ground one in front of the forest floor.
            var crit = mShowCritters ? computeCritter(hour, min, secVal, isNight) : null;
            if (crit != null && isSkyCritter(crit[0] as Number)) {
                drawCritter(dc, crit);
            }

            // F. Draw Rolling Autumn Hills (sine-wave polygons)
            var hillPhase1 = secVal.toFloat() * 0.015;
            var hillPhase2 = secVal.toFloat() * 0.010 + 1.7;
            // Back hill (dark olive)
            drawHill(dc, (h * 0.74).toNumber(), 9, 70.0, hillPhase1, 0x5C5226);
            // Front hill (burnt sienna)
            drawHill(dc, (h * 0.80).toNumber(), 7, 52.0, hillPhase2, 0x7A3F1E);

            // G. Draw Leaf-litter Forest Floor
            var floorY = (h * 0.88).toNumber();
            dc.setColor(0x6E3A16, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(0, floorY, w, h - floorY);
            // A few scattered fallen leaves on the ground
            for (var i = 0; i < LITTER_X.size(); i++) {
                var lx = (LITTER_X[i] * w / 454).toNumber();
                var ly = floorY + ((h - floorY) * 0.5).toNumber();
                drawMapleLeaf(dc, lx, ly, (w * 0.012).toNumber() + 3, LITTER_COLORS[i % 3], false);
            }

            // H. Draw a small grove of swaying autumn trees with leaves falling
            //    out of each canopy.
            drawForest(dc, floorY, min, secVal);

            // H.5. Seasonal-holiday decorations rest on the leaf litter, nestled
            //      by the trees at the bottom corners (opt-in via settings).
            var decorY = (floorY + (h - floorY) * 0.42).toNumber();
            if (mShowHalloween) {
                drawJackOLantern(dc, (w * 0.17).toNumber(), decorY, (w * 0.05).toNumber(), secVal);
            }
            if (mShowThanksgiving) {
                drawPumpkinPatch(dc, (w * 0.83).toNumber(), decorY, (w * 0.046).toNumber());
            }

            // I. Ground visitors (squirrel scurrying, fox trotting, hedgehog
            //    trundling) are drawn in front of the forest floor.
            if (crit != null && !isSkyCritter(crit[0] as Number)) {
                drawCritter(dc, crit);
            }

            // (The maple-leaf seconds marker is drawn LAST, on top of everything.)
        }

        // --- Center Clock & Date ---
        drawTime(dc, cx, cy - (h * 0.05).toNumber());
        if (mShowDate) {
            drawDate(dc, cx, cy + (h * 0.06).toNumber());
        }

        // --- Bottom Complications (Symmetrical Layout) ---
        var metricsY = (h * 0.815).toNumber() + dy;
        var leftX    = (w * 0.22).toNumber() + dx;
        var rightX   = (w * 0.78).toNumber() + dx;

        // Bottom complications are user-configurable (see resources/settings).
        drawComplication(dc, leftX, metricsY, mLeftComp);
        drawComplication(dc, rightX, metricsY, mRightComp);

        // Steps Progress Bar & Numeric Text (Centered)
        var barW = (w * 0.38).toNumber();
        var barH = 8;
        var barY = (h * 0.91).toNumber() + dy;
        var stepsFraction = getStepFraction();
        drawXpBar(dc, cx, barY, barW, barH, stepsFraction);

        if (!burnIn) {
            var actInfo = mActInfo;
            var steps = (actInfo != null && actInfo.steps != null) ? actInfo.steps : 0;
            var stepsStr = steps.format("%d") + " STEPS";
            drawTextWithOutline(dc, cx, barY - 14, mFontLabel, stepsStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, 0xFFFFFF);
        }

        // --- Maple Leaf Seconds (drawn LAST so it sits above everything) ----
        // A black-outlined maple leaf orbits the dial as the seconds marker. Only
        // shown while the watch is ACTIVE (high power); the OS stops per-second
        // updates ~15s after a wrist raise, so rather than leave the marker
        // parked/frozen we hide it until the watch wakes again. Gated on mIsSleep
        // (not mLowPower) because MIP devices never set mLowPower.
        if (!mIsSleep) {
            var secAngle = (secVal * 6.0) * Math.PI / 180.0;
            var secRadius = (w * 0.44).toNumber() - 10;
            var csx = cx + (secRadius * Math.sin(secAngle)).toNumber();
            var csy = cy - (secRadius * Math.cos(secAngle)).toNumber();
            drawMapleLeaf(dc, csx, csy, (w * 0.022).toNumber(), 0xE0651E, true);

            // Adaptive quality: measure how long this active frame took and nudge
            // the detail level so the watch keeps issuing per-second updates
            // (i.e. the seconds marker keeps moving) instead of hitting the budget.
            var dt = System.getTimer() - mFrameStart;
            if (dt > Q_SLOW_MS) {
                if (mQuality > 0) { mQuality--; }
            } else if (dt < Q_FAST_MS) {
                if (mQuality < 3) { mQuality++; }
            }
        }
    }

    // Anti-burn-in pixel shift for AMOLED always-on mode. Cycles through a few
    // small offsets so static pixels are not lit identically minute after minute.
    private function computeBurnInShift() as Array<Number> {
        var clock = (mClock != null) ? mClock : System.getClockTime();
        var phase = clock.min % 4;
        if (phase == 1)      { return [4, 2] as Array<Number>; }
        else if (phase == 2) { return [-3, 4] as Array<Number>; }
        else if (phase == 3) { return [3, -4] as Array<Number>; }
        return [0, 0] as Array<Number>;
    }

    // ------------------------------------------------------------------ Elements

    function drawTime(dc as Dc, cx as Number, cy as Number) as Void {
        var clock = (mClock != null) ? mClock : System.getClockTime();
        var hour = clock.hour;
        var min = clock.min;
        var settings = (mSettings != null) ? mSettings : System.getDeviceSettings();
        var is24 = settings.is24Hour;
        if (!is24) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var hourStr = is24 ? hour.format("%02d") : hour.format("%d");
        var timeStr = hourStr + ":" + min.format("%02d");

        // Dim in AOD, warm cream-white otherwise
        var color = mLowPower ? 0x6E6E6E : 0xFFEFD8;
        drawTextWithOutline(dc, cx, cy, mFontTime, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, color);
    }

    function drawDate(dc as Dc, cx as Number, y as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = info.day_of_week.toUpper() + "   " + info.month.toUpper() + " " + info.day;

        // Append weather if available. Skipped in always-on/low-power so the
        // weather lookup never runs inside the partial-update budget (and so the
        // dim AOD date stays consistent between full and partial redraws).
        var weatherStr = mLowPower ? null : getWeatherString();
        if (weatherStr != null) {
            dateStr = dateStr + "   •   " + weatherStr;
        }

        // Dim in AOD, warm amber otherwise
        var color = mLowPower ? 0x555555 : 0xFFAE5A;
        drawTextWithOutline(dc, cx, y, mFontDate, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER, color);
    }

    private function drawCloud(dc as Dc, x as Number, y as Number) as Void {
        dc.setColor(0xD8D0C4, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 12, y, 10);
        dc.fillCircle(x + 12, y, 10);
        dc.fillCircle(x, y - 5, 14);
        dc.fillRectangle(x - 12, y - 2, 24, 12);
    }

    // Rolling autumn hill - a sine-wave polygon filled to the bottom of the screen.
    private function drawHill(dc as Dc, yBase as Number, amp as Number, waveLen as Float, phase as Float, color as Number) as Void {
        var w = mWidth;
        var h = mHeight;

        var steps = 12;
        var stepW = w / steps;
        // Reuse a persistent buffer (and its point pairs) instead of allocating
        // a fresh array + sub-arrays on every call (twice per frame).
        if (mHillPts == null) {
            var buf = new [steps + 3] as Array<Array>;
            for (var k = 0; k < steps + 3; k++) { buf[k] = [0, 0]; }
            mHillPts = buf;
        }
        var points = mHillPts;
        points[0][0] = w; points[0][1] = h;
        points[1][0] = 0; points[1][1] = h;

        for (var i = 0; i <= steps; i++) {
            var x = i * stepW;
            var angle = (x.toFloat() / waveLen) + phase;
            var y = yBase + (amp * Math.sin(angle)).toNumber();
            points[i + 2][0] = x;
            points[i + 2][1] = y;
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(points);
    }

    // A small grove of autumn trees. Each tree sways a little, and a handful of
    // maple leaves spill out of its canopy and flutter down to the ground - leaves
    // only ever originate from a tree, never from empty sky.
    private function drawForest(dc as Dc, floorY as Number, min as Number, secVal as Number) as Void {
        var w = mWidth;
        var tSec = (min * 60 + secVal).toFloat();

        // Grove detail scales with adaptive quality (the grove is the single most
        // expensive per-frame draw, so it sheds segments/leaves first under load).
        var trunkSteps = (mQuality >= 3) ? 12 : (mQuality == 2) ? 10 : 8;
        var blobCount  = (mQuality >= 2) ? 9  : (mQuality == 1) ? 7 : 5;
        var leavesPerTree = (mQuality >= 2) ? 3 : (mQuality == 1) ? 2 : 1;

        // Draw the trunks + canopies first.
        for (var i = 0; i < FOREST_TXF.size(); i++) {
            var sway = 0.05 * Math.sin(tSec * 0.04 + i * 1.3);
            drawAutumnTree(dc, (FOREST_TXF[i] * w).toNumber(), floorY, sway, FOREST_TSC[i], trunkSteps, blobCount);
        }

        // Then rain leaves down out of each canopy (drawn on top of the trees).
        for (var i = 0; i < FOREST_TXF.size(); i++) {
            var scale = FOREST_TSC[i];
            var sway = 0.05 * Math.sin(tSec * 0.04 + i * 1.3);
            var canopyX = canopyCenterX((FOREST_TXF[i] * w).toNumber(), sway, scale);
            var canopyY = canopyCenterY(floorY, scale);
            var canopyR = (0.14 * w * scale);

            for (var k = 0; k < leavesPerTree; k++) {
                var seed = i * 7 + k;
                var speed = 0.0006 + (k % 3) * 0.00025;
                var fall = (tSec * speed + seed * 0.37);
                fall = fall - Math.floor(fall);

                var startY = canopyY - (canopyR * 0.4).toNumber();
                var endY = floorY + 6;
                var y = (startY + fall * (endY - startY)).toNumber();

                // Spread leaves across the canopy width, then let them drift
                // sideways more and more as they fall.
                var spread = ((k - (leavesPerTree - 1) / 2.0)) * canopyR * 0.6;
                var drift = canopyR * 0.5 * Math.sin(tSec * 0.06 + seed);
                var x = (canopyX + spread + drift * fall).toNumber();

                drawMapleLeaf(dc, x, y, (w * 0.013 * scale).toNumber() + 2, LEAF_COLORS[seed % LEAF_COLORS.size()], false);
            }
        }
    }

    // Canopy center, kept in sync between tree drawing and leaf spawning.
    private function canopyCenterX(baseX as Number, sway as Float, scale as Float) as Number {
        return (baseX - mWidth * 0.03 * scale + sway * 40 * scale + sway * 20).toNumber();
    }

    private function canopyCenterY(baseY as Number, scale as Float) as Number {
        return (baseY - mHeight * 0.30 * scale - mHeight * 0.02 * scale).toNumber();
    }

    // A bare-trunked deciduous tree with a fiery autumn canopy, sized by `scale`.
    private function drawAutumnTree(dc as Dc, baseX as Number, baseY as Number, sway as Float, scale as Float, trunkSteps as Number, blobCount as Number) as Void {
        var w = mWidth;
        var h = mHeight;

        var trunkTopX = (baseX - w * 0.03 * scale + sway * 40 * scale).toNumber();
        var trunkTopY = (baseY - h * 0.30 * scale).toNumber();

        // Trunk (tapered, dark brown)
        var trunkColor = 0x3A2614;
        dc.setColor(trunkColor, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i <= trunkSteps; i++) {
            var tt = i.toFloat() / trunkSteps.toFloat();
            var x = (baseX + (trunkTopX - baseX) * tt).toNumber();
            var y = (baseY + (trunkTopY - baseY) * tt).toNumber();
            var r = (8.0 * scale - 5.0 * scale * tt).toNumber();
            if (r < 2) { r = 2; }
            dc.fillCircle(x, y, r);
        }

        // A couple of branches reaching into the canopy
        dc.setPenWidth(3);
        dc.setColor(trunkColor, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(trunkTopX, (trunkTopY + h * 0.06 * scale).toNumber(), (trunkTopX - w * 0.07 * scale).toNumber(), (trunkTopY - h * 0.01 * scale).toNumber());
        dc.drawLine(trunkTopX, (trunkTopY + h * 0.09 * scale).toNumber(), (trunkTopX + w * 0.06 * scale).toNumber(), (trunkTopY + h * 0.01 * scale).toNumber());
        dc.setPenWidth(1);

        // Canopy - overlapping foliage blobs in fall colors
        var cxC = (trunkTopX + sway * 20).toNumber();
        var cyC = (trunkTopY - h * 0.02 * scale).toNumber();
        for (var i = 0; i < blobCount; i++) {
            var x = (cxC + CANOPY_BX[i] * w * scale + sway * 15).toNumber();
            var y = (cyC + CANOPY_BY[i] * h * scale).toNumber();
            var r = (CANOPY_BR[i] * w * scale).toNumber();
            dc.setColor(CANOPY_COLORS[CANOPY_CI[i]], Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, r);
        }
    }

    // A small stylized maple leaf (convex diamond body + midrib + stem).
    // When `outline` is set it gets a black border in 8 directions, just like
    // the text, so it stays legible against the brown forest floor.
    private function drawMapleLeaf(dc as Dc, x as Number, y as Number, r as Number, color as Number, outline as Boolean) as Void {
        if (r < 3) { r = 3; }

        if (outline && !mLowPower) {
            drawMapleLeafShape(dc, x - 1, y - 1, r, 0x000000, 0x000000);
            drawMapleLeafShape(dc, x + 1, y - 1, r, 0x000000, 0x000000);
            drawMapleLeafShape(dc, x - 1, y + 1, r, 0x000000, 0x000000);
            drawMapleLeafShape(dc, x + 1, y + 1, r, 0x000000, 0x000000);
            drawMapleLeafShape(dc, x - 1, y,     r, 0x000000, 0x000000);
            drawMapleLeafShape(dc, x + 1, y,     r, 0x000000, 0x000000);
            drawMapleLeafShape(dc, x,     y - 1, r, 0x000000, 0x000000);
            drawMapleLeafShape(dc, x,     y + 1, r, 0x000000, 0x000000);
        }

        drawMapleLeafShape(dc, x, y, r, color, 0x5A3A1E);
    }

    private function drawMapleLeafShape(dc as Dc, x as Number, y as Number, r as Number, bodyColor as Number, stemColor as Number) as Void {
        var hw = (r * 0.62).toNumber();

        // Stem
        dc.setColor(stemColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(x, y + (r * 0.5).toNumber(), x, y + r);

        // Leaf body (pointed top, rounded lower lobes)
        dc.setColor(bodyColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [x, y - r],
            [x + hw, y - (r * 0.15).toNumber()],
            [x + (hw * 0.6).toNumber(), y + (r * 0.5).toNumber()],
            [x - (hw * 0.6).toNumber(), y + (r * 0.5).toNumber()],
            [x - hw, y - (r * 0.15).toNumber()]
        ] as Array<Array>);

        // Midrib vein
        dc.setColor(stemColor, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, y - (r * 0.8).toNumber(), x, y + (r * 0.45).toNumber());
    }

    private function drawAutumnBezel(dc as Dc, gx as Number, gy as Number, r as Number, lit as Boolean) as Void {
        var gold      = lit ? 0xFFC043 : 0x8A6A3A;
        var sand      = lit ? 0xFFE6B0 : 0xC8B486;
        var glowColor = lit ? 0xFFA838 : 0x6A3810;

        if (lit) {
            dc.setPenWidth(4);
            dc.setColor(scaleColor(glowColor, 0.4), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 2);
        }

        dc.setPenWidth(3);
        dc.setColor(sand, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r + 1);

        dc.setPenWidth(1);
        dc.setColor(gold, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r - 1);
    }

    // Liquid-fill globe.
    function drawGlobe(dc as Dc, gx as Number, gy as Number, r as Number,
                       value as Number, available as Boolean,
                       bright as Number, dark as Number, rim as Number, glow as Number) as Void {
        if (mLowPower) {
            drawGlobeLowPower(dc, gx, gy, r, value, available, rim);
            return;
        }

        // 1. Soft outer glow
        if (available && value > 0 && !mFlatGlobes) {
            dc.setPenWidth(3);
            dc.setColor(scaleColor(glow, 0.60), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 2);
            dc.setPenWidth(2);
            dc.setColor(scaleColor(glow, 0.30), Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(gx, gy, r + 5);
        }

        // 2. Dark glass sphere base.
        dc.setColor(scaleColor(dark, 0.55), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(gx, gy, r);

        // 3. Liquid fill
        if (available && value > 0) {
            var v = value;
            if (v > 100) { v = 100; }
            var fillH = (2.0 * r) * v / 100.0;
            var surfaceY = ((gy + r) - fillH).toNumber();
            var bottomY = gy + r - 1;
            var flatTop = bright;
            var flatBottom = lerpColor(bright, dark, 0.5);
            var step = 2;
            for (var y = surfaceY; y <= bottomY; y += step) {
                var half = chordHalf(r - 1, y - gy);
                if (half < 1) { continue; }
                var depth = (y - surfaceY).toFloat() / fillH;
                var c;
                if (mFlatGlobes) {
                    c = (depth < 0.55) ? flatTop : flatBottom;
                } else {
                    var tt = 1.0 - depth;
                    if (tt < 0.0) { tt = 0.0; }
                    if (tt > 1.0) { tt = 1.0; }
                    c = lerpColor(dark, bright, tt);
                }
                dc.setColor(c, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(gx - half, y, 2 * half, step);
            }

            // Molten core
            if (fillH > r * 0.5 && !mFlatGlobes) {
                var coreY = (gy + r - fillH * 0.45).toNumber();
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.10), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(gx, coreY, (r * 0.22).toNumber());
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.22), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(gx, coreY, (r * 0.10).toNumber());
            }

            // Bright meniscus line
            var mHalf = chordHalf(r, surfaceY - gy);
            if (mHalf > 1) {
                dc.setPenWidth(2);
                dc.setColor(lerpColor(bright, 0xFFFFFF, 0.35), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(gx - mHalf, surfaceY, gx + mHalf, surfaceY);
            }
        }

        // 4. Specular glass highlight
        if (available) {
            dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(gx - (r * 0.34).toNumber(), gy - (r * 0.42).toNumber(), (r * 0.12).toNumber());
        }

        // 5. Bezel
        drawAutumnBezel(dc, gx, gy, r, (available && value > 0));
    }

    // Burn-in-safe globe: just a thin dim ring + a thin fluid-level line.
    function drawGlobeLowPower(dc as Dc, gx as Number, gy as Number, r as Number,
                               value as Number, available as Boolean, rim as Number) as Void {
        dc.setPenWidth(1);
        dc.setColor(scaleColor(rim, 0.45), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(gx, gy, r);
        if (available && value > 0) {
            var v = value;
            if (v > 100) { v = 100; }
            var surfaceY = ((gy + r) - (2.0 * r) * v / 100.0).toNumber();
            var half = chordHalf(r, surfaceY - gy);
            if (half > 1) {
                dc.setColor(scaleColor(rim, 0.65), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(gx - half, surfaceY, gx + half, surfaceY);
            }
        }
    }

    // Steps progress bar
    function drawXpBar(dc as Dc, cx as Number, y as Number, barW as Number, barH as Number, frac as Float) as Void {
        var x = cx - barW / 2;
        var top = y - barH / 2;
        var rad = barH / 2;

        if (frac < 0.0) { frac = 0.0; }
        if (frac > 1.0) { frac = 1.0; }
        var fw = (barW * frac).toNumber();

        if (mLowPower) {
            dc.setPenWidth(1);
            dc.setColor(scaleColor(C_XP_FILL, 0.40), Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x, top, barW, barH, rad);
            if (fw > 2) {
                dc.setColor(scaleColor(C_XP_FILL, 0.55), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x + 2, y, x + fw - 2, y);
            }
            return;
        }

        // Track (dark earth)
        dc.setColor(C_XP_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, top, barW, barH, rad);

        // Fill (burnt-orange progress)
        if (frac > 0.0) {
            if (fw < barH) { fw = barH; }
            if (fw > barW) { fw = barW; }
            dc.setColor(C_XP_FILL, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, top, fw, barH, rad);
        }

        // Harvest frame + acorn-gold end caps
        dc.setPenWidth(1);
        dc.setColor(C_XP_BORDER, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x, top, barW, barH, rad);

        dc.setColor(C_XP_BRIGHT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 2, y, 3);
        dc.fillCircle(x + barW + 2, y, 3);
    }

    // ------------------------------------------------------------------- Data

    function getStepFraction() as Float {
        var info = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
        if (info == null || info.steps == null) { return 0.0; }
        var steps = info.steps;
        var goal = mStepGoalOverride;
        if (goal <= 0) {
            if (info.stepGoal != null && info.stepGoal > 0) {
                goal = info.stepGoal;
            } else {
                goal = 10000;
            }
        }
        if (goal <= 0) { return 0.0; }
        var f = steps.toFloat() / goal.toFloat();
        if (f > 1.0) { f = 1.0; }
        return f;
    }

    function getBodyBattery() as Number or Null {
        try {
            if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
                var iter = SensorHistory.getBodyBatteryHistory({
                    :period => 1,
                    :order => SensorHistory.ORDER_NEWEST_FIRST
                });
                if (iter != null) {
                    var sample = iter.next();
                    if (sample != null && sample.data != null) {
                        var v = sample.data.toNumber();
                        if (v < 0) { v = 0; }
                        if (v > 100) { v = 100; }
                        return v;
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return null;
    }

    // Current heart rate in BPM. The sensor reading is cached and refreshed at
    // most once every ~10 seconds to stay within the watch-face power budget.
    // Returns null when no recent reading is available.
    function getHeartRate() as Number or Null {
        var nowSec = Time.now().value();
        if (mCachedHr != null && (nowSec - mHrLastSec) < 10) {
            return mCachedHr;
        }
        mHrLastSec = nowSec;
        try {
            if (Toybox has :Activity) {
                var info = Activity.getActivityInfo();
                if (info != null && info.currentHeartRate != null) {
                    mCachedHr = info.currentHeartRate;
                    return mCachedHr;
                }
            }
            if ((Toybox has :ActivityMonitor) && (ActivityMonitor has :getHeartRateHistory)) {
                var it = ActivityMonitor.getHeartRateHistory(1, true);
                if (it != null) {
                    var s = it.next();
                    if (s != null && s.heartRate != null && s.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                        mCachedHr = s.heartRate;
                        return mCachedHr;
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return mCachedHr;
    }

    function getDeviceBattery() as Number {
        var stats = System.getSystemStats();
        return (stats.battery != null) ? stats.battery.toNumber() : 0;
    }

    function getSteps() as Number {
        var info = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
        return (info != null && info.steps != null) ? info.steps : 0;
    }

    function getCalories() as Number {
        var info = (mActInfo != null) ? mActInfo : ActivityMonitor.getInfo();
        return (info != null && info.calories != null) ? info.calories : 0;
    }

    // --------------------------------------------------------- Complications

    // Draw one configurable complication (icon + value) centered on cx.
    private function drawComplication(dc as Dc, cx as Number, y as Number, opt as Number) as Void {
        if (opt == COMP_OFF) { return; }

        var valStr = "--";
        var level = -1;
        var accent = 0xFFFFFF;

        if (opt == COMP_HR) {
            var hr = getHeartRate();
            valStr = (hr != null) ? hr.format("%d") : "--";
            accent = 0xFF6A2E;            // maple-orange heart
        } else if (opt == COMP_BODY) {
            var bb = getBodyBattery();
            valStr = (bb != null) ? bb.format("%d") + "%" : "--";
            accent = 0xFFC043;            // harvest-gold bolt
        } else if (opt == COMP_BATTERY) {
            var b = getDeviceBattery();
            valStr = b.format("%d") + "%";
            level = b;
            accent = 0xFFB23A;            // golden-amber battery
        } else if (opt == COMP_STEPS) {
            valStr = getSteps().format("%d");
            accent = 0xE0A828;            // wheat-gold boot
        } else if (opt == COMP_CALORIES) {
            valStr = getCalories().format("%d");
            accent = 0xD4622A;            // burnt-orange flame
        } else {
            return;
        }

        var textColor = mLowPower ? 0x6E6E6E : 0xFFFFFF;
        var iconColor = mLowPower ? 0x6E6E6E : accent;

        var textWidth = dc.getTextWidthInPixels(valStr, mFontLabel);
        var totalW = 16 + 6 + textWidth;
        var startX = cx - totalW / 2;

        drawComplicationIcon(dc, opt, startX + 8, y, iconColor, level);
        drawTextWithOutline(dc, startX + 22, y, mFontLabel, valStr,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER, textColor);
    }

    private function drawComplicationIcon(dc as Dc, kind as Number, x as Number, y as Number, color as Number, level as Number) as Void {
        if (kind == COMP_HR) {
            drawHeartIcon(dc, x, y, color);
        } else if (kind == COMP_BODY) {
            drawBoltIcon(dc, x, y, color);
        } else if (kind == COMP_BATTERY) {
            drawBatteryIcon(dc, x, y, color, level);
        } else if (kind == COMP_STEPS) {
            drawBootIcon(dc, x, y, color);
        } else if (kind == COMP_CALORIES) {
            drawFlameIcon(dc, x, y, color);
        }
    }

    // Body Battery -> lightning bolt (energy).
    private function drawBoltIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawBoltShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawBoltShape(dc, x - 1, y - 1);
        drawBoltShape(dc, x + 1, y - 1);
        drawBoltShape(dc, x - 1, y + 1);
        drawBoltShape(dc, x + 1, y + 1);
        drawBoltShape(dc, x - 1, y);
        drawBoltShape(dc, x + 1, y);
        drawBoltShape(dc, x,     y - 1);
        drawBoltShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawBoltShape(dc, x, y);
    }

    private function drawBoltShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillPolygon([
            [x + 2, y - 8], [x - 5, y + 1], [x - 1, y + 1],
            [x - 2, y + 8], [x + 5, y - 2], [x + 1, y - 2]
        ] as Array<Array>);
    }

    // Steps -> boot.
    private function drawBootIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawBootShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawBootShape(dc, x - 1, y - 1);
        drawBootShape(dc, x + 1, y - 1);
        drawBootShape(dc, x - 1, y + 1);
        drawBootShape(dc, x + 1, y + 1);
        drawBootShape(dc, x - 1, y);
        drawBootShape(dc, x + 1, y);
        drawBootShape(dc, x,     y - 1);
        drawBootShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawBootShape(dc, x, y);
    }

    private function drawBootShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillRoundedRectangle(x - 4, y - 7, 6, 10, 2);  // leg
        dc.fillRoundedRectangle(x - 4, y + 1, 11, 4, 2);  // foot
    }

    // Calories -> flame.
    private function drawFlameIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawFlameShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawFlameShape(dc, x - 1, y - 1);
        drawFlameShape(dc, x + 1, y - 1);
        drawFlameShape(dc, x - 1, y + 1);
        drawFlameShape(dc, x + 1, y + 1);
        drawFlameShape(dc, x - 1, y);
        drawFlameShape(dc, x + 1, y);
        drawFlameShape(dc, x,     y - 1);
        drawFlameShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawFlameShape(dc, x, y);
    }

    private function drawFlameShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillPolygon([
            [x, y - 8], [x + 5, y - 1], [x + 4, y + 4], [x - 4, y + 4], [x - 5, y - 1]
        ] as Array<Array>);
        dc.fillCircle(x, y + 2, 4);
    }

    // Battery icon: a horizontal cell with a terminal nub and a fill bar whose
    // width tracks the live charge level (0-100). A black halo behind it keeps
    // the outline legible against the moving backdrop, matching the heart icon.
    private function drawBatteryIcon(dc as Dc, x as Number, y as Number, color as Number, level as Number) as Void {
        var bw = 14;
        var bh = 9;
        var left = x - bw / 2;
        var top = y - bh / 2;

        var lvl = level;
        if (lvl < 0) { lvl = 0; }
        if (lvl > 100) { lvl = 100; }

        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawRoundedRectangle(left, top, bw, bh, 2);
            dc.fillRectangle(left + bw, y - 2, 2, 4);
            return;
        }

        // Black halo backing (shell + nub) for legibility.
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(left - 1, top - 1, bw + 2, bh + 2, 3);
        dc.fillRectangle(left + bw, y - 3, 4, 6);

        // Battery shell + terminal nub.
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(left, top, bw, bh, 2);
        dc.fillRectangle(left + bw, y - 2, 2, 4);

        // Inner fill bar proportional to the charge level.
        var innerMax = bw - 4;
        var fillW = (innerMax * lvl / 100).toNumber();
        if (fillW > 0) {
            dc.fillRectangle(left + 2, top + 2, fillW, bh - 4);
        }
    }

    // ------------------------------------------------------------ Critters

    // Decide which little woodland visitor (if any) is crossing right now.
    // Returns [type, dir, frac, seed] or null. At most one critter is ever active,
    // and quiet periods leave the scene empty so it stays calm ("once in a while").
    private function computeCritter(hour as Number, min as Number, sec as Number, isNight as Boolean) as Array or Null {
        var PERIOD = 38.0;  // a visitor may appear once per this many seconds
        var CROSS  = 8.0;   // how long the crossing animation lasts

        var tDay = (hour * 3600 + min * 60 + sec).toFloat();
        var period = (tDay / PERIOD).toNumber();
        var local = tDay - period * PERIOD;

        // ~1 in 5 windows is a quiet stretch with no visitor at all.
        if (period % 5 == 0) { return null; }
        if (local >= CROSS) { return null; }

        var frac = local / CROSS;          // 0..1 progress across the screen
        var dir = ((period * 31 + 7) % 2 == 0) ? 1 : -1;
        var sel = (period * 17 + 5) % 4;

        var type;
        if (isNight) {
            // night pool: hedgehog + fox forage, owl + bat take to the air.
            // No squirrels or geese at night.
            var nightPool = [CR_HEDGEHOG, CR_OWL, CR_FOX, CR_BAT] as Array<Number>;
            type = nightPool[sel];
        } else {
            // day pool: squirrel, a skein of geese, fox, hedgehog.
            var dayPool = [CR_SQUIRREL, CR_GEESE, CR_FOX, CR_HEDGEHOG] as Array<Number>;
            type = dayPool[sel];
        }

        // When a seasonal-holiday mode is on, hand a slice of the crossings to a
        // themed visitor (about 1 in 3) instead of the usual woodland one.
        if (mShowHalloween || mShowThanksgiving) {
            if (((period * 13 + 3) % 3) == 0) {
                var pick = period * 7 + 2;
                if (mShowHalloween && mShowThanksgiving) {
                    type = (pick % 2 == 0) ? halloweenCritter(pick) : CR_TURKEY;
                } else if (mShowHalloween) {
                    type = halloweenCritter(pick);
                } else {
                    type = CR_TURKEY;
                }
            }
        }
        return [type, dir, frac, period] as Array;
    }

    // Alternate the two Halloween visitors deterministically.
    private function halloweenCritter(pick as Number) as Number {
        return ((pick / 2) % 2 == 0) ? CR_BLACKCAT : CR_GHOST;
    }

    // Sky critters fly across overhead (drawn behind the grove); the others walk
    // along the ground (drawn in front of the forest floor).
    private function isSkyCritter(type as Number) as Boolean {
        return type == CR_GEESE || type == CR_OWL || type == CR_BAT || type == CR_GHOST;
    }

    // Draw the active critter, positioning it for its type.
    private function drawCritter(dc as Dc, crit as Array) as Void {
        var w = mWidth;
        var h = mHeight;
        var type = crit[0] as Number;
        var dir = crit[1] as Number;
        var frac = crit[2] as Float;

        var margin = (w * 0.18).toNumber();
        var span = w + 2 * margin;
        var x;
        if (dir == 1) {
            x = (-margin + frac * span).toNumber();
        } else {
            x = (w + margin - frac * span).toNumber();
        }

        if (type == CR_SQUIRREL) {
            var groundY = (h * 0.92).toNumber();
            drawSquirrel(dc, x, groundY, dir, frac, (w * 0.038).toNumber());
        } else if (type == CR_FOX) {
            var groundY = (h * 0.915).toNumber();
            drawFox(dc, x, groundY, dir, frac, (w * 0.045).toNumber());
        } else if (type == CR_HEDGEHOG) {
            var groundY = (h * 0.93).toNumber();
            drawHedgehog(dc, x, groundY, dir, frac, (w * 0.04).toNumber());
        } else if (type == CR_GEESE) {
            var skyY = (h * 0.17).toNumber();
            drawGeese(dc, x, skyY, dir, frac, (w * 0.035).toNumber());
        } else if (type == CR_OWL) {
            var skyY = (h * 0.23 + (h * 0.02) * Math.sin(frac * Math.PI * 2.0)).toNumber();
            drawOwl(dc, x, skyY, dir, frac, (w * 0.05).toNumber());
        } else if (type == CR_BAT) {
            var skyY = (h * 0.22 + (h * 0.03) * Math.sin(frac * Math.PI * 4.0)).toNumber();
            drawBat(dc, x, skyY, dir, frac, (w * 0.04).toNumber());
        } else if (type == CR_BLACKCAT) {
            var groundY = (h * 0.92).toNumber();
            drawBlackCat(dc, x, groundY, dir, frac, (w * 0.045).toNumber());
        } else if (type == CR_GHOST) {
            var skyY = (h * 0.24 + (h * 0.04) * Math.sin(frac * Math.PI * 3.0)).toNumber();
            drawGhost(dc, x, skyY, dir, frac, (w * 0.05).toNumber());
        } else if (type == CR_TURKEY) {
            var groundY = (h * 0.92).toNumber();
            drawTurkey(dc, x, groundY, dir, frac, (w * 0.05).toNumber());
        }
    }

    // ---- Squirrel (bounds across the forest floor, bushy tail curled up) ----
    private function drawSquirrel(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 8) { s = 8; }
        // A bounding gait: the body rises and dips as it scampers.
        var hop = (Math.sin(frac * Math.PI * 12.0)).abs();
        var yy = (y - hop * s * 0.45).toNumber();
        var legPhase = frac * Math.PI * 18.0;
        // black outline (4 diagonal offsets), then russet body
        squirrelSil(dc, x - 1, yy - 1, dir, s, legPhase, 0x000000);
        squirrelSil(dc, x + 1, yy - 1, dir, s, legPhase, 0x000000);
        squirrelSil(dc, x - 1, yy + 1, dir, s, legPhase, 0x000000);
        squirrelSil(dc, x + 1, yy + 1, dir, s, legPhase, 0x000000);
        squirrelSil(dc, x, yy, dir, s, legPhase, 0xB5651D);
        // pale belly + cheek
        dc.setColor(0xE8C49A, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x + dir * s * 0.55).toNumber(), (yy + s * 0.15).toNumber(), (s * 0.28).toNumber());
        // eye
        dc.setColor(0x140A04, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x + dir * s * 0.95).toNumber(), (yy - s * 0.4).toNumber(), 2);
    }

    private function squirrelSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, legPhase as Float, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        // hindquarters + front body
        dc.fillCircle((x - dir * s * 0.2).toNumber(), y, (s * 0.55).toNumber());
        dc.fillCircle((x + dir * s * 0.45).toNumber(), (y - s * 0.1).toNumber(), (s * 0.45).toNumber());
        // little scampering legs
        dc.setPenWidth(2);
        var wob = (Math.sin(legPhase) * s * 0.2);
        dc.drawLine((x - dir * s * 0.2).toNumber(), (y + s * 0.4).toNumber(), (x - dir * s * 0.2 - wob).toNumber(), (y + s * 0.85).toNumber());
        dc.drawLine((x + dir * s * 0.4).toNumber(), (y + s * 0.4).toNumber(), (x + dir * s * 0.4 + wob).toNumber(), (y + s * 0.85).toNumber());
        dc.setPenWidth(1);
        // head + pointed ear
        var hx = (x + dir * s * 0.9).toNumber();
        var hy = (y - s * 0.35).toNumber();
        dc.fillCircle(hx, hy, (s * 0.3).toNumber());
        dc.fillPolygon([
            [(hx - dir * s * 0.05).toNumber(), (hy - s * 0.2).toNumber()],
            [(hx + dir * s * 0.1).toNumber(), (hy - s * 0.6).toNumber()],
            [(hx + dir * s * 0.25).toNumber(), (hy - s * 0.15).toNumber()]
        ] as Array<Array>);
        // bushy tail, curling up and over the back (behind the travel dir)
        var tx = (x - dir * s * 0.7).toNumber();
        dc.fillCircle(tx, (y - s * 0.1).toNumber(), (s * 0.35).toNumber());
        dc.fillCircle((tx - dir * s * 0.2).toNumber(), (y - s * 0.6).toNumber(), (s * 0.42).toNumber());
        dc.fillCircle((tx + dir * s * 0.05).toNumber(), (y - s * 1.05).toNumber(), (s * 0.4).toNumber());
        dc.fillCircle((tx + dir * s * 0.5).toNumber(), (y - s * 1.2).toNumber(), (s * 0.3).toNumber());
    }

    // ---- Fox (trots across the forest floor, white-tipped brush) ----
    private function drawFox(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 9) { s = 9; }
        var bob = (Math.sin(frac * Math.PI * 8.0) * s * 0.08).toNumber();
        var yy = y - bob;
        var legPhase = frac * Math.PI * 14.0;
        foxSil(dc, x - 1, yy - 1, dir, s, legPhase, 0x000000);
        foxSil(dc, x + 1, yy - 1, dir, s, legPhase, 0x000000);
        foxSil(dc, x - 1, yy + 1, dir, s, legPhase, 0x000000);
        foxSil(dc, x + 1, yy + 1, dir, s, legPhase, 0x000000);
        foxSil(dc, x, yy, dir, s, legPhase, 0xD2691E);
        // white-tipped brush
        var tx = (x - dir * s * 1.05).toNumber();
        dc.setColor(0xF5E6D0, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((tx - dir * s * 0.95).toNumber(), (yy - s * 0.55).toNumber(), (s * 0.3).toNumber());
        // white cheek/chest
        dc.fillCircle((x + dir * s * 1.15).toNumber(), (yy + s * 0.05).toNumber(), (s * 0.2).toNumber());
        // dark socks
        dc.setColor(0x2A1A0E, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var step = (Math.sin(legPhase) * s * 0.25);
        dc.drawLine((x - dir * s * 0.5).toNumber(), (yy + s * 0.45).toNumber(), (x - dir * s * 0.5 - step).toNumber(), (yy + s * 0.95).toNumber());
        dc.drawLine((x + dir * s * 0.6).toNumber(), (yy + s * 0.45).toNumber(), (x + dir * s * 0.6 + step).toNumber(), (yy + s * 0.95).toNumber());
        dc.setPenWidth(1);
        // eye + nose
        var hx = (x + dir * s * 1.25).toNumber();
        var hy = (yy - s * 0.3).toNumber();
        dc.setColor(0x140A04, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((hx + dir * s * 0.1).toNumber(), hy, 2);
        dc.fillCircle((hx + dir * s * 0.9).toNumber(), (hy + s * 0.15).toNumber(), 2);
    }

    private function foxSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, legPhase as Float, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        // long body
        dc.fillRoundedRectangle((x - s * 1.0).toNumber(), (y - s * 0.35).toNumber(), (s * 2.0).toNumber(), (s * 0.7).toNumber(), (s * 0.35).toNumber());
        dc.fillCircle((x + dir * s * 0.9).toNumber(), y, (s * 0.4).toNumber());
        // legs (front + back pair, trotting)
        dc.setPenWidth(2);
        var step = (Math.sin(legPhase) * s * 0.25);
        dc.drawLine((x - dir * s * 0.5).toNumber(), (y + s * 0.2).toNumber(), (x - dir * s * 0.5 - step).toNumber(), (y + s * 0.95).toNumber());
        dc.drawLine((x + dir * s * 0.6).toNumber(), (y + s * 0.2).toNumber(), (x + dir * s * 0.6 + step).toNumber(), (y + s * 0.95).toNumber());
        dc.setPenWidth(1);
        // head
        var hx = (x + dir * s * 1.25).toNumber();
        var hy = (y - s * 0.3).toNumber();
        dc.fillCircle(hx, hy, (s * 0.42).toNumber());
        // pointed snout
        dc.fillPolygon([
            [(hx + dir * s * 0.2).toNumber(), (hy - s * 0.1).toNumber()],
            [(hx + dir * s * 1.0).toNumber(), (hy + s * 0.1).toNumber()],
            [(hx + dir * s * 0.2).toNumber(), (hy + s * 0.28).toNumber()]
        ] as Array<Array>);
        // two upright ears
        dc.fillPolygon([
            [(hx - dir * s * 0.1).toNumber(), (hy - s * 0.25).toNumber()],
            [(hx - dir * s * 0.05).toNumber(), (hy - s * 0.95).toNumber()],
            [(hx + dir * s * 0.3).toNumber(), (hy - s * 0.3).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [(hx + dir * s * 0.25).toNumber(), (hy - s * 0.3).toNumber()],
            [(hx + dir * s * 0.55).toNumber(), (hy - s * 0.9).toNumber()],
            [(hx + dir * s * 0.6).toNumber(), (hy - s * 0.2).toNumber()]
        ] as Array<Array>);
        // sweeping brush tail
        var tx = (x - dir * s * 1.0).toNumber();
        dc.fillPolygon([
            [tx, (y - s * 0.3).toNumber()],
            [(tx - dir * s * 1.2).toNumber(), (y - s * 0.85).toNumber()],
            [(tx - dir * s * 1.1).toNumber(), (y + s * 0.2).toNumber()],
            [tx, (y + s * 0.3).toNumber()]
        ] as Array<Array>);
    }

    // ---- Hedgehog (trundles along, spiny back, little snout) ----
    private function drawHedgehog(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 8) { s = 8; }
        var legPhase = frac * Math.PI * 16.0;
        hedgehogSil(dc, x - 1, y - 1, dir, s, legPhase, 0x000000);
        hedgehogSil(dc, x + 1, y - 1, dir, s, legPhase, 0x000000);
        hedgehogSil(dc, x - 1, y + 1, dir, s, legPhase, 0x000000);
        hedgehogSil(dc, x + 1, y + 1, dir, s, legPhase, 0x000000);
        hedgehogSil(dc, x, y, dir, s, legPhase, 0x6E4A2E);
        // pale snout/face
        dc.setColor(0xC8A878, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x + dir * s * 0.85).toNumber(), (y + s * 0.12).toNumber(), (s * 0.28).toNumber());
        // nose + eye
        dc.setColor(0x140A04, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x + dir * s * 1.15).toNumber(), (y + s * 0.18).toNumber(), 2);
        dc.fillCircle((x + dir * s * 0.8).toNumber(), (y - s * 0.05).toNumber(), 2);
    }

    private function hedgehogSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, legPhase as Float, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        // domed spiny body
        dc.fillRoundedRectangle((x - s * 0.95).toNumber(), (y - s * 0.4).toNumber(), (s * 1.9).toNumber(), (s * 0.85).toNumber(), (s * 0.42).toNumber());
        dc.fillCircle(x, (y - s * 0.15).toNumber(), (s * 0.75).toNumber());
        // spines radiating up and back
        dc.setPenWidth(2);
        for (var i = 0; i < 7; i++) {
            var a = Math.PI * (0.95 + i * 0.13);   // upper-rear arc
            var bx = (x + (s * 0.7) * Math.cos(a)).toNumber();
            var by = (y - s * 0.15 + (s * 0.7) * Math.sin(a)).toNumber();
            var tx2 = (x + (s * 1.15) * Math.cos(a)).toNumber();
            var ty2 = (y - s * 0.15 + (s * 1.15) * Math.sin(a)).toNumber();
            // bias spines toward the rear (away from travel dir)
            dc.drawLine(bx - dir * 1, by, tx2 - dir * 3, ty2);
        }
        dc.setPenWidth(1);
        // pointed face
        var hx = (x + dir * s * 0.85).toNumber();
        var hy = (y + s * 0.12).toNumber();
        dc.fillCircle(hx, hy, (s * 0.32).toNumber());
        dc.fillPolygon([
            [hx, (hy - s * 0.2).toNumber()],
            [(hx + dir * s * 0.5).toNumber(), (hy + s * 0.1).toNumber()],
            [hx, (hy + s * 0.3).toNumber()]
        ] as Array<Array>);
        // little feet
        dc.setPenWidth(2);
        var step = (Math.sin(legPhase) * s * 0.12);
        dc.drawLine((x - dir * s * 0.4).toNumber(), (y + s * 0.4).toNumber(), (x - dir * s * 0.4 - step).toNumber(), (y + s * 0.62).toNumber());
        dc.drawLine((x + dir * s * 0.3).toNumber(), (y + s * 0.4).toNumber(), (x + dir * s * 0.3 + step).toNumber(), (y + s * 0.62).toNumber());
        dc.setPenWidth(1);
    }

    // ---- Geese (a small migrating V crosses the sky) ----
    private function drawGeese(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 6) { s = 6; }
        var flap = Math.sin(frac * Math.PI * 10.0) * 0.35;
        // lead bird at the apex (front), four more trailing in two arms.
        birdChevron(dc, x, y, flap, s);
        for (var i = 1; i <= 2; i++) {
            var bx = (x - dir * i * s * 0.95).toNumber();
            birdChevron(dc, bx, (y - i * s * 0.5).toNumber(), flap, s);
            birdChevron(dc, bx, (y + i * s * 0.5).toNumber(), flap, s);
        }
    }

    private function birdChevron(dc as Dc, x as Number, y as Number, flap as Float, s as Number) as Void {
        dc.setColor(0x2A2418, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var wingY = (y - s * (0.3 + flap)).toNumber();
        dc.drawLine((x - s).toNumber(), wingY, x, y);
        dc.drawLine(x, y, (x + s).toNumber(), wingY);
        dc.setPenWidth(1);
    }

    // ---- Owl (glides silently across the night sky, wings spread) ----
    private function drawOwl(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 9) { s = 9; }
        var flap = Math.sin(frac * Math.PI * 8.0);
        owlSil(dc, x - 1, y - 1, dir, s, flap, 0x000000);
        owlSil(dc, x + 1, y - 1, dir, s, flap, 0x000000);
        owlSil(dc, x - 1, y + 1, dir, s, flap, 0x000000);
        owlSil(dc, x + 1, y + 1, dir, s, flap, 0x000000);
        owlSil(dc, x, y, dir, s, flap, 0x7A5230);
        // pale facial disc
        dc.setColor(0xC8A878, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x - s * 0.22).toNumber(), (y - s * 0.5).toNumber(), (s * 0.24).toNumber());
        dc.fillCircle((x + s * 0.22).toNumber(), (y - s * 0.5).toNumber(), (s * 0.24).toNumber());
        // big eyes + beak
        dc.setColor(0xFFD24A, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x - s * 0.22).toNumber(), (y - s * 0.5).toNumber(), (s * 0.16).toNumber());
        dc.fillCircle((x + s * 0.22).toNumber(), (y - s * 0.5).toNumber(), (s * 0.16).toNumber());
        dc.setColor(0x140A04, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x - s * 0.22).toNumber(), (y - s * 0.5).toNumber(), 2);
        dc.fillCircle((x + s * 0.22).toNumber(), (y - s * 0.5).toNumber(), 2);
        dc.setColor(0xE0902A, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [(x - 2).toNumber(), (y - s * 0.32).toNumber()],
            [(x + 2).toNumber(), (y - s * 0.32).toNumber()],
            [x, (y - s * 0.12).toNumber()]
        ] as Array<Array>);
    }

    private function owlSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, flap as Float, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        // rounded body + head
        dc.fillRoundedRectangle((x - s * 0.5).toNumber(), (y - s * 0.7).toNumber(), s, (s * 1.3).toNumber(), (s * 0.45).toNumber());
        // ear tufts
        dc.fillPolygon([
            [(x - s * 0.45).toNumber(), (y - s * 0.6).toNumber()],
            [(x - s * 0.3).toNumber(), (y - s * 1.0).toNumber()],
            [(x - s * 0.15).toNumber(), (y - s * 0.6).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [(x + s * 0.15).toNumber(), (y - s * 0.6).toNumber()],
            [(x + s * 0.3).toNumber(), (y - s * 1.0).toNumber()],
            [(x + s * 0.45).toNumber(), (y - s * 0.6).toNumber()]
        ] as Array<Array>);
        // wings spread to each side, flapping
        var tipY = (y - flap * s * 0.5).toNumber();
        dc.fillPolygon([
            [(x - s * 0.4).toNumber(), (y - s * 0.2).toNumber()],
            [(x - s * 1.7).toNumber(), tipY],
            [(x - s * 0.4).toNumber(), (y + s * 0.4).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [(x + s * 0.4).toNumber(), (y - s * 0.2).toNumber()],
            [(x + s * 1.7).toNumber(), tipY],
            [(x + s * 0.4).toNumber(), (y + s * 0.4).toNumber()]
        ] as Array<Array>);
    }

    // ---- Bat (flutters across the night sky on scalloped wings) ----
    private function drawBat(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 7) { s = 7; }
        var flap = Math.sin(frac * Math.PI * 16.0);
        var tipY = (y - flap * s * 0.6).toNumber();
        // a faint black outline pass, then the dusky body
        batSil(dc, x, y, tipY, s, 0x000000, 1);
        batSil(dc, x, y, tipY, s, 0x2A2233, 0);
        // tiny eyes
        dc.setColor(0xC83A3A, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x - s * 0.12).toNumber(), (y - s * 0.05).toNumber(), 1);
        dc.fillCircle((x + s * 0.12).toNumber(), (y - s * 0.05).toNumber(), 1);
    }

    private function batSil(dc as Dc, x as Number, y as Number, tipY as Number, s as Number, c as Number, grow as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        var g = grow;
        // body
        dc.fillCircle(x, y, (s * 0.3).toNumber() + g);
        // two ears
        dc.fillPolygon([
            [(x - s * 0.25).toNumber(), (y - s * 0.2).toNumber()],
            [(x - s * 0.1).toNumber(), (y - s * 0.6).toNumber()],
            [(x + 0).toNumber(), (y - s * 0.2).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [(x + 0).toNumber(), (y - s * 0.2).toNumber()],
            [(x + s * 0.1).toNumber(), (y - s * 0.6).toNumber()],
            [(x + s * 0.25).toNumber(), (y - s * 0.2).toNumber()]
        ] as Array<Array>);
        // left wing (scalloped lower edge via two triangles)
        dc.fillPolygon([
            [x, y],
            [(x - s * 1.0).toNumber(), tipY],
            [(x - s * 1.6).toNumber(), (y + s * 0.1).toNumber()],
            [(x - s * 0.8).toNumber(), (y + s * 0.3).toNumber()],
            [(x - s * 0.3).toNumber(), (y + s * 0.1).toNumber()]
        ] as Array<Array>);
        // right wing
        dc.fillPolygon([
            [x, y],
            [(x + s * 1.0).toNumber(), tipY],
            [(x + s * 1.6).toNumber(), (y + s * 0.1).toNumber()],
            [(x + s * 0.8).toNumber(), (y + s * 0.3).toNumber()],
            [(x + s * 0.3).toNumber(), (y + s * 0.1).toNumber()]
        ] as Array<Array>);
    }

    // ---- Black cat (Halloween: arched back, curled tail, glowing eyes) ----
    private function drawBlackCat(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 8) { s = 8; }
        var legPhase = frac * Math.PI * 12.0;
        // a faint midnight-violet rim, then the black body
        catSil(dc, x, y, dir, s, legPhase, 0x2A2233, 1);
        catSil(dc, x, y, dir, s, legPhase, 0x000000, 0);
        // glowing eyes
        dc.setColor(0xBFE04A, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x + dir * s * 0.95).toNumber(), (y - s * 0.55).toNumber(), 2);
        dc.fillCircle((x + dir * s * 1.15).toNumber(), (y - s * 0.55).toNumber(), 2);
    }

    private function catSil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, legPhase as Float, c as Number, grow as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        var g = grow;
        // rear haunch + front shoulder
        dc.fillCircle((x - dir * s * 0.7).toNumber(), y, (s * 0.5).toNumber() + g);
        dc.fillCircle((x + dir * s * 0.65).toNumber(), y, (s * 0.45).toNumber() + g);
        // arched back joining them
        dc.fillPolygon([
            [(x - dir * s * 0.7).toNumber(), (y - s * 0.5 - g).toNumber()],
            [x, (y - s * 1.0 - g).toNumber()],
            [(x + dir * s * 0.65).toNumber(), (y - s * 0.45 - g).toNumber()],
            [(x + dir * s * 0.65).toNumber(), (y + s * 0.1).toNumber()],
            [(x - dir * s * 0.7).toNumber(), (y + s * 0.1).toNumber()]
        ] as Array<Array>);
        // legs (front + back, stepping)
        dc.setPenWidth(2 + g);
        var step = (Math.sin(legPhase) * s * 0.2);
        dc.drawLine((x - dir * s * 0.7).toNumber(), (y + s * 0.3).toNumber(), (x - dir * s * 0.7 - step).toNumber(), (y + s * 0.85).toNumber());
        dc.drawLine((x + dir * s * 0.6).toNumber(), (y + s * 0.3).toNumber(), (x + dir * s * 0.6 + step).toNumber(), (y + s * 0.85).toNumber());
        dc.setPenWidth(1);
        // head + ears
        var hx = (x + dir * s * 1.05).toNumber();
        var hy = (y - s * 0.45).toNumber();
        dc.fillCircle(hx, hy, (s * 0.34).toNumber() + g);
        dc.fillPolygon([
            [(hx - dir * s * 0.05).toNumber(), (hy - s * 0.2).toNumber()],
            [(hx + dir * s * 0.05).toNumber(), (hy - s * 0.65).toNumber()],
            [(hx + dir * s * 0.3).toNumber(), (hy - s * 0.25).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [(hx + dir * s * 0.25).toNumber(), (hy - s * 0.25).toNumber()],
            [(hx + dir * s * 0.45).toNumber(), (hy - s * 0.6).toNumber()],
            [(hx + dir * s * 0.5).toNumber(), (hy - s * 0.15).toNumber()]
        ] as Array<Array>);
        // tail curling up behind
        var tx = (x - dir * s * 1.0).toNumber();
        dc.setPenWidth(4 + g);
        dc.drawLine(tx, (y - s * 0.1).toNumber(), (tx - dir * s * 0.3).toNumber(), (y - s * 0.8).toNumber());
        dc.drawLine((tx - dir * s * 0.3).toNumber(), (y - s * 0.8).toNumber(), (tx + dir * s * 0.15).toNumber(), (y - s * 1.25).toNumber());
        dc.setPenWidth(1);
    }

    // ---- Ghost (Halloween: a floaty sheet ghost with a wavy hem) ----
    private function drawGhost(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 9) { s = 9; }
        ghostSil(dc, x, y, s, 0x3A3A4A, 1);
        ghostSil(dc, x, y, s, 0xF0F0F8, 0);
        // hollow eyes + an "oooo" mouth
        dc.setColor(0x2A2A38, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x - s * 0.28).toNumber(), (y - s * 0.15).toNumber(), (s * 0.14).toNumber());
        dc.fillCircle((x + s * 0.28).toNumber(), (y - s * 0.15).toNumber(), (s * 0.14).toNumber());
        dc.fillCircle(x, (y + s * 0.3).toNumber(), (s * 0.12).toNumber());
    }

    private function ghostSil(dc as Dc, x as Number, y as Number, s as Number, c as Number, grow as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        var g = grow;
        // rounded head + body
        dc.fillCircle(x, (y - s * 0.2).toNumber(), (s * 0.7).toNumber() + g);
        dc.fillRectangle((x - s * 0.7 - g).toNumber(), (y - s * 0.2).toNumber(), (s * 1.4 + 2 * g).toNumber(), (s * 0.85).toNumber());
        // three scalloped tails along the hem
        dc.fillCircle((x - s * 0.46).toNumber(), (y + s * 0.65).toNumber(), (s * 0.26).toNumber() + g);
        dc.fillCircle(x, (y + s * 0.7).toNumber(), (s * 0.26).toNumber() + g);
        dc.fillCircle((x + s * 0.46).toNumber(), (y + s * 0.65).toNumber(), (s * 0.26).toNumber() + g);
    }

    // ---- Turkey (Thanksgiving: fanned tail, red wattle, struts) ----
    private function drawTurkey(dc as Dc, x as Number, y as Number, dir as Number, frac as Float, s as Number) as Void {
        if (s < 9) { s = 9; }
        var legPhase = frac * Math.PI * 10.0;

        // Tail fan behind (away from travel dir): concentric colored feathers.
        var fanX = (x - dir * s * 0.7).toNumber();
        var fanY = (y - s * 0.3).toNumber();
        var feather = [0x7A3F1E, 0xB23A1E, 0xD4622A, 0xE0A828, 0xD4622A, 0xB23A1E, 0x7A3F1E] as Array<Number>;
        for (var i = 0; i < 7; i++) {
            var a = Math.PI * (0.62 + i * 0.085);  // spread up-and-back
            var fx = (fanX - dir * (s * 1.45) * Math.cos(a)).toNumber();
            var fy = (fanY - (s * 1.45) * Math.sin(a)).toNumber();
            // black outline, then the feather color
            dc.setColor(0x1A0E06, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(fx, fy, (s * 0.3).toNumber() + 1);
            dc.setColor(feather[i], Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(fx, fy, (s * 0.26).toNumber());
        }

        // black outline pass + body
        turkeySil(dc, x, y, dir, s, legPhase, 0x000000, 1);
        turkeySil(dc, x, y, dir, s, legPhase, 0x5A3015, 0);
        // pale breast
        dc.setColor(0x8A5A2E, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((x + dir * s * 0.55).toNumber(), (y + s * 0.1).toNumber(), (s * 0.3).toNumber());
        // red wattle + yellow beak + eye on the head
        var hx = (x + dir * s * 1.05).toNumber();
        var hy = (y - s * 0.55).toNumber();
        dc.setColor(0xC8281E, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((hx + dir * s * 0.1).toNumber(), (hy + s * 0.3).toNumber(), (s * 0.12).toNumber());
        dc.setColor(0xE0A828, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [(hx + dir * s * 0.2).toNumber(), (hy + s * 0.02).toNumber()],
            [(hx + dir * s * 0.6).toNumber(), (hy + s * 0.12).toNumber()],
            [(hx + dir * s * 0.2).toNumber(), (hy + s * 0.22).toNumber()]
        ] as Array<Array>);
        dc.setColor(0x140A04, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle((hx + dir * s * 0.05).toNumber(), hy, 2);
    }

    private function turkeySil(dc as Dc, x as Number, y as Number, dir as Number, s as Number, legPhase as Float, c as Number, grow as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        var g = grow;
        // plump body
        dc.fillCircle(x, y, (s * 0.7).toNumber() + g);
        dc.fillCircle((x + dir * s * 0.4).toNumber(), (y + s * 0.05).toNumber(), (s * 0.55).toNumber() + g);
        // legs (stepping)
        dc.setColor((g > 0) ? c : 0xE0A828, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2 + g);
        var step = (Math.sin(legPhase) * s * 0.18);
        dc.drawLine((x + dir * s * 0.1).toNumber(), (y + s * 0.55).toNumber(), (x + dir * s * 0.1 - step).toNumber(), (y + s * 1.0).toNumber());
        dc.drawLine((x + dir * s * 0.45).toNumber(), (y + s * 0.55).toNumber(), (x + dir * s * 0.45 + step).toNumber(), (y + s * 1.0).toNumber());
        dc.setPenWidth(1);
        // neck + head
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle((x + dir * s * 0.6).toNumber(), (y - s * 0.6).toNumber(), (s * 0.3).toNumber() + g, (s * 0.7).toNumber(), 3);
        dc.fillCircle((x + dir * s * 1.05).toNumber(), (y - s * 0.55).toNumber(), (s * 0.26).toNumber() + g);
    }

    // ----------------------------------------------------------- Decorations

    // Carved, glowing jack-o'-lantern resting on the leaf litter (Halloween).
    private function drawJackOLantern(dc as Dc, x as Number, y as Number, s as Number, secVal as Number) as Void {
        if (s < 10) { s = 10; }
        // warm glow that flickers gently with the seconds
        var flick = 0.85 + 0.15 * Math.sin(secVal.toFloat() * 0.9);
        dc.setColor(scaleColor(0xFF8A1E, 0.30 * flick), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, (s * 1.35).toNumber());

        // black silhouette (ribbed body, slightly oversized) for legibility
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, (s * 1.05).toNumber());
        dc.fillCircle((x - s * 0.55).toNumber(), y, (s * 0.85).toNumber());
        dc.fillCircle((x + s * 0.55).toNumber(), y, (s * 0.85).toNumber());

        // orange ribbed body
        dc.setColor(0xE0651E, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, s);
        dc.fillCircle((x - s * 0.55).toNumber(), y, (s * 0.8).toNumber());
        dc.fillCircle((x + s * 0.55).toNumber(), y, (s * 0.8).toNumber());
        // rib shading
        dc.setColor(0xB24A12, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine((x - s * 0.3).toNumber(), (y - s * 0.75).toNumber(), (x - s * 0.3).toNumber(), (y + s * 0.75).toNumber());
        dc.drawLine((x + s * 0.3).toNumber(), (y - s * 0.75).toNumber(), (x + s * 0.3).toNumber(), (y + s * 0.75).toNumber());
        dc.setPenWidth(1);

        // stem
        dc.setColor(0x3F5A1E, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle((x - s * 0.12).toNumber(), (y - s * 1.2).toNumber(), (s * 0.24).toNumber(), (s * 0.35).toNumber());

        // glowing carved face (lit from within)
        var lit = lerpColor(0xFFD24A, 0xFFF0A0, flick - 0.85);
        dc.setColor(lit, Graphics.COLOR_TRANSPARENT);
        // triangular eyes
        dc.fillPolygon([
            [(x - s * 0.55).toNumber(), (y - s * 0.15).toNumber()],
            [(x - s * 0.2).toNumber(), (y - s * 0.15).toNumber()],
            [(x - s * 0.37).toNumber(), (y + s * 0.15).toNumber()]
        ] as Array<Array>);
        dc.fillPolygon([
            [(x + s * 0.2).toNumber(), (y - s * 0.15).toNumber()],
            [(x + s * 0.55).toNumber(), (y - s * 0.15).toNumber()],
            [(x + s * 0.37).toNumber(), (y + s * 0.15).toNumber()]
        ] as Array<Array>);
        // small nose
        dc.fillPolygon([
            [x, (y + s * 0.05).toNumber()],
            [(x - s * 0.12).toNumber(), (y + s * 0.3).toNumber()],
            [(x + s * 0.12).toNumber(), (y + s * 0.3).toNumber()]
        ] as Array<Array>);
        // jagged grin
        dc.fillPolygon([
            [(x - s * 0.6).toNumber(), (y + s * 0.4).toNumber()],
            [(x - s * 0.35).toNumber(), (y + s * 0.55).toNumber()],
            [(x - s * 0.15).toNumber(), (y + s * 0.4).toNumber()],
            [x, (y + s * 0.58).toNumber()],
            [(x + s * 0.15).toNumber(), (y + s * 0.4).toNumber()],
            [(x + s * 0.35).toNumber(), (y + s * 0.55).toNumber()],
            [(x + s * 0.6).toNumber(), (y + s * 0.4).toNumber()],
            [(x + s * 0.4).toNumber(), (y + s * 0.72).toNumber()],
            [(x - s * 0.4).toNumber(), (y + s * 0.72).toNumber()]
        ] as Array<Array>);
    }

    // A little harvest patch of pumpkins + a gourd on the leaf litter (Thanksgiving).
    private function drawPumpkinPatch(dc as Dc, x as Number, y as Number, s as Number) as Void {
        if (s < 9) { s = 9; }
        // a smaller pumpkin behind, a green-gold gourd, then the main pumpkin
        drawPumpkin(dc, (x + s * 1.0).toNumber(), (y + s * 0.25).toNumber(), (s * 0.62).toNumber(), 0xD4622A);
        drawGourd(dc, (x - s * 1.05).toNumber(), (y + s * 0.35).toNumber(), (s * 0.55).toNumber());
        drawPumpkin(dc, x, y, s, 0xE0651E);
    }

    private function drawPumpkin(dc as Dc, x as Number, y as Number, s as Number, color as Number) as Void {
        // black outline
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, s + 1);
        dc.fillCircle((x - s * 0.5).toNumber(), y, (s * 0.78).toNumber() + 1);
        dc.fillCircle((x + s * 0.5).toNumber(), y, (s * 0.78).toNumber() + 1);
        // ribbed orange body
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, s);
        dc.fillCircle((x - s * 0.5).toNumber(), y, (s * 0.78).toNumber());
        dc.fillCircle((x + s * 0.5).toNumber(), y, (s * 0.78).toNumber());
        // rib shading
        dc.setColor(scaleColor(color, 0.7), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine((x - s * 0.28).toNumber(), (y - s * 0.7).toNumber(), (x - s * 0.28).toNumber(), (y + s * 0.7).toNumber());
        dc.drawLine((x + s * 0.28).toNumber(), (y - s * 0.7).toNumber(), (x + s * 0.28).toNumber(), (y + s * 0.7).toNumber());
        dc.setPenWidth(1);
        // stem
        dc.setColor(0x6E4A22, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle((x - s * 0.12).toNumber(), (y - s * 1.15).toNumber(), (s * 0.24).toNumber(), (s * 0.3).toNumber());
    }

    private function drawGourd(dc as Dc, x as Number, y as Number, s as Number) as Void {
        // outline
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, (y + s * 0.4).toNumber(), (s * 0.7).toNumber() + 1);
        dc.fillCircle(x, (y - s * 0.4).toNumber(), (s * 0.4).toNumber() + 1);
        // green-gold body: bulb + neck
        dc.setColor(0x9AA82A, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, (y + s * 0.4).toNumber(), (s * 0.7).toNumber());
        dc.setColor(0xE0A828, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, (y - s * 0.4).toNumber(), (s * 0.4).toNumber());
        // stem
        dc.setColor(0x6E4A22, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle((x - s * 0.1).toNumber(), (y - s * 0.95).toNumber(), (s * 0.2).toNumber(), (s * 0.3).toNumber());
    }

    // ----------------------------------------------------------- Sun times

    // Recompute today's local sunrise/sunset from the watch's last-known
    // location. Cached per day; keeps the fixed autumn fallback until a real
    // location fix is available, then stops recomputing for the day.
    private function updateSunTimes() as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var doy = dayOfYear(info.year, info.month, info.day);
        if (doy == mSunDay && mSunValid) { return; }
        if (doy != mSunDay) {
            mSunDay = doy;
            mSunrise = 6.5;
            mSunset = 18.5;
            mSunValid = false;
            mSunLastTry = -10000;  // new day: allow an immediate retry
        }

        // Not yet valid for today: a location fix (or a usable result) isn't
        // available. Throttle retries so we don't run the location lookup + the
        // heavy sunrise/sunset trig on every redraw while we wait.
        var nowSec = Time.now().value();
        if ((nowSec - mSunLastTry) < 60) { return; }
        mSunLastTry = nowSec;

        var loc = getLocationDeg();
        if (loc == null) { return; }
        var offset = System.getClockTime().timeZoneOffset.toFloat() / 3600.0;
        var sr = computeSunEvent(doy, loc[0], loc[1], offset, true);
        var ss = computeSunEvent(doy, loc[0], loc[1], offset, false);
        if (sr != null && ss != null && ss > sr) {
            mSunrise = sr;
            mSunset = ss;
            mSunValid = true;
        }
    }

    // Last-known location in degrees [lat, lon], or null. Prefers the activity
    // location, then the weather observation location - neither powers the GPS.
    private function getLocationDeg() as Array<Float> or Null {
        try {
            if (Toybox has :Activity) {
                var ai = Activity.getActivityInfo();
                if (ai != null && ai.currentLocation != null) {
                    var d = ai.currentLocation.toDegrees();
                    return [d[0].toFloat(), d[1].toFloat()];
                }
            }
        } catch (e) {
        }
        try {
            if (Toybox has :Weather) {
                var cc = Weather.getCurrentConditions();
                if (cc != null && cc.observationLocationPosition != null) {
                    var d = cc.observationLocationPosition.toDegrees();
                    return [d[0].toFloat(), d[1].toFloat()];
                }
            }
        } catch (e) {
        }
        return null;
    }

    // Standard sunrise/sunset algorithm (NOAA / Almanac). Returns local time in
    // hours (0-24) for the event, or null at extreme latitudes where the sun
    // does not rise/set on the given day.
    private function computeSunEvent(n as Number, lat as Float, lng as Float, offset as Float, sunrise as Boolean) as Float or Null {
        var ZENITH = 90.833;
        var D2R = Math.PI / 180.0;
        var R2D = 180.0 / Math.PI;

        var lngHour = lng / 15.0;
        var tt = sunrise ? (n + ((6.0 - lngHour) / 24.0)) : (n + ((18.0 - lngHour) / 24.0));

        var m = (0.9856 * tt) - 3.289;
        var l = m + (1.916 * Math.sin(m * D2R)) + (0.020 * Math.sin(2.0 * m * D2R)) + 282.634;
        l = normDeg(l);

        var ra = Math.atan(0.91764 * Math.tan(l * D2R)) * R2D;
        ra = normDeg(ra);
        var lQuad = (Math.floor(l / 90.0) * 90.0).toFloat();
        var raQuad = (Math.floor(ra / 90.0) * 90.0).toFloat();
        ra = ra + (lQuad - raQuad);
        ra = ra / 15.0;

        var sinDec = 0.39782 * Math.sin(l * D2R);
        var cosDec = Math.cos(Math.asin(sinDec));

        var cosH = (Math.cos(ZENITH * D2R) - (sinDec * Math.sin(lat * D2R))) / (cosDec * Math.cos(lat * D2R));
        if (cosH > 1.0 || cosH < -1.0) { return null; }

        var bigH = sunrise ? (360.0 - (Math.acos(cosH) * R2D)) : (Math.acos(cosH) * R2D);
        bigH = bigH / 15.0;

        var bigT = bigH + ra - (0.06571 * tt) - 6.622;
        var ut = normHour(bigT - lngHour);
        return normHour(ut + offset);
    }

    private function dayOfYear(year as Number, month as Number, day as Number) as Number {
        var cum = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334] as Array<Number>;
        var n = cum[month - 1] + day;
        if (month > 2 && isLeapYear(year)) { n += 1; }
        return n;
    }

    private function isLeapYear(y as Number) as Boolean {
        return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
    }

    // NOTE: these use bounded modulo arithmetic rather than `while` loops. A
    // non-finite input (NaN/Infinity) from the sun math would make a subtract-
    // in-a-loop spin forever and hang the watch face; modulo can never loop.
    private function normDeg(a as Float) as Float {
        if (!(a > -1.0e9 && a < 1.0e9)) { return 0.0; }  // guard NaN / Infinity
        var r = a - 360.0 * Math.floor(a / 360.0);
        if (r < 0.0) { r += 360.0; }
        if (r >= 360.0) { r -= 360.0; }
        return r;
    }

    private function normHour(a as Float) as Float {
        if (!(a > -1.0e9 && a < 1.0e9)) { return 0.0; }  // guard NaN / Infinity
        var r = a - 24.0 * Math.floor(a / 24.0);
        if (r < 0.0) { r += 24.0; }
        if (r >= 24.0) { r -= 24.0; }
        return r;
    }

    // ------------------------------------------------------------ Color helpers

    function chordHalf(r as Number, dy as Number) as Number {
        var d = r * r - dy * dy;
        if (d <= 0) { return 0; }
        return Math.sqrt(d).toNumber();
    }

    function lerpColor(c1 as Number, c2 as Number, t as Float) as Number {
        if (t < 0.0) { t = 0.0; }
        if (t > 1.0) { t = 1.0; }
        var r1 = (c1 >> 16) & 0xFF;
        var g1 = (c1 >> 8) & 0xFF;
        var b1 = c1 & 0xFF;
        var r2 = (c2 >> 16) & 0xFF;
        var g2 = (c2 >> 8) & 0xFF;
        var b2 = c2 & 0xFF;
        var r = (r1 + ((r2 - r1) * t)).toNumber();
        var g = (g1 + ((g2 - g1) * t)).toNumber();
        var b = (b1 + ((b2 - b1) * t)).toNumber();
        return (r << 16) | (g << 8) | b;
    }

    function scaleColor(c as Number, f as Float) as Number {
        return lerpColor(0x000000, c, f);
    }

    // Smoothly calculate autumn sky colors based on hour of day. The 9 keyframes
    // run midnight -> pre-dawn -> sunrise glow -> morning -> midday -> late
    // afternoon -> sunset glow -> twilight -> midnight. When the day is "normal"
    // the keyframe HOURS are anchored to the real sunrise/sunset so dawn and the
    // golden-hour sunset land at the true times; otherwise a fixed autumn schedule
    // is used. The warm autumn color palette itself is identical in both cases.
    private function getSkyColors(hour as Number, min as Number) as Array<Number> {
        var t = hour.toFloat() + min.toFloat() / 60.0;

        var sr = mSunrise;
        var ss = mSunset;
        var hours;

        // The keyframe colors are identical for both schedules; only the hour
        // anchors differ, so reuse the hoisted color tables and avoid rebuilding
        // three nine-element arrays on every frame.
        if (sr > 1.6 && ss < 22.4 && (ss - sr) > 4.0) {
            var mid = (sr + ss) / 2.0;
            hours = [0.0, sr - 1.5, sr, sr + 1.5, mid, ss - 1.5, ss, ss + 1.5, 24.0];
        } else {
            hours = SKY_HOURS_FALLBACK;
        }
        var topColors    = SKY_TOP;
        var bottomColors = SKY_BOTTOM;

        var idx = 0;
        for (var i = 0; i < hours.size() - 1; i++) {
            if (t >= hours[i] && t < hours[i+1]) {
                idx = i;
                break;
            }
        }

        var frac = (t - hours[idx]) / (hours[idx+1] - hours[idx]);
        var cTop = lerpColor(topColors[idx], topColors[idx+1], frac);
        var cBottom = lerpColor(bottomColors[idx], bottomColors[idx+1], frac);

        return [cTop, cBottom] as Array<Number>;
    }

    // Cached AMOLED sky gradient. Returns a buffered bitmap of the gradient, or
    // null if buffered bitmaps aren't available / couldn't be allocated (the
    // caller then renders the gradient directly). The expensive per-row fill loop
    // only runs when the colors or dimensions change (≈once per minute) or when
    // the graphics pool has reclaimed the previous buffer.
    private function getSkyBitmap(w as Number, skyH as Number, cTop as Number, cBottom as Number) as Graphics.BufferedBitmap or Null {
        if (!(Graphics has :createBufferedBitmap)) { return null; }

        var bmp = (mSkyBufRef != null) ? mSkyBufRef.get() : null;

        // Allocate the buffer ONCE (or only re-allocate if the graphics pool
        // reclaimed it, or the size changed). Recreating it every minute just
        // because the colors changed churns the pool and can exhaust it over
        // time, which silently drops us into the slow per-frame fallback below.
        if (bmp == null || w != mSkyKeyW || skyH != mSkyKeyH) {
            try {
                var ref = Graphics.createBufferedBitmap({ :width => w, :height => skyH });
                if (ref == null) { mSkyBufRef = null; return null; }
                mSkyBufRef = ref;
                bmp = ref.get();
                if (bmp == null) { return null; }
            } catch (e) {
                mSkyBufRef = null;
                return null;
            }
            mSkyKeyW = w;
            mSkyKeyH = skyH;
            mSkyKeyTop = cTop + 1;  // invalidate so the gradient repaints below
        }

        // Repaint into the EXISTING buffer only when the colors change (~once a
        // minute), reusing the same allocation instead of making a new one.
        if (cTop != mSkyKeyTop || cBottom != mSkyKeyBottom) {
            var bdc = bmp.getDc();
            var step = 4;
            for (var y = 0; y < skyH; y += step) {
                var frac = y.toFloat() / skyH.toFloat();
                var c = lerpColor(cTop, cBottom, frac);
                bdc.setColor(c, Graphics.COLOR_TRANSPARENT);
                bdc.fillRectangle(0, y, w, step);
            }
            mSkyKeyTop = cTop;
            mSkyKeyBottom = cBottom;
        }
        return bmp;
    }

    // ----------------------------------------------------------- Lifecycle

    function onHide() as Void {}

    function onExitSleep() as Void {
        mIsSleep = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        mIsSleep = true;
        mLastMin = -1;
        WatchUi.requestUpdate();
    }

    private function getWeatherString() as String or Null {
        try {
            if (Toybox has :Weather) {
                var conditions = Weather.getCurrentConditions();
                if (conditions != null && conditions.temperature != null) {
                    var temp = conditions.temperature;
                    var settings = (mSettings != null) ? mSettings : System.getDeviceSettings();
                    var isImperial = (settings has :temperatureUnits) && (settings.temperatureUnits != System.UNIT_METRIC);
                    if (isImperial) {
                        temp = (temp * 9.0 / 5.0 + 32.0).toNumber();
                        return temp.format("%d") + "°F";
                    } else {
                        return temp.format("%d") + "°C";
                    }
                }
            }
        } catch (e) {
            // fall through
        }
        return null;
    }

    private function drawTextWithOutline(dc as Dc, x as Number, y as Number, font as Graphics.FontType, text as String, justify as Number, textColor as Number) as Void {
        if (mLowPower) {
            dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, text, justify);
            return;
        }
        // Outline cost scales with adaptive quality. The long date line is the
        // single most expensive text, so shedding outline passes here is the
        // biggest per-frame win when the device is struggling:
        //   q>=3 -> full 8-neighbour outline; q==2 -> 4 diagonals;
        //   q==1 -> 2 diagonals;             q==0 -> no outline.
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        if (mQuality >= 2) {
            dc.drawText(x - 1, y - 1, font, text, justify);
            dc.drawText(x + 1, y - 1, font, text, justify);
            dc.drawText(x - 1, y + 1, font, text, justify);
            dc.drawText(x + 1, y + 1, font, text, justify);
            if (mQuality >= 3) {
                dc.drawText(x - 1, y,     font, text, justify);
                dc.drawText(x + 1, y,     font, text, justify);
                dc.drawText(x,     y - 1, font, text, justify);
                dc.drawText(x,     y + 1, font, text, justify);
            }
        } else if (mQuality == 1) {
            dc.drawText(x - 1, y - 1, font, text, justify);
            dc.drawText(x + 1, y + 1, font, text, justify);
        }
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, justify);
    }

    private function drawHeartIcon(dc as Dc, x as Number, y as Number, color as Number) as Void {
        if (mLowPower) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawHeartShape(dc, x, y);
            return;
        }
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        drawHeartShape(dc, x - 1, y - 1);
        drawHeartShape(dc, x + 1, y - 1);
        drawHeartShape(dc, x - 1, y + 1);
        drawHeartShape(dc, x + 1, y + 1);
        drawHeartShape(dc, x - 1, y);
        drawHeartShape(dc, x + 1, y);
        drawHeartShape(dc, x,     y - 1);
        drawHeartShape(dc, x,     y + 1);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        drawHeartShape(dc, x, y);
    }

    private function drawHeartShape(dc as Dc, x as Number, y as Number) as Void {
        dc.fillCircle(x - 4, y - 3, 4);
        dc.fillCircle(x + 4, y - 3, 4);
        dc.fillPolygon([[x - 8, y - 3], [x + 8, y - 3], [x, y + 7]] as Array<Array>);
    }

    // Low-power partial update, called up to once per second in sleep mode.
    //
    // This MUST stay cheap: onPartialUpdate runs under a strict execution-time /
    // power budget, and exceeding it repeatedly makes the system disable partial
    // updates (the face "freezes" in always-on). The old implementation called
    // the full onUpdate() here, clearing and re-rendering the ENTIRE screen,
    // which is exactly what the budget forbids.
    //
    // The always-on layer shows no seconds, so nothing changes sub-minute. We
    // therefore redraw only when the minute rolls over, clip to the central
    // time/date band, and clear + repaint just that region.
    //
    // This cheap clipped path is ONLY safe on AMOLED always-on (burn-in) mode.
    // On MIP devices the sleep frame is the full colour scene, so clipping +
    // clearing a band here would paint a black rectangle over it; in that case
    // we fall back to the original full redraw.
    function onPartialUpdate(dc as Dc) as Void {
        var clock = System.getClockTime();
        var min = clock.min;
        if (min == mLastMin) { return; }
        mLastMin = min;
        mClock = clock;

        var settings = System.getDeviceSettings();
        mSettings = settings;  // cache for drawTime / getWeatherString this frame
        var hasBurnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        var aod = hasBurnIn && mIsSleep;

        // Not AMOLED always-on (or no clip support): preserve the original
        // full-scene minute refresh.
        if (!aod || !(dc has :setClip)) {
            onUpdate(dc);
            return;
        }

        mLowPower = true;

        // Match the anti-burn-in pixel shift used by the full minute redraw.
        var shift = computeBurnInShift();
        var cx = mCenterX + shift[0];
        var cy = mCenterY + shift[1];

        // Clip to the central time/date band so the clear + redraw is bounded to
        // a small region instead of the whole display.
        var clipY = (mHeight * 0.30).toNumber();
        var clipH = (mHeight * 0.34).toNumber();
        if (dc has :setClip) { dc.setClip(0, clipY, mWidth, clipH); }

        dc.setColor(BG_COLOR, BG_COLOR);
        dc.clear();

        drawTime(dc, cx, cy - (mHeight * 0.05).toNumber());
        if (mShowDate) {
            drawDate(dc, cx, cy + (mHeight * 0.06).toNumber());
        }

        if (dc has :clearClip) { dc.clearClip(); }
    }
}
