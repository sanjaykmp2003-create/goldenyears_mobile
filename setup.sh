#!/usr/bin/env bash
# One-time setup: generates the android/ios platform folders around the Dart code, then installs packages.
# Requires Flutter >= 3.24 (https://docs.flutter.dev/get-started/install).
set -e
flutter create . --org com.goldenyears --project-name unicare_mobile --platforms=android,ios
rm -f test/widget_test.dart

MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
  sed -i.bak 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$MANIFEST"
fi
# Allow plain http:// to your dev server. REMOVE this for production (use https).
if ! grep -q usesCleartextTraffic "$MANIFEST"; then
  sed -i.bak 's#<application#<application android:usesCleartextTraffic="true"#' "$MANIFEST"
fi
rm -f "$MANIFEST.bak"

flutter pub get
echo
echo "Done. Run:  flutter run --dart-define=API_URL=http://<your-server>:8080/api"
