import 'models.dart';
import 'teaching.dart';

/// Weight presets.
/// DO 015, s. 2026 (Classroom Assessment, effective SY 2026-2027) and the legacy DO 8, s. 2015
/// weights kept for Grade 12 learners not yet on the Strengthened SHS Curriculum.
class WeightPreset {
  final String id;
  final String label;
  final String group;
  final double ww;
  final double pt;
  final double ex;
  final bool exSplit;
  final String transmute;

  const WeightPreset(
    this.id,
    this.label,
    this.group,
    this.ww,
    this.pt,
    this.ex,
    this.exSplit,
    this.transmute,
  );
}

const weightPresets = <WeightPreset>[
  WeightPreset(
    'core',
    'English, Filipino, Math, Science, AP, GMRC/VE (Grades 4-10)',
    'DO 015, s. 2026',
    20,
    50,
    30,
    true,
    'table2026',
  ),
  WeightPreset(
    'mapeh',
    'EPP/TLE, MAPEH (Grades 4-10)',
    'DO 015, s. 2026',
    20,
    60,
    20,
    true,
    'table2026',
  ),
  WeightPreset(
    'makabansa',
    'Makabansa (Grades 2-3)',
    'DO 015, s. 2026',
    20,
    50,
    30,
    true,
    'table2026',
  ),
  WeightPreset(
    'shs_core',
    'SHS Core / Other Academic Electives',
    'DO 015, s. 2026',
    20,
    50,
    30,
    true,
    'table2026',
  ),
  WeightPreset(
    'shs_field',
    'SHS Field Exposure, Arts Apprenticeship, Creative Production',
    'DO 015, s. 2026',
    15,
    70,
    15,
    false,
    'table2026',
  ),
  WeightPreset(
    'shs_arts',
    'SHS Arts, Sports, Health and Wellness Electives',
    'DO 015, s. 2026',
    20,
    60,
    20,
    true,
    'table2026',
  ),
  WeightPreset(
    'shs_research',
    'SHS Research Electives, Design and Innovation',
    'DO 015, s. 2026',
    40,
    60,
    0,
    false,
    'table2026',
  ),
  WeightPreset(
    'shs_techpro',
    'SHS TechPro Electives',
    'DO 015, s. 2026',
    15,
    65,
    20,
    true,
    'table2026',
  ),
  WeightPreset(
    'shs_immersion',
    'SHS Work Immersion',
    'DO 015, s. 2026',
    20,
    80,
    0,
    false,
    'table2026',
  ),
  WeightPreset(
    'do8_lang',
    'Languages, AP, EsP (old curriculum)',
    'DO 8, s. 2015',
    30,
    50,
    20,
    false,
    'table2026',
  ),
  WeightPreset(
    'do8_math',
    'Math, Science (old curriculum)',
    'DO 8, s. 2015',
    40,
    40,
    20,
    false,
    'table2026',
  ),
  WeightPreset(
    'do8_mapeh',
    'MAPEH, EPP/TLE (old curriculum)',
    'DO 8, s. 2015',
    20,
    60,
    20,
    false,
    'table2026',
  ),
  WeightPreset(
    'do8_shs_core',
    'SHS Core (Grade 12 old curriculum)',
    'DO 8, s. 2015',
    25,
    50,
    25,
    false,
    'table2026',
  ),
  WeightPreset(
    'custom',
    'Custom weights',
    'Set by teacher',
    20,
    50,
    30,
    true,
    'table2026',
  ),
];

WeightPreset presetById(String id) => weightPresets.firstWhere(
      (p) => p.id == id,
      orElse: () => weightPresets.first,
    );

/// Examination split under DO 015, s. 2026: ST1 30%, ST2 30%, Term Examination 40%.
const exSplitWeights = {'st1': 30.0, 'st2': 30.0, 'te': 40.0};

/// Adjusted transmutation table for SY 2026-2027 (DO 015, s. 2026). Each entry: lowest initial grade -> term grade.
const _table2026 = <List<num>>[
  [99.50, 100],
  [98.32, 99],
  [97.14, 98],
  [95.96, 97],
  [94.78, 96],
  [93.60, 95],
  [92.42, 94],
  [91.24, 93],
  [90.06, 92],
  [88.88, 91],
  [87.70, 90],
  [86.52, 89],
  [85.34, 88],
  [84.16, 87],
  [82.98, 86],
  [81.80, 85],
  [80.62, 84],
  [79.44, 83],
  [78.26, 82],
  [77.08, 81],
  [75.90, 80],
  [74.72, 79],
  [73.54, 78],
  [72.36, 77],
  [71.18, 76],
  [70.00, 75],
  [65.34, 74],
  [60.67, 73],
  [56.01, 72],
  [51.34, 71],
  [46.67, 70],
  [42.01, 69],
  [37.34, 68],
  [32.68, 67],
  [28.01, 66],
  [23.35, 65],
  [18.68, 64],
  [14.01, 63],
  [9.35, 62],
  [4.68, 61],
  [0.00, 60],
];

const transmuteLabels = {
  'raw': 'Institution policy (percentage / custom grade bands)',
  'table2026': 'Adjusted table, SY 2026-2027 (DO 015, s. 2026)',
  'do8': 'DO 8, s. 2015 transmutation',
  'none': 'Zero-based, no transmutation (SY 2027-2028 onward)',
};

double round2(double v) => (v * 100).roundToDouble() / 100;

int transmute(double initialGrade, String mode) {
  final ig = round2(initialGrade.clamp(0, 100).toDouble());
  switch (mode) {
    case 'raw':
      return ig.round();
    case 'do8':
      if (ig >= 100) return 100;
      return ig >= 60
          ? 75 + ((ig - 60) / 1.6 + 1e-9).floor()
          : 60 + (ig / 4 + 1e-9).floor();
    case 'none':
      final g = ig.round();
      return g < 60 ? 60 : g;
    default:
      for (final row in _table2026) {
        if (ig >= row[0] - 1e-9) return row[1].toInt();
      }
      return 60;
  }
}

/// Descriptors. DO 015, s. 2026 for current classes; DO 8, s. 2015 for legacy classes.
String descriptor(num grade, {bool legacy = false}) {
  if (legacy) {
    if (grade >= 90) return 'Outstanding';
    if (grade >= 85) return 'Very Satisfactory';
    if (grade >= 80) return 'Satisfactory';
    if (grade >= 75) return 'Fairly Satisfactory';
    return 'Did Not Meet Expectations';
  }
  if (grade >= 90) return 'Advancing';
  if (grade >= 80) return 'Benchmarking';
  if (grade >= 75) return 'Connecting';
  if (grade >= 65) return 'Developing';
  return 'Emerging';
}

/// Key Stage 1 letter grades (DO 015, s. 2026).
const ks1Letters = {
  'A': 'Advancing (Namumukod-tangi)',
  'B': 'Benchmarking (Napamamalas)',
  'C': 'Connecting (Natutungo)',
  'D': 'Developing (Napauunlad)',
  'E': 'Emerging (Nagsisimula)',
};

String letterFromPercent(double p) {
  if (p >= 90) return 'A';
  if (p >= 80) return 'B';
  if (p >= 75) return 'C';
  if (p >= 65) return 'D';
  return 'E';
}

class ComponentScore {
  final double got;
  final double hps;
  final double? ps;
  const ComponentScore(this.got, this.hps, this.ps);
}

class TermResult {
  final Map<String, ComponentScore> comps;
  final double initialGrade;
  final int? termGrade;
  final String? letter;
  final bool incomplete;
  final int missing;
  final bool hasData;

  const TermResult({
    required this.comps,
    required this.initialGrade,
    required this.termGrade,
    required this.letter,
    required this.incomplete,
    required this.missing,
    required this.hasData,
  });

  /// The value shown on reports: the term grade, or the letter in descriptive mode.
  String get display => letter ?? (termGrade?.toString() ?? '');
}

class GradeEngine {
  final SchoolClass cls;
  final List<Activity> activities;

  /// activityId -> learnerId -> score
  final Map<String, Map<String, double>> scores;

  /// learnerId -> term -> override value (a number or a letter)
  final Map<String, Map<int, String>> overrides;

  GradeEngine(
    this.cls,
    this.activities,
    this.scores, {
    this.overrides = const {},
  });

  double weightOf(String comp) => comp == 'ww'
      ? cls.ww
      : comp == 'pt'
          ? cls.pt
          : cls.ex;

  ComponentScore _sum(Iterable<Activity> acts, String learnerId) {
    var got = 0.0, hps = 0.0;
    for (final a in acts) {
      if (a.workStates[learnerId] == 'excused') continue;
      final score = scores[a.id]?[learnerId];
      if (score == null) continue;
      hps += a.hps;
      got += score;
    }
    return ComponentScore(got, hps, hps > 0 ? got / hps * 100 : null);
  }

  TermResult term(String learnerId, int term) {
    final acts = activities.where((a) => a.term == term).toList();
    var missing = 0;
    for (final a in acts) {
      if (a.workStates[learnerId] != 'excused' &&
          scores[a.id]?[learnerId] == null) missing++;
    }
    final comps = <String, ComponentScore>{};
    for (final c in ['ww', 'pt']) {
      comps[c] = _sum(acts.where((a) => a.comp == c), learnerId);
    }
    final exActs = acts.where((a) => a.comp == 'ex').toList();
    if (cls.exSplit) {
      var weighted = 0.0, used = 0.0, got = 0.0, hps = 0.0;
      for (final sub in exSplitWeights.keys) {
        final part = _sum(
          exActs.where((a) => (a.sub.isEmpty ? 'te' : a.sub) == sub),
          learnerId,
        );
        got += part.got;
        hps += part.hps;
        if (part.ps != null) {
          weighted += part.ps! * exSplitWeights[sub]!;
          used += exSplitWeights[sub]!;
        }
      }
      comps['ex'] = ComponentScore(got, hps, used > 0 ? weighted / used : null);
    } else {
      comps['ex'] = _sum(exActs, learnerId);
    }

    var weighted = 0.0, usedWeight = 0.0, totalWeight = 0.0;
    for (final c in ['ww', 'pt', 'ex']) {
      final w = weightOf(c);
      if (w <= 0) continue;
      final assigned = acts.where((a) => a.comp == c).toList();
      if (assigned.isNotEmpty &&
          assigned.every((a) => a.workStates[learnerId] == 'excused')) continue;
      totalWeight += w;
      final ps = comps[c]!.ps;
      if (ps != null) {
        weighted += ps * w;
        usedWeight += w;
      }
    }
    final hasData = usedWeight > 0;
    final ig = hasData ? round2(weighted / usedWeight) : 0.0;
    final incomplete = missing > 0 || usedWeight < totalWeight - 1e-9;

    final ov = overrides[learnerId]?[term];
    if (cls.mode == 'descriptive') {
      final letter = (ov != null && ov.isNotEmpty)
          ? ov
          : (hasData ? letterFromPercent(ig) : null);
      return TermResult(
        comps: comps,
        initialGrade: ig,
        termGrade: null,
        letter: letter,
        incomplete: incomplete,
        missing: missing,
        hasData: hasData,
      );
    }
    int? tg = hasData ? transmute(ig, cls.transmute) : null;
    final ovNum = ov == null ? null : int.tryParse(ov);
    if (ovNum != null) tg = ovNum;
    final policy = TeachingPolicy.decode(cls.teachingPolicy);
    final converted =
        cls.transmute == 'raw' && hasData && policy.bands.isNotEmpty
            ? policy.convert(ig)
            : null;
    return TermResult(
      comps: comps,
      initialGrade: ig,
      termGrade: tg,
      letter: converted,
      incomplete: incomplete,
      missing: missing,
      hasData: hasData || ovNum != null,
    );
  }

  /// Final grade: average of the term grades, rounded to the nearest whole number.
  FinalResult finalGrade(String learnerId, int terms) {
    final results = [for (var t = 1; t <= terms; t++) term(learnerId, t)];
    if (cls.mode == 'descriptive') {
      final letters = results.map((r) => r.letter).whereType<String>().toList();
      return FinalResult(
        results,
        null,
        letters.isEmpty ? null : letters.last,
        letters.length < terms ||
            results.any((r) => r.incomplete || r.missing > 0),
      );
    }
    final grades = results.map((r) => r.termGrade).whereType<int>().toList();
    if (grades.isEmpty) return FinalResult(results, null, null, true);
    if (cls.transmute == 'raw') {
      final policy = TeachingPolicy.decode(cls.teachingPolicy);
      final assessed = results.where((r) => r.hasData).toList();
      final average =
          assessed.fold<double>(0, (sum, r) => sum + r.initialGrade) /
              assessed.length;
      return FinalResult(
        results,
        average.round(),
        policy.convert(average),
        assessed.length < terms ||
            assessed.any((r) => r.incomplete || r.missing > 0),
        passing: policy.passing,
        percentage: average,
      );
    }
    final avg = grades.reduce((a, b) => a + b) / grades.length;
    return FinalResult(
        results,
        avg.round(),
        null,
        grades.length < terms ||
            results.any((r) => r.incomplete || r.missing > 0));
  }
}

class FinalResult {
  final double? percentage;
  final double passing;
  final List<TermResult> terms;
  final int? finalGrade;
  final String? letter;
  final bool partial;
  const FinalResult(
    this.terms,
    this.finalGrade,
    this.letter,
    this.partial, {
    this.passing = 75,
    this.percentage,
  });

  String get remarks {
    if (finalGrade == null)
      return letter == null ? '' : (partial ? 'In progress' : 'Completed');
    if (partial) return 'In progress';
    return (percentage ?? finalGrade!) >= passing ? 'Passed' : 'Failed';
  }
}

/// Promotion status for Key Stages 2 to 4 (DO 015, s. 2026).
String promotionStatus(List<int> finalGrades) {
  final failed = finalGrades.where((g) => g < 75).length;
  if (failed == 0) return 'Promoted';
  if (failed <= 2) return 'For Summer Remedial Class';
  return 'Retained';
}

/// General average: average of final grades, as a whole number.
int? generalAverage(List<int> finalGrades) {
  if (finalGrades.isEmpty) return null;
  return (finalGrades.reduce((a, b) => a + b) / finalGrades.length).round();
}

/// Academic excellence: GA of 90 or higher with no final grade below 80.
bool withHonors(List<int> finalGrades) {
  final ga = generalAverage(finalGrades);
  return ga != null && ga >= 90 && finalGrades.every((g) => g >= 80);
}
