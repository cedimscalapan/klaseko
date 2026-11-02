#!/usr/bin/env bash
# KlaseKo one-time setup on macOS or Linux. Run from the project folder: bash tool/setup.sh
set -euo pipefail
flutter --version
if [ ! -d android ]; then
  flutter create --org ph.klaseko --project-name klaseko --platforms android,ios .
fi
dart run tool/patch_platforms.dart
flutter pub get
# Brand: app icon (standalone tool, so its dependencies stay out of the app). The launch screen is written by patch_platforms.
dart pub global activate flutter_launcher_icons 0.14.4 >/dev/null
dart pub global run flutter_launcher_icons || echo "::warning::App icon generation failed"
echo "Setup done. Run: flutter run   (or: flutter build apk --release)"
