# Trackley

A Flutter app for manually starting and stopping GPS travel tracking. It records only distance totals per day on the device and shows the current month's daily-distance chart.

## Run it

1. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install) and Android Studio / Xcode as appropriate.
2. From this folder, run `flutter create .` to generate Android and iOS platform folders.
3. Run `flutter pub get`.
4. Add the required location permissions below, then run `flutter run` on a physical phone.

## Platform permissions

**Android — `android/app/src/main/AndroidManifest.xml`** (inside the top-level `manifest` tag):

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

**iPhone — `ios/Runner/Info.plist`** (inside the `dict`):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Your location is used only while you manually track a trip.</string>
```

This first version tracks while the app is active. Continuing a manually active trip in the background requires platform-specific background-location configuration, a persistent Android notification, and more extensive battery/privacy design.

