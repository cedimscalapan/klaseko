import 'package:flutter/material.dart';

import 'theme.dart';

/// KlaseKo brand: names, tagline and the logo drawn in code (sharp at every size, no image files).
class Brand {
  static const name = 'KlaseKo';
  static const meaning = '"Klase ko" means "my class".';
  static const tagline = 'Isang entry, tapos na ang forms.';
  static const taglineEn = 'One entry, and your forms are done.';
  static const description = 'Class records, exams and paper checking for DepEd teachers. Works offline.';
  static const version = '1.0.0';

  // Brand colors: the same in light and dark themes, so the logo always looks the same.
  static const navy = Color(0xFF173E75);
  static const navyDeep = Color(0xFF0F2D57);
  static const gold = Color(0xFFD8B567);
}

/// The logo symbol: a navy rounded square with a navy "K" inside a white answer bubble, like the
/// lettered bubbles on a test paper, and one gold shaded bubble. Matches the app icon
/// (tool/make_brand_assets.py) and assets/branding/klaseko-mark.svg.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48, this.plain = false});
  final double size;

  /// Without the navy square, for use on navy backgrounds (headers, splash).
  final bool plain;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MarkPainter(plain: plain)),
      );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.plain});
  final bool plain;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 1024;
    if (!plain) {
      final rect = Offset.zero & size;
      final paint = Paint()
        ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.navy, Brand.navyDeep]).createShader(rect);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.225)), paint);
    }
    final symbolScale = plain ? 1.12 : 1.0; // the plain mark uses the whole box
    final c = Offset(size.width / 2, size.height / 2);
    double k(double v) => v * s * symbolScale;
    final bubble = c + Offset(k(-50), k(54));
    canvas.drawCircle(bubble, k(286), Paint()..color = Colors.white);
    final letter = Path();
    for (final shape in _letterK) {
      for (var i = 0; i < shape.length; i += 2) {
        final p = bubble + Offset(k((shape[i] - 418) * 0.48), k((350 - shape[i + 1]) * 0.48));
        if (i == 0) {
          letter.moveTo(p.dx, p.dy);
        } else {
          letter.lineTo(p.dx, p.dy);
        }
      }
      letter.close();
    }
    canvas.drawPath(letter, Paint()..color = Brand.navyDeep);
    canvas.drawCircle(c + Offset(k(246), k(-230)), k(100), Paint()..color = Brand.gold);
  }

  /// The "K" of Lexend ExtraBold in font units (y up): upper arm, stem and lower leg.
  static const _letterK = [
    [223, 201, 161, 355, 500, 700, 728, 700],
    [83, 0, 83, 700, 281, 700, 281, 0],
    [526, 0, 270, 336, 400, 448, 753, 0],
  ];

  @override
  bool shouldRepaint(_MarkPainter old) => old.plain != plain;
}

/// "KlaseKo" in Lexend ExtraBold with "Ko" in gold.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 24, this.onDark = false});
  final double size;

  /// White text, for navy headers.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final main = onDark ? Colors.white : palette.text;
    final accent = onDark ? Brand.gold : gold;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Klase', style: TextStyle(color: main)),
        TextSpan(text: 'Ko', style: TextStyle(color: accent)),
      ]),
      style: TextStyle(fontFamily: 'Lexend', fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -0.02 * size, height: 1.1),
    );
  }
}

/// Symbol and name side by side, with an optional tagline underneath.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 40, this.showTagline = false, this.onDark = false});
  final double size;
  final bool showTagline;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        BrandMark(size: size),
        SizedBox(width: size * 0.3),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          BrandWordmark(size: size * 0.62, onDark: onDark),
          if (showTagline)
            Text(Brand.tagline,
                style: TextStyle(fontSize: size * 0.28, color: onDark ? Colors.white.withAlpha(200) : mutedText(context), fontWeight: FontWeight.w500)),
        ]),
      ]);
}
