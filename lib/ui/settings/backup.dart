import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db.dart';
import '../../core/export/share.dart';
import '../../core/models.dart';
import '../../core/backup_crypto.dart';
import '../widgets.dart';

const _backupKey = 'last_backup';
const _remindAfterDays = 14;

/// Saves everything to one file through the share sheet and remembers when it was done.
Future<void> backUpNow(BuildContext context) async {
  final password = await backupPassword(context, creating: true);
  if (password == null || !context.mounted) return;
  await withProgress(context, 'Making a backup...', () async {
    final json = await store.repo.exportJson();
    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final encrypted = await BackupCrypto.seal(json, password);
    final shared = await saveAndShare(
      Uint8List.fromList(utf8.encode(encrypted)),
      'KlaseKo backup $stamp.kkbackup',
      'application/octet-stream',
    );
    if (shared) {
      await store.repo.putSettings({_backupKey: '${now()}'});
      store.changed();
    }
  });
}

Future<String?> backupPassword(
  BuildContext context, {
  bool creating = false,
}) async {
  final password = TextEditingController();
  final repeat = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(
        title: Text(creating ? 'Protect your backup' : 'Unlock backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              creating
                  ? 'Use at least 12 characters. Keep this password safe; it cannot be recovered.'
                  : 'Enter the password used when making this backup.',
            ),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onChanged: (_) => update(() {}),
            ),
            if (creating)
              TextField(
                controller: repeat,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Repeat password'),
                onChanged: (_) => update(() {}),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed:
                password.text.isNotEmpty &&
                    (!creating ||
                        (password.text.length >= 12 &&
                            password.text == repeat.text))
                ? () => Navigator.pop(ctx, password.text)
                : null,
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}

int? _daysSince(int? millis) => millis == null
    ? null
    : DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(millis))
          .inDays;

/// "Last backup: today", for the Back up row.
String backupStatus(Map<String, String> settings) {
  final days = _daysSince(int.tryParse(settings[_backupKey] ?? ''));
  if (days == null)
    return 'No backup yet. Save all classes, scores and exams to one file, and keep it in Google Drive or on a USB drive.';
  final when = days == 0
      ? 'today'
      : days == 1
      ? 'yesterday'
      : '$days days ago';
  return 'Last backup: $when. Keep the file in Google Drive or on a USB drive.';
}

/// A reminder for the Today screen when records have gone too long without a backup, or null.
String? backupReminder(
  Map<String, String> settings,
  List<SchoolClass> classes,
) {
  if (classes.isEmpty) return null;
  final last = _daysSince(int.tryParse(settings[_backupKey] ?? ''));
  if (last != null)
    return last >= _remindAfterDays
        ? 'Your last backup was $last days ago. A lost phone would lose those records.'
        : null;
  final oldest = classes.map((c) => c.created).reduce((a, b) => a < b ? a : b);
  return _daysSince(oldest)! >= _remindAfterDays
      ? 'You have no backup yet. A lost phone would lose your records.'
      : null;
}
