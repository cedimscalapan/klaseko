import 'package:flutter/material.dart';

/// Ballpen blue for actions, red pen for scores and checking, cool paper white for the ground.
const brandBlue = Color(0xFF1F4FD1);
const penRed = Color(0xFFCF2A2A);
const goodGreen = Color(0xFF23824F);
const lateAmber = Color(0xFFA86F00);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: brandBlue, brightness: brightness, primary: brightness == Brightness.light ? brandBlue : null);
  final light = brightness == Brightness.light;
  final radius = BorderRadius.circular(14);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: light ? const Color(0xFFF4F7FB) : const Color(0xFF0E1320),
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: light ? const Color(0xFFF4F7FB) : const Color(0xFF0E1320),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? Colors.white : const Color(0xFF161D2C),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: light ? Colors.white : const Color(0xFF161D2C),
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
