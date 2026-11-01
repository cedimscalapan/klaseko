import 'package:flutter/material.dart';

import '../../core/export/form_data.dart';
import '../../core/models.dart';
import '../attendance/attendance_screen.dart';
import '../exams/exams_screen.dart';
import '../grades/class_record_screen.dart';
import '../reports/reports_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'class_form.dart';
import 'learners_screen.dart';

class _Detail {
  final SchoolClass cls;
  final List<Learner> learners;
  final Map<String, String> today;
  final int exams;
  final int activities;
  _Detail(this.cls, this.learners, this.today, this.exams, this.activities);
}

class ClassDetailScreen extends StatelessWidget {
  const ClassDetailScreen({super.key, required this.classId});
  final String classId;

  Future<_Detail?> _load() async {
    final repo = store.repo;
    final cls = await repo.classById(classId);
    if (cls == null) return null;
    final today = dayKey(DateTime.now());
    return _Detail(
      cls,
      await repo.learners(classId),
      (await repo.attendance(classId, from: today, to: today))[today] ?? {},
      (await repo.exams(classId: classId)).length,
      (await repo.activities(classId)).length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Loader<_Detail?>(
      load: _load,
      builder: (context, d) {
        if (d == null) return const Scaffold(body: Center(child: Text('This class was deleted.')));
        final c = d.cls;
        final active = d.learners.where((l) => l.isActive).length;
        final males = d.learners.where((l) => l.sex == 'M').length;
        return Scaffold(
          appBar: AppBar(
            title: Text(c.title),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') {
                    push(context, ClassFormScreen(existing: c));
                  } else if (v == 'delete') {
                    final ok = await confirm(context,
                        title: 'Delete ${c.title}?',
                        message: 'This removes the class, its learners, attendance, scores and exams from this phone. Make a backup first if you may need them.');
                    if (ok) {
                      await store.repo.deleteClass(c.id);
                      store.changed();
                      if (context.mounted) Navigator.pop(context);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit class'))),
                  PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: penRed), title: Text('Delete class'))),
                ],
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.subject, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('SY ${c.sy} · ${c.advisory ? 'Advisory class' : 'Subject class'}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  Pill('$active learners ($males M, ${d.learners.length - males} F)', color: brandBlue),
                  Pill('WW ${c.ww.toInt()} · PT ${c.pt.toInt()} · EX ${c.ex.toInt()}', color: lateAmber),
                  if (c.mode == 'descriptive') const Pill('Letter grades', color: goodGreen),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            _Action(
              icon: Icons.people_alt_outlined,
              title: 'Learners',
              subtitle: d.learners.isEmpty ? 'Add or paste your class list' : '${d.learners.length} on the class list',
              onTap: () => push(context, LearnersScreen(cls: c)),
              highlight: d.learners.isEmpty,
            ),
            _Action(
              icon: Icons.fact_check_outlined,
              title: 'Attendance',
              subtitle: d.today.isEmpty ? 'Not taken today' : '${d.today.values.where((s) => s != 'A').length} of ${d.today.length} present today',
              onTap: () => push(context, AttendanceScreen(cls: c)),
            ),
            _Action(
              icon: Icons.grid_on_outlined,
              title: 'Class record',
              subtitle: '${d.activities} activities · grades computed automatically',
              onTap: () => push(context, ClassRecordScreen(cls: c)),
            ),
            _Action(
              icon: Icons.quiz_outlined,
              title: 'Exams and quizzes',
              subtitle: d.exams == 0 ? 'Make a test and printable answer sheets' : '${d.exams} exam(s) · print, check, analyze',
              onTap: () => push(context, ExamsScreen(cls: c)),
            ),
            _Action(
              icon: Icons.description_outlined,
              title: 'Reports and school forms',
              subtitle: c.advisory ? 'SF1, SF2, SF9, class record, grade sheet' : 'SF2, class record, grade sheet',
              onTap: () => push(context, ReportsScreen(cls: c)),
            ),
          ]),
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.title, required this.subtitle, required this.onTap, this.highlight = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          onTap: onTap,
          color: highlight ? Theme.of(context).colorScheme.primaryContainer : null,
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: brandBlue.withAlpha(28), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: brandBlue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      );
}
