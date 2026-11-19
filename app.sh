set -e
mkdir -p app/src/main/java/com/focus/lock app/src/main/res/xml app/src/main/res/values

cat > settings.gradle <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { google(); mavenCentral() } }
rootProject.name = 'focuslock'
include ':app'
EOF

cat > build.gradle <<'EOF'
plugins { id 'com.android.application' version '8.5.2' apply false }
EOF

cat > app/build.gradle <<'EOF'
plugins { id 'com.android.application' }
android {
  namespace 'com.focus.lock'
  compileSdk 34
  defaultConfig { applicationId 'com.focus.lock'; minSdk 26; targetSdk 34; versionCode 1; versionName '1.0' }
  compileOptions { sourceCompatibility JavaVersion.VERSION_17; targetCompatibility JavaVersion.VERSION_17 }
}
EOF

cat > app/src/main/AndroidManifest.xml <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:label="Focus Lock">
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
    <service android:name=".LockService" android:exported="true"
        android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
      <intent-filter><action android:name="android.accessibilityservice.AccessibilityService"/></intent-filter>
      <meta-data android:name="android.accessibilityservice" android:resource="@xml/accessibility_config"/>
    </service>
  </application>
</manifest>
EOF

cat > app/src/main/res/values/strings.xml <<'EOF'
<resources><string name="desc">Locks the phone to study apps only</string></resources>
EOF

cat > app/src/main/res/xml/accessibility_config.xml <<'EOF'
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
  android:accessibilityEventTypes="typeWindowStateChanged"
  android:accessibilityFeedbackType="feedbackGeneric"
  android:notificationTimeout="100"
  android:canRetrieveWindowContent="false"
  android:description="@string/desc" />
EOF

cat > app/src/main/java/com/focus/lock/Prefs.java <<'EOF'
package com.focus.lock;
import android.content.Context;
import android.content.SharedPreferences;
public class Prefs {
  // TEST VALUE: 2 minutes. Change to 2*60*60*1000L (2 hours) after testing.
  public static final long DELAY = 2 * 60 * 1000L;
  public static SharedPreferences sp(Context c) { return c.getSharedPreferences("f", 0); }
  public static boolean isLocked(Context c) {
    SharedPreferences s = sp(c);
    long d = s.getLong("disableAt", 0);
    if (d > 0 && System.currentTimeMillis() >= d) {
      s.edit().putBoolean("locked", false).putLong("disableAt", 0).apply();
    }
    return s.getBoolean("locked", false);
  }
  public static void lock(Context c) { sp(c).edit().putBoolean("locked", true).putLong("disableAt", 0).apply(); }
  public static void requestDisable(Context c) {
    if (sp(c).getLong("disableAt", 0) == 0)
      sp(c).edit().putLong("disableAt", System.currentTimeMillis() + DELAY).apply();
  }
  public static void cancelDisable(Context c) { sp(c).edit().putLong("disableAt", 0).apply(); }
}
EOF

cat > app/src/main/java/com/focus/lock/LockService.java <<'EOF'
package com.focus.lock;
import android.accessibilityservice.AccessibilityService;
import android.view.accessibility.AccessibilityEvent;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
public class LockService extends AccessibilityService {
  // Apps allowed while locked. Add study apps here.
  static final Set<String> ALLOWED = new HashSet<>(Arrays.asList(
    "com.focus.lock", "com.google.android.youtube",
    "com.sec.android.app.launcher", "com.android.systemui", "android",
    "com.samsung.android.honeyboard", "com.google.android.inputmethod.latin",
    "com.samsung.android.dialer", "com.google.android.dialer", "com.samsung.android.incallui",
    "com.samsung.android.app.notes", "com.sec.android.app.myfiles",
    "com.sec.android.app.popupcalculator", "com.sec.android.app.clockpackage"));
  @Override public void onAccessibilityEvent(AccessibilityEvent e) {
    if (e.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return;
    CharSequence p = e.getPackageName();
    if (p == null || !Prefs.isLocked(this)) return;
    if (!ALLOWED.contains(p.toString())) performGlobalAction(GLOBAL_ACTION_HOME);
  }
  @Override public void onInterrupt() {}
}
EOF

cat > app/src/main/java/com/focus/lock/MainActivity.java <<'EOF'
package com.focus.lock;
import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
public class MainActivity extends Activity {
  TextView st;
  Handler h = new Handler(Looper.getMainLooper());
  Runnable r = new Runnable() { public void run() { refresh(); h.postDelayed(this, 1000); } };
  void btn(LinearLayout root, String t, View.OnClickListener l) {
    Button x = new Button(this); x.setText(t); x.setOnClickListener(l); root.addView(x);
  }
  @Override protected void onCreate(Bundle s) {
    super.onCreate(s);
    LinearLayout l = new LinearLayout(this);
    l.setOrientation(LinearLayout.VERTICAL);
    l.setPadding(40, 100, 40, 40);
    st = new TextView(this); st.setTextSize(22); l.addView(st);
    btn(l, "1. Enable Accessibility (one time)", v -> startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)));
    btn(l, "2. Start Lock", v -> { Prefs.lock(this); refresh(); });
    btn(l, "Request disable (wait time)", v -> { Prefs.requestDisable(this); refresh(); });
    btn(l, "Cancel disable request", v -> { Prefs.cancelDisable(this); refresh(); });
    setContentView(l);
  }
  @Override protected void onResume() { super.onResume(); h.post(r); }
  @Override protected void onPause() { super.onPause(); h.removeCallbacks(r); }
  void refresh() {
    boolean lk = Prefs.isLocked(this);
    long d = Prefs.sp(this).getLong("disableAt", 0);
    String t = lk ? "LOCKED" : "Unlocked";
    if (lk && d > 0) {
      long m = (d - System.currentTimeMillis()) / 60000;
      t += "\nUnlocks in " + (m / 60) + "h " + (m % 60) + "m";
    }
    st.setText(t);
  }
}
EOF
