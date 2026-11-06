import 'package:flutter/material.dart';

import '../../core/companion.dart';
import '../../core/models.dart';
import '../grades/class_record_screen.dart';
import '../grades/score_entry_screen.dart';
import '../theme.dart';
import '../widgets.dart';

class WorkTrackerScreen extends StatefulWidget {
  const WorkTrackerScreen(
      {super.key,
      required this.cls,
      this.activityId,
      this.initialFilter = 'Missing'});
  final SchoolClass cls;
  final String? activityId;
  final String initialFilter;
  @override
  State<WorkTrackerScreen> createState() => _WorkTrackerScreenState();
}

class _WorkData {
  _WorkData(this.activities, this.learners, this.entries);
  final List<Activity> activities;
  final List<Learner> learners;
  final List<WorkEntry> entries;
}

class _WorkTrackerScreenState extends State<WorkTrackerScreen> {
  late String filter = widget.initialFilter;
  late String selectedActivity = widget.activityId ?? '';
  String query = '';
  int term = 0;
  bool busy = false;

  Future<_WorkData> load() async {
    final activities = await store.repo.activities(widget.cls.id);
    final learners = (await store.repo.learners(widget.cls.id))
        .where((l) => l.isActive)
        .toList();
    final scores = await store.repo.scores(widget.cls.id);
    return _WorkData(activities, learners,
        workEntries(activities, learners, scores, DateTime.now()));
  }

  Future<void> changeStatus(WorkEntry entry, WorkStatus status) async {
    if (busy) return;
    if (entry.score != null &&
        [WorkStatus.missing, WorkStatus.excused, WorkStatus.unrecorded]
            .contains(status)) {
      final ok = await confirm(context,
          title: 'Replace the recorded score?',
          message:
              'Marking this work ${status.label.toLowerCase()} removes ${entry.score} points for ${entry.learner.fullName}.',
          action: 'Replace score');
      if (!ok || !mounted) return;
    }
    setState(() => busy = true);
    try {
      await store.repo
          .setWorkStatus(entry.activity.id, entry.learner.id, status);
      store.changed();
      if (mounted)
        toast(context, 'Marked ${status.label.toLowerCase()}.', success: true);
    } catch (_) {
      if (mounted) toast(context, 'Could not update this work. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseStatus(WorkEntry entry) async {
    final result = await showModalBottomSheet<WorkStatus>(
        context: context,
        useSafeArea: true,
        builder: (ctx) => SingleChildScrollView(
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                      title: Text(entry.learner.fullName),
                      subtitle: Text(entry.activity.title)),
                  for (final status
                      in WorkStatus.values.where((s) => s != WorkStatus.scored))
                    ListTile(
                        leading: Icon(status == entry.status
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off),
                        title: Text(status.label),
                        subtitle: status == WorkStatus.excused
                            ? const Text('Exclude from this learner’s grade')
                            : status == WorkStatus.unrecorded
                                ? const Text(
                                    'No status; overdue work will appear as missing')
                                : null,
                        onTap: () => Navigator.pop(ctx, status)),
                ]))));
    if (result != null && mounted) await changeStatus(entry, result);
  }

  Future<void> dueDate(Activity activity) async {
    final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Assessment due date'),
                content: Text(
                    '${activity.title}\n${activity.dueDate.isEmpty ? 'No due date yet.' : 'Due ${activity.dueDate}'}\n\nUnrecorded work appears as missing after this date. Submitted work stays in Awaiting score.'),
                actions: [
                  if (activity.dueDate.isNotEmpty)
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, ''),
                        child: const Text('Remove date')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.tryParse(activity.dueDate) ??
                                DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100));
                        if (date != null && ctx.mounted)
                          Navigator.pop(ctx, localDay(date));
                      },
                      child: const Text('Choose date'))
                ]));
    if (result == null) return;
    try {
      await store.repo.setWorkDueDate(activity.id, result);
      store.changed();
    } catch (_) {
      if (mounted) toast(context, 'Could not save the due date. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: ClassTitle('Work tracker', widget.cls)),
        body: Loader<_WorkData>(
            load: load,
            builder: (context, data) {
              final activityId =
                  data.activities.any((a) => a.id == selectedActivity)
                      ? selectedActivity
                      : '';
              final terms = data.activities.map((a) => a.term).toSet().toList()
                ..sort();
              final activeTerm = terms.contains(term) ? term : 0;
              final entries = data.entries
                  .where((e) =>
                      (activityId.isEmpty || e.activity.id == activityId) &&
                      (activeTerm == 0 || e.activity.term == activeTerm) &&
                      '${e.learner.fullName} ${e.activity.title}'
                          .toLowerCase()
                          .contains(query.toLowerCase()) &&
                      (filter == 'All' ||
                          (filter == 'Missing' &&
                              e.status == WorkStatus.missing) ||
                          (filter == 'Awaiting score' && e.awaitingScore) ||
                          (filter == 'Unrecorded' &&
                              e.status == WorkStatus.unrecorded)))
                  .toList();
              final missing = data.entries
                  .where((e) => e.status == WorkStatus.missing)
                  .length;
              return AbsorbPointer(
                  absorbing: busy,
                  child: CustomScrollView(slivers: [
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '$missing missing ${missing == 1 ? 'submission' : 'submissions'} across this class',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 4),
                                  Text(
                                      'Blank is not zero. Enter 0 only when you intend to award zero points. Grades stay in progress while scores are pending.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: mutedText(context))),
                                  const SizedBox(height: 12),
                                  TextField(
                                      onChanged: (v) =>
                                          setState(() => query = v),
                                      decoration: const InputDecoration(
                                          prefixIcon: Icon(Icons.search),
                                          hintText:
                                              'Find a learner or assessment')),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                        flex: 2,
                                        child: DropdownButtonFormField<String>(
                                            key: ValueKey(activityId),
                                            initialValue: activityId,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                                labelText: 'Assessment'),
                                            items: [
                                              const DropdownMenuItem(
                                                  value: '',
                                                  child:
                                                      Text('All assessments')),
                                              for (final a in data.activities)
                                                DropdownMenuItem(
                                                    value: a.id,
                                                    child: Text(a.title,
                                                        overflow: TextOverflow
                                                            .ellipsis))
                                            ],
                                            onChanged: (v) => setState(() =>
                                                selectedActivity = v ?? ''))),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: DropdownButtonFormField<int>(
                                            key: ValueKey(activeTerm),
                                            initialValue: activeTerm,
                                            isExpanded: true,
                                            decoration: const InputDecoration(
                                                labelText: 'Period'),
                                            items: [
                                              const DropdownMenuItem(
                                                  value: 0, child: Text('All')),
                                              for (final t in terms)
                                                DropdownMenuItem(
                                                    value: t, child: Text('$t'))
                                            ],
                                            onChanged: (v) =>
                                                setState(() => term = v ?? 0)))
                                  ]),
                                  const SizedBox(height: 8),
                                  SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(children: [
                                        for (final value in [
                                          'Missing',
                                          'Awaiting score',
                                          'Unrecorded',
                                          'All'
                                        ])
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 8),
                                              child: ChoiceChip(
                                                  label: Text(value),
                                                  selected: filter == value,
                                                  onSelected: (_) => setState(
                                                      () => filter = value)))
                                      ])),
                                  if (activityId.isNotEmpty)
                                    Wrap(spacing: 8, children: [
                                      TextButton.icon(
                                          onPressed: () => dueDate(
                                              data.activities.firstWhere(
                                                  (a) => a.id == activityId)),
                                          icon:
                                              const Icon(Icons.event_outlined),
                                          label: Text(data.activities
                                                  .firstWhere(
                                                      (a) => a.id == activityId)
                                                  .dueDate
                                                  .isEmpty
                                              ? 'Set due date'
                                              : 'Due ${data.activities.firstWhere((a) => a.id == activityId).dueDate}')),
                                      TextButton.icon(
                                          onPressed: () => push(
                                              context,
                                              ScoreEntryScreen(
                                                  cls: widget.cls,
                                                  activity: data.activities
                                                      .firstWhere((a) =>
                                                          a.id == activityId))),
                                          icon: const Icon(Icons.edit_outlined),
                                          label: const Text('Enter scores'))
                                    ]),
                                ]))),
                    if (busy)
                      const SliverToBoxAdapter(
                          child: LinearProgressIndicator(minHeight: 2)),
                    if (entries.isEmpty)
                      SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                              icon: Icons.assignment_turned_in_outlined,
                              title: data.activities.isEmpty
                                  ? 'Use your existing assessments'
                                  : 'Nothing here right now',
                              message: data.activities.isEmpty
                                  ? 'Add an activity in the class record. It will appear here automatically.'
                                  : data.learners.isEmpty
                                      ? 'Add learners to this class to track submissions.'
                                      : filter == 'Missing'
                                          ? 'Select an assessment to set a due date, or open Unrecorded to mark work missing or submitted.'
                                          : 'Try another filter or search.',
                              action: data.activities.isEmpty
                                  ? FilledButton(
                                      onPressed: () => push(context,
                                          ClassRecordScreen(cls: widget.cls)),
                                      child: const Text('Open class record'))
                                  : null))
                    else
                      SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          sliver: SliverList.builder(
                              itemCount: entries.length,
                              itemBuilder: (context, index) {
                                final e = entries[index];
                                return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: AppCard(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(e.learner.fullName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 4),
                                          Text(
                                              '${e.activity.title} · Period ${e.activity.term}'),
                                          Text(
                                              '${e.status.label}${e.score == null ? '' : ' · ${fmtScore(e.score!)} / ${fmtScore(e.activity.hps)}'}${e.activity.dueDate.isEmpty ? '' : ' · Due ${e.activity.dueDate}'}',
                                              style: TextStyle(
                                                  color: mutedText(context),
                                                  fontSize: 12)),
                                          const SizedBox(height: 8),
                                          Wrap(spacing: 8, children: [
                                            if (e.status ==
                                                    WorkStatus.missing ||
                                                e.status ==
                                                    WorkStatus.unrecorded)
                                              OutlinedButton(
                                                  onPressed: () => changeStatus(
                                                      e,
                                                      e.activity.dueDate
                                                                  .isNotEmpty &&
                                                              e.activity.dueDate
                                                                      .compareTo(localDay(
                                                                          DateTime
                                                                              .now())) <
                                                                  0
                                                          ? WorkStatus.late
                                                          : WorkStatus
                                                              .submitted),
                                                  child:
                                                      const Text('Received')),
                                            if (e.awaitingScore ||
                                                e.score != null)
                                              OutlinedButton(
                                                  onPressed: () => push(
                                                      context,
                                                      ScoreEntryScreen(
                                                          cls: widget.cls,
                                                          activity: e.activity,
                                                          learnerId:
                                                              e.learner.id)),
                                                  child: const Text(
                                                      'Enter score')),
                                            TextButton(
                                                onPressed: () =>
                                                    chooseStatus(e),
                                                child: const Text(
                                                    'Change status')),
                                            TextButton(
                                                onPressed: () =>
                                                    dueDate(e.activity),
                                                child: const Text('Due date')),
                                          ]),
                                        ])));
                              })),
                  ]));
            }),
      );
}
