import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klaseko/ui/onboarding_screen.dart';
import 'package:klaseko/ui/theme.dart';
import 'package:klaseko/ui/widgets.dart';

void main() {
  testWidgets(
    'Onboarding advances, validates and returns with visible controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: const OnboardingScreen(),
        ),
      );
      expect(find.text('Step 1 of 3'), findsOneWidget);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 3'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.textContaining('Please enter'), findsWidgets);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'Shared navigation row wraps at narrow width with large text: $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 800),
                textScaler: TextScaler.linear(1.6),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: NavRow(
                    icon: Icons.school_outlined,
                    title: 'School policy and grading',
                    subtitle: 'Configure your institution rules and grade conversion.',
                    onTap: () => tapped = true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('School policy and grading'));
        expect(tapped, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
