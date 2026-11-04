import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db.dart';
import '../../core/export/share.dart';
import '../../core/models.dart';
import '../widgets.dart';

const _backupKey = 'last_backup';
const _remindAfterDays = 14;

/// Saves everything to one file through the share sheet and remembers when it was done.
Future<void> backUpNow(BuildContext context) async {
  await withProgress(context, 'Making a backup...', () async {
    final json = await store.repo.exportJson();
    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final shared = await saveAndShare(Uint8List.fromList(utf8.encode(json)), 'KlaseKo backup $stamp.json', 'application/json');
    if (shared) {
      await store.repo.putSettings({_backupKey: '${now()}'});
      store.changed();
    }
  });
}

int? _daysSince(int? millis) => millis == null ? null : DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(millis)).inDays;

/// "Last backup: today", for the Back up row.
String backupStatus(Map<String, String> settings) {
  final days = _daysSince(int.tryParse(settings[_backupKey] ?? ''));
  if (days == null) return 'No backup yet. Save all classes, scores and exams to one file, and keep it in Google Drive or on a USB drive.';
  final when = days == 0 ? 'today' : days == 1 ? 'yesterday' : '$days days ago';
  return 'Last backup: $when. Keep the file in Google Drive or on a USB drive.';
}

/// A reminder for the Today screen when records have gone too long without a backup, or null.
String? backupReminder(Map<String, String> settings, List<SchoolClass> classes) {
  if (classes.isEmpty) return null;
  final last = _daysSince(int.tryParse(settings[_backupKey] ?? ''));
  if (last != null) return last >= _remindAfterDays ? 'Your last backup was $last days ago. A lost phone would lose those records.' : null;
  final oldest = classes.map((c) => c.created).reduce((a, b) => a < b ? a : b);
  return _daysSince(oldest)! >= _remindAfterDays ? 'You have no backup yet. A lost phone would lose your records.' : null;
}
