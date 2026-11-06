import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/companion.dart';
import '../core/models.dart';
import 'attendance/attendance_screen.dart';
import 'brand.dart';
import 'classes/class_detail_screen.dart';
import 'classes/class_form.dart';
import 'classes/learners_screen.dart';
import 'companion/class_notes_screen.dart';
import 'companion/class_routine.dart';
import 'companion/work_tracker_screen.dart';
import 'settings/backup.dart';
import 'theme.dart';
import 'widgets.dart';

class _TodayClass {
  const _TodayClass(this.cls, this.learners, this.routine, this.marked);
  final SchoolClass cls;
  final int learners, marked;
  final ClassRoutine routine;
}

class _TodayData {
  const _TodayData(this.classes, this.settings, this.actions);
  final List<_TodayClass> classes;
  final Map<String, String> settings;
  final List<TodayAction> actions;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onGo, this.active = true});
  final void Function(int tab) onGo;
  final bool active;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? timer;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (widget.active) refresh();
    });
  }

  void refresh() {
    if (mounted) setState(() => revision++);
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) revision++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<_TodayData> load() async {
    final repo = store.repo;
    final today = DateTime.now();
    final day = localDay(today);
    final settings = await repo.settings();
    final prefs = TodayPreferences.fromSettings(settings);
    final classes = <_TodayClass>[];
    final actions = <TodayAction>[];
    for (final cls in await repo.classes()) {
      final learners =
          (await repo.learners(cls.id)).where((l) => l.isActive).toList();
      final routine = ClassRoutine.decode(settings['routine_${cls.id}']);
      final attendance =
          (await repo.attendance(cls.id, from: day, to: day))[day] ?? {};
      final marked = learners.where((l) => attendance.containsKey(l.id)).length;
      classes.add(_TodayClass(cls, learners.length, routine, marked));
      final detail = '${cls.title} · ${cls.subject}';
      if (prefs.reminders) {
        for (final note in await repo.classNotes(cls.id)) {
          if (note.done ||
              note.remindOn.isEmpty ||
              note.remindOn.compareTo(day) > 0) continue;
          actions.add(TodayAction(
              id: 'note_${note.id}',
              kind: 'note',
              classId: cls.id,
              title: 'Your class reminder',
              detail: '$detail\n${note.text}',
              priority: 1,
              noteId: note.id));
        }
      }
      if (learners.isEmpty) {
        actions.add(TodayAction(
            id: 'learners_${cls.id}',
            kind: 'learners',
            classId: cls.id,
            title: 'Add a class list',
            detail: detail,
            priority: 0));
        continue;
      }
      if (prefs.attendance &&
          routine.occursOn(today) &&
          marked < learners.length) {
        actions.add(TodayAction(
            id: 'attendance_${cls.id}',
            kind: 'attendance',
            classId: cls.id,
            title: marked == 0 ? 'Take attendance' : 'Finish attendance',
            detail: '$detail · ${learners.length - marked} to mark',
            priority: 2,
            minute: routine.minute ?? 24 * 60));
      }
      final activities = await repo.activities(cls.id);
      final entries =
          workEntries(activities, learners, await repo.scores(cls.id), today);
      final missing =
          entries.where((e) => e.status == WorkStatus.missing).toList();
      if (missing.isNotEmpty) {
        actions.add(TodayAction(
            id: 'missing_${cls.id}',
            kind: 'missing',
            classId: cls.id,
            activityId: missing.first.activity.id,
            title: 'Follow up missing work',
            detail: '$detail · ${missing.length} missing submissions',
            priority: 3));
      }
      final awaiting = entries.where((e) => e.awaitingScore).toList();
      if (awaiting.isNotEmpty) {
        actions.add(TodayAction(
            id: 'scoring_${cls.id}',
            kind: 'scoring',
            classId: cls.id,
            title: 'Score received work',
            detail: '$detail · ${awaiting.length} awaiting scores',
            priority: 4));
      }
    }
    if (prefs.backupReminders) {
      final backup =
          backupReminder(settings, classes.map((c) => c.cls).toList());
      if (backup != null)
        actions.add(TodayAction(
            id: 'backup',
            kind: 'backup',
            classId: '',
            title: 'Back up your records',
            detail: backup,
            priority: 5));
    }
    classes.sort((a, b) {
      final aToday = a.routine.occursOn(today),
          bToday = b.routine.occursOn(today);
      if (aToday != bToday) return aToday ? -1 : 1;
      return (a.routine.minute ?? 1440).compareTo(b.routine.minute ?? 1440);
    });
    return _TodayData(classes, settings, actions);
  }

  void act(_TodayData data, TodayAction action) {
    if (action.kind == 'backup') {
      backUpNow(context);
      return;
    }
    final cls = data.classes.firstWhere((c) => c.cls.id == action.classId).cls;
    switch (action.kind) {
      case 'learners':
        push(context, ImportLearnersScreen(cls: cls));
      case 'attendance':
        push(context, AttendanceScreen(cls: cls));
      case 'missing':
        push(context, WorkTrackerScreen(cls: cls));
      case 'scoring':
        push(context,
            WorkTrackerScreen(cls: cls, initialFilter: 'Awaiting score'));
      case 'note':
        push(context, ClassNotesScreen(cls: cls));
    }
  }

  Future<void> options(_TodayData data) async {
    final prefs = TodayPreferences.fromSettings(data.settings);
    var reminders = prefs.reminders, attendance = prefs.attendance;
    var backupReminders = prefs.backupReminders;
    final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: const Text('Make Today yours'),
                  content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Suggest attendance'),
                            subtitle: const Text(
                                'Uses your optional class routine; otherwise Monday to Friday.'),
                            value: attendance,
                            onChanged: (v) => update(() => attendance = v)),
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Note reminders'),
                            subtitle: const Text(
                                'Only inside Today, when you open the app. You can dismiss any suggestion for the day.'),
                            value: reminders,
                            onChanged: (v) => update(() => reminders = v)),
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Backup reminders'),
                            subtitle: const Text(
                                'An occasional suggestion to save an encrypted backup.'),
                            value: backupReminders,
                            onChanged: (v) =>
                                update(() => backupReminders = v)),
                        TextButton(
                            onPressed: () async {
                              await store.repo.putSettings({
                                for (final key in data.settings.keys.where(
                                    (k) => k.startsWith('today_dismiss_')))
                                  key: ''
                              });
                              store.changed();
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            },
                            child:
                                const Text('Show dismissed suggestions again')),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Save'))
                  ],
                )));
    if (result != true) return;
    await store.repo.putSettings({
      'today_reminders': reminders ? '1' : '0',
      'today_backup_reminders': backupReminders ? '1' : '0',
      'today_attendance': attendance ? '1' : '0'
    });
    store.changed();
  }

  Future<void> dismiss(TodayAction action) async {
    await store.repo
        .putSettings({'today_dismiss_${action.id}': localDay(DateTime.now())});
    store.changed();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Loader<_TodayData>(
              key: ValueKey(revision),
              load: load,
              builder: (context, data) {
                final today = DateTime.now();
                final next =
                    nextTodayAction(data.actions, data.settings, today);
                final all = data.classes.map((c) => c.cls).toList();
                final todays = data.classes
                    .where((c) => c.routine.occursOn(today))
                    .toList();
                final hour = today.hour;
                final greeting = hour < 12
                    ? 'Magandang umaga'
                    : hour < 18
                        ? 'Magandang hapon'
                        : 'Magandang gabi';
                final name = store.profile.teacher.trim().split(' ').first;
                void choose(String title, void Function(SchoolClass) action) {
                  if (all.isEmpty) {
                    push(context, const ClassFormScreen());
                    return;
                  }
                  pickClass(context, all, title, action);
                }

                return RefreshIndicator(
                    onRefresh: () async => refresh(),
                    child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        children: [
                          Row(children: [
                            const BrandLogo(size: 34),
                            const Spacer(),
                            const Tooltip(
                                message: 'Saved on this device · works offline',
                                child: Icon(Icons.verified_user_outlined,
                                    size: 22)),
                            const SizedBox(width: 8),
                            IconButton(
                                tooltip: 'Today options',
                                onPressed: () => options(data),
                                icon: const Icon(Icons.tune_rounded))
                          ]),
                          const SizedBox(height: 14),
                          HeroHeader(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(DateFormat('EEEE, MMMM d').format(today),
                                    style: TextStyle(
                                        color: Colors.white.withAlpha(215))),
                                const SizedBox(height: 8),
                                Text(
                                    '$greeting${name.isEmpty ? '' : ', $name'}!',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 26)),
                                const SizedBox(height: 8),
                                const Text(
                                    'A little less paperwork. More time to teach.',
                                    style: TextStyle(color: Colors.white)),
                              ])),
                          const SectionTitle('Your next step'),
                          if (next != null)
                            AppCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                            child: Text(next.title,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700))),
                                        IconButton(
                                            tooltip: 'Dismiss for today',
                                            onPressed: () => dismiss(next),
                                            icon:
                                                const Icon(Icons.close_rounded))
                                      ]),
                                  const SizedBox(height: 4),
                                  Text(next.detail,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: mutedText(context),
                                          height: 1.5)),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                      onPressed: () => act(data, next),
                                      icon: const Icon(
                                          Icons.arrow_forward_rounded),
                                      label: Text(next.kind == 'attendance'
                                          ? 'Open attendance'
                                          : next.kind == 'missing'
                                              ? 'Open missing work'
                                              : next.kind == 'scoring'
                                                  ? 'Review submissions'
                                                  : next.kind == 'note'
                                                      ? 'Open class notes'
                                                      : next.kind == 'backup'
                                                          ? 'Make backup'
                                                          : 'Add learners')),
                                ]))
                          else
                            AppCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(
                                      all.isEmpty
                                          ? 'Start with one class'
                                          : 'You have room to focus',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  const SizedBox(height: 8),
                                  Text(all.isEmpty
                                      ? 'Add your class and use the same learner list for attendance, scores and forms.'
                                      : 'No more suggestions for today. Your class tools are always available below.'),
                                  if (all.isEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: FilledButton.icon(
                                            onPressed: () => push(context,
                                                const ClassFormScreen()),
                                            icon: const Icon(Icons.add),
                                            label: const Text('Add class'))),
                                ])),
                          const SectionTitle('Quick actions'),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            OutlinedButton.icon(
                                onPressed: () => choose(
                                    'Take attendance',
                                    (c) => push(
                                        context, AttendanceScreen(cls: c))),
                                icon: const Icon(Icons.fact_check_outlined),
                                label: const Text('Attendance')),
                            OutlinedButton.icon(
                                onPressed: () => widget.onGo(2),
                                icon:
                                    const Icon(Icons.document_scanner_outlined),
                                label: const Text('Check papers')),
                            OutlinedButton.icon(
                                onPressed: () => choose('Note for which class?',
                                    (c) => quickClassNote(context, c)),
                                icon: const Icon(Icons.edit_note_rounded),
                                label: const Text('Quick note')),
                          ]),
                          SectionTitle('Today’s classes',
                              trailing: TextButton(
                                  onPressed: () => widget.onGo(1),
                                  child: const Text('See all'))),
                          if (all.isNotEmpty && todays.isEmpty)
                            const Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: Text(
                                    'No classes in your usual routine today. Open Classes to work on any class.')),
                          for (final c in todays)
                            NavRow(
                                icon: Icons.auto_stories_outlined,
                                title: '${c.cls.title} · ${c.cls.subject}',
                                subtitle:
                                    '${c.routine.minute == null ? '' : '${TimeOfDay(hour: c.routine.minute! ~/ 60, minute: c.routine.minute! % 60).format(context)} · '}${c.learners} learners',
                                onTap: () => push(context,
                                    ClassDetailScreen(classId: c.cls.id))),
                          if (all.isNotEmpty)
                            TextButton.icon(
                                onPressed: () => choose(
                                    'Set an optional class routine',
                                    (c) => editClassRoutine(context, c)),
                                icon: const Icon(Icons.schedule_outlined),
                                label: const Text('Set class days and time')),
                        ]));
              })));
}
