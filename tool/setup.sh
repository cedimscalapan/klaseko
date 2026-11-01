#!/usr/bin/env bash
# KlaseKo one-time setup on macOS or Linux. Run from the project folder: bash tool/setup.sh
set -euo pipefail
flutter --version
if [ ! -d android ]; then
  flutter create --org ph.klaseko --project-name klaseko --platforms android,ios .
fi
dart run tool/patch_platforms.dart
flutter pub get
echo "Setup done. Run: flutter run   (or: flutter build apk --release)"
