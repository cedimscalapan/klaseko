import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/store.dart';
import 'ui/onboarding_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  // The Lexend font license, shown under About > Open-source licenses.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Lexend font'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  await AppStore.init();
  runApp(const KlaseKoApp());
}

ThemeMode themeModeOf(String v) => switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

class KlaseKoApp extends StatelessWidget {
  const KlaseKoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) => MaterialApp(
        title: 'KlaseKo',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: themeModeOf(AppStore.instance.profile.themeMode),
        builder: (context, child) => PaletteScope(brightness: Theme.of(context).brightness, child: child ?? const SizedBox()),
        home: AppStore.instance.onboarded ? const Shell() : const OnboardingScreen(),
      ),
    );
  }
}

/// Keeps the shared palette in step with the theme on screen. When the theme switches (from the
/// Appearance setting or the phone's dark mode), every screen is redrawn with the new colors
/// while keeping its place and its data.
class PaletteScope extends StatefulWidget {
  const PaletteScope({super.key, required this.brightness, required this.child});
  final Brightness brightness;
  final Widget child;

  @override
  State<PaletteScope> createState() => _PaletteScopeState();
}

class _PaletteScopeState extends State<PaletteScope> {
  @override
  void didUpdateWidget(PaletteScope old) {
    super.didUpdateWidget(old);
    if (old.brightness != widget.brightness) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        void visit(Element e) {
          e.markNeedsBuild();
          e.visitChildren(visit);
        }

        (context as Element).visitChildren(visit);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    usePalette(widget.brightness);
    return widget.child;
  }
}
