#!/usr/bin/env bash
# KlaseKo one-time setup on macOS or Linux. Run from the project folder: bash tool/setup.sh
set -euo pipefail
flutter --version
if [ ! -d android ]; then
  flutter create --org ph.klaseko --project-name klaseko --platforms android,ios .
fi
dart run tool/patch_platforms.dart
flutter pub get
# Brand: app icon and launch screen (standalone tools, so their dependencies stay out of the app).
dart pub global activate flutter_launcher_icons 0.14.4 >/dev/null
dart pub global run flutter_launcher_icons || echo "::warning::App icon generation failed"
dart pub global activate flutter_native_splash 2.4.8 >/dev/null
dart pub global run flutter_native_splash:create || echo "::warning::Launch screen generation failed"
echo "Setup done. Run: flutter run   (or: flutter build apk --release)"
