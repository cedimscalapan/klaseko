import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

/// One learner found in a class list. [sex] is null when the list does not say.
class ClassListRow {
  final String last;
  final String first;
  final String middle;
  final String? sex;
  final String lrn;
  const ClassListRow({required this.last, required this.first, this.middle = '', this.sex, this.lrn = ''});
}

class ClassListResult {
  final List<ClassListRow> rows;

  /// Lines that had text but no recognizable "Last, First" name.
  final List<String> skipped;
  const ClassListResult(this.rows, this.skipped);
}

final _sexHeading = RegExp(r'^(males?|boys?|lalaki|females?|girls?|babae)\b[\s:()\d]*$', caseSensitive: false);
final _numbering = RegExp(r'^\d{1,3}(\s*[.)\-:]\s*|\s+)(?=\D)');
final _total = RegExp(r'\btotal\b', caseSensitive: false);
const _columnWords = {
  'lrn', 'name', 'names', 'sex', 'gender', 'no', 'no.', 'age', 'birth date', 'birthdate', 'learner', 'learners',
  "learner's name", 'name of learner', 'last name', 'first name', 'middle name', 'address',
};

/// Reads a class list copied from SF1, LIS, Excel or typed by hand, one learner per line:
/// "Last, First, Middle, M, LRN". Numbering, ages and dates are ignored, the parts can be in any
/// order after the name, and "MALE" and "FEMALE" heading lines set the sex of the names under them.
ClassListResult parseClassList(String text) {
  final rows = <ClassListRow>[];
  final skipped = <String>[];
  String? section;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || _total.hasMatch(line)) continue;
    if (_sexHeading.hasMatch(line)) {
      final w = line.toLowerCase();
      section = w.startsWith('f') || w.startsWith('g') || w.startsWith('babae') ? 'F' : 'M';
      continue;
    }
    String? lrn;
    String? sex;
    final names = <String>[];
    for (final part in line.replaceFirst(_numbering, '').split(RegExp(r'[\t,;]'))) {
      final p = part.trim();
      final up = p.toUpperCase();
      if (p.isEmpty) continue;
      if (RegExp(r'^\d{6,}$').hasMatch(p)) {
        lrn = p;
      } else if (up == 'M' || up == 'F' || up == 'MALE' || up == 'FEMALE') {
        sex = up.substring(0, 1);
      } else if (!RegExp(r'\d').hasMatch(p)) {
        names.add(p);
      }
    }
    if (names.any((n) => _columnWords.contains(n.toLowerCase()))) continue; // a row of column titles
    if (names.length < 2) {
      skipped.add(line);
      continue;
    }
    rows.add(ClassListRow(last: names[0], first: names[1], middle: names.length > 2 ? names[2] : '', sex: sex ?? section, lrn: lrn ?? ''));
  }
  return ClassListResult(rows, skipped);
}

/// Turns an Excel workbook into text for [parseClassList]: one line per row, cells separated by tabs.
String xlsxToText(Uint8List bytes) {
  final book = xl.Excel.decodeBytes(bytes);
  final lines = <String>[];
  for (final sheet in book.tables.values) {
    for (final row in sheet.rows) {
      final cells = [for (final c in row) if (c?.value != null) c!.value.toString()];
      if (cells.isNotEmpty) lines.add(cells.join('\t'));
    }
  }
  return lines.join('\n');
}
