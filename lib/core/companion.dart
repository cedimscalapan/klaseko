import 'dart:convert';

import 'models.dart';

String localDay(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

enum WorkStatus {
  unrecorded('Unrecorded'),
  missing('Missing'),
  submitted('Submitted'),
  late('Late'),
  excused('Excused'),
  scored('Scored');

  const WorkStatus(this.label);
  final String label;
}

/// Scores remain the source of truth. A late submission can also have a score.
WorkStatus workStatus(
    Activity activity, String learner, double? score, DateTime today) {
  final saved = activity.workStates[learner];
  if (saved == 'excused') return WorkStatus.excused;
  if (saved == 'late') return WorkStatus.late;
  if (score != null) return WorkStatus.scored;
  if (saved == 'submitted') return WorkStatus.submitted;
  if (saved == 'missing') return WorkStatus.missing;
  if (activity.dueDate.isNotEmpty &&
      activity.dueDate.compareTo(localDay(today)) < 0) {
    return WorkStatus.missing;
  }
  return WorkStatus.unrecorded;
}

class WorkEntry {
  const WorkEntry(this.activity, this.learner, this.score, this.status);
  final Activity activity;
  final Learner learner;
  final double? score;
  final WorkStatus status;
  bool get awaitingScore =>
      score == null &&
      (status == WorkStatus.submitted || status == WorkStatus.late);
}

List<WorkEntry> workEntries(List<Activity> activities, List<Learner> learners,
    Map<String, Map<String, double>> scores, DateTime today) {
  final entries = <WorkEntry>[];
  for (final activity in activities) {
    for (final learner in learners.where((l) => l.isActive)) {
      final score = scores[activity.id]?[learner.id];
      entries.add(WorkEntry(activity, learner, score,
          workStatus(activity, learner.id, score, today)));
    }
  }
  // The earliest overdue work comes first; undated work stays at the end.
  entries.sort((a, b) {
    final date = (a.activity.dueDate.isEmpty ? '9999' : a.activity.dueDate)
        .compareTo(b.activity.dueDate.isEmpty ? '9999' : b.activity.dueDate);
    if (date != 0) return date;
    final title = a.activity.title.compareTo(b.activity.title);
    return title != 0
        ? title
        : a.learner.fullName.compareTo(b.learner.fullName);
  });
  return entries;
}

class ClassNote {
  const ClassNote(
      {required this.id,
      required this.classId,
      required this.text,
      required this.created,
      required this.updated,
      this.learnerId = '',
      this.remindOn = '',
      this.pinned = false,
      this.done = false});
  final String id, classId, text, learnerId, remindOn;
  final int created, updated;
  final bool pinned, done;
  ClassNote copyWith(
          {String? text,
          String? learnerId,
          String? remindOn,
          bool? pinned,
          bool? done,
          int? updated}) =>
      ClassNote(
          id: id,
          classId: classId,
          text: text ?? this.text,
          created: created,
          updated: updated ?? this.updated,
          learnerId: learnerId ?? this.learnerId,
          remindOn: remindOn ?? this.remindOn,
          pinned: pinned ?? this.pinned,
          done: done ?? this.done);
  Map<String, dynamic> toJson() => {
        'id': id,
        'classId': classId,
        'text': text,
        'created': created,
        'updated': updated,
        'learnerId': learnerId,
        'remindOn': remindOn,
        'pinned': pinned,
        'done': done
      };
  factory ClassNote.fromJson(Map<String, dynamic> m) => ClassNote(
      id: m['id'] as String,
      classId: m['classId'] as String,
      text: m['text'] as String,
      created: m['created'] as int,
      updated: m['updated'] as int,
      learnerId: m['learnerId'] as String? ?? '',
      remindOn: m['remindOn'] as String? ?? '',
      pinned: m['pinned'] == true,
      done: m['done'] == true);
}

/// An optional weekly routine, separate from attendance and the school calendar.
class ClassRoutine {
  const ClassRoutine({this.days = const [], this.minute});
  final List<int> days;
  final int? minute;
  bool get configured => days.isNotEmpty;
  bool occursOn(DateTime date) => configured
      ? days.contains(date.weekday)
      : date.weekday <= DateTime.friday;
  Map<String, dynamic> toJson() => {'days': days, 'minute': minute};
  factory ClassRoutine.decode(String? value) {
    if (value == null || value.isEmpty) return const ClassRoutine();
    final m = jsonDecode(value) as Map<String, dynamic>;
    return ClassRoutine(
        days: (m['days'] as List).cast<int>(), minute: m['minute'] as int?);
  }
}

class TodayPreferences {
  const TodayPreferences(
      {this.reminders = false,
      this.attendance = true,
      this.backupReminders = false});
  final bool reminders, attendance, backupReminders;
  factory TodayPreferences.fromSettings(Map<String, String> settings) =>
      TodayPreferences(
          reminders: settings['today_reminders'] == '1',
          backupReminders: settings['today_backup_reminders'] == '1',
          attendance: settings['today_attendance'] != '0');
}

class TodayAction {
  const TodayAction(
      {required this.id,
      required this.kind,
      required this.classId,
      required this.title,
      required this.detail,
      required this.priority,
      this.activityId,
      this.noteId,
      this.minute = 0});
  final String id, kind, classId, title, detail;
  final String? activityId, noteId;
  final int priority, minute;
}

/// One suggestion, with dismissals scoped to the local calendar day.
TodayAction? nextTodayAction(
    List<TodayAction> actions, Map<String, String> settings, DateTime today) {
  final visible = actions
      .where((a) => settings['today_dismiss_${a.id}'] != localDay(today))
      .toList();
  visible.sort((a, b) {
    final priority = a.priority.compareTo(b.priority);
    if (priority != 0) return priority;
    final time = a.minute.compareTo(b.minute);
    return time != 0 ? time : a.id.compareTo(b.id);
  });
  return visible.isEmpty ? null : visible.first;
}
