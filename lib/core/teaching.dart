import 'dart:convert';

import 'models.dart';

/// Institution policy snapshots are kept with each class; they never claim a universal CHED formula.
class TeachingPolicy {
  String sector, institution, source;
  int periods;
  double passing;
  bool confirmed;
  List<Map<String, dynamic>> bands;
  TeachingPolicy({
    this.sector = 'DepEd',
    this.institution = '',
    this.source = '',
    this.periods = 3,
    this.passing = 75,
    this.confirmed = false,
    List<Map<String, dynamic>>? bands,
  }) : bands = bands ?? [];
  factory TeachingPolicy.decode(String? text) {
    if (text == null || text.isEmpty) return TeachingPolicy();
    final m = jsonDecode(text) as Map<String, dynamic>;
    return TeachingPolicy(
      sector: m['sector'] as String,
      institution: m['institution'] as String,
      source: m['source'] as String,
      periods: m['periods'] as int,
      passing: (m['passing'] as num).toDouble(),
      confirmed: m['confirmed'] == true,
      bands: (m['bands'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
  String encode() => jsonEncode({
    'sector': sector,
    'institution': institution,
    'source': source,
    'periods': periods,
    'passing': passing,
    'confirmed': confirmed,
    'bands': bands,
  });
  String convert(double percent) {
    final ordered = [...bands]
      ..sort((a, b) => (b['minimum'] as num).compareTo(a['minimum'] as num));
    for (final b in ordered) {
      if (percent >= (b['minimum'] as num)) return b['grade'].toString();
    }
    return percent.toStringAsFixed(2);
  }
}

double? outcomePercent(
  Iterable<Activity> activities,
  Map<String, Map<String, double>> scores,
  String learner,
) {
  double got = 0, total = 0;
  for (final a in activities) {
    if (a.workStates[learner] == 'excused') continue;
    final score = scores[a.id]?[learner];
    if (score != null) {
      got += score;
      total += a.hps;
    }
  }
  return total == 0 ? null : got / total * 100;
}
