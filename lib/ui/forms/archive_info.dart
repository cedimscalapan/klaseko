import 'dart:typed_data';

import '../../core/export/share.dart';
import '../../core/models.dart';
import '../widgets.dart';

/// Names of the archive's form folders.
const archiveForms = {
  'sf1': 'SF1 School Register',
  'sf2': 'SF2 Daily Attendance',
  'sf5': 'SF5 Promotion and Proficiency',
  'sf9': 'SF9 Report Cards',
  'record': 'Class Records',
  'grades': 'Summary of Grades',
  'analysis': 'Item Analysis',
  'test': 'Test Papers and Keys',
  'sheets': 'Answer Sheets',
};

/// Where a made form belongs in the archive.
class ArchiveInfo {
  final SchoolClass cls;
  final String form;
  final int? term;

  /// The month or similar the form covers, such as "November 2026".
  final String? period;
  const ArchiveInfo(this.cls, this.form, {this.term, this.period});
}

/// Files a made form in the archive. Making the same form again replaces its older copy. A problem
/// here never stops the teacher from getting the form itself.
Future<void> archiveForm(ArchiveInfo info, String fileName, Uint8List bytes, String mime) async {
  try {
    await store.repo.saveArchive(
      ArchiveEntry(
        id: '',
        classId: info.cls.id,
        classTitle: info.cls.title,
        subject: info.cls.subject,
        sy: info.cls.sy,
        form: info.form,
        term: info.term,
        period: info.period ?? '',
        title: fileName.replaceFirst(RegExp(r'\.\w+$'), ''),
        mime: mime,
        created: DateTime.now().millisecondsSinceEpoch,
      ),
      bytes,
    );
    store.changed();
  } catch (_) {}
}

/// Files the form in the archive, then opens the share sheet.
Future<bool> shareAndArchive(ArchiveInfo info, Uint8List bytes, String fileName, String mime) async {
  await archiveForm(info, fileName, bytes, mime);
  return saveAndShare(bytes, fileName, mime);
}
