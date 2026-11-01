import 'dart:math';

import 'models.dart';

/// Item analysis and Mean Percentage Score (MPS) for one exam.
class ItemStat {
  final int index;
  final ExamItem item;
  final int correct;
  final int n;
  final List<int> counts; // per choice A-D
  final int blanks;
  final double difficulty; // proportion correct (p)
  final double discrimination; // upper 27% minus lower 27%

  ItemStat(this.index, this.item, this.correct, this.n, this.counts, this.blanks, this.difficulty, this.discrimination);

  double get percent => difficulty * 100;

  String get difficultyLabel {
    if (difficulty >= 0.81) return 'Very easy';
    if (difficulty >= 0.61) return 'Easy';
    if (difficulty >= 0.41) return 'Average';
    if (difficulty >= 0.21) return 'Difficult';
    return 'Very difficult';
  }

  String get discriminationLabel {
    if (discrimination >= 0.40) return 'Very good';
    if (discrimination >= 0.30) return 'Good';
    if (discrimination >= 0.20) return 'Fair';
    return 'Poor';
  }

  /// Retain, revise or reject, using the usual difficulty and discrimination cut-offs.
  String get decision {
    final okDifficulty = difficulty >= 0.21 && difficulty <= 0.80;
    if (okDifficulty && discrimination >= 0.20) return 'Retain';
    if (discrimination < 0) return 'Reject';
    if (!okDifficulty && discrimination < 0.20) return 'Reject';
    return 'Revise';
  }

  /// Mastery of the item: 75% correct and up is mastered.
  String get mastery => percent >= 75 ? 'Mastered' : percent >= 50 ? 'Nearly mastered' : 'Least mastered';

  /// The wrong choice picked most often, if any.
  int? get topDistractor {
    var best = -1, bestCount = 0;
    for (var c = 0; c < counts.length; c++) {
      if (c != item.answer && counts[c] > bestCount) {
        best = c;
        bestCount = counts[c];
      }
    }
    return best < 0 ? null : best;
  }
}

class CompetencyStat {
  final String name;
  final List<int> items;
  final double percent;
  CompetencyStat(this.name, this.items, this.percent);
  String get mastery => percent >= 75 ? 'Mastered' : percent >= 50 ? 'Nearly mastered' : 'Least mastered';
}

class ExamStats {
  final int n;
  final int k;
  final double mean;
  final double sd;
  final int highest;
  final int lowest;
  final double mps;
  final List<ItemStat> items;
  final List<CompetencyStat> competencies;
  final Map<int, int> distribution; // score -> count

  ExamStats(this.n, this.k, this.mean, this.sd, this.highest, this.lowest, this.mps, this.items, this.competencies, this.distribution);

  String get masteryLevel => masteryLevelOf(mps);
}

/// DepEd mastery levels by MPS.
String masteryLevelOf(double mps) {
  if (mps >= 96) return 'Mastered';
  if (mps >= 86) return 'Closely approximating mastery';
  if (mps >= 66) return 'Moving towards mastery';
  if (mps >= 35) return 'Average';
  if (mps >= 15) return 'Low';
  if (mps >= 5) return 'Very low';
  return 'Absolutely no mastery';
}

ExamStats analyzeExam(List<ExamItem> items, List<ExamResponse> responses) {
  final k = items.length;
  final n = responses.length;
  final scores = responses.map((r) => scoreAnswers(items, r.answers)).toList();
  final mean = n == 0 ? 0.0 : scores.reduce((a, b) => a + b) / n;
  final sd = n < 2 ? 0.0 : sqrt(scores.map((s) => pow(s - mean, 2)).reduce((a, b) => a + b) / (n - 1));
  final mps = (n == 0 || k == 0) ? 0.0 : mean / k * 100;

  final ranked = List<int>.generate(n, (i) => i)..sort((a, b) => scores[b].compareTo(scores[a]));
  final g = n < 2 ? 0 : max(1, (n * 0.27).round());
  final upper = ranked.take(g).toList();
  final lower = ranked.reversed.take(g).toList();

  final stats = <ItemStat>[];
  for (var i = 0; i < k; i++) {
    final it = items[i];
    final counts = List<int>.filled(4, 0);
    var blanks = 0, correct = 0;
    for (final r in responses) {
      final a = i < r.answers.length ? r.answers[i] : ansBlank;
      if (a >= 0 && a < 4) {
        counts[a]++;
      } else {
        blanks++;
      }
      if (a == it.answer) correct++;
    }
    double disc = 0;
    if (g > 0) {
      int hit(List<int> group) => group.where((idx) {
            final ans = responses[idx].answers;
            return i < ans.length && ans[i] == it.answer;
          }).length;
      disc = (hit(upper) - hit(lower)) / g;
    }
    stats.add(ItemStat(i, it, correct, n, counts, blanks, n == 0 ? 0 : correct / n, disc));
  }

  final byComp = <String, List<int>>{};
  for (final s in stats) {
    final c = s.item.competency.trim().isEmpty ? 'Untagged items' : s.item.competency.trim();
    (byComp[c] ??= []).add(s.index);
  }
  final comps = byComp.entries.map((e) {
    final pct = e.value.map((i) => stats[i].percent).reduce((a, b) => a + b) / e.value.length;
    return CompetencyStat(e.key, e.value, pct);
  }).toList()
    ..sort((a, b) => a.percent.compareTo(b.percent));

  final dist = <int, int>{};
  for (final s in scores) {
    dist[s] = (dist[s] ?? 0) + 1;
  }

  return ExamStats(n, k, mean, sd, scores.isEmpty ? 0 : scores.reduce(max), scores.isEmpty ? 0 : scores.reduce(min), mps, stats, comps, dist);
}
