// Adds what KlaseKo needs to the Android and iOS folders that `flutter create` generates:
// camera permission, app name, minimum Android version, launch screen and iOS permission messages.
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

  // Signs release builds with the permanent key when the build provides one (see docs/SELLING.md).
  // Without it Flutter uses a temporary key, and an update cannot install over the old version.
  final gradle = File('android/app/build.gradle.kts');
  if (gradle.existsSync()) {
    var s = gradle.readAsStringSync();
    if (!s.contains('KLASEKO_KEYSTORE')) {
      s = s.replaceFirst('    buildTypes {', '''    signingConfigs {
        create("klaseko") {
            val store = System.getenv("KLASEKO_KEYSTORE")
            if (store != null) {
                storeFile = file(store)
                storePassword = System.getenv("KLASEKO_KEY_PASSWORD")
                keyAlias = "klaseko"
                keyPassword = System.getenv("KLASEKO_KEY_PASSWORD")
            }
        }
    }

    buildTypes {''');
      s = s.replaceFirst('signingConfig = signingConfigs.getByName("debug")',
          'signingConfig = signingConfigs.getByName(if (System.getenv("KLASEKO_KEYSTORE") != null) "klaseko" else "debug")');
      gradle.writeAsStringSync(s);
      stdout.writeln('Added release signing to build.gradle.kts');
    }
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

  // Text recognition ships only the Latin model; tell the release shrinker (R8) that the other
  // script models referenced by the plugin are intentionally absent.
  final rules = File('android/app/proguard-rules.pro');
  if (Directory('android/app').existsSync()) {
    final existing = rules.existsSync() ? rules.readAsStringSync() : '';
    if (!existing.contains('com.google.mlkit.vision.text.chinese')) {
      rules.writeAsStringSync('''$existing
# KlaseKo: only the Latin text recognition model is bundled.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
''');
      stdout.writeln('Wrote android/app/proguard-rules.pro');
    }
  }

  // Launch screen: the KlaseKo symbol on navy. Android 12+ uses its own splash API, so it gets
  // separate styles (light and dark, since night resources outrank API-level ones).
  const res = 'android/app/src/main/res';
  if (Directory(res).existsSync()) {
    Directory('$res/drawable-xxxhdpi').createSync(recursive: true);
    File('assets/branding/splash.png').copySync('$res/drawable-xxxhdpi/klaseko_splash.png');
    File('assets/branding/splash_android12.png').copySync('$res/drawable-xxxhdpi/klaseko_splash12.png');
    const background = '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item><color android:color="#0F2D57" /></item>
    <item><bitmap android:gravity="center" android:src="@drawable/klaseko_splash" /></item>
</layer-list>
''';
    for (final dir in ['drawable', 'drawable-v21']) {
      Directory('$res/$dir').createSync(recursive: true);
      File('$res/$dir/launch_background.xml').writeAsStringSync(background);
    }
    String styles(String parent) => '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="$parent">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowSplashScreenBackground">#0F2D57</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/klaseko_splash12</item>
    </style>
    <style name="NormalTheme" parent="$parent">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
''';
    for (final (dir, parent) in [('values-v31', '@android:style/Theme.Light.NoTitleBar'), ('values-night-v31', '@android:style/Theme.Black.NoTitleBar')]) {
      Directory('$res/$dir').createSync(recursive: true);
      File('$res/$dir/styles.xml').writeAsStringSync(styles(parent));
    }
    stdout.writeln('Wrote the Android launch screen');
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
