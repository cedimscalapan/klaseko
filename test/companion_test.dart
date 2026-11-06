import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klaseko/core/companion.dart';
import 'package:klaseko/core/grading.dart';
import 'package:klaseko/core/models.dart';
import 'package:klaseko/core/teaching.dart';
import 'package:klaseko/core/export/xlsx_docs.dart';
import 'package:excel/excel.dart' as xl;
import 'package:klaseko/ui/companion/class_notes_screen.dart';
import 'package:klaseko/ui/theme.dart';

SchoolClass fixtureClass() => SchoolClass(
    id: 'c',
    sy: '2026-2027',
    grade: 'College',
    section: 'A',
    subject: 'Mathematics',
    preset: 'custom',
    ww: 100,
    pt: 0,
    ex: 0,
    exSplit: false,
    transmute: 'raw',
    mode: 'numeric',
    advisory: false,
    created: 0);
Activity activity(String id) => Activity(
    id: id, classId: 'c', term: 1, comp: 'ww', title: id, hps: 20, created: 0);
Learner learner(String id, {String status = 'active'}) => Learner(
    id: id,
    classId: 'c',
    num: 1,
    last: 'Dela Cruz',
    first: id,
    sex: 'F',
    status: status);

void main() {
  final today = DateTime(2026, 11, 6);
  test('Missing is based on a confirmed due date, never the activity date', () {
    final a = activity('a')..day = '2026-01-01';
    expect(workStatus(a, 's', null, today), WorkStatus.unrecorded);
    a.dueDate = '2026-11-06';
    expect(workStatus(a, 's', null, today), WorkStatus.unrecorded);
    a.dueDate = '2026-11-05';
    expect(workStatus(a, 's', null, today), WorkStatus.missing);
    expect(workStatus(a, 's', 0, today), WorkStatus.scored);
  });
  test('Received, late and excused work do not become missing when overdue',
      () {
    final a = activity('a')..dueDate = '2026-10-01';
    for (final status in [
      WorkStatus.submitted,
      WorkStatus.late,
      WorkStatus.excused
    ]) {
      a.workStates['s'] = status.name;
      expect(workStatus(a, 's', null, today), status);
    }
    a.workStates['s'] = 'late';
    expect(workStatus(a, 's', 15, today), WorkStatus.late);
  });
  test('Follow-up excludes departed learners and sorts oldest due work first',
      () {
    final a = activity('new')..dueDate = '2026-11-05';
    final b = activity('old')..dueDate = '2026-10-01';
    final entries = workEntries(
        [a, b],
        [learner('active'), learner('gone', status: 'transferred_out')],
        {},
        today);
    expect(entries.length, 2);
    expect(entries.first.activity.id, 'old');
    expect(entries.every((e) => e.status == WorkStatus.missing), isTrue);
  });
  test('Received and late submissions wait for a score; zero is already scored',
      () {
    final a = activity('a')..workStates = {'s': 'submitted', 'l': 'late'};
    final entries = workEntries([
      a
    ], [
      learner('s'),
      learner('l'),
      learner('z')
    ], {
      'a': {'z': 0}
    }, today);
    expect(entries.where((e) => e.awaitingScore).length, 2);
    expect(
        entries.firstWhere((e) => e.learner.id == 'z').awaitingScore, isFalse);
  });
  test('Pending work does not lower a running grade or become a final grade',
      () {
    final a = activity('scored'), b = activity('missing');
    final engine = GradeEngine(fixtureClass(), [
      a,
      b
    ], {
      'scored': {'s': 16}
    });
    final result = engine.term('s', 1);
    expect(result.initialGrade, 80);
    expect(result.missing, 1);
    expect(result.incomplete, isTrue);
    expect(engine.finalGrade('s', 1).remarks, 'In progress');
  });
  test('An explicit zero counts in grades, unlike an unrecorded submission',
      () {
    final engine = GradeEngine(fixtureClass(), [
      activity('a'),
      activity('b')
    ], {
      'a': {'s': 16},
      'b': {'s': 0}
    });
    expect(engine.term('s', 1).initialGrade, 40);
    expect(engine.term('s', 1).missing, 0);
    expect(engine.finalGrade('s', 1).partial, isFalse);
  });
  test('Excused work is excluded from grades and outcome evidence', () {
    final a = activity('a'), b = activity('b')..workStates['s'] = 'excused';
    final scores = {
      'a': {'s': 16.0},
      'b': {'s': 0.0}
    };
    final result = GradeEngine(fixtureClass(), [a, b], scores).term('s', 1);
    expect(result.initialGrade, 80);
    expect(result.missing, 0);
    expect(result.incomplete, isFalse);
    expect(outcomePercent([a, b], scores, 's'), 80);
  });
  test('An entirely excused component does not keep the grade incomplete', () {
    final cls = fixtureClass()
      ..ww = 50
      ..pt = 50;
    final b = activity('b')
      ..comp = 'pt'
      ..workStates['s'] = 'excused';
    final result = GradeEngine(cls, [
      activity('a'),
      b
    ], {
      'a': {'s': 16}
    }).term('s', 1);
    expect(result.incomplete, isFalse);
    expect(result.initialGrade, 80);
  });
  test('No evidence produces no grade even if all assignments are excused', () {
    final a = activity('a')..workStates['s'] = 'excused';
    final result = GradeEngine(fixtureClass(), [a], {}).term('s', 1);
    expect(result.hasData, isFalse);
    expect(result.display, isEmpty);
  });
  test('One next action respects priority, schedule order and daily dismissal',
      () {
    const actions = [
      TodayAction(
          id: 'late',
          kind: 'attendance',
          classId: 'c',
          title: '',
          detail: '',
          priority: 2,
          minute: 900),
      TodayAction(
          id: 'early',
          kind: 'attendance',
          classId: 'd',
          title: '',
          detail: '',
          priority: 2,
          minute: 480),
      TodayAction(
          id: 'work',
          kind: 'missing',
          classId: 'c',
          title: '',
          detail: '',
          priority: 3),
    ];
    expect(nextTodayAction(actions, {}, today)!.id, 'early');
    final settings = {'today_dismiss_early': '2026-11-06'};
    expect(nextTodayAction(actions, settings, today)!.id, 'late');
    expect(
        nextTodayAction(actions, settings, today.add(const Duration(days: 1)))!
            .id,
        'early');
    expect(nextTodayAction([], {}, today), isNull);
  });
  test('Reminders require opt-in, while attendance can be switched off', () {
    expect(TodayPreferences.fromSettings({}).reminders, isFalse);
    expect(TodayPreferences.fromSettings({}).backupReminders, isFalse);
    final prefs = TodayPreferences.fromSettings(
        {'today_reminders': '1', 'today_attendance': '0'});
    expect(prefs.reminders, isTrue);
    expect(prefs.attendance, isFalse);
    expect(prefs.backupReminders, isFalse);
  });
  test(
      'Routine is optional and supports weekend classes without taking attendance',
      () {
    expect(const ClassRoutine().occursOn(DateTime(2026, 11, 7)), isFalse);
    final routine = ClassRoutine.decode(
        jsonEncode(const ClassRoutine(days: [6], minute: 480).toJson()));
    expect(routine.occursOn(DateTime(2026, 11, 7)), isTrue);
    expect(routine.occursOn(today), isFalse);
    expect(routine.minute, 480);
  });
  test('Notes retain linkage, reminders and completion in backup-ready JSON',
      () {
    const note = ClassNote(
        id: 'n',
        classId: 'c',
        text: 'Bring graph paper',
        created: 1,
        updated: 2,
        learnerId: 's',
        remindOn: '2026-11-07',
        pinned: true);
    final copy = ClassNote.fromJson(
        jsonDecode(jsonEncode(note.toJson())) as Map<String, dynamic>);
    expect(copy.copyWith(done: true).done, isTrue);
    expect(copy.learnerId, 's');
    expect(copy.remindOn, '2026-11-07');
    expect(copy.pinned, isTrue);
    expect(copy.copyWith(text: 'Updated').created, 1);
  });
  test(
      'Class record export identifies running grades and withheld final grades',
      () {
    final cls = fixtureClass();
    final engine = GradeEngine(cls, [
      activity('a'),
      activity('b')
    ], {
      'a': {'s': 16}
    });
    final bytes = buildClassRecordXlsx(
        SchoolProfile()..terms = 1, cls, [learner('s')], engine);
    final book = xl.Excel.decodeBytes(bytes);
    final cells = book.tables.values
        .expand((s) => s.rows)
        .expand((r) => r)
        .map((c) => c?.value.toString() ?? '')
        .toList();
    expect(cells.any((v) => v.contains('(running)')), isTrue);
    expect(cells, contains('In progress'));
    expect(cells, isNot(contains('Passed')));
  });
  for (final brightness in Brightness.values) {
    testWidgets('Quick note saves with one input at narrow width: $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(320, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ClassNote? result;
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: Builder(
              builder: (ctx) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await showModalBottomSheet<ClassNote>(
                            context: ctx,
                            isScrollControlled: true,
                            builder: (_) => NoteEditor(
                                cls: fixtureClass(), learners: [learner('s')]));
                      },
                      child: const Text('Open note'))))));
      await tester.tap(find.text('Open note'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Save note'))
              .onPressed,
          isNull);
      await tester.enterText(find.widgetWithText(TextField, 'Note'),
          'Continue fractions tomorrow');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save note'));
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(result!.text, 'Continue fractions tomorrow');
      expect(result!.classId, 'c');
      expect(result!.learnerId, isEmpty);
      expect(result!.remindOn, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
