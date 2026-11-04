import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/export/form_data.dart';
import '../core/models.dart';
import 'attendance/attendance_screen.dart';
import 'attention_screen.dart';
import 'brand.dart';
import 'classes/class_detail_screen.dart';
import 'classes/class_form.dart';
import 'classes/learners_screen.dart';
import 'grades/class_record_screen.dart';
import 'settings/backup.dart';
import 'theme.dart';
import 'widgets.dart';

class _ClassSummary {
  final SchoolClass cls;
  final int learners;
  final int marked;
  final int present;
  final int unchecked;
  final int belowPassing;
  _ClassSummary(this.cls, this.learners, this.marked, this.present, this.unchecked, this.belowPassing);

  bool get attendanceDone => learners > 0 && marked >= learners;
}

class _HomeData {
  final List<_ClassSummary> classes;
  final int attention;
  final String? backupReminder;
  _HomeData(this.classes, this.attention, this.backupReminder);
}

Color classColor(int i) => palette.classColors[i % palette.classColors.length];

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onGo});
  final void Function(int tab) onGo;

  Future<_HomeData> _load() async {
    final repo = store.repo;
    final today = dayKey(DateTime.now());
    final out = <_ClassSummary>[];
    var attention = 0;
    for (final c in await repo.classes()) {
      final learners = (await repo.learners(c.id)).where((l) => l.isActive).toList();
      final att = (await repo.attendance(c.id, from: today, to: today))[today] ?? {};
      var unchecked = 0;
      for (final e in await repo.exams(classId: c.id)) {
        if ((await repo.items(e.id)).isEmpty) continue;
        final resp = await repo.responses(e.id);
        unchecked += learners.where((l) => !resp.containsKey(l.id)).length;
      }
      final rows = await attentionFor(c, learners);
      attention += rows.length;
      out.add(_ClassSummary(c, learners.length, att.length, att.values.where((s) => s != 'A').length, unchecked, rows.where((r) => r.grade != null).length));
    }
    return _HomeData(out, attention, backupReminder(await repo.settings(), [for (final s in out) s.cls]));
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'Magandang umaga' : hour < 18 ? 'Magandang hapon' : 'Magandang gabi';
    final name = store.profile.teacher.trim().split(' ').first;
    final weekend = DateTime.now().weekday > DateTime.friday;
    return Scaffold(
      body: SafeArea(
        child: Loader<_HomeData>(
          load: _load,
          builder: (context, data) {
            final classes = data.classes;
            final all = [for (final c in classes) c.cls];
            final noLearners = [for (final c in classes) if (c.learners == 0) c.cls];
            final pending = [for (final c in classes) if (c.learners > 0 && !c.attendanceDone) c.cls];
            final unchecked = classes.fold<int>(0, (a, c) => a + c.unchecked);
            void takeAttendance(List<SchoolClass> from) => pickClass(context, from, 'Take attendance', (c) => push(context, AttendanceScreen(cls: c)));
            final tasks = <(String, String, bool, VoidCallback)>[
              if (noLearners.isNotEmpty)
                (
                  'Add your learners',
                  noLearners.length == 1 ? '${noLearners.first.title} has no learners yet' : '${noLearners.length} classes have no learners yet',
                  false,
                  () => pickClass(context, noLearners, 'Add learners', (c) => push(context, ImportLearnersScreen(cls: c))),
                ),
              if (!weekend && noLearners.length < classes.length)
                (
                  'Take attendance',
                  pending.isEmpty ? 'Done for all classes' : pending.length == 1 ? '${pending.first.title} is left today' : '${pending.length} classes left today',
                  pending.isEmpty,
                  () => takeAttendance(pending.isEmpty ? all : pending),
                ),
              (
                'Check papers',
                unchecked == 0 ? 'No papers waiting' : unchecked == 1 ? '1 paper waiting' : '$unchecked papers waiting',
                unchecked == 0,
                () => onGo(2),
              ),
            ];

            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
              const Padding(padding: EdgeInsets.fromLTRB(2, 0, 2, 12), child: Align(alignment: Alignment.centerLeft, child: BrandLogo(size: 34))),
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
                      onTap: () => classes.isEmpty ? push(context, const ClassFormScreen()) : takeAttendance(pending.isEmpty ? all : pending),
                    ),
                    const SizedBox(width: 10),
                    HeroAction(icon: Icons.document_scanner_rounded, label: 'Check papers', onTap: () => onGo(2)),
                    const SizedBox(width: 10),
                    HeroAction(
                      icon: Icons.edit_note_rounded,
                      label: 'Add scores',
                      onTap: () => classes.isEmpty
                          ? push(context, const ClassFormScreen())
                          : pickClass(context, all, 'Add scores', (c) => push(context, ClassRecordScreen(cls: c))),
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
                const SectionTitle('To do today'),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Column(children: [for (final t in tasks) _task(context, t)]),
                ),
                if (data.attention > 0 || data.backupReminder != null) const SizedBox(height: 10),
                if (data.attention > 0)
                  NavRow(
                    icon: Icons.volunteer_activism_rounded,
                    title: data.attention == 1 ? '1 learner needs help' : '${data.attention} learners need help',
                    subtitle: 'Grades below 75 or many absences',
                    color: penRed,
                    onTap: () => push(context, const AttentionScreen()),
                  ),
                if (data.backupReminder != null)
                  NavRow(
                    icon: Icons.backup_rounded,
                    title: 'Back up your records',
                    subtitle: data.backupReminder,
                    color: lateAmber,
                    onTap: () => backUpNow(context),
                  ),
                SectionTitle('Your classes', trailing: TextButton(onPressed: () => onGo(1), child: const Text('See all'))),
                for (var i = 0; i < classes.length; i++) _classCard(context, classes[i], i, weekend),
              ],
            ]);
          },
        ),
      ),
    );
  }

  Widget _task(BuildContext context, (String, String, bool, VoidCallback) t) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: t.$4,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(t.$3 ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: t.$3 ? goodGreen : mutedText(context), size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.$1, style: TextStyle(fontWeight: FontWeight.w600, color: t.$3 ? mutedText(context) : null)),
                Text(t.$2, style: TextStyle(fontSize: 12.5, color: mutedText(context))),
              ]),
            ),
            if (!t.$3) Icon(Icons.arrow_forward_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
          ]),
        ),
      );

  Widget _classCard(BuildContext context, _ClassSummary c, int i, bool weekend) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          onTap: () => push(context, ClassDetailScreen(classId: c.cls.id)),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: classColor(i).withAlpha(isDark(context) ? 60 : 30), borderRadius: BorderRadius.circular(16)),
              child: Text(gradeShort(c.cls.grade), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: classColor(i))),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.cls.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('${c.cls.subject} · ${c.learners} learners', style: TextStyle(fontSize: 13, color: mutedText(context))),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (c.attendanceDone)
                    Pill('${c.present}/${c.learners} present', color: goodGreen, icon: Icons.check_rounded)
                  else if (c.marked > 0)
                    Pill('${c.learners - c.marked} left to mark', color: lateAmber, icon: Icons.schedule_rounded)
                  else if (!weekend && c.learners > 0)
                    Pill('No attendance yet', color: lateAmber, icon: Icons.schedule_rounded),
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
