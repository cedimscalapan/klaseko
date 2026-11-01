// Adds what KlaseKo needs to the Android and iOS folders that `flutter create` generates:
// camera permission, app name, minimum Android version and iOS permission messages.
// Run from the project folder: dart run tool/patch_platforms.dart
import 'dart:io';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (manifest.existsSync()) {
    var s = manifest.readAsStringSync();
    if (!s.contains('android.permission.CAMERA')) {
      s = s.replaceFirst('<application', '<uses-permission android:name="android.permission.CAMERA" />\n    <application');
    }
    s = s.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="KlaseKo"');
    manifest.writeAsStringSync(s);
    stdout.writeln('Patched AndroidManifest.xml');
  }

  for (final name in ['android/app/build.gradle', 'android/app/build.gradle.kts']) {
    final f = File(name);
    if (!f.existsSync()) continue;
    final s = f
        .readAsStringSync()
        .replaceAll('minSdk = flutter.minSdkVersion', 'minSdk = 23')
        .replaceAll('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 23');
    f.writeAsStringSync(s);
    stdout.writeln('Set minSdk 23 in $name');
  }

  final plist = File('ios/Runner/Info.plist');
  if (plist.existsSync()) {
    var s = plist.readAsStringSync();
    const entries = {
      'NSCameraUsageDescription': 'KlaseKo uses the camera to check answer sheets. Photos stay on your phone.',
      'NSPhotoLibraryUsageDescription': 'KlaseKo can read answer sheet photos from your library.',
    };
    entries.forEach((k, v) {
      if (!s.contains(k)) {
        final i = s.lastIndexOf('</dict>');
        s = '${s.substring(0, i)}\t<key>$k</key>\n\t<string>$v</string>\n${s.substring(i)}';
      }
    });
    s = s.replaceFirst(RegExp(r'<key>CFBundleDisplayName</key>\s*<string>[^<]*</string>'), '<key>CFBundleDisplayName</key>\n\t<string>KlaseKo</string>');
    plist.writeAsStringSync(s);
    stdout.writeln('Patched Info.plist');
  }
}
