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
///     the paper may be outside the photo as long as every bubble is inside it. A photo of just the
///     bubbles is placed from the grid they form; the way up comes from the item numbers if they are
///     in view, otherwise from the small letters printed inside the empty bubbles.
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

const _retakeMarkers = 'The bubbles could not be read. Fit all the bubbles in the photo, in good light, then try again.';
const _retakeGrid = 'The bubbles were found, but not which way is up. Move a little closer, or include the item numbers in the photo.';
const _retakeFit = 'The sheet could not be lined up. Keep the paper flat and the phone steady, then try again.';
const _outsidePhoto = 'Part of the answers is outside the photo. Move the phone back a little so all the bubbles are in view.';
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
    final img2 = _Img(g, w, h);
    final n = min(req.items, SheetLayout.maxItems);
    final lab = _label(g, w, h, thr);
    final sheet = _findSheet(lab, g, w, h, thr, n);
    var found = sheet.hom;
    var layout = sheet.box ?? BoxLayout.full;
    if (found == null) {
      // No usable markers: a close-up of the answers. Place the sheet from the bubbles themselves.
      final grid = _findGrid(lab, img2, w, h, thr, n);
      found = grid.hom;
      if (found == null) return OmrResult.fail(grid.error ?? (sheet.inconsistent ? _retakeFit : _retakeMarkers));
      layout = grid.box ?? layout;
    }
    if (n > layout.maxItems) return OmrResult.fail('This answer sheet has room for ${layout.maxItems} items, but the exam has $n. Print full-page sheets for this exam.');
    final hom = found;
    // Every bubble that will be read must be inside the photo.
    bool inside(Pt p) {
      final q = hom.map(p.x, p.y);
      return q.x >= 3 && q.y >= 3 && q.x <= w - 4 && q.y <= h - 4;
    }

    for (var i = 0; i < n; i++) {
      if (!inside(layout.item(i, 0)) || !inside(layout.item(i, SheetLayout.choices - 1))) return OmrResult.fail(_outsidePhoto);
    }
    // The learner number is read when it is in the photo; otherwise the teacher picks the learner.
    // Only version 3 markers mean the number is at the top right; otherwise it is in the answer box.
    Pt idAt(int col, int d) => sheet.hom != null && sheet.box == null ? SheetLayout.idBubble(col, d) : layout.id(col, d);
    final idInView = [0, 1].every((col) => inside(idAt(col, 0)) && inside(idAt(col, 9)));
    final rows = <List<double>>[];
    final ringScores = <double>[];
    final offsets = <double>[];
    for (var i = 0; i < n; i++) {
      final centers = [for (var c = 0; c < SheetLayout.choices; c++) layout.item(i, c)];
      final reg = _register(img2, hom, centers, layout.bubbleR);
      ringScores.add(reg.score);
      offsets.add(sqrt(reg.dx * reg.dx + reg.dy * reg.dy));
      rows.add([for (final c in centers) _darknessAt(img2, hom, c.x + reg.dx, c.y + reg.dy, layout.bubbleR)]);
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
      final centers = [for (var d = 0; d < 10; d++) idAt(col, d)];
      final reg = _register(img2, hom, centers, layout.idR);
      final f = [for (final c in centers) _darknessAt(img2, hom, c.x + reg.dx, c.y + reg.dy, layout.idR)];
      final sorted = [...f]..sort((a, b) => b.compareTo(a));
      final m = sorted.first;
      if (m <= 0.15 || sorted[1] >= m * 0.6) return null;
      return f.indexOf(m);
    }

    final tens = idInView ? digit(0) : null, ones = idInView ? digit(1) : null;
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

  /// The answer box the markers belong to; null for the outer markers of a version 3 sheet.
  final BoxLayout? box;
  _Sheet(this.hom, this.estimated, this.markers, {this.inconsistent = false, this.box});
}

_Sheet _findSheet(_Labeled lab, Uint8List g, int w, int h, int thr, int items) {
  final area = w * h;
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
  // Codes come in sets of eight: version 3, then each answer box size. Use the set seen most.
  final seen = List<int>.filled(3, 0);
  for (final id in found.keys) {
    seen[id ~/ 8]++;
  }
  var set = 2;
  for (final s in const [1, 0]) {
    if (seen[s] > seen[set]) set = s;
  }
  found.removeWhere((id, _) => id ~/ 8 != set);
  if (found.length < 2) return _Sheet(null, false, found.length);

  final box = set == 0 ? null : BoxLayout.all[set - 1];
  final half = (box?.marker ?? SheetLayout.marker) / 2;
  final centers = box?.markers(items) ?? SheetLayout.markerCenters;
  final src = <Pt>[], dst = <Pt>[];
  found.forEach((id, m) {
    final c = centers[id % 8];
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
  return _Sheet(hom, found.length < 3, found.length, box: box);
}

// ---------------------------------------------------------------------------
// Finding the sheet without markers: the bubble grid and the item numbers
// ---------------------------------------------------------------------------

class _GridFit {
  final _Homography? hom;
  final String? error;
  final BoxLayout? box;
  _GridFit(this.hom, [this.error, this.box]);
}

/// Places the sheet from a photo of just the bubbles. Their outlines (and shaded bubbles) form a
/// regular grid: four choices across and one row per item. Every way that grid could sit on the
/// sheet is tried (which way is up, which column of items, which rows), and only placements where
/// every item's printed outlines are found are kept. The grid looks the same upside down, so when
/// more than one is left, the item numbers or the printed letters must clearly pick one. If they
/// cannot, the photo is refused: a wrong way up would reverse every answer.
_GridFit _findGrid(_Labeled lab, _Img im, int w, int h, int thr, int n) {
  if (n == 0) return _GridFit(null);
  // 1. Round blobs of one common size: empty outlines and shaded bubbles.
  final cands = <(double, double, double)>[];
  for (final b in lab.blobs) {
    final bw = b.maxX - b.minX + 1, bh = b.maxY - b.minY + 1;
    if (bw < 10 || bh < 10 || bw > w / 3 || bh > h / 3) continue;
    final ar = bw / bh;
    if (ar < 0.7 || ar > 1.43) continue;
    final fill = b.count / (bw * bh);
    if (fill < 0.08 || fill > 0.95) continue;
    if ((b.cx - (b.minX + b.maxX) / 2).abs() > 0.2 * bw || (b.cy - (b.minY + b.maxY) / 2).abs() > 0.2 * bh) continue;
    // The middle of the box, not of the ink: a printed outline can break in a small photo.
    cands.add(((b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2, (bw + bh) / 2));
  }
  var most = 0;
  var size = 0.0;
  for (final c in cands) {
    final k = cands.where((o) => (o.$3 - c.$3).abs() <= 0.15 * c.$3).length;
    if (k > most) {
      most = k;
      size = c.$3;
    }
  }
  final pts = [for (final c in cands) if ((c.$3 - size).abs() <= 0.2 * size) Pt(c.$1, c.$2)];
  if (pts.length < 8) return _GridFit(null);

  // 2. The grid's two directions and spacings, from the distances between neighbouring bubbles.
  final angs = <double>[], lens = <double>[];
  for (final p in pts) {
    for (final q in pts) {
      final dx = q.x - p.x, dy = q.y - p.y;
      final l = sqrt(dx * dx + dy * dy);
      if (l >= 1.2 * size && l <= 2.3 * size) {
        angs.add((atan2(dy, dx) * 180 / pi) % 180);
        lens.add(l);
      }
    }
  }
  if (angs.isEmpty) return _GridFit(null);
  final hist = List<double>.filled(180, 0);
  for (final a in angs) {
    hist[a.floor() % 180]++;
  }
  double smooth(int i) {
    var s = 0.0;
    for (var k = -3; k <= 3; k++) {
      s += hist[(i + k) % 180];
    }
    return s;
  }

  var t1 = 0;
  for (var i = 1; i < 180; i++) {
    if (smooth(i) > smooth(t1)) t1 = i;
  }
  var t2 = (t1 + 70) % 180;
  for (var k = -20; k <= 20; k++) {
    final i = (t1 + 90 + k) % 180;
    if (smooth(i) > smooth(t2)) t2 = i;
  }
  Pt? axis(int t) {
    final l = <double>[];
    var d = 0.0;
    for (var i = 0; i < angs.length; i++) {
      final off = ((angs[i] - t + 90) % 180) - 90;
      if (off.abs() > 10) continue;
      l.add(lens[i]);
      d += off;
    }
    if (l.isEmpty) return null;
    final a = (t + d / l.length) * pi / 180, len = _median(l);
    return Pt(len * cos(a), len * sin(a));
  }

  final ga = axis(t1);
  var gb = axis(t2);
  if (ga == null || gb == null) return _GridFit(null);
  // A photo is never mirrored, so the second direction is always a quarter turn clockwise from the first.
  if (-ga.y * gb.x + ga.x * gb.y < 0) gb = Pt(-gb.x, -gb.y);

  // 3. Grid positions, grown outwards from bubble to bubble so a tilted or curved page is followed.
  final coord = <int, (int, int)>{};
  final comps = <List<int>>[];
  const steps = [(1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2)];
  for (var seed = 0; seed < pts.length; seed++) {
    if (coord.containsKey(seed)) continue;
    final comp = [seed];
    final local = <int, (Pt, Pt)>{seed: (ga, gb)};
    coord[seed] = (0, 0);
    for (var qi = 0; qi < comp.length; qi++) {
      final p = comp[qi];
      final (a, b) = local[p]!;
      final (k, r) = coord[p]!;
      final tol = 0.28 * min(sqrt(a.x * a.x + a.y * a.y), sqrt(b.x * b.x + b.y * b.y));
      for (final (dk, dr) in steps) {
        final px = pts[p].x + dk * a.x + dr * b.x, py = pts[p].y + dk * a.y + dr * b.y;
        var q = -1;
        var dq = tol;
        for (var j = 0; j < pts.length; j++) {
          final d = sqrt(pow(pts[j].x - px, 2) + pow(pts[j].y - py, 2));
          if (d <= dq) {
            dq = d;
            q = j;
          }
        }
        if (q < 0 || coord.containsKey(q)) continue;
        coord[q] = (k + dk, r + dr);
        final step = Pt(pts[q].x - pts[p].x, pts[q].y - pts[p].y);
        local[q] = dk != 0 ? (Pt(step.x / dk, step.y / dk), b) : (a, Pt(step.x / dr, step.y / dr));
        comp.add(q);
      }
    }
    comps.add(comp);
  }
  // The item grid is exactly four choices across. Other round marks, like learner number bubbles,
  // form groups of their own.
  int span(List<int> group, int Function((int, int)) axis) {
    final v = [for (final i in group) axis(coord[i]!)];
    return v.reduce(max) - v.reduce(min) + 1;
  }

  final itemGroups = comps.where((c) => span(c, (p) => p.$1) == SheetLayout.choices || span(c, (p) => p.$2) == SheetLayout.choices);
  if (itemGroups.isEmpty) return _GridFit(null);
  final comp = itemGroups.reduce((a, b) => a.length >= b.length ? a : b);
  if (comp.length < 8) return _GridFit(null);
  final ks = [for (final i in comp) coord[i]!.$1], rs = [for (final i in comp) coord[i]!.$2];
  final kmin = ks.reduce(min), kmax = ks.reduce(max), rmin = rs.reduce(min), rmax = rs.reduce(max);
  final sk = kmax - kmin + 1, sr = rmax - rmin + 1;

  // 4. Each way the grid can sit on a sheet of each size.
  _GridFit tryBox(BoxLayout box) {
    // 4. Each way the grid can sit on the sheet: (choice, row) of a grid position, and the number of rows.
    final orients = <((int, int) Function(int, int), int)>[
      if (sk == SheetLayout.choices) ((int k, int r) => (k - kmin, r - rmin), sr),
      if (sk == SheetLayout.choices) ((int k, int r) => (kmax - k, rmax - r), sr),
      if (sr == SheetLayout.choices) ((int k, int r) => (r - rmin, kmax - k), sk),
      if (sr == SheetLayout.choices) ((int k, int r) => (rmax - r, k - kmin), sk),
    ];
    final passed = <_Homography>[];
    var outside = false;
    final blocks = box.columnsFor(n);
    for (final (place, rows) in orients) {
      for (var block = 0; block < blocks; block++) {
        final rowsIn = min(box.rowsPerColumn, n - block * box.rowsPerColumn);
        for (var top = 0; top + rows <= rowsIn; top++) {
          final src = <Pt>[], dst = <Pt>[];
          for (final i in comp) {
            final (c, row) = place(coord[i]!.$1, coord[i]!.$2);
            src.add(box.item(block * box.rowsPerColumn + top + row, c));
            dst.add(pts[i]);
          }
          final hom = _fitSkippingStrays(src, dst, 1.2);
          if (hom == null) continue;
          if (!_itemsInside(hom, box, n, w, h)) {
            outside = true;
            continue;
          }
          final regs = [
            for (var i = 0; i < n; i++)
              _register(im, hom, [for (var c = 0; c < SheetLayout.choices; c++) box.item(i, c)], box.bubbleR)
          ];
          final scores = [for (final r in regs) r.score];
          final med = _median(scores);
          if (med < 0.06 || scores.any((s) => s < med * 0.4) || regs.any((r) => sqrt(r.dx * r.dx + r.dy * r.dy) > 1.25)) continue;
          // Refit on every item's outlines.
          final src2 = <Pt>[], dst2 = <Pt>[];
          for (var i = 0; i < n; i++) {
            for (var c = 0; c < SheetLayout.choices; c++) {
              final b = box.item(i, c);
              src2.add(b);
              dst2.add(hom.map(b.x + regs[i].dx, b.y + regs[i].dy));
            }
          }
          final refined = _solveHomography(src2, dst2);
          if (refined != null) passed.add(refined);
        }
      }
    }
    if (passed.isEmpty) return _GridFit(null, outside ? _outsidePhoto : _retakeMarkers);
    if (passed.length == 1) return _GridFit(passed.first, null, box);
    final numbered = [for (final p in passed) if (_labelsFound(im, p, box, n, thr) >= n * 0.8) p];
    if (numbered.length == 1) return _GridFit(numbered.first, null, box);
    final scores = [for (final p in passed) _letterMatch(im, p, box, n)];
    final sorted = [...scores]..sort();
    final best = sorted.last;
    if (best >= 0.6 && best - sorted[sorted.length - 2] >= 0.15) return _GridFit(passed[scores.indexOf(best)], null, box);
    return _GridFit(null, _retakeGrid);
  }

  _GridFit? failed;
  for (final box in BoxLayout.all) {
    if (n > box.maxItems) continue;
    final fit = tryBox(box);
    if (fit.hom != null) return fit;
    failed ??= fit;
  }
  return failed ?? _GridFit(null);
}

/// Fits the sheet, leaving out up to a fifth of the points if they are far off (a mis-seen bubble).
_Homography? _fitSkippingStrays(List<Pt> src, List<Pt> dst, double tolMm) {
  final first = _solveHomography(src, dst);
  if (first == null) return null;
  final keep = [for (var i = 0; i < src.length; i++) if (_fitsWithin(first, [src[i]], [dst[i]], tolMm)) i];
  if (keep.length == src.length) return first;
  if (keep.length < src.length * 0.8) return null;
  final s2 = [for (final i in keep) src[i]], d2 = [for (final i in keep) dst[i]];
  final second = _solveHomography(s2, d2);
  return second != null && _fitsWithin(second, s2, d2, tolMm) ? second : null;
}

/// True when every point lands within [tolMm] of where the fitted sheet puts it.
bool _fitsWithin(_Homography hom, List<Pt> src, List<Pt> dst, double tolMm) {
  for (var i = 0; i < src.length; i++) {
    final p = hom.map(src[i].x, src[i].y);
    final e = hom.map(src[i].x + 1, src[i].y);
    final pxPerMm = sqrt(pow(e.x - p.x, 2) + pow(e.y - p.y, 2));
    if (pxPerMm == 0 || sqrt(pow(p.x - dst[i].x, 2) + pow(p.y - dst[i].y, 2)) / pxPerMm > tolMm) return false;
  }
  return true;
}

bool _itemsInside(_Homography hom, BoxLayout box, int n, int w, int h) {
  for (var i = 0; i < n; i++) {
    for (final c in const [0, SheetLayout.choices - 1]) {
      final b = box.item(i, c);
      // The whole bubble, not just its middle, so a cut-off mark is never read as a light one.
      for (final (dx, dy) in const [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)]) {
        final q = hom.map(b.x + dx * box.bubbleR, b.y + dy * box.bubbleR);
        if (q.x < 0 || q.y < 0 || q.x > w - 1 || q.y > h - 1) return false;
      }
    }
  }
  return true;
}

/// How many items have ink where their printed number should be, just left of choice A.
int _labelsFound(_Img im, _Homography hom, BoxLayout box, int n, int thr) {
  var found = 0;
  for (var i = 0; i < n; i++) {
    final s = box.glyphScale, right = box.labelRightAt(i), row = box.item(i, 0).y;
    var dark = 0, total = 0;
    for (var y = row - 1.4 * s; y <= row + 1.41 * s; y += 0.25 * s) {
      for (var x = right - 2.8 * s; x <= right + 0.21 * s; x += 0.25 * s) {
        final q = hom.map(x, y);
        final px = q.x.round(), py = q.y.round();
        total++;
        if (px >= 0 && py >= 0 && px < im.w && py < im.h && im.g[py * im.w + px] < thr) dark++;
      }
    }
    if (dark >= total * 0.04) found++;
  }
  return found;
}

/// The letters A, B, C and D printed inside the bubbles, on a 0.2 mm grid (0 = paper, 9 = full ink).
const bubbleLetterGlyphs = [
  ['0000000000', '0000530000', '0001880000', '0005473000', '0009137000', '0037009100', '0068779500', '0091113900', '0460000830', '0420000340', '0000000000'],
  ['000000000', '046664000', '066336800', '064000910', '065113800', '069889500', '064000830', '064000650', '066334920', '046665200', '000000000'],
  ['0000000000', '0003675000', '0067226800', '0380000620', '0550000000', '0640000000', '0550000100', '0280000740', '0077226800', '0004675000', '0000000000'],
  ['000000000', '066664000', '094336800', '091000740', '091000370', '091000380', '091000470', '091000740', '094336800', '066664000', '000000000'],
];

/// How well the empty bubbles show the letter this placement expects there, from -1 to 1. The right
/// way up scores about 0.8 and upside down about 0.5, even in photos of a light printout.
double _letterMatch(_Img im, _Homography hom, BoxLayout box, int n) {
  const size = 21;
  final cell = 0.2 * box.glyphScale;
  final patches = <Float64List>[];
  final letters = <int>[];
  final fills = <double>[];
  for (var i = 0; i < n; i++) {
    for (var c = 0; c < SheetLayout.choices; c++) {
      final b = box.item(i, c);
      final p = Float64List(size * size);
      var sum = 0.0;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final q = hom.map(b.x + (x - size ~/ 2) * cell, b.y + (y - size ~/ 2) * cell);
          final v = im.dark(q.x.round(), q.y.round());
          p[y * size + x] = v;
          sum += v;
        }
      }
      patches.add(p);
      letters.add(c);
      fills.add(sum / p.length);
    }
  }
  final usual = _median(fills);
  var total = 0.0;
  var count = 0;
  for (var k = 0; k < patches.length; k++) {
    if (fills[k] > usual * 2 + 0.05) continue; // a shaded bubble hides its letter
    total += _bestGlyphMatch(patches[k], size, bubbleLetterGlyphs[letters[k]]);
    count++;
  }
  return count == 0 ? 0 : total / count;
}

/// Best normalized correlation of a glyph at any position in a patch.
double _bestGlyphMatch(Float64List patch, int size, List<String> glyph) {
  final gh = glyph.length, gw = glyph.first.length;
  final g = Float64List(gh * gw);
  var gMean = 0.0;
  for (var y = 0; y < gh; y++) {
    for (var x = 0; x < gw; x++) {
      g[y * gw + x] = glyph[y].codeUnitAt(x) - 48.0;
      gMean += g[y * gw + x];
    }
  }
  gMean /= g.length;
  var gNorm = 0.0;
  for (var i = 0; i < g.length; i++) {
    g[i] -= gMean;
    gNorm += g[i] * g[i];
  }
  var best = -1.0;
  for (var oy = 0; oy + gh <= size; oy++) {
    for (var ox = 0; ox + gw <= size; ox++) {
      var mean = 0.0;
      for (var y = 0; y < gh; y++) {
        for (var x = 0; x < gw; x++) {
          mean += patch[(oy + y) * size + ox + x];
        }
      }
      mean /= g.length;
      var cross = 0.0, norm = 0.0;
      for (var y = 0; y < gh; y++) {
        for (var x = 0; x < gw; x++) {
          final d = patch[(oy + y) * size + ox + x] - mean;
          cross += d * g[y * gw + x];
          norm += d * d;
        }
      }
      if (norm > 1e-9 && cross / sqrt(norm * gNorm) > best) best = cross / sqrt(norm * gNorm);
    }
  }
  return best;
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
