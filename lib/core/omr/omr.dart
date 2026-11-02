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
///  2. Eight coded markers (corners and edge middles) are found in any rotation. Each one says which
///     marker it is and which way is up, so any two visible markers place the whole sheet. Parts of
///     the paper may be outside the photo as long as every bubble is inside it.
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

  /// True when only two markers were visible (the fit was then confirmed on every item).
  final bool estimatedCorner;

  /// True when the learner shaded very lightly. Erasures can then be as dark as real answers,
  /// so the teacher must compare the whole sheet with the paper before saving.
  final bool lightMarks;

  const OmrResult({
    required this.ok,
    this.error,
    this.learnerNum,
    this.answers = const [],
    this.review = const [],
    this.fills = const [],
    this.estimatedCorner = false,
    this.lightMarks = false,
  });

  factory OmrResult.fail(String message) => OmrResult(ok: false, error: message);
}

const _retakeMarkers = 'The answer sheet was not found. Make sure the bubbles and at least two of the black markers are in the photo, in good light, then try again.';
const _retakeFit = 'The sheet could not be lined up. Keep the paper flat and the phone steady, then try again.';
const _outsidePhoto = 'Part of the answers is outside the photo. Move the phone back a little so all the bubbles and the learner number are in view.';
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
    final hom = sheet.hom;
    if (hom == null) return OmrResult.fail(sheet.inconsistent ? _retakeFit : _retakeMarkers);
    final img2 = _Img(g, w, h);

    final n = min(req.items, SheetLayout.maxItems);
    // Every bubble that will be read must be inside the photo.
    bool inside(Pt p) {
      final q = hom.map(p.x, p.y);
      return q.x >= 3 && q.y >= 3 && q.x <= w - 4 && q.y <= h - 4;
    }

    for (var i = 0; i < n; i++) {
      if (!inside(SheetLayout.itemBubble(i, 0)) || !inside(SheetLayout.itemBubble(i, SheetLayout.choices - 1))) return OmrResult.fail(_outsidePhoto);
    }
    for (final col in const [0, 1]) {
      if (!inside(SheetLayout.idBubble(col, 0)) || !inside(SheetLayout.idBubble(col, 9))) return OmrResult.fail(_outsidePhoto);
    }
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
      if (sheet.estimated && (weak > 0 || drift > 0)) return OmrResult.fail(_retakeFit);
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
      lightMarks: cls.lightMarks,
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
// Finding the sheet: coded markers
// ---------------------------------------------------------------------------

class _Blob {
  final int id;
  int count = 0, minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
  double sx = 0, sy = 0;
  _Blob(this.id);
  double get cx => sx / count;
  double get cy => sy / count;
}

class _Labeled {
  final Int32List labels;
  final List<_Blob> blobs;
  _Labeled(this.labels, this.blobs);
}

_Labeled _label(Uint8List g, int w, int h, int thr) {
  final labels = Int32List(w * h);
  final stack = Int32List(w * h);
  final blobs = <_Blob>[];
  for (var start = 0; start < w * h; start++) {
    if (labels[start] != 0 || g[start] >= thr) continue;
    final b = _Blob(blobs.length + 1);
    blobs.add(b);
    var sp = 0;
    stack[sp++] = start;
    labels[start] = b.id;
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
        labels[idx - 1] = b.id;
        stack[sp++] = idx - 1;
      }
      if (x < w - 1 && labels[idx + 1] == 0 && g[idx + 1] < thr) {
        labels[idx + 1] = b.id;
        stack[sp++] = idx + 1;
      }
      if (y > 0 && labels[idx - w] == 0 && g[idx - w] < thr) {
        labels[idx - w] = b.id;
        stack[sp++] = idx - w;
      }
      if (y < h - 1 && labels[idx + w] == 0 && g[idx + w] < thr) {
        labels[idx + w] = b.id;
        stack[sp++] = idx + w;
      }
    }
  }
  return _Labeled(labels, blobs);
}

List<Pt> _clockwise(List<Pt> pts) {
  final cx = pts.fold<double>(0, (a, p) => a + p.x) / pts.length;
  final cy = pts.fold<double>(0, (a, p) => a + p.y) / pts.length;
  return [...pts]..sort((a, b) => atan2(a.y - cy, a.x - cx).compareTo(atan2(b.y - cy, b.x - cx)));
}

/// Four corners of a square-ish blob: the boundary point farthest from the centre, the point
/// farthest from that one, then the farthest points on each side of that diagonal.
List<Pt>? _quadCorners(Int32List labels, int w, _Blob b) {
  final pts = <Pt>[];
  for (var y = b.minY; y <= b.maxY; y++) {
    for (var x = b.minX; x <= b.maxX; x++) {
      final i = y * w + x;
      if (labels[i] != b.id) continue;
      if (labels[i - 1] != b.id || labels[i + 1] != b.id || labels[i - w] != b.id || labels[i + w] != b.id) {
        pts.add(Pt(x.toDouble(), y.toDouble()));
      }
    }
  }
  if (pts.length < 8) return null;
  final cx = b.cx, cy = b.cy;
  var p1 = pts.first;
  var d = -1.0;
  for (final p in pts) {
    final v = (p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy);
    if (v > d) {
      d = v;
      p1 = p;
    }
  }
  var p3 = p1;
  d = -1;
  for (final p in pts) {
    final v = (p.x - p1.x) * (p.x - p1.x) + (p.y - p1.y) * (p.y - p1.y);
    if (v > d) {
      d = v;
      p3 = p;
    }
  }
  Pt? p2, p4;
  var dp = 0.0, dn = 0.0;
  for (final p in pts) {
    final v = (p3.x - p1.x) * (p.y - p1.y) - (p3.y - p1.y) * (p.x - p1.x);
    if (v > dp) {
      dp = v;
      p2 = p;
    }
    if (v < dn) {
      dn = v;
      p4 = p;
    }
  }
  if (p2 == null || p4 == null) return null;
  return _clockwise([p1, p2, p3, p4]);
}

class _Marker {
  final int id;
  final List<Pt> corners; // image points for the marker's own TL, TR, BR, BL
  final int dist;
  _Marker(this.id, this.corners, this.dist);
}

const _unitSquare = [Pt(0, 0), Pt(6, 0), Pt(6, 6), Pt(0, 6)];

/// Reads a candidate quad as a coded marker, trying its four possible starting corners.
_Marker? _decodeMarker(Uint8List g, int w, int h, int thr, List<Pt> quad) {
  _Marker? best;
  for (var s = 0; s < 4; s++) {
    final q = [for (var k = 0; k < 4; k++) quad[(k + s) % 4]];
    final hm = _solveHomography(_unitSquare, q);
    if (hm == null) continue;
    double cell(int r, int c) {
      var dark = 0, t = 0;
      for (final oy in const [0.3, 0.5, 0.7]) {
        for (final ox in const [0.3, 0.5, 0.7]) {
          final p = hm.map(c + ox, r + oy);
          final x = p.x.round(), y = p.y.round();
          if (x < 0 || y < 0 || x >= w || y >= h) return -1;
          t++;
          if (g[y * w + x] < thr) dark++;
        }
      }
      return dark / t;
    }

    var border = 0.0;
    for (var i = 0; i < 6; i++) {
      for (final rc in [(0, i), (5, i), (i, 0), (i, 5)]) {
        final v = cell(rc.$1, rc.$2);
        if (v < 0) return null;
        border += v;
      }
    }
    if (border / 24 < 0.75) return null;
    final bits = <int>[];
    for (var r = 1; r <= 4; r++) {
      for (var c = 1; c <= 4; c++) {
        bits.add(cell(r, c) >= 0.5 ? 1 : 0);
      }
    }
    for (var id = 0; id < SheetLayout.markerCodes.length; id++) {
      var dist = 0;
      for (var i = 0; i < 16; i++) {
        if (bits[i] != (SheetLayout.markerBit(id, i ~/ 4, i % 4) ? 1 : 0)) dist++;
      }
      if (dist <= 2 && (best == null || dist < best.dist)) best = _Marker(id, q, dist);
    }
  }
  return best;
}

class _Sheet {
  final _Homography? hom;
  final bool estimated;
  final int markers;
  final bool inconsistent;
  _Sheet(this.hom, this.estimated, this.markers, {this.inconsistent = false});
}

_Sheet _findSheet(Uint8List g, int w, int h, int thr) {
  final area = w * h;
  final lab = _label(g, w, h, thr);
  final found = <int, _Marker>{};
  for (final b in lab.blobs) {
    if (b.count < area * 0.00006 || b.count > area * 0.02) continue;
    if (b.minX <= 0 || b.minY <= 0 || b.maxX >= w - 1 || b.maxY >= h - 1) continue;
    final bw = b.maxX - b.minX + 1, bh = b.maxY - b.minY + 1;
    final ar = bw / bh;
    if (ar < 0.4 || ar > 2.5 || b.count / (bw * bh) < 0.35) continue;
    final quad = _quadCorners(lab.labels, w, b);
    if (quad == null) continue;
    final m = _decodeMarker(g, w, h, thr, quad);
    if (m != null && (found[m.id] == null || m.dist < found[m.id]!.dist)) found[m.id] = m;
  }
  if (found.length < 2) return _Sheet(null, false, found.length);

  const half = SheetLayout.marker / 2;
  final src = <Pt>[], dst = <Pt>[];
  found.forEach((id, m) {
    final c = SheetLayout.markerCenters[id];
    src.addAll([Pt(c.x - half, c.y - half), Pt(c.x + half, c.y - half), Pt(c.x + half, c.y + half), Pt(c.x - half, c.y + half)]);
    dst.addAll(m.corners);
  });
  final hom = _solveHomography(src, dst);
  if (hom == null) return _Sheet(null, false, found.length);
  // Every marker corner must land within 1.5 mm of where the fitted sheet puts it.
  for (var i = 0; i < src.length; i++) {
    final p = hom.map(src[i].x, src[i].y);
    final e = hom.map(src[i].x + 1, src[i].y);
    final pxPerMm = sqrt(pow(e.x - p.x, 2) + pow(e.y - p.y, 2));
    final err = sqrt(pow(p.x - dst[i].x, 2) + pow(p.y - dst[i].y, 2)) / pxPerMm;
    if (err > 1.5) return _Sheet(null, false, found.length, inconsistent: true);
  }
  return _Sheet(hom, found.length < 3, found.length);
}

/// Projective map from sheet millimetres to image pixels, fitted by least squares on normalised
/// points (works for exactly 4 points and for many).
class _Homography {
  final List<double> h;
  final double sx0, sy0, ss, dx0, dy0, ds;
  _Homography(this.h, this.sx0, this.sy0, this.ss, this.dx0, this.dy0, this.ds);

  Pt map(double x, double y) {
    final nx = (x - sx0) * ss, ny = (y - sy0) * ss;
    final d = h[6] * nx + h[7] * ny + 1;
    final u = (h[0] * nx + h[1] * ny + h[2]) / d, v = (h[3] * nx + h[4] * ny + h[5]) / d;
    return Pt(u / ds + dx0, v / ds + dy0);
  }
}

_Homography? _solveHomography(List<Pt> src, List<Pt> dst) {
  (double, double, double) norm(List<Pt> pts) {
    final cx = pts.fold<double>(0, (a, p) => a + p.x) / pts.length;
    final cy = pts.fold<double>(0, (a, p) => a + p.y) / pts.length;
    var d = 0.0;
    for (final p in pts) {
      d += sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy));
    }
    d /= pts.length;
    return (cx, cy, d == 0 ? 1.0 : sqrt2 / d);
  }

  final (scx, scy, ss) = norm(src);
  final (dcx, dcy, ds) = norm(dst);
  final m = List.generate(8, (_) => List<double>.filled(9, 0));
  void addRow(List<double> row, double rhs) {
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        m[r][c] += row[r] * row[c];
      }
      m[r][8] += row[r] * rhs;
    }
  }

  for (var i = 0; i < src.length; i++) {
    final x = (src[i].x - scx) * ss, y = (src[i].y - scy) * ss;
    final u = (dst[i].x - dcx) * ds, v = (dst[i].y - dcy) * ds;
    addRow([x, y, 1, 0, 0, 0, -u * x, -u * y], u);
    addRow([0, 0, 0, x, y, 1, -v * x, -v * y], v);
  }
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var r = col + 1; r < 8; r++) {
      if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
    }
    final tmp = m[col];
    m[col] = m[pivot];
    m[pivot] = tmp;
    final pv = m[col][col];
    if (pv.abs() < 1e-12) return null;
    for (var c = col; c < 9; c++) {
      m[col][c] /= pv;
    }
    for (var r = 0; r < 8; r++) {
      if (r == col) continue;
      final f = m[r][col];
      if (f == 0) continue;
      for (var c = col; c < 9; c++) {
        m[r][c] -= f * m[col][c];
      }
    }
  }
  return _Homography([for (var i = 0; i < 8; i++) m[i][8]], scx, scy, ss, dcx, dcy, ds);
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
  final bool lightMarks;
  _Classified(this.answers, this.review, {this.lightMarks = false});
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
      // A mark far darker than this learner's usual marks may be an erasure or a correction: show it too.
      final unusual = markLevel > 0 && top > markLevel * 2.2;
      answers.add(order[0]);
      flag = second > top * 0.45 || top < level * 0.65 || secondMarked || light || unusual;
    } else {
      answers.add(-2);
      flag = true;
    }
    if (flag) review.add(i);
  }
  return _Classified(answers, review, lightMarks: answered.isNotEmpty && markLevel < 0.35);
}
