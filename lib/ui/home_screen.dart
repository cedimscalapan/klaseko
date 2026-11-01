import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/export/form_data.dart';
import '../core/grading.dart';
import '../core/models.dart';
import 'attendance/attendance_screen.dart';
import 'classes/class_detail_screen.dart';
import 'classes/class_form.dart';
import 'grades/class_record_screen.dart';
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

const _classColors = [brandBlue, violet, teal, Color(0xFFD9480F), Color(0xFF2B8A3E), Color(0xFFC2255C)];
Color classColor(int i) => _classColors[i % _classColors.length];

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
        if ((await repo.items(e.id)).isEmpty) continue;
        final resp = await repo.responses(e.id);
        unchecked += learners.where((l) => !resp.containsKey(l.id)).length;
      }
      final engine = GradeEngine(c, await repo.activities(c.id), await repo.scores(c.id), overrides: await repo.overrides(c.id));
      var below = 0;
      for (final l in learners) {
        for (var t = store.profile.terms; t >= 1; t--) {
          final r = engine.term(l.id, t);
          if (r.hasData) {
            if ((r.termGrade ?? 100) < 75 || r.letter == 'D' || r.letter == 'E') below++;
            break;
          }
        }
      }
      out.add(_ClassSummary(c, learners.length, att.isNotEmpty, att.values.where((s) => s != 'A').length, unchecked, below));
    }
    return out;
  }

  void _pickClass(BuildContext context, List<_ClassSummary> classes, String title, void Function(SchoolClass) open) {
    if (classes.length == 1) {
      open(classes.first.cls);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(title, style: Theme.of(ctx).textTheme.titleLarge)),
          for (var i = 0; i < classes.length; i++)
            ListTile(
              leading: CircleAvatar(backgroundColor: classColor(i).withAlpha(30), child: Text(classes[i].cls.grade.replaceAll(RegExp(r'[^0-9]'), ''), style: TextStyle(color: classColor(i), fontWeight: FontWeight.w800))),
              title: Text(classes[i].cls.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(classes[i].cls.subject),
              onTap: () {
                Navigator.pop(ctx);
                open(classes[i].cls);
              },
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'Magandang umaga' : hour < 18 ? 'Magandang hapon' : 'Magandang gabi';
    final name = store.profile.teacher.trim().split(' ').first;
    return Scaffold(
      body: SafeArea(
        child: Loader<List<_ClassSummary>>(
          load: _load,
          builder: (context, classes) {
            final pendingAttendance = classes.where((c) => !c.attendanceToday && c.learners > 0).toList();
            final unchecked = classes.fold<int>(0, (a, c) => a + c.unchecked);
            final below = classes.fold<int>(0, (a, c) => a + c.belowPassing);
            final learners = classes.fold<int>(0, (a, c) => a + c.learners);
            final tasks = <(String, String, bool, VoidCallback)>[
              (
                'Take attendance',
                pendingAttendance.isEmpty ? 'Done for all classes' : '${pendingAttendance.length} class(es) left today',
                pendingAttendance.isEmpty,
                () => _pickClass(context, pendingAttendance.isEmpty ? classes : pendingAttendance, 'Take attendance', (c) => push(context, AttendanceScreen(cls: c))),
              ),
              ('Check papers', unchecked == 0 ? 'No papers waiting' : '$unchecked paper(s) waiting', unchecked == 0, () => onGo(2)),
              ('Help struggling learners', below == 0 ? 'Everyone is at 75 or above' : '$below learner(s) below 75 now', below == 0, () => onGo(1)),
            ];
            final done = tasks.where((t) => t.$3).length;

            return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
              HeroHeader(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(DateFormat('EEEE, MMMM d').format(DateTime.now()),
                          style: TextStyle(color: Colors.white.withAlpha(210), fontWeight: FontWeight.w500)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(99)),
                      child: Text('SY ${store.profile.sy}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text('$greet${name.isEmpty ? '' : ', $name'}!',
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.2)),
                  if (store.profile.schoolName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(store.profile.schoolName, style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13)),
                    ),
                  const SizedBox(height: 18),
                  Row(children: [
                    HeroAction(
                      icon: Icons.fact_check_rounded,
                      label: 'Attendance',
                      onTap: () => classes.isEmpty
                          ? push(context, const ClassFormScreen())
                          : _pickClass(context, classes, 'Take attendance', (c) => push(context, AttendanceScreen(cls: c))),
                    ),
                    const SizedBox(width: 10),
                    HeroAction(icon: Icons.document_scanner_rounded, label: 'Check papers', onTap: () => onGo(2)),
                    const SizedBox(width: 10),
                    HeroAction(
                      icon: Icons.edit_note_rounded,
                      label: 'Add scores',
                      onTap: () => classes.isEmpty
                          ? push(context, const ClassFormScreen())
                          : _pickClass(context, classes, 'Add scores', (c) => push(context, ClassRecordScreen(cls: c))),
                    ),
                  ]),
                ]),
              ),
              if (classes.isEmpty) ...[
                const SizedBox(height: 16),
                AppCard(
                  child: EmptyState(
                    icon: Icons.groups_rounded,
                    title: 'Add your first class',
                    message: 'A class is one section and subject, for example Grade 8 - Sampaguita, Mathematics.',
                    action: FilledButton.icon(
                      onPressed: () => push(context, const ClassFormScreen()),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add class'),
                    ),
                  ),
                ),
              ] else ...[
                SectionTitle('To do today', trailing: Text('$done of ${tasks.length} done', style: TextStyle(color: mutedText(context), fontWeight: FontWeight.w600))),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Column(children: [
                    SlimProgress(value: done / tasks.length, color: goodGreen),
                    const SizedBox(height: 6),
                    for (final t in tasks)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: t.$4,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(children: [
                            Icon(t.$3 ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: t.$3 ? goodGreen : mutedText(context), size: 26),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(t.$1,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      decoration: t.$3 ? TextDecoration.lineThrough : null,
                                      color: t.$3 ? mutedText(context) : null,
                                    )),
                                Text(t.$2, style: TextStyle(fontSize: 12.5, color: mutedText(context))),
                              ]),
                            ),
                            if (!t.$3) Icon(Icons.arrow_forward_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
                          ]),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.55,
                  children: [
                    StatTile(icon: Icons.groups_rounded, label: 'Learners', value: '$learners', sub: '${classes.length} class(es)', onTap: () => onGo(1)),
                    StatTile(
                      icon: Icons.document_scanner_rounded,
                      label: 'Papers to check',
                      value: '$unchecked',
                      sub: 'Across your exams',
                      color: unchecked > 0 ? lateAmber : goodGreen,
                      onTap: () => onGo(2),
                    ),
                  ],
                ),
                SectionTitle('Your classes', trailing: TextButton(onPressed: () => onGo(1), child: const Text('See all'))),
                for (var i = 0; i < classes.length; i++) _classCard(context, classes[i], i),
              ],
            ]);
          },
        ),
      ),
    );
  }

  Widget _classCard(BuildContext context, _ClassSummary c, int i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          onTap: () => push(context, ClassDetailScreen(classId: c.cls.id)),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: classColor(i).withAlpha(isDark(context) ? 60 : 30), borderRadius: BorderRadius.circular(16)),
              child: Text(c.cls.grade.replaceAll(RegExp(r'[^0-9]'), '').isEmpty ? 'K' : c.cls.grade.replaceAll(RegExp(r'[^0-9]'), ''),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: classColor(i))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.cls.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('${c.cls.subject} · ${c.learners} learners', style: TextStyle(fontSize: 13, color: mutedText(context))),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (c.attendanceToday)
                    Pill('${c.present}/${c.learners} present', color: goodGreen, icon: Icons.check_rounded)
                  else
                    const Pill('No attendance yet', color: lateAmber, icon: Icons.schedule_rounded),
                  if (c.unchecked > 0) Pill('${c.unchecked} to check', color: brandBlue, icon: Icons.document_scanner_rounded),
                  if (c.belowPassing > 0) Pill('${c.belowPassing} below 75', color: penRed, icon: Icons.trending_down_rounded),
                ]),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: mutedText(context)),
          ]),
        ),
      );
}
