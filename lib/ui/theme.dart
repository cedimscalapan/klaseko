import 'package:flutter/material.dart';

/// Ballpen blue for actions, red pen for scores and checking, cool paper white for the ground.
const brandBlue = Color(0xFF1F4FD1);
const brandDeep = Color(0xFF14213D);
const penRed = Color(0xFFCF2A2A);
const goodGreen = Color(0xFF1E8A52);
const lateAmber = Color(0xFFB07400);
const violet = Color(0xFF6B4EE6);
const teal = Color(0xFF0E8C8C);

const _paperLight = Color(0xFFF3F6FB);
const _paperDark = Color(0xFF0C111C);
const _cardDark = Color(0xFF151C2B);

/// Brand gradient used on hero headers.
const heroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF2557E8), Color(0xFF1A3FB0)],
);

bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
Color cardColor(BuildContext context) => isDark(context) ? _cardDark : Colors.white;
Color mutedText(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;

List<BoxShadow> softShadow(BuildContext context) => isDark(context)
    ? const []
    : const [
        BoxShadow(color: Color(0x0F14213D), blurRadius: 18, offset: Offset(0, 6)),
        BoxShadow(color: Color(0x0814213D), blurRadius: 3, offset: Offset(0, 1)),
      ];

ThemeData buildTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: brandBlue,
    brightness: brightness,
    primary: light ? brandBlue : const Color(0xFF8FADFF),
    surface: light ? _paperLight : _paperDark,
  );
  final radius = BorderRadius.circular(16);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Lexend');
  final text = base.textTheme.copyWith(
    headlineLarge: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.15),
    headlineMedium: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.2),
    headlineSmall: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleLarge: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    titleSmall: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: const TextStyle(fontSize: 16, height: 1.45),
    bodyMedium: const TextStyle(fontSize: 14.5, height: 1.45),
    bodySmall: const TextStyle(fontSize: 12.5, height: 1.4),
    labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  );
  return base.copyWith(
    textTheme: text.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
    scaffoldBackgroundColor: light ? _paperLight : _paperDark,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: light ? _paperLight : _paperDark,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Lexend', fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? Colors.white : _cardDark,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant.withAlpha(160))),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 54),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: 'Lexend', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 54),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(fontFamily: 'Lexend', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: const TextStyle(fontFamily: 'Lexend', fontSize: 15, fontWeight: FontWeight.w600)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: const TextStyle(fontFamily: 'Lexend', fontSize: 15, fontWeight: FontWeight.w600),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: light ? Colors.white : _cardDark,
      indicatorColor: scheme.primary.withAlpha(30),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
            size: 26,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: 'Lexend',
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          )),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        textStyle: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withAlpha(120), space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      contentTextStyle: const TextStyle(fontFamily: 'Lexend', fontSize: 14.5),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
