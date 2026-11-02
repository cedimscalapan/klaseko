import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// KlaseKo palette: a calm, government-style look.
///
/// Light: navy on soft off-white paper, muted gold accent. Dark: soft blue-gray surfaces (never
/// pure black), slightly dimmed text and desaturated accents, so long evening sessions are easy on
/// the eyes. Status colors (green, amber, red) are muted and always paired with words or icons.
/// Text on surfaces meets WCAG AA contrast in both themes.
class AppPalette {
  final Brightness brightness;
  final Color primary; // navy actions, links, selected states
  final Color navyDeep; // headers and hero bands
  final Color gold; // accent
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color pen; // red-pen scores
  final Color background;
  final Color surface; // cards
  final Color surfaceAlt; // tinted panels
  final Color border;
  final Color text;
  final Color textMuted;
  final List<Color> hero; // hero gradient
  final List<Color> classColors;

  const AppPalette({
    required this.brightness,
    required this.primary,
    required this.navyDeep,
    required this.gold,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.pen,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.hero,
    required this.classColors,
  });

  static const light = AppPalette(
    brightness: Brightness.light,
    primary: Color(0xFF1B4A8C),
    navyDeep: Color(0xFF0F2D57),
    gold: Color(0xFF85600F),
    success: Color(0xFF2B7348),
    warning: Color(0xFF9A5B00),
    danger: Color(0xFFB0302A),
    info: Color(0xFF2B6575),
    pen: Color(0xFFB0302A),
    background: Color(0xFFF3F4F6),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDF1F6),
    border: Color(0xFFD9DEE5),
    text: Color(0xFF1B2330),
    textMuted: Color(0xFF586273),
    hero: [Color(0xFF173E75), Color(0xFF0F2D57)],
    classColors: [Color(0xFF1B4A8C), Color(0xFF85600F), Color(0xFF2B6575), Color(0xFF7A2E3A), Color(0xFF2B7348), Color(0xFF4F5D75)],
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    primary: Color(0xFF9DBBEA),
    navyDeep: Color(0xFF1A2C47),
    gold: Color(0xFFD8B567),
    success: Color(0xFF7CC69A),
    warning: Color(0xFFE2B062),
    danger: Color(0xFFEE8F86),
    info: Color(0xFF86C1CE),
    pen: Color(0xFFEE8F86),
    background: Color(0xFF12171E),
    surface: Color(0xFF1A2029),
    surfaceAlt: Color(0xFF212A35),
    border: Color(0xFF2E3846),
    text: Color(0xFFE1E5EA),
    textMuted: Color(0xFF9BA5B3),
    hero: [Color(0xFF1E3352), Color(0xFF172840)],
    classColors: [Color(0xFF9DBBEA), Color(0xFFD8B567), Color(0xFF86C1CE), Color(0xFFE2A0AA), Color(0xFF7CC69A), Color(0xFFAEB8CC)],
  );
}

AppPalette _palette = AppPalette.light;

/// The palette for the theme currently on screen. Set by the app shell whenever the brightness
/// changes; every screen is then rebuilt (see main.dart).
AppPalette get palette => _palette;
void usePalette(Brightness b) => _palette = b == Brightness.dark ? AppPalette.dark : AppPalette.light;

// Semantic color names used across the screens.
Color get brandBlue => _palette.primary;
Color get brandDeep => _palette.navyDeep;
Color get penRed => _palette.pen;
Color get goodGreen => _palette.success;
Color get lateAmber => _palette.warning;
Color get violet => _palette.gold; // secondary accent
Color get teal => _palette.info;
Color get gold => _palette.gold;
Color get dangerRed => _palette.danger;

/// Navy gradient used on hero headers.
LinearGradient get heroGradient => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _palette.hero);

bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
Color cardColor(BuildContext context) => isDark(context) ? AppPalette.dark.surface : AppPalette.light.surface;
Color mutedText(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;

List<BoxShadow> softShadow(BuildContext context) => isDark(context)
    ? const []
    : const [
        BoxShadow(color: Color(0x0D0F2D57), blurRadius: 16, offset: Offset(0, 5)),
        BoxShadow(color: Color(0x0A0F2D57), blurRadius: 2, offset: Offset(0, 1)),
      ];

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  final light = brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppPalette.light.primary,
    brightness: brightness,
    primary: p.primary,
    onPrimary: light ? Colors.white : const Color(0xFF0E1A2C),
    secondary: p.gold,
    onSecondary: light ? Colors.white : const Color(0xFF231A05),
    tertiary: p.info,
    error: p.danger,
    surface: p.background,
    onSurface: p.text,
    onSurfaceVariant: p.textMuted,
    outline: light ? const Color(0xFF8C96A5) : const Color(0xFF6C7686),
    outlineVariant: p.border,
    surfaceContainerHighest: p.surfaceAlt,
    primaryContainer: light ? const Color(0xFFDCE6F4) : const Color(0xFF263A59),
    onPrimaryContainer: light ? const Color(0xFF0F2D57) : const Color(0xFFD7E3F7),
  );
  final radius = BorderRadius.circular(14);
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
    textTheme: text.apply(bodyColor: p.text, displayColor: p.text),
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    cardColor: p.surface,
    dividerColor: p.border,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Lexend', fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: p.text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: p.textMuted),
      hintStyle: TextStyle(color: p.textMuted.withAlpha(170)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 54),
        backgroundColor: p.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: 'Lexend', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 54),
        foregroundColor: p.primary,
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: p.border),
        textStyle: const TextStyle(fontFamily: 'Lexend', fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.primary, textStyle: const TextStyle(fontFamily: 'Lexend', fontSize: 15, fontWeight: FontWeight.w600)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: light ? p.navyDeep : p.primary,
      foregroundColor: light ? Colors.white : const Color(0xFF0E1A2C),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      extendedTextStyle: const TextStyle(fontFamily: 'Lexend', fontSize: 15, fontWeight: FontWeight.w600),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: p.surface,
      indicatorColor: p.primary.withAlpha(light ? 28 : 46),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.primary : p.textMuted, size: 26)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: 'Lexend',
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? p.primary : p.textMuted,
          )),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        textStyle: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: BorderSide(color: p.border)),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    dividerTheme: DividerThemeData(color: p.border, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: light ? p.navyDeep : const Color(0xFF2A3442),
      contentTextStyle: const TextStyle(fontFamily: 'Lexend', fontSize: 14.5, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    popupMenuTheme: PopupMenuThemeData(color: p.surface, surfaceTintColor: Colors.transparent),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
