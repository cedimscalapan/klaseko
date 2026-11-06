import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/export/form_data.dart';
import '../../core/models.dart';
import '../../core/teaching.dart';
import '../attendance/attendance_screen.dart';
import '../exams/exams_screen.dart';
import '../grades/class_record_screen.dart';
import '../reports/reports_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import '../teaching_screen.dart';
import '../forms/forms_assistant_screen.dart';
import 'class_form.dart';
import 'learners_screen.dart';

class _Detail {
  final SchoolClass cls;
  final List<Learner> learners;
  final Map<String, String> today;
  final int exams;
  final int activities;

  /// Another class of this section that already has its class list.
  final SchoolClass? listFrom;
  _Detail(
    this.cls,
    this.learners,
    this.today,
    this.exams,
    this.activities,
    this.listFrom,
  );
}

class ClassDetailScreen extends StatelessWidget {
  const ClassDetailScreen({super.key, required this.classId});
  final String classId;

  Future<_Detail?> _load() async {
    final repo = store.repo;
    final cls = await repo.classById(classId);
    if (cls == null) return null;
    final today = dayKey(DateTime.now());
    final learners = await repo.learners(classId);
    SchoolClass? listFrom;
    if (learners.isEmpty) {
      for (final other in await sectionClasses(repo, cls)) {
        if ((await repo.learners(other.id)).isNotEmpty) {
          listFrom = other;
          break;
        }
      }
    }
    return _Detail(
      cls,
      learners,
      (await repo.attendance(classId, from: today, to: today))[today] ?? {},
      (await repo.exams(classId: classId)).length,
      (await repo.activities(classId)).length,
      listFrom,
    );
  }

  Future<void> _copyList(
    BuildContext context,
    SchoolClass c,
    SchoolClass from,
  ) async {
    final source =
        (await store.repo.learners(from.id)).where((l) => l.isActive);
    for (final l in source) {
      await store.repo.saveLearner(
        Learner.fromMap({...l.toMap(), 'id': newId(), 'class_id': c.id}),
      );
    }
    store.changed();
    if (context.mounted)
      toast(context, 'Class list added from ${from.subject}.', success: true);
  }

  Future<void> _delete(BuildContext context, SchoolClass c) async {
    final ok = await confirm(
      context,
      title: 'Delete ${c.title}?',
      message:
          'This removes the class, its learners, attendance, scores and exams from this phone. Make a backup first if you may need them.',
    );
    if (!ok) return;
    await store.repo.deleteClass(c.id);
    store.changed();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Loader<_Detail?>(
      load: _load,
      builder: (context, d) {
        if (d == null)
          return const Scaffold(
            body: EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Class deleted',
              message: 'This class is no longer on this phone.',
            ),
          );
        final c = d.cls;
        final active = d.learners.where((l) => l.isActive).toList();
        final present = d.today.values.where((s) => s != 'A').length;
        return Scaffold(
          appBar: AppBar(
            title: Text(c.subject),
            actions: [
              IconButton(
                tooltip: 'Edit class',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => push(context, ClassFormScreen(existing: c)),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'delete' ? _delete(context, c) : null,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: penRed),
                      title: Text('Delete class'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              HeroHeader(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SY ${c.sy} · ${c.advisory ? 'Advisory class' : 'Subject class'} · WW ${c.ww.toInt()} / PT ${c.pt.toInt()} / EX ${c.ex.toInt()}',
                      style: TextStyle(
                        color: Colors.white.withAlpha(210),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _heroStat('${active.length}', 'learners'),
                        _divider(),
                        _heroStat(
                          d.today.isEmpty ? '-' : '$present/${d.today.length}',
                          'present today',
                        ),
                        _divider(),
                        _heroStat(
                          '${d.exams}',
                          d.exams == 1 ? 'exam' : 'exams',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (d.learners.isEmpty) ...[
                const SizedBox(height: 14),
                if (d.listFrom != null)
                  NavRow(
                    icon: Icons.group_add_rounded,
                    title: 'Use the class list from ${d.listFrom!.subject}',
                    subtitle: 'The same section, already entered',
                    highlight: true,
                    color: goodGreen,
                    onTap: () => _copyList(context, c, d.listFrom!),
                  ),
                NavRow(
                  icon: Icons.person_add_alt_1_rounded,
                  title: 'Start here: add your learners',
                  subtitle:
                      'Choose an Excel file, or paste the list from SF1 or LIS',
                  highlight: true,
                  onTap: () => push(context, ImportLearnersScreen(cls: c)),
                ),
              ],
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width < 360 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.4
                    ? 1
                    : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent:
                    174 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 3),
                children: [
                  ActionTile(
                    icon: Icons.fact_check_rounded,
                    title: 'Attendance',
                    subtitle:
                        d.today.isEmpty ? 'Not taken today' : 'Taken today',
                    color: goodGreen,
                    badge: d.today.isEmpty ? 'To do' : null,
                    onTap: () => push(context, AttendanceScreen(cls: c)),
                  ),
                  ActionTile(
                    icon: Icons.grid_view_rounded,
                    title: 'Class record',
                    subtitle:
                        '${d.activities} activities · grades auto-computed',
                    onTap: () => push(context, ClassRecordScreen(cls: c)),
                  ),
                  ActionTile(
                    icon: Icons.quiz_rounded,
                    title: 'Exams',
                    subtitle: d.exams == 0
                        ? 'Make a test and answer sheets'
                        : 'Print, check, analyze',
                    color: violet,
                    onTap: () => push(context, ExamsScreen(cls: c)),
                  ),
                  ActionTile(
                    icon: Icons.people_alt_rounded,
                    title: 'Learners',
                    subtitle: '${d.learners.length} on the class list',
                    color: teal,
                    onTap: () => push(context, LearnersScreen(cls: c)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              NavRow(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Forms Assistant',
                  subtitle:
                      'Enter once, fix missing inputs and generate a form pack',
                  onTap: () => push(context, FormsAssistantScreen(cls: c))),
              NavRow(
                icon: Icons.school,
                title: 'Teaching workspace',
                subtitle:
                    'School policy, rubrics, outcomes, support and reports',
                onTap: () => push(context, TeachingScreen(cls: c)),
              ),
              NavRow(
                icon: Icons.description_rounded,
                title: TeachingPolicy.decode(c.teachingPolicy).sector == 'DepEd'
                    ? 'Reports and school forms'
                    : 'Institution reports',
                subtitle: c.advisory
                    ? 'SF1, SF2, SF9, class record, grade sheet'
                    : 'SF2, class record, grade sheet',
                color: gold,
                onTap: () => push(
                  context,
                  TeachingPolicy.decode(c.teachingPolicy).sector == 'DepEd'
                      ? ReportsScreen(cls: c)
                      : TeachingScreen(cls: c),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _heroStat(String value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style:
                  TextStyle(color: Colors.white.withAlpha(200), fontSize: 12),
            ),
          ],
        ),
      );

  Widget _divider() => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: Colors.white.withAlpha(60),
      );
}
