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

  // Some plugins still compile against an older Android SDK than the AndroidX libraries they pull in,
  // which fails the release build's AAR metadata check. Compile every plugin against SDK 36.
  // The hook goes before `evaluationDependsOn(":app")` so it is registered before any project is evaluated.
  const ktsHook = '''
// KlaseKo: compile every plugin against a recent Android SDK.
subprojects {
    val raiseCompileSdk = {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                androidExt.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(androidExt, 36)
            } catch (e: Exception) {
                logger.warn("KlaseKo: could not set compileSdk for " + project.name + ": " + e.message)
            }
        }
    }
    if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
}

''';
  const groovyHook = '''
// KlaseKo: compile every plugin against a recent Android SDK.
subprojects { p ->
    def raiseCompileSdk = {
        def androidExt = p.extensions.findByName("android")
        if (androidExt != null) {
            try {
                androidExt.compileSdkVersion(36)
            } catch (e) {
                p.logger.warn("KlaseKo: could not set compileSdk for " + p.name + ": " + e.message)
            }
        }
    }
    if (p.state.executed) raiseCompileSdk() else p.afterEvaluate { raiseCompileSdk() }
}

''';
  for (final (name, hook) in [('android/build.gradle.kts', ktsHook), ('android/build.gradle', groovyHook)]) {
    final f = File(name);
    if (!f.existsSync()) continue;
    var s = f.readAsStringSync();
    if (s.contains('KlaseKo: compile every plugin')) continue;
    final dep = s.indexOf('evaluationDependsOn');
    final at = dep < 0 ? -1 : s.lastIndexOf('subprojects', dep);
    s = at < 0 ? '$s\n$hook' : '${s.substring(0, at)}$hook${s.substring(at)}';
    f.writeAsStringSync(s);
    stdout.writeln('Added compileSdk 36 hook to $name');
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
