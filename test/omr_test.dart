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
  BoxLayout? box,
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
        final centers = box?.markers(answers.length) ?? SheetLayout.markerCenters;
        final size = box?.marker ?? SheetLayout.marker;
        for (var id = 0; id < centers.length; id++) {
          final c = centers[id];
          final lx = fx - (c.x - size / 2), ly = fy - (c.y - size / 2);
          if (lx < 0 || ly < 0 || lx >= size || ly >= size) continue;
          final col = lx ~/ (size / 6), row = ly ~/ (size / 6);
          final border = row == 0 || col == 0 || row == 5 || col == 5;
          if (border || SheetLayout.markerBit((box?.codeStart ?? 0) + id, row - 1, col - 1)) v = 25;
        }
        void bubble(double cx, double cy, double r, String key) {
          final d = sqrt((fx - cx) * (fx - cx) + (fy - cy) * (fy - cy));
          if ((d - r).abs() < 0.18) v = min(v, 110.0);
          if (d < r * 0.92 && shaded.contains(key)) v = (key.startsWith('d') ? 30 : pencil).toDouble();
        }

        final items = box ?? BoxLayout.full;
        if (fy > items.firstRowY - 4 && fy < items.firstRowY + items.rowsPerColumn * items.rowStep) {
          for (var i = 0; i < answers.length; i++) {
            // Item number, right-aligned just left of choice A: one 1.6 mm wide digit per character.
            final s = items.glyphScale, end = items.labelRightAt(i);
            final digits = '${i + 1}'.length;
            if (numbers && (fy - items.item(i, 0).y).abs() < 1.3 * s && fx < end && fx > end - 1.6 * s * digits && ((end - fx) % (1.6 * s)) < 0.4 * s) v = 30;
            for (var c = 0; c < 4; c++) {
              final b = items.item(i, c);
              if ((b.x - fx).abs() < 4 && (b.y - fy).abs() < 4) {
                bubble(b.x, b.y, items.bubbleR, 'i$i:$c');
                if (letters && !shaded.contains('i$i:$c')) {
                  final g = bubbleLetterGlyphs[c];
                  final row = ((fy - b.y) / (0.2 * s) + g.length / 2).floor(), col = ((fx - b.x) / (0.2 * s) + g.first.length / 2).floor();
                  if (row >= 0 && row < g.length && col >= 0 && col < g.first.length) v = min(v, 228.0 - int.parse(g[row][col]) * 5);
                }
              }
            }
          }
        }
        if (box != null) {
          for (var col = 0; col < 2; col++) {
            for (var d = 0; d < 10; d++) {
              final b = box.id(col, d);
              if ((b.x - fx).abs() < 4 && (b.y - fy).abs() < 4) bubble(b.x, b.y, box.idR, 'd$col:$d');
            }
          }
        } else if (fx > SheetLayout.idX0 - 4) {
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

  // The answer box: the photo is centred on sheet point (cx, cy) mm.
  Uint8List boxPhoto(List<int> a, int learner, double cx, double cy, {double rotDeg = 0, double pxPerMm = 12, BoxLayout layout = BoxLayout.full, bool numbers = true, bool letters = false}) {
    final r = rotDeg * pi / 180, ca = cos(r), sa = sin(r);
    final px = cx - 90, py = cy - 125; // from the page centre, which is the sheet frame's centre
    final u = (px * ca - py * sa) * pxPerMm, v = (px * sa + py * ca) * pxPerMm;
    return photo(answers: a, learnerNum: learner, pxPerMm: pxPerMm, dx: -u, dy: -v, rotDeg: rotDeg, box: layout, numbers: numbers, letters: letters);
  }

  void expectBox(OmrResult r, int? learner) {
    expect(r.ok, isTrue, reason: r.error);
    expect(r.learnerNum, learner);
    for (var i = 0; i < ten.length; i++) {
      if (!r.review.contains(i)) expect(r.answers[i], ten[i], reason: 'item ${i + 1}');
    }
    expect(r.review.length, lessThan(2));
  }

  test('reads only the answer box', () {
    expectBox(readAnswerSheet(OmrRequest(boxPhoto(ten, 27, 44, 117.6), 10)), 27);
  });

  test('reads a tilted answer box', () {
    expectBox(readAnswerSheet(OmrRequest(boxPhoto(ten, 8, 44, 117.6, rotDeg: 9, pxPerMm: 10.5), 10)), 8);
  });

  test('reads an upside-down answer box', () {
    expectBox(readAnswerSheet(OmrRequest(boxPhoto(ten, 53, 44, 117.6, rotDeg: 177), 10)), 53);
  });

  test('reads the answer box with its right side cut off', () {
    expectBox(readAnswerSheet(OmrRequest(boxPhoto(ten, 27, 28, 117.6), 10)), null);
  });

  test('reads the answer box with no markers in the photo, learner number included', () {
    expectBox(readAnswerSheet(OmrRequest(boxPhoto(ten, 27, 44, 116, pxPerMm: 15), 10)), 27);
  });

  test('reads a 1/4 sheet', () {
    expectBox(readAnswerSheet(OmrRequest(boxPhoto(ten, 27, 30.5, 35, layout: BoxLayout.quarter, pxPerMm: 14), 10)), 27);
  });

  test('reads a tilted, upside-down 1/4 sheet', () {
    expectBox(readAnswerSheet(OmrRequest(boxPhoto(ten, 53, 30.5, 35, layout: BoxLayout.quarter, pxPerMm: 13, rotDeg: 172), 10)), 53);
  });

  test('reads a 1/4 sheet with two columns of items', () {
    final thirty = answers.sublist(0, 30);
    final r = readAnswerSheet(OmrRequest(boxPhoto(thirty, 12, 32, 47.5, layout: BoxLayout.quarter), 30));
    expect(r.ok, isTrue, reason: r.error);
    expect(r.learnerNum, 12);
    for (var i = 0; i < thirty.length; i++) {
      if (!r.review.contains(i)) expect(r.answers[i], thirty[i], reason: 'item ${i + 1}');
    }
  });

  test('reads a 1/4 sheet with no markers or numbers in the photo', () {
    final r = readAnswerSheet(OmrRequest(boxPhoto(ten, 27, 30.5, 35, layout: BoxLayout.quarter, pxPerMm: 22, numbers: false, letters: true), 10));
    expect(r.ok, isTrue, reason: r.error);
    for (var i = 0; i < ten.length; i++) {
      if (!r.review.contains(i)) expect(r.answers[i], ten[i], reason: 'item ${i + 1}');
    }
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
