import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'sheet_layout.dart';

/// Optical mark reading for KlaseKo answer sheets. Pure Dart, runs fully offline in a
/// background isolate: `compute(readAnswerSheet, OmrRequest(bytes, items))`.
///
/// Design goal: never return a wrong answer silently. Every step either reads the sheet with
/// confidence, flags an item for the teacher to check, or refuses the photo and asks for a retake.
///  1. Lighting is flattened (shadows and uneven light removed).
///  2. The corner squares are found in any rotation; the orientation bar tells top from bottom.
///     If one corner is hidden, it is estimated, but only trusted if step 3 confirms it exactly.
///  3. Each item is locked onto its printed bubble outlines, which corrects small position errors.
///     If the outlines are not found where expected, the photo is refused.
///  4. Marks are judged against this sheet's own paper level and this learner's own shading, so
///     light pencil and small dots are read, and erasures or stray dots are flagged for review.
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

  /// Items the teacher should look at (faint, erased, doubled or stray marks).
  final List<int> review;

  /// Darkness (0..1) of every bubble, items x 4.
  final List<List<double>> fills;

  /// True when one corner square was hidden and its position was estimated (and then confirmed).
  final bool estimatedCorner;

  const OmrResult({
    required this.ok,
    this.error,
    this.learnerNum,
    this.answers = const [],
    this.review = const [],
    this.fills = const [],
    this.estimatedCorner = false,
  });

  factory OmrResult.fail(String message) => OmrResult(ok: false, error: message);
}

const _retakeCorners = 'The sheet was not found clearly. Fit all 4 black corner squares in the frame, keep the paper flat, and try again.';
const _retakeOutlines = 'The bubbles did not line up with the sheet. Hold the phone straight above the paper, keep it flat, and try again.';

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
    final raw = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = small.getPixel(x, y);
        raw[y * w + x] = ((p.r * 299 + p.g * 587 + p.b * 114) / 1000).round().clamp(0, 255);
      }
    }
    final g = _flatten(raw, w, h);
    final thr = _otsu(g);
    final sheet = _findSheet(g, w, h, thr);
    if (sheet == null) return OmrResult.fail(_retakeCorners);
    final hom = sheet.hom;
    final img2 = _Img(g, w, h);

    final n = min(req.items, SheetLayout.maxItems);
    final rows = <List<double>>[];
    final ringScores = <double>[];
    final offsets = <double>[];
    for (var i = 0; i < n; i++) {
      final centers = [for (var c = 0; c < SheetLayout.choices; c++) SheetLayout.itemBubble(i, c)];
      final reg = _register(img2, hom, centers, SheetLayout.bubbleR);
      ringScores.add(reg.score);
      offsets.add(sqrt(reg.dx * reg.dx + reg.dy * reg.dy));
      rows.add([for (final c in centers) _darknessAt(img2, hom, c.x + reg.dx, c.y + reg.dy, SheetLayout.bubbleR)]);
    }
    if (n > 0) {
      final ringMed = _median(ringScores);
      final weak = ringScores.where((v) => v < ringMed * 0.4).length;
      if (ringMed < 0.06 || weak > n * 0.15) return OmrResult.fail(_retakeOutlines);
      final drift = offsets.where((d) => d > 1.25).length;
      if (sheet.estimated && (weak > 0 || drift > 0)) return OmrResult.fail(_retakeCorners);
      if (drift > n * 0.1) return OmrResult.fail(_retakeOutlines);
    }

    final cls = _classify(rows);
    final review = <int>{...cls.review};
    if (n > 0) {
      final ringMed = _median(ringScores);
      for (var i = 0; i < n; i++) {
        if (ringScores[i] < ringMed * 0.4) review.add(i);
      }
    }

    // Learner number: each digit column is registered and read like an item with 10 choices.
    int? digit(int col) {
      final centers = [for (var d = 0; d < 10; d++) SheetLayout.idBubble(col, d)];
      final reg = _register(img2, hom, centers, SheetLayout.idR);
      final f = [for (final c in centers) _darknessAt(img2, hom, c.x + reg.dx, c.y + reg.dy, SheetLayout.idR)];
      final sorted = [...f]..sort((a, b) => b.compareTo(a));
      final m = sorted.first;
      if (m <= 0.15 || sorted[1] >= m * 0.6) return null;
      return f.indexOf(m);
    }

    final tens = digit(0), ones = digit(1);
    final learnerNum = (tens == null && ones == null) ? null : (tens ?? 0) * 10 + (ones ?? 0);

    return OmrResult(
      ok: true,
      learnerNum: learnerNum,
      answers: cls.answers,
      review: review.toList()..sort(),
      fills: rows,
      estimatedCorner: sheet.estimated,
    );
  } catch (e) {
    return OmrResult.fail('Reading failed: $e');
  }
}

// ---------------------------------------------------------------------------
// Image helpers
// ---------------------------------------------------------------------------

class _Img {
  final Uint8List g;
  final int w;
  final int h;
  const _Img(this.g, this.w, this.h);

  /// 0 = paper, 1 = black.
  double dark(int x, int y) => (x < 0 || y < 0 || x >= w || y >= h) ? 0 : (230 - min(230, g[y * w + x])) / 230;
}

/// Divides by a paper-brightness map (80th percentile per 32 px cell, smoothed and interpolated),
/// which removes shadows and uneven light.
Uint8List _flatten(Uint8List g, int w, int h) {
  const cs = 32;
  final gw = (w / cs).ceil(), gh = (h / cs).ceil();
  final grid = Float64List(gw * gh);
  final hist = Int32List(256);
  for (var gy = 0; gy < gh; gy++) {
    for (var gx = 0; gx < gw; gx++) {
      hist.fillRange(0, 256, 0);
      var cnt = 0;
      for (var y = gy * cs; y < min(h, gy * cs + cs); y++) {
        for (var x = gx * cs; x < min(w, gx * cs + cs); x++) {
          hist[g[y * w + x]]++;
          cnt++;
        }
      }
      var acc = 0, v = 255;
      final target = cnt * 0.8;
      for (var i = 0; i < 256; i++) {
        acc += hist[i];
        if (acc >= target) {
          v = i;
          break;
        }
      }
      grid[gy * gw + gx] = max(v, 40).toDouble();
    }
  }
  final g2 = Float64List(gw * gh);
  for (var gy = 0; gy < gh; gy++) {
    for (var gx = 0; gx < gw; gx++) {
      var m = 0.0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final yy = gy + dy, xx = gx + dx;
          if (yy >= 0 && yy < gh && xx >= 0 && xx < gw) m = max(m, grid[yy * gw + xx]);
        }
      }
      g2[gy * gw + gx] = m;
    }
  }
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final fy = min(gh - 1.001, max(0.0, y / cs - 0.5));
    final y0 = fy.floor();
    final ty = fy - y0;
    final y1 = min(gh - 1, y0 + 1);
    for (var x = 0; x < w; x++) {
      final fx = min(gw - 1.001, max(0.0, x / cs - 0.5));
      final x0 = fx.floor();
      final tx = fx - x0;
      final x1 = min(gw - 1, x0 + 1);
      final bg = (g2[y0 * gw + x0] * (1 - tx) + g2[y0 * gw + x1] * tx) * (1 - ty) + (g2[y1 * gw + x0] * (1 - tx) + g2[y1 * gw + x1] * tx) * ty;
      out[y * w + x] = (g[y * w + x] * 230 / bg).round().clamp(0, 255);
    }
  }
  return out;
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

double _median(List<double> a) {
  final s = [...a]..sort();
  return s[s.length ~/ 2];
}

// ---------------------------------------------------------------------------
// Finding the sheet
// ---------------------------------------------------------------------------

class _Blob {
  int count = 0, minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
  double sx = 0, sy = 0;
  double get cx => sx / count;
  double get cy => sy / count;
}

List<_Blob> _blobs(Uint8List g, int w, int h, int thr) {
  final labels = Int32List(w * h);
  final stack = Int32List(w * h);
  final blobs = <_Blob>[];
  for (var start = 0; start < w * h; start++) {
    if (labels[start] != 0 || g[start] >= thr) continue;
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
      if (x > 0 && labels[idx - 1] == 0 && g[idx - 1] < thr) {
        labels[idx - 1] = id;
        stack[sp++] = idx - 1;
      }
      if (x < w - 1 && labels[idx + 1] == 0 && g[idx + 1] < thr) {
        labels[idx + 1] = id;
        stack[sp++] = idx + 1;
      }
      if (y > 0 && labels[idx - w] == 0 && g[idx - w] < thr) {
        labels[idx - w] = id;
        stack[sp++] = idx - w;
      }
      if (y < h - 1 && labels[idx + w] == 0 && g[idx + w] < thr) {
        labels[idx + w] = id;
        stack[sp++] = idx + w;
      }
    }
  }
  return blobs;
}

class _Sheet {
  final _Homography hom;
  final double score;
  final bool estimated;
  _Sheet(this.hom, this.score, this.estimated);
}

class _Cand {
  final Pt p;
  final int? area; // null for an estimated corner
  _Cand(this.p, this.area);
}

const _frame = [Pt(0, 0), Pt(SheetLayout.frameW, 0), Pt(SheetLayout.frameW, SheetLayout.frameH), Pt(0, SheetLayout.frameH)];

double _polyArea(List<Pt> q) {
  var a = 0.0;
  for (var j = 0; j < q.length; j++) {
    final p1 = q[j], p2 = q[(j + 1) % q.length];
    a += p1.x * p2.y - p2.x * p1.y;
  }
  return a.abs() / 2;
}

List<_Cand> _clockwise(List<_Cand> pts) {
  final cx = pts.fold<double>(0, (a, p) => a + p.p.x) / pts.length;
  final cy = pts.fold<double>(0, (a, p) => a + p.p.y) / pts.length;
  return [...pts]..sort((a, b) => atan2(a.p.y - cy, a.p.x - cx).compareTo(atan2(b.p.y - cy, b.p.x - cx)));
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

final _barPts = _rectPoints(SheetLayout.barX0, SheetLayout.barY0, SheetLayout.barX1, SheetLayout.barY1);
final _barMirrorPts = _rectPoints(SheetLayout.frameW - SheetLayout.barX1, SheetLayout.frameH - SheetLayout.barY1,
    SheetLayout.frameW - SheetLayout.barX0, SheetLayout.frameH - SheetLayout.barY0);

double _fillPts(Uint8List g, int w, int h, int thr, _Homography hom, List<Pt> pts) {
  var dark = 0, total = 0;
  for (final p in pts) {
    final q = hom.map(p.x, p.y);
    final x = q.x.round(), y = q.y.round();
    if (x < 0 || y < 0 || x >= w || y >= h) continue;
    total++;
    if (g[y * w + x] < thr) dark++;
  }
  return total == 0 ? 0 : dark / total;
}

/// Scores one assignment of image points to the sheet corners (tl, tr, br, bl).
_Sheet? _scoreQuad(Uint8List g, int w, int h, int thr, List<_Cand> quad, bool estimated) {
  final hom = _tryHomography([for (final c in quad) c.p]);
  if (hom == null) return null;
  var sizeErr = 0.0;
  const half = SheetLayout.marker / 2;
  for (var i = 0; i < 4; i++) {
    final area = quad[i].area;
    if (area == null) continue;
    final c = _frame[i];
    final expected = _polyArea([
      hom.map(c.x - half, c.y - half),
      hom.map(c.x + half, c.y - half),
      hom.map(c.x + half, c.y + half),
      hom.map(c.x - half, c.y + half),
    ]);
    if (expected <= 0) return null;
    final r = area / expected;
    if (r < 0.45 || r > 2.0) return null;
    sizeErr += log(r).abs();
  }
  final bar = _fillPts(g, w, h, thr, hom, _barPts);
  final mirror = _fillPts(g, w, h, thr, hom, _barMirrorPts);
  if (bar < 0.55 || mirror > 0.35) return null;
  final score = bar - mirror - sizeErr * 0.2 - (estimated ? 0.3 : 0);
  return _Sheet(hom, score, estimated);
}

_Sheet? _findSheet(Uint8List g, int w, int h, int thr) {
  final area = w * h;
  final blobs = _blobs(g, w, h, thr).where((b) {
    if (b.count < area * 0.00008 || b.count > area * 0.015) return false;
    final bw = b.maxX - b.minX + 1, bh = b.maxY - b.minY + 1;
    final ar = bw / bh;
    return ar > 0.5 && ar < 2 && b.count / (bw * bh) >= 0.5;
  }).toList()
    ..sort((a, b) => b.count.compareTo(a.count));
  final cands = [for (final b in blobs.take(12)) _Cand(Pt(b.cx, b.cy), b.count)];

  _Sheet? best;
  void tryQuad(List<_Cand> ordered, bool estimated) {
    for (var r = 0; r < 4; r++) {
      final quad = [for (var k = 0; k < 4; k++) ordered[(k + r) % 4]];
      final s = _scoreQuad(g, w, h, thr, quad, estimated);
      if (s != null && (best == null || s.score > best!.score)) best = s;
    }
  }

  // Four real corner squares.
  for (var a = 0; a < cands.length; a++) {
    for (var b = a + 1; b < cands.length; b++) {
      for (var c = b + 1; c < cands.length; c++) {
        for (var d = c + 1; d < cands.length; d++) {
          final ordered = _clockwise([cands[a], cands[b], cands[c], cands[d]]);
          if (_polyArea([for (final o in ordered) o.p]) < area * 0.08) continue;
          tryQuad(ordered, false);
        }
      }
    }
  }
  if (best != null) return best;

  // Three corner squares: estimate the hidden one (parallelogram). It is only accepted later if
  // every item's printed outlines line up exactly.
  for (var a = 0; a < cands.length; a++) {
    for (var b = a + 1; b < cands.length; b++) {
      for (var c = b + 1; c < cands.length; c++) {
        final tri = [cands[a], cands[b], cands[c]];
        for (var k = 0; k < 3; k++) {
          final m = tri[k], o1 = tri[(k + 1) % 3], o2 = tri[(k + 2) % 3];
          final fourth = _Cand(Pt(o1.p.x + o2.p.x - m.p.x, o1.p.y + o2.p.y - m.p.y), null);
          final ordered = _clockwise([m, o1, fourth, o2]);
          if (_polyArea([for (final o in ordered) o.p]) < area * 0.08) continue;
          tryQuad(ordered, true);
        }
      }
    }
  }
  return best;
}

_Homography? _tryHomography(List<Pt> dst) {
  try {
    return _Homography.fromFrame(dst);
  } catch (_) {
    return null;
  }
}

class _Homography {
  final List<double> h;
  _Homography(this.h);

  /// Maps sheet millimetres (frame space) to image pixels.
  factory _Homography.fromFrame(List<Pt> dst) {
    final a = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final sx = _frame[i].x, sy = _frame[i].y, dx = dst[i].x, dy = dst[i].y;
      a[2 * i] = [sx, sy, 1, 0, 0, 0, -dx * sx, -dx * sy, dx];
      a[2 * i + 1] = [0, 0, 0, sx, sy, 1, -dy * sx, -dy * sy, dy];
    }
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var r = col + 1; r < 8; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;
      final pv = a[col][col];
      if (pv.abs() < 1e-12) throw StateError('Corner points are not usable.');
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

// ---------------------------------------------------------------------------
// Locking onto the printed outlines and reading the marks
// ---------------------------------------------------------------------------

double _sample(_Img im, _Homography hom, double x, double y) {
  final q = hom.map(x, y);
  return im.dark(q.x.round(), q.y.round());
}

final _cosTable = [for (var k = 0; k < 24; k++) cos(k / 24 * 2 * pi)];
final _sinTable = [for (var k = 0; k < 24; k++) sin(k / 24 * 2 * pi)];

/// How much darker the printed outline circle is than a circle just outside it.
double _ringContrast(_Img im, _Homography hom, double cx, double cy, double r) {
  var a = 0.0, b = 0.0;
  for (var k = 0; k < 24; k++) {
    final c = _cosTable[k], s = _sinTable[k];
    a += max(_sample(im, hom, cx + r * c, cy + r * s),
        max(_sample(im, hom, cx + (r - 0.25) * c, cy + (r - 0.25) * s), _sample(im, hom, cx + (r + 0.25) * c, cy + (r + 0.25) * s)));
    b += _sample(im, hom, cx + (r + 0.9) * c, cy + (r + 0.9) * s);
  }
  return (a - b) / 24;
}

class _Reg {
  final double dx, dy, score;
  const _Reg(this.dx, this.dy, this.score);
}

/// Finds the offset (mm) that best lines up a group of bubbles with their printed outlines.
_Reg _register(_Img im, _Homography hom, List<Pt> centers, double r) {
  double score(double dx, double dy) {
    var s = 0.0;
    for (final c in centers) {
      s += _ringContrast(im, hom, c.x + dx, c.y + dy, r);
    }
    return s / centers.length;
  }

  var best = _Reg(0, 0, score(0, 0));
  for (var dy = -2.0; dy <= 2.001; dy += 0.5) {
    for (var dx = -2.0; dx <= 2.001; dx += 0.5) {
      final v = score(dx, dy);
      if (v > best.score) best = _Reg(dx, dy, v);
    }
  }
  final coarse = best;
  for (var dy = -0.375; dy <= 0.376; dy += 0.125) {
    for (var dx = -0.375; dx <= 0.376; dx += 0.125) {
      final v = score(coarse.dx + dx, coarse.dy + dy);
      if (v > best.score) best = _Reg(coarse.dx + dx, coarse.dy + dy, v);
    }
  }
  return best;
}

/// Mean darkness of a bubble's inner disk (62% of the radius, so the printed outline is excluded).
double _darknessAt(_Img im, _Homography hom, double cx, double cy, double r) {
  final centre = hom.map(cx, cy);
  final edge = hom.map(cx + r, cy);
  final rp = sqrt(pow(edge.x - centre.x, 2) + pow(edge.y - centre.y, 2)) * 0.62;
  final r2 = rp * rp;
  var s = 0.0;
  var t = 0;
  for (var y = (centre.y - rp).floor(); y <= (centre.y + rp).ceil(); y++) {
    for (var x = (centre.x - rp).floor(); x <= (centre.x + rp).ceil(); x++) {
      final dx = x - centre.x, dy = y - centre.y;
      if (dx * dx + dy * dy > r2) continue;
      s += im.dark(x, y);
      t++;
    }
  }
  return t == 0 ? 0 : s / t;
}

class _Classified {
  final List<int> answers;
  final List<int> review;
  _Classified(this.answers, this.review);
}

/// Decides each item's answer using this sheet's own statistics.
_Classified _classify(List<List<double>> rows) {
  const minMark = 0.05;
  if (rows.isEmpty) return _Classified(const [], const []);
  // Paper level and noise come from each item's three lightest bubbles, which are almost always unmarked.
  final lights = <double>[for (final f in rows) ...([...f]..sort()).take(3)];
  final base = _median(lights);
  final mad = _median([for (final v in lights) (v - base).abs()]) * 1.4826 + 0.003;
  final tops = [for (final f in rows) f.reduce(max) - base];
  final floor = max(minMark, 6 * mad);
  final answered = tops.where((t) => t >= floor).toList()..sort();
  // How dark this learner shades: the median darkest bubble among answered items.
  final markLevel = answered.isEmpty ? 0.0 : answered[answered.length ~/ 2];
  final thr = base + max(floor, min(0.45 * markLevel, 0.12));
  // With few answered items the learner's shading cannot be learned, so light marks are shown for checking.
  final fewMarks = answered.length < rows.length * 0.3;
  final level = max(markLevel, thr - base);

  final answers = <int>[];
  final review = <int>[];
  for (var i = 0; i < rows.length; i++) {
    final f = rows[i];
    final ex = [for (final v in f) v - base];
    final order = List<int>.generate(ex.length, (k) => k)..sort((a, b) => ex[b].compareTo(ex[a]));
    final top = ex[order[0]], second = ex[order[1]];
    final marked = f.where((v) => v >= thr).length;
    final others = [for (final k in order.skip(1)) ex[k]];
    final othersMean = others.reduce((a, b) => a + b) / others.length;
    final othersSpread = others.reduce(max) - others.reduce(min) + 0.005;
    var flag = false;
    if (marked == 0) {
      // Read as blank, but one bubble stands out from the other three: show it to the teacher.
      final standsOut = top - othersMean > 0.03 && top - othersMean > 2.2 * othersSpread;
      answers.add(-1);
      flag = top > (thr - base) * 0.6 || standsOut;
    } else if (marked == 1 || top >= second * 2.2) {
      // Unsure when a second bubble carries a real mark (erasure or stray dot), the answer is much lighter
      // than this learner's usual marks, or the sheet has too few marks to know what a light mark means.
      final secondMarked = second > max(0.5 * (thr - base), max(4 * mad, 0.025));
      final light = fewMarks && top < 0.35;
      answers.add(order[0]);
      flag = second > top * 0.45 || top < level * 0.55 || secondMarked || light;
    } else {
      answers.add(-2);
      flag = true;
    }
    if (flag) review.add(i);
  }
  return _Classified(answers, review);
}
