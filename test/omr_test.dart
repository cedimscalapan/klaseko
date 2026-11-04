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
  bool numbers = true,
  bool letters = false,
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
            // Item number, right-aligned just left of choice A: one 1.6 mm wide digit per character.
            final lab = SheetLayout.itemLabel(i);
            final digits = '${i + 1}'.length;
            if (numbers && (fy - lab.y).abs() < 1.3 && fx < lab.x + 2 && fx > lab.x + 2 - 1.6 * digits && ((lab.x + 2 - fx) % 1.6) < 0.4) v = 30;
            for (var c = 0; c < 4; c++) {
              final b = SheetLayout.itemBubble(i, c);
              if ((b.x - fx).abs() < 4 && (b.y - fy).abs() < 4) {
                bubble(b.x, b.y, SheetLayout.bubbleR, 'i$i:$c');
                if (letters && !shaded.contains('i$i:$c')) {
                  final g = bubbleLetterGlyphs[c];
                  final row = ((fy - b.y) / 0.2 + g.length / 2).floor(), col = ((fx - b.x) / 0.2 + g.first.length / 2).floor();
                  if (row >= 0 && row < g.length && col >= 0 && col < g.first.length) v = min(v, 228.0 - int.parse(g[row][col]) * 5);
                }
              }
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

  // Close-ups of the answers only: no markers and no learner number in the photo. The photo is
  // centred on page point (61.95, 141.7) mm, the middle of items 1-10; at 16 px/mm it shows about
  // 75 x 94 mm of the sheet.
  final ten = answers.sublist(0, 10);
  Uint8List closeUp(List<int> a, {double rotDeg = 0, double pxPerMm = 16, int pencil = 45, bool numbers = true, bool letters = false}) {
    final r = rotDeg * pi / 180, ca = cos(r), sa = sin(r);
    final u = (-46 * ca - 2 * sa) * pxPerMm, v = (-46 * sa + 2 * ca) * pxPerMm;
    return photo(answers: a, learnerNum: 0, pxPerMm: pxPerMm, dx: -u, dy: -v, rotDeg: rotDeg, pencil: pencil, numbers: numbers, letters: letters);
  }

  void expectCloseUp(OmrResult r) {
    expect(r.ok, isTrue, reason: r.error);
    expect(r.learnerNum, isNull);
    for (var i = 0; i < ten.length; i++) {
      if (r.review.contains(i)) continue;
      expect(r.answers[i], ten[i], reason: 'item ${i + 1}');
    }
    expect(r.review.length, lessThan(2));
  }

  test('reads a close-up of the bubbles without markers', () {
    expectCloseUp(readAnswerSheet(OmrRequest(closeUp(ten, rotDeg: 4), 10)));
  });

  test('reads an upside-down close-up with light pencil', () {
    expectCloseUp(readAnswerSheet(OmrRequest(closeUp(ten, rotDeg: 181, pencil: 150), 10)));
  });

  test('reads a sideways close-up', () {
    expectCloseUp(readAnswerSheet(OmrRequest(closeUp(ten, rotDeg: -88, pxPerMm: 14), 10)));
  });

  test('reads just the bubbles, without item numbers', () {
    expectCloseUp(readAnswerSheet(OmrRequest(closeUp(ten, rotDeg: 3, numbers: false, letters: true), 10)));
  });

  test('reads just the bubbles upside down, with light pencil', () {
    expectCloseUp(readAnswerSheet(OmrRequest(closeUp(ten, rotDeg: 178, pencil: 150, numbers: false, letters: true), 10)));
  });

  test('reads just the bubbles sideways', () {
    expectCloseUp(readAnswerSheet(OmrRequest(closeUp(ten, rotDeg: 92, pxPerMm: 14, numbers: false, letters: true), 10)));
  });

  test('refuses when nothing shows which way is up', () {
    final r = readAnswerSheet(OmrRequest(closeUp(ten, numbers: false), 10));
    expect(r.ok, isFalse);
  });

  test('refuses a close-up that leaves out some items', () {
    final r = readAnswerSheet(OmrRequest(closeUp(answers.sublist(0, 16)), 16));
    expect(r.ok, isFalse);
  });

  test('reads the answers when only the learner number is outside the photo', () {
    final r = readAnswerSheet(OmrRequest(photo(answers: answers, learnerNum: 12, pxPerMm: 5.2, dy: -330), 40));
    expect(r.ok, isTrue, reason: r.error);
    expect(r.learnerNum, isNull);
    for (var i = 0; i < answers.length; i++) {
      if (!r.review.contains(i)) expect(r.answers[i], answers[i], reason: 'item ${i + 1}');
    }
  });

  test('refuses when answers are outside the photo', () {
    final r = readAnswerSheet(OmrRequest(photo(answers: answers, learnerNum: 12, pxPerMm: 5.2, dy: 330), 40));
    expect(r.ok, isFalse);
  });
}
