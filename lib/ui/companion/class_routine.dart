import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/companion.dart';
import '../../core/models.dart';
import '../widgets.dart';

const weekLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

Future<void> editClassRoutine(BuildContext context, SchoolClass cls) async {
  final saved = await store.repo.settings();
  final routine = ClassRoutine.decode(saved['routine_${cls.id}']);
  final days = routine.days.toSet();
  int? minute = routine.minute;
  if (!context.mounted) return;
  final result = await showDialog<ClassRoutine>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
                title: const Text('Class routine'),
                content: SizedBox(
                    width: 420,
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('${cls.title} · ${cls.subject}'),
                          const SizedBox(height: 12),
                          const Text(
                              'Optional. Choose the days you usually meet so Today can put this class first.'),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, children: [
                            for (var i = 0; i < 7; i++)
                              FilterChip(
                                  label: Text(weekLabels[i]),
                                  selected: days.contains(i + 1),
                                  onSelected: (v) => update(() {
                                        if (v) {
                                          days.add(i + 1);
                                        } else {
                                          days.remove(i + 1);
                                        }
                                      }))
                          ]),
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Start time (optional)'),
                              subtitle: Text(minute == null
                                  ? 'No time set'
                                  : TimeOfDay(
                                          hour: minute! ~/ 60,
                                          minute: minute! % 60)
                                      .format(ctx)),
                              trailing: minute == null
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear start time',
                                      onPressed: () =>
                                          update(() => minute = null),
                                      icon: const Icon(Icons.close)),
                              onTap: () async {
                                final time = await showTimePicker(
                                    context: ctx,
                                    initialTime: minute == null
                                        ? const TimeOfDay(hour: 8, minute: 0)
                                        : TimeOfDay(
                                            hour: minute! ~/ 60,
                                            minute: minute! % 60));
                                if (time != null && ctx.mounted)
                                  update(() =>
                                      minute = time.hour * 60 + time.minute);
                              }),
                          const Text(
                              'This does not mark attendance or change the school calendar.'),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, const ClassRoutine()),
                      child: const Text('Clear routine')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: days.isEmpty
                          ? null
                          : () => Navigator.pop(
                              ctx,
                              ClassRoutine(
                                  days: days.toList()..sort(), minute: minute)),
                      child: const Text('Save'))
                ],
              )));
  if (result == null) return;
  await store.repo
      .putSettings({'routine_${cls.id}': jsonEncode(result.toJson())});
  store.changed();
}
