import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/export/form_data.dart';
import '../core/grading.dart';
import '../core/models.dart';
import 'attendance/attendance_screen.dart';
import 'classes/class_detail_screen.dart';
import 'classes/class_form.dart';
import 'theme.dart';
import 'widgets.dart';

class _ClassSummary {
  final SchoolClass cls;
  final int learners;
  final bool attendanceToday;
  final int present;
  final int unchecked;
  final int belowPassing;
  _ClassSummary(this.cls, this.learners, this.attendanceToday, this.present, this.unchecked, this.belowPassing);
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onGo});
  final void Function(int tab) onGo;

  Future<List<_ClassSummary>> _load() async {
    final repo = store.repo;
    final today = dayKey(DateTime.now());
    final out = <_ClassSummary>[];
    for (final c in await repo.classes()) {
      final learners = (await repo.learners(c.id)).where((l) => l.isActive).toList();
      final att = (await repo.attendance(c.id, from: today, to: today))[today] ?? {};
      var unchecked = 0;
      for (final e in await repo.exams(classId: c.id)) {
        final resp = await repo.responses(e.id);
        if (resp.isNotEmpty || (await repo.items(e.id)).isNotEmpty) {
          unchecked += learners.where((l) => !resp.containsKey(l.id)).length;
        }
      }
      final engine = GradeEngine(c, await repo.activities(c.id), await repo.scores(c.id), overrides: await repo.overrides(c.id));
      var below = 0;
      for (final l in learners) {
        for (var t = store.profile.terms; t >= 1; t--) {
          final r = engine.term(l.id, t);
          if (r.hasData) {
            if ((r.termGrade ?? 100) < 75 || (r.letter != null && (r.letter == 'D' || r.letter == 'E'))) below++;
            break;
          }
        }
      }
      out.add(_ClassSummary(c, learners.length, att.isNotEmpty, att.values.where((s) => s != 'A').length, unchecked, below));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'Magandang umaga' : hour < 18 ? 'Magandang hapon' : 'Magandang gabi';
    final name = store.profile.teacher.split(' ').first;
    return Scaffold(
      body: SafeArea(
        child: Loader<List<_ClassSummary>>(
          load: _load,
          builder: (context, classes) {
            final pendingAttendance = classes.where((c) => !c.attendanceToday && c.learners > 0).toList();
            final unchecked = classes.fold<int>(0, (a, c) => a + c.unchecked);
            final below = classes.fold<int>(0, (a, c) => a + c.belowPassing);
            return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
              Text(DateFormat('EEEE, MMMM d').format(DateTime.now()),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('$greet${name.isEmpty ? '' : ', $name'}!', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              if (classes.isEmpty)
                AppCard(
                  child: EmptyState(
                    icon: Icons.groups_outlined,
                    title: 'Add your first class',
                    message: 'A class is one section and subject, for example Grade 8 - Sampaguita, Mathematics.',
                    action: FilledButton.icon(
                      onPressed: () => push(context, const ClassFormScreen()),
                      icon: const Icon(Icons.add),
                      label: const Text('Add class'),
                    ),
                  ),
                )
              else ...[
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.45,
                  children: [
                    StatTile(
                      label: 'Attendance today',
                      value: '${classes.length - pendingAttendance.length}/${classes.length}',
                      sub: pendingAttendance.isEmpty ? 'All classes done' : '${pendingAttendance.length} class(es) to go',
                      color: pendingAttendance.isEmpty ? goodGreen : null,
                    ),
                    StatTile(label: 'Papers to check', value: '$unchecked', sub: 'Across your exams', onTap: () => onGo(2)),
                    StatTile(label: 'Classes', value: '${classes.length}', sub: '${classes.fold<int>(0, (a, c) => a + c.learners)} learners', onTap: () => onGo(1)),
                    StatTile(label: 'Below 75 now', value: '$below', sub: 'Latest term, all classes', color: below > 0 ? penRed : goodGreen),
                  ],
                ),
                if (pendingAttendance.isNotEmpty) ...[
                  const SectionTitle('Take attendance'),
                  for (final c in pendingAttendance)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        onTap: () => push(context, AttendanceScreen(cls: c.cls)),
                        child: Row(children: [
                          const Icon(Icons.fact_check_outlined, color: brandBlue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.cls.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('${c.cls.subject} · ${c.learners} learners', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ]),
                          ),
                          const Icon(Icons.chevron_right),
                        ]),
                      ),
                    ),
                ],
                const SectionTitle('Your classes'),
                for (final c in classes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => push(context, ClassDetailScreen(classId: c.cls.id)),
                      child: Row(children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(c.cls.grade.replaceAll(RegExp(r'[^0-9]'), ''), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.cls.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(c.cls.subject, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ]),
                        ),
                        if (c.attendanceToday) Pill('${c.present}/${c.learners} present', color: goodGreen) else const Pill('No attendance', color: lateAmber),
                      ]),
                    ),
                  ),
              ],
            ]);
          },
        ),
      ),
    );
  }
}
