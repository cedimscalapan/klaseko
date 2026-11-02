import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:klaseko/core/omr/omr.dart';
import 'package:klaseko/core/omr/sheet_layout.dart';

/// Draws a photo of a shaded KlaseKo answer sheet: the page is scaled, rotated and shifted, so
/// parts of the paper can fall outside the photo.
Uint8List photo({
  required List<int> answers,
  required int learnerNum,
  double rotDeg = 0,
  double pxPerMm = 4.6,
  double dx = 0,
  double dy = 0,
  int pencil = 45,
  int seed = 1,
}) {
  const w = 1200, h = 1500;
  const pageW = 215.9, pageH = 279.4;
  final ox = (pageW - SheetLayout.frameW) / 2, oy = (pageH - SheetLayout.frameH) / 2;
  final a = rotDeg * pi / 180, ca = cos(a), sa = sin(a);
  final rnd = Random(seed);
  final im = img.Image(width: w, height: h);
  final shaded = <String>{};
  for (var i = 0; i < answers.length; i++) {
    if (answers[i] >= 0) shaded.add('i$i:${answers[i]}');
  }
  shaded.add('d0:${learnerNum ~/ 10}');
  shaded.add('d1:${learnerNum % 10}');

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // image px -> page mm (inverse of scale, rotate about the photo centre, shift)
      final ux = x - w / 2 - dx, uy = y - h / 2 - dy;
      final px = (ux * ca + uy * sa) / pxPerMm + pageW / 2;
      final py = (-ux * sa + uy * ca) / pxPerMm + pageH / 2;
      var v = 95.0; // table
      if (px >= 0 && py >= 0 && px <= pageW && py <= pageH) {
        v = 228;
        final fx = px - ox, fy = py - oy;
        for (var id = 0; id < SheetLayout.markerCenters.length; id++) {
          final c = SheetLayout.markerCenters[id];
          final lx = fx - (c.x - SheetLayout.marker / 2), ly = fy - (c.y - SheetLayout.marker / 2);
          if (lx < 0 || ly < 0 || lx >= SheetLayout.marker || ly >= SheetLayout.marker) continue;
          final col = lx ~/ SheetLayout.markerCell, row = ly ~/ SheetLayout.markerCell;
          final border = row == 0 || col == 0 || row == 5 || col == 5;
          if (border || SheetLayout.markerBit(id, row - 1, col - 1)) v = 25;
        }
        void bubble(double cx, double cy, double r, String key) {
          final d = sqrt((fx - cx) * (fx - cx) + (fy - cy) * (fy - cy));
          if ((d - r).abs() < 0.18) v = min(v, 110.0);
          if (d < r * 0.92 && shaded.contains(key)) v = (key.startsWith('d') ? 30 : pencil).toDouble();
        }

        if (fy > SheetLayout.firstRowY - 4 && fy < SheetLayout.firstRowY + 20 * SheetLayout.rowStep) {
          for (var i = 0; i < answers.length; i++) {
            for (var c = 0; c < 4; c++) {
              final b = SheetLayout.itemBubble(i, c);
              if ((b.x - fx).abs() < 4 && (b.y - fy).abs() < 4) bubble(b.x, b.y, SheetLayout.bubbleR, 'i$i:$c');
            }
          }
        }
        if (fx > SheetLayout.idX0 - 4) {
          for (var col = 0; col < 2; col++) {
            for (var d = 0; d < 10; d++) {
              final b = SheetLayout.idBubble(col, d);
              if ((b.x - fx).abs() < 4 && (b.y - fy).abs() < 4) bubble(b.x, b.y, SheetLayout.idR, 'd$col:$d');
            }
          }
        }
      }
      v += (rnd.nextDouble() - 0.5) * 24;
      final g = v.round().clamp(0, 255);
      im.setPixelRgb(x, y, g, g, g);
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

void main() {
  final rnd = Random(5);
  final answers = List<int>.generate(40, (_) => rnd.nextInt(4));
  answers[6] = -1;

  void expectRead(OmrResult r, int learner) {
    expect(r.ok, isTrue, reason: r.error);
    expect(r.learnerNum, learner);
    expect(r.answers.length, answers.length);
    for (var i = 0; i < answers.length; i++) {
      if (r.review.contains(i)) continue; // a flagged item is shown to the teacher, never saved silently
      expect(r.answers[i], answers[i], reason: 'item ${i + 1}');
    }
    expect(r.review.length, lessThan(3));
  }

  test('reads a whole sheet', () {
    expectRead(readAnswerSheet(OmrRequest(photo(answers: answers, learnerNum: 27), 40)), 27);
  });

  test('reads a rotated sheet with the left edge outside the photo', () {
    expectRead(readAnswerSheet(OmrRequest(photo(answers: answers, learnerNum: 8, rotDeg: 12, pxPerMm: 5.0, dx: 95), 40)), 8);
  });

  test('reads an upside-down sheet with light pencil', () {
    expectRead(readAnswerSheet(OmrRequest(photo(answers: answers, learnerNum: 53, rotDeg: 183, pencil: 160, seed: 3), 40)), 53);
  });

  test('refuses when answers are outside the photo', () {
    final r = readAnswerSheet(OmrRequest(photo(answers: answers, learnerNum: 12, pxPerMm: 5.2, dy: -330), 40));
    expect(r.ok, isFalse);
  });
}
