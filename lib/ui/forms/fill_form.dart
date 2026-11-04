import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/export/form_data.dart';
import '../../core/export/share.dart';
import '../../core/forms/form_values.dart';
import '../../core/forms/template_fill.dart';
import '../../core/models.dart';
import '../reports/sf9_screen.dart';
import '../widgets.dart';
import 'archive_info.dart';

class _FillJob {
  final Uint8List bytes;
  final List<CellMap> maps;
  final String form;
  final FormValues values;
  const _FillJob(this.bytes, this.maps, this.form, this.values);
}

FillResult _fillJob(_FillJob j) => fillXlsx(j.bytes, j.maps, j.form, j.values);

Future<DateTime?> _pickMonth(BuildContext context) {
  final months = schoolMonths(store.profile.sy);
  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Which month?', style: Theme.of(ctx).textTheme.titleLarge)),
        for (final (y, m) in months)
          ListTile(
            title: Text('${monthNames[m - 1]} $y'),
            trailing: y == DateTime.now().year && m == DateTime.now().month ? const Icon(Icons.today_rounded) : null,
            onTap: () => Navigator.pop(ctx, DateTime(y, m)),
          ),
      ]),
    ),
  );
}

Future<int?> _pickTerm(BuildContext context, int initial) => showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Which term?', style: Theme.of(ctx).textTheme.titleLarge)),
          for (var t = 1; t <= store.profile.terms; t++)
            ListTile(
              title: Text(store.profile.termName(t)),
              trailing: t == initial ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(ctx, t),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );

/// Fills the teacher's own layout with this class's data, files it in the archive and shares it.
/// A report card makes one file per learner, shared together in one zip file.
Future<void> fillAndShare(BuildContext context, SchoolClass cls, FormTemplate t) async {
  final repo = store.repo;
  final profile = store.profile;
  DateTime? pickedMonth;
  int? pickedTerm;
  if (t.form == 'sf2') {
    pickedMonth = await _pickMonth(context);
    if (pickedMonth == null) return;
  } else if (t.form == 'record') {
    final activities = await repo.activities(cls.id);
    if (!context.mounted) return;
    pickedTerm = await _pickTerm(context, latestTerm(activities));
    if (pickedTerm == null) return;
  }
  final month = pickedMonth, term = pickedTerm;
  if (!context.mounted) return;
  final maps = CellMap.decode(t.mapping);
  var notFitted = 0;
  await withProgress(context, 'Filling your form...', () async {
    final source = await repo.templateBytes(t);
    if (source == null) throw const FormatException('This layout\'s file is no longer on the phone. Please upload it again.');
    final safeName = t.name.isEmpty ? (templateForms[t.form] ?? 'Form') : t.name;
    final period = month == null ? null : '${monthNames[month.month - 1]} ${month.year}';
    final info = ArchiveInfo(cls, t.form, term: term, period: period);
    final areas = t.form == 'sf9' || t.form == 'sf5' ? await loadAreas(cls) : null;
    try {
      if (t.form == 'sf9') {
        final learners = (await repo.learners(cls.id)).where((l) => l.isActive).toList();
        if (learners.isEmpty) throw const FormatException('Add learners to this class first.');
        final zip = Archive();
        for (final l in learners) {
          final v = await buildFormValues(repo, profile, cls, t.form, learner: l, areas: areas);
          final filled = await compute(_fillJob, _FillJob(source, maps, t.form, v));
          final name = '$safeName ${l.last} ${l.first}.xlsx';
          await archiveForm(info, name, filled.bytes, xlsxMime);
          zip.addFile(ArchiveFile(safeFileName(name), filled.bytes.length, filled.bytes));
        }
        final zipped = Uint8List.fromList(ZipEncoder().encode(zip) ?? const <int>[]);
        await saveAndShare(zipped, '$safeName ${cls.title}.zip', 'application/zip');
        return;
      }
      final v = await buildFormValues(repo, profile, cls, t.form, month: month, term: term, areas: areas);
      final filled = await compute(_fillJob, _FillJob(source, maps, t.form, v));
      notFitted = filled.notFitted;
      final label = [safeName, cls.title, if (period != null) period, if (term != null) profile.termName(term)].join(' ');
      await shareAndArchive(info, filled.bytes, '$label.xlsx', xlsxMime);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('This layout could not be filled. Open the file in Excel or WPS, save it again as .xlsx, and upload it again.');
    }
  });
  if (notFitted > 0 && context.mounted) {
    toast(context, notFitted == 1 ? '1 learner did not fit in the rows of this layout. Add rows to the form, or check where the list starts.' : '$notFitted learners did not fit in the rows of this layout. Add rows to the form, or check where the list starts.');
  }
}
