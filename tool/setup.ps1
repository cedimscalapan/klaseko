# KlaseKo one-time setup on Windows. Run from the project folder after installing Flutter and Android Studio:
#   powershell -ExecutionPolicy Bypass -File tool\setup.ps1
$ErrorActionPreference = 'Stop'
flutter --version
if (-not (Test-Path 'android')) {
    flutter create --org ph.klaseko --project-name klaseko --platforms android,ios .
}
dart run tool/patch_platforms.dart
flutter pub get
Write-Host ''
Write-Host 'Setup done. Plug in an Android phone with USB debugging on, then run:  flutter run'
Write-Host 'To make an installable APK:  flutter build apk --release'
