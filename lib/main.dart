import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/store.dart';
import 'ui/onboarding_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await AppStore.init();
  runApp(const KlaseKoApp());
}

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
        home: AppStore.instance.onboarded ? const Shell() : const OnboardingScreen(),
      ),
    );
  }
}
