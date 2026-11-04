import 'package:flutter/material.dart';

import '../core/export/form_data.dart';
import '../core/grading.dart';
import '../core/models.dart';
import 'grades/class_record_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Absences in the last 30 days that put a learner on the list.
const absenceAlert = 5;

class AttentionRow {
  final Learner learner;

  /// The latest term grade when it is below passing, otherwise null.
  final String? grade;
  final int term;
  final int absences;
  const AttentionRow(this.learner, this.grade, this.term, this.absences);
}

/// Learners in a class whose latest grade is below passing or who are often absent.
Future<List<AttentionRow>> attentionFor(SchoolClass c, List<Learner> learners) async {
  final repo = store.repo;
  final engine = GradeEngine(c, await repo.activities(c.id), await repo.scores(c.id), overrides: await repo.overrides(c.id));
  final today = DateTime.now();
  final att = await repo.attendance(c.id, from: dayKey(today.subtract(const Duration(days: 30))), to: dayKey(today));
  final out = <AttentionRow>[];
  for (final l in learners) {
    String? grade;
    var term = 0;
    for (var t = store.profile.terms; t >= 1; t--) {
      final r = engine.term(l.id, t);
      if (!r.hasData) continue;
      if ((r.termGrade ?? 100) < 75 || r.letter == 'D' || r.letter == 'E') {
        grade = r.display;
        term = t;
      }
      break;
    }
    final absences = att.values.where((day) => day[l.id] == 'A').length;
    if (grade != null || absences >= absenceAlert) out.add(AttentionRow(l, grade, term, absences));
  }
  return out;
}

class AttentionScreen extends StatelessWidget {
  const AttentionScreen({super.key});

  Future<List<(SchoolClass, List<AttentionRow>)>> _load() async {
    final out = <(SchoolClass, List<AttentionRow>)>[];
    for (final c in await store.repo.classes()) {
      final learners = (await store.repo.learners(c.id)).where((l) => l.isActive).toList();
      final rows = await attentionFor(c, learners);
      if (rows.isNotEmpty) out.add((c, rows));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Learners who need help')),
      body: Loader<List<(SchoolClass, List<AttentionRow>)>>(
        load: _load,
        builder: (context, groups) {
          if (groups.isEmpty) {
            return const EmptyState(
              icon: Icons.sentiment_satisfied_alt_rounded,
              title: 'No one on the list',
              message: 'Learners appear here when their latest grade is below 75, or when they have $absenceAlert or more absences in 30 days.',
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            for (final (c, rows) in groups) ...[
              SectionTitle('${c.subject} · ${c.title}'),
              for (final r in rows) _row(context, c, r),
            ],
          ]);
        },
      ),
    );
  }

  Widget _row(BuildContext context, SchoolClass c, AttentionRow r) {
    final reasons = [
      if (r.grade != null) '${store.profile.termName(r.term)} grade ${r.grade}',
      if (r.absences >= absenceAlert) '${r.absences} absences in 30 days',
    ];
    final guardian = [r.learner.guardian.trim(), r.learner.contact.trim()].where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () => push(context, ClassRecordScreen(cls: c)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.learner.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(reasons.join(' · '), style: TextStyle(fontSize: 13, color: penRed, fontWeight: FontWeight.w600)),
              if (guardian.isNotEmpty) Text('Guardian: $guardian', style: TextStyle(fontSize: 12.5, color: mutedText(context))),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: mutedText(context)),
        ]),
      ),
    );
  }
}
