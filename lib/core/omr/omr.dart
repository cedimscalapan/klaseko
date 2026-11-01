import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'sheet_layout.dart';

/// Optical mark reading for KlaseKo answer sheets. Pure Dart, runs fully offline in a
/// background isolate: `compute(readAnswerSheet, OmrRequest(bytes, items))`.
class OmrRequest {
  final Uint8List bytes;
  final int items;
  const OmrRequest(this.bytes, this.items);
}

class OmrResult {
  final bool ok;
  final String? error;

  /// Learner number read from the two digit columns, or null when not shaded.
  final int? learnerNum;

  /// One code per item: 0..3 = A..D, -1 = blank, -2 = more than one shaded.
  final List<int> answers;

  /// Darkness (0..1) of every bubble, items x 4. Lets the review screen show what was read.
  final List<List<double>> fills;
  final double confidence;

  const OmrResult({
    required this.ok,
    this.error,
    this.learnerNum,
    this.answers = const [],
    this.fills = const [],
    this.confidence = 0,
  });

  factory OmrResult.fail(String message) => OmrResult(ok: false, error: message);
}

const double _shaded = 0.42;

OmrResult readAnswerSheet(OmrRequest req) {
  try {
    final decoded = img.decodeImage(req.bytes);
    if (decoded == null) return OmrResult.fail('The photo could not be opened. Try again.');
    final oriented = img.bakeOrientation(decoded);
    final longSide = max(oriented.width, oriented.height);
    final scale = longSide > 1400 ? 1400 / longSide : 1.0;
    final small = scale < 1
        ? img.copyResize(oriented,
            width: (oriented.width * scale).round(), height: (oriented.height * scale).round(), interpolation: img.Interpolation.average)
        : oriented;
    final w = small.width, h = small.height;
    final gray = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = small.getPixel(x, y);
        gray[y * w + x] = ((p.r * 299 + p.g * 587 + p.b * 114) / 1000).round().clamp(0, 255);
      }
    }
    final thr = _otsu(gray);
    final markers = _findMarkers(gray, w, h, thr);
    if (markers == null) {
      return OmrResult.fail('Could not find the 4 black corner squares. Fit the whole sheet inside the frame, on a flat surface with good light.');
    }

    var corners = markers; // tl, tr, br, bl in image space
    var hom = _Homography.fromFrame(corners);
    final top = _fill(gray, w, h, thr, hom, _rectPoints(SheetLayout.barX0, SheetLayout.barY0, SheetLayout.barX1, SheetLayout.barY1));
    final bottom = _fill(gray, w, h, thr, hom, _rectPoints(SheetLayout.frameW - SheetLayout.barX1, SheetLayout.frameH - SheetLayout.barY1,
        SheetLayout.frameW - SheetLayout.barX0, SheetLayout.frameH - SheetLayout.barY0));
    // The orientation bar must show on one edge; if not, the corners found are not the markers.
    if (max(top, bottom) < 0.6) {
      return OmrResult.fail('The sheet was not found clearly. Fit all 4 black squares inside the frame and hold the phone straight above the paper.');
    }
    if (bottom > top + 0.2) {
      corners = [corners[2], corners[3], corners[0], corners[1]];
      hom = _Homography.fromFrame(corners);
    }

    // Learner number
    int? digit(int col) {
      var best = -1;
      var bestFill = 0.0, second = 0.0;
      for (var d = 0; d < 10; d++) {
        final c = SheetLayout.idBubble(col, d);
        final f = _bubbleFill(gray, w, h, thr, hom, c, SheetLayout.idR);
        if (f > bestFill) {
          second = bestFill;
          bestFill = f;
          best = d;
        } else if (f > second) {
          second = f;
        }
      }
      if (bestFill < _shaded || second > bestFill * 0.75) return null;
      return best;
    }

    final tens = digit(0), ones = digit(1);
    final learnerNum = (tens == null && ones == null) ? null : (tens ?? 0) * 10 + (ones ?? 0);

    final n = min(req.items, SheetLayout.maxItems);
    final answers = <int>[];
    final fills = <List<double>>[];
    var margins = 0.0;
    for (var i = 0; i < n; i++) {
      final f = [for (var c = 0; c < SheetLayout.choices; c++) _bubbleFill(gray, w, h, thr, hom, SheetLayout.itemBubble(i, c), SheetLayout.bubbleR)];
      fills.add(f);
      final sorted = [...f]..sort((a, b) => b.compareTo(a));
      final best = f.indexOf(sorted[0]);
      if (sorted[0] < _shaded) {
        answers.add(-1);
        margins += _shaded - sorted[0];
      } else if (sorted[1] >= _shaded && sorted[1] > sorted[0] * 0.7) {
        answers.add(-2);
      } else {
        answers.add(best);
        margins += sorted[0] - sorted[1];
      }
    }
    final confidence = n == 0 ? 0.0 : (margins / n).clamp(0, 1).toDouble();
    return OmrResult(ok: true, learnerNum: learnerNum, answers: answers, fills: fills, confidence: confidence);
  } catch (e) {
    return OmrResult.fail('Reading failed: $e');
  }
}

int _otsu(Uint8List gray) {
  final hist = List<int>.filled(256, 0);
  for (final v in gray) {
    hist[v]++;
  }
  final total = gray.length;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = 0.0, thr = 127;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      thr = t;
    }
  }
  return thr;
}

class _Blob {
  int count = 0, minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
  double sx = 0, sy = 0;
  double get cx => sx / count;
  double get cy => sy / count;
}

/// Finds the four solid square markers: dark, square, almost fully filled blobs nearest each corner.
List<Pt>? _findMarkers(Uint8List gray, int w, int h, int thr) {
  final labels = Int32List(w * h);
  final stack = Int32List(w * h);
  final blobs = <_Blob>[];
  final area = w * h;
  for (var start = 0; start < area; start++) {
    if (labels[start] != 0 || gray[start] >= thr) continue;
    final b = _Blob();
    blobs.add(b);
    final id = blobs.length;
    var sp = 0;
    stack[sp++] = start;
    labels[start] = id;
    while (sp > 0) {
      final idx = stack[--sp];
      final x = idx % w, y = idx ~/ w;
      b.count++;
      b.sx += x;
      b.sy += y;
      if (x < b.minX) b.minX = x;
      if (x > b.maxX) b.maxX = x;
      if (y < b.minY) b.minY = y;
      if (y > b.maxY) b.maxY = y;
      if (x > 0 && labels[idx - 1] == 0 && gray[idx - 1] < thr) {
        labels[idx - 1] = id;
        stack[sp++] = idx - 1;
      }
      if (x < w - 1 && labels[idx + 1] == 0 && gray[idx + 1] < thr) {
        labels[idx + 1] = id;
        stack[sp++] = idx + 1;
      }
      if (y > 0 && labels[idx - w] == 0 && gray[idx - w] < thr) {
        labels[idx - w] = id;
        stack[sp++] = idx - w;
      }
      if (y < h - 1 && labels[idx + w] == 0 && gray[idx + w] < thr) {
        labels[idx + w] = id;
        stack[sp++] = idx + w;
      }
    }
  }
  final minArea = area * 0.00012, maxArea = area * 0.012;
  final cands = blobs.where((b) {
    if (b.count < minArea || b.count > maxArea) return false;
    final bw = b.maxX - b.minX + 1, bh = b.maxY - b.minY + 1;
    final aspect = bw / bh;
    if (aspect < 0.6 || aspect > 1.6) return false;
    // A tilted square fills less of its bounding box, so this test is loose; the checks below do the rest.
    return b.count / (bw * bh) >= 0.6;
  }).toList();
  if (cands.length < 4) return null;

  // Markers are the biggest solid squares; drop smaller blobs such as shaded bubbles.
  cands.sort((a, b) => b.count.compareTo(a.count));
  final ref = cands[3].count;
  final big = cands.where((b) => b.count >= ref * 0.4).toList();

  // Corners by diagonal extremes: TL = min(x+y), TR = max(x-y), BR = max(x+y), BL = min(x-y).
  _Blob pick(double Function(_Blob) f, bool wantMax) =>
      big.reduce((best, b) => (wantMax ? f(b) > f(best) : f(b) < f(best)) ? b : best);
  final picked = [
    pick((b) => b.cx + b.cy, false),
    pick((b) => b.cx - b.cy, true),
    pick((b) => b.cx + b.cy, true),
    pick((b) => b.cx - b.cy, false),
  ];
  if (picked.toSet().length < 4) return null;
  final pts = picked.map((b) => Pt(b.cx, b.cy)).toList();

  // Sanity: the quadrilateral must be reasonably large, sheet-shaped and not folded.
  double dist(Pt a, Pt b) => sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
  final topSide = dist(pts[0], pts[1]), bottomSide = dist(pts[3], pts[2]);
  final leftSide = dist(pts[0], pts[3]), rightSide = dist(pts[1], pts[2]);
  if (max(topSide, bottomSide) < w * 0.3 || max(leftSide, rightSide) < h * 0.3) return null;
  if (max(topSide, bottomSide) > min(topSide, bottomSide) * 1.8) return null;
  if (max(leftSide, rightSide) > min(leftSide, rightSide) * 1.8) return null;
  final ratio = (leftSide + rightSide) / (topSide + bottomSide);
  final expected = SheetLayout.frameH / SheetLayout.frameW;
  if (ratio < expected * 0.6 || ratio > expected * 1.6) return null;

  // Each blob must be about as big as a 9 mm marker would look at that corner.
  // A shaded bubble is about 4 times smaller, so a wrong pick is rejected here.
  final hom = _Homography.fromFrame(pts);
  const frame = [Pt(0, 0), Pt(SheetLayout.frameW, 0), Pt(SheetLayout.frameW, SheetLayout.frameH), Pt(0, SheetLayout.frameH)];
  const half = SheetLayout.marker / 2;
  for (var i = 0; i < 4; i++) {
    final c = frame[i];
    final q = [hom.map(c.x - half, c.y - half), hom.map(c.x + half, c.y - half), hom.map(c.x + half, c.y + half), hom.map(c.x - half, c.y + half)];
    var a2 = 0.0;
    for (var j = 0; j < 4; j++) {
      a2 += q[j].x * q[(j + 1) % 4].y - q[(j + 1) % 4].x * q[j].y;
    }
    final expectedArea = a2.abs() / 2;
    if (expectedArea <= 0) return null;
    final r = picked[i].count / expectedArea;
    if (r < 0.5 || r > 1.8) return null;
  }
  return pts;
}

class _Homography {
  final List<double> h;
  _Homography(this.h);

  /// Maps sheet millimetres (frame space) to image pixels.
  factory _Homography.fromFrame(List<Pt> dst) {
    final src = [Pt(0, 0), Pt(SheetLayout.frameW, 0), Pt(SheetLayout.frameW, SheetLayout.frameH), Pt(0, SheetLayout.frameH)];
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final sx = src[i].x, sy = src[i].y, dx = dst[i].x, dy = dst[i].y;
      a[2 * i] = [sx, sy, 1, 0, 0, 0, -dx * sx, -dx * sy, dx];
      a[2 * i + 1] = [0, 0, 0, sx, sy, 1, -dy * sx, -dy * sy, dy];
    }
    // Gaussian elimination with partial pivoting.
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var r = col + 1; r < 8; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      final pv = a[col][col];
      if (pv.abs() < 1e-12) throw StateError('Corner markers are not usable.');
      for (var c = col; c < 9; c++) {
        a[col][c] /= pv;
      }
      for (var r = 0; r < 8; r++) {
        if (r == col) continue;
        final f = a[r][col];
        if (f == 0) continue;
        for (var c = col; c < 9; c++) {
          a[r][c] -= f * a[col][c];
        }
      }
    }
    return _Homography([for (var i = 0; i < 8; i++) a[i][8]]);
  }

  Pt map(double x, double y) {
    final d = h[6] * x + h[7] * y + 1;
    return Pt((h[0] * x + h[1] * y + h[2]) / d, (h[3] * x + h[4] * y + h[5]) / d);
  }
}

List<Pt> _rectPoints(double x0, double y0, double x1, double y1) {
  final pts = <Pt>[];
  for (var y = y0; y <= y1; y += 0.5) {
    for (var x = x0; x <= x1; x += 0.8) {
      pts.add(Pt(x, y));
    }
  }
  return pts;
}

double _fill(Uint8List gray, int w, int h, int thr, _Homography hom, List<Pt> pts) {
  var dark = 0, total = 0;
  for (final p in pts) {
    final q = hom.map(p.x, p.y);
    final x = q.x.round(), y = q.y.round();
    if (x < 0 || y < 0 || x >= w || y >= h) continue;
    total++;
    if (gray[y * w + x] < thr) dark++;
  }
  return total == 0 ? 0 : dark / total;
}

/// Share of dark pixels inside the inner 65% of a bubble (the printed outline is excluded).
double _bubbleFill(Uint8List gray, int w, int h, int thr, _Homography hom, Pt c, double rMm) {
  final centre = hom.map(c.x, c.y);
  final edge = hom.map(c.x + rMm, c.y);
  final rPx = sqrt(pow(edge.x - centre.x, 2) + pow(edge.y - centre.y, 2)) * 0.65;
  if (rPx < 1) return 0;
  final r2 = rPx * rPx;
  var dark = 0, total = 0;
  final x0 = (centre.x - rPx).floor(), x1 = (centre.x + rPx).ceil();
  final y0 = (centre.y - rPx).floor(), y1 = (centre.y + rPx).ceil();
  // Slightly stricter than the global threshold so pencil shading and soft shadows separate.
  final limit = thr + 10;
  for (var y = y0; y <= y1; y++) {
    if (y < 0 || y >= h) continue;
    for (var x = x0; x <= x1; x++) {
      if (x < 0 || x >= w) continue;
      final dx = x - centre.x, dy = y - centre.y;
      if (dx * dx + dy * dy > r2) continue;
      total++;
      if (gray[y * w + x] < limit) dark++;
    }
  }
  return total == 0 ? 0 : dark / total;
}
