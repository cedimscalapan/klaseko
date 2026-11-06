import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'workbook_patch.dart';
import 'assistant.dart' show extraFieldsFor, recordFields;

/// How a piece of data is placed from the cell it is assigned to.
enum FieldKind {
  /// Verified administrative or historical rows, not necessarily learners.
  record,

  /// One value in that cell.
  single,

  /// A series going right from that cell, such as the days of a month.
  across,

  /// One value per learner, going down from that cell.
  learner,

  /// A series going right, on each learner's row.
  learnerAcross,

  /// One value per learning area, going down.
  area,

  /// One value per core value behavior, going down.
  value,
}

class FormDataField {
  final String id;
  final String label;
  final FieldKind kind;
  const FormDataField(this.id, this.label, this.kind);
}

/// Forms that can use a teacher's own Excel layout, and the data each one offers.
const templateForms = {
  'sf1': 'SF1 School Register',
  'sf2': 'SF2 Daily Attendance',
  'sf3': 'SF3 Books Issued and Returned',
  'sf4': 'SF4 School Movement and Attendance',
  'sf6': 'SF6 School Promotion Summary',
  'sf7': 'SF7 Personnel Assignments',
  'sf8': 'SF8 Health and Nutrition',
  'sf10': 'SF10 Permanent Academic Record',
  'sf5': 'SF5 Promotion and Proficiency',
  'sf9': 'SF9 Report Card',
  'record': 'Class Record',
  'grades': 'Summary of Grades',
};

const _about = [
  FormDataField('school_name', 'School name', FieldKind.single),
  FormDataField('school_id', 'School ID', FieldKind.single),
  FormDataField('region', 'Region', FieldKind.single),
  FormDataField('division', 'Division', FieldKind.single),
  FormDataField('district', 'District', FieldKind.single),
  FormDataField('school_head', 'School head', FieldKind.single),
  FormDataField('sy', 'School year', FieldKind.single),
  FormDataField('teacher', 'Teacher or adviser', FieldKind.single),
  FormDataField('grade', 'Grade level', FieldKind.single),
  FormDataField('section', 'Section', FieldKind.single),
  FormDataField('subject', 'Subject or learning area', FieldKind.single),
  FormDataField('today', 'Date today', FieldKind.single),
  FormDataField('male_count', 'Number of males', FieldKind.single),
  FormDataField('female_count', 'Number of females', FieldKind.single),
  FormDataField('total_count', 'Number of learners', FieldKind.single),
];

const _learnerRows = [
  FormDataField('no', 'Learner number', FieldKind.learner),
  FormDataField('name', 'Full name', FieldKind.learner),
  FormDataField('last', 'Last name', FieldKind.learner),
  FormDataField('first', 'First name', FieldKind.learner),
  FormDataField('middle', 'Middle name', FieldKind.learner),
  FormDataField('lrn', 'LRN', FieldKind.learner),
  FormDataField('sex', 'Sex', FieldKind.learner),
];

const _sf1 = [
  FormDataField('birth', 'Birth date', FieldKind.learner),
  FormDataField('age', 'Age', FieldKind.learner),
  FormDataField('address', 'Address', FieldKind.learner),
  FormDataField('guardian', 'Parent or guardian', FieldKind.learner),
  FormDataField('contact', 'Contact number', FieldKind.learner),
  FormDataField('remarks', 'Remarks', FieldKind.learner),
];

const _sf2 = [
  FormDataField('month', 'Month', FieldKind.single),
  FormDataField('school_days', 'School days this month', FieldKind.single),
  FormDataField('day_numbers', 'Dates (goes right)', FieldKind.across),
  FormDataField(
      'day_letters', 'Weekday letters (goes right)', FieldKind.across),
  FormDataField('day_marks', 'Daily marks: x or T (goes right on each row)',
      FieldKind.learnerAcross),
  FormDataField('absent', 'Total absent', FieldKind.learner),
  FormDataField('tardy', 'Total tardy', FieldKind.learner),
  FormDataField('remarks', 'Remarks', FieldKind.learner),
  FormDataField(
      'present_m', 'Males present per day (goes right)', FieldKind.across),
  FormDataField(
      'present_f', 'Females present per day (goes right)', FieldKind.across),
  FormDataField(
      'present_all', 'All present per day (goes right)', FieldKind.across),
];

List<FormDataField> _sf5() => [
      const FormDataField('ga', 'General average', FieldKind.learner),
      const FormDataField('action', 'Action taken', FieldKind.learner),
      const FormDataField(
          'below', 'Learning areas below 75', FieldKind.learner),
      for (final (id, label) in const [
        ('promoted', 'Promoted'),
        ('remedial', 'For Summer Remedial Class'),
        ('retained', 'Retained'),
        ('level1', 'Advancing (90-100)'),
        ('level2', 'Benchmarking (80-89)'),
        ('level3', 'Connecting (75-79)'),
        ('level4', 'Developing (65-74)'),
        ('level5', 'Emerging (below 65)'),
      ])
        for (final (suffix, who) in const [
          ('m', 'male'),
          ('f', 'female'),
          ('t', 'total')
        ])
          FormDataField('${id}_$suffix', '$label: $who', FieldKind.single),
    ];

const _grades = [
  FormDataField('term_1', 'Term 1 grade', FieldKind.learner),
  FormDataField('term_2', 'Term 2 grade', FieldKind.learner),
  FormDataField('term_3', 'Term 3 grade', FieldKind.learner),
  FormDataField('term_4', 'Quarter 4 grade', FieldKind.learner),
  FormDataField('final', 'Final grade', FieldKind.learner),
  FormDataField('descriptor', 'Descriptor', FieldKind.learner),
  FormDataField('remarks', 'Remarks', FieldKind.learner),
];

List<FormDataField> _record() => [
      const FormDataField('term', 'Term', FieldKind.single),
      for (final (c, name) in const [
        ('ww', 'Written Work'),
        ('pt', 'Performance Tasks'),
        ('ex', 'Examinations')
      ]) ...[
        FormDataField(
            '${c}_titles', '$name: titles (goes right)', FieldKind.across),
        FormDataField(
            '${c}_hps', '$name: highest scores (goes right)', FieldKind.across),
        FormDataField(
            '${c}_hps_total', '$name: total highest score', FieldKind.single),
        FormDataField('${c}_weight', '$name: weight', FieldKind.single),
        FormDataField('${c}_scores', '$name: scores (goes right on each row)',
            FieldKind.learnerAcross),
        FormDataField('${c}_total', '$name: total', FieldKind.learner),
        FormDataField('${c}_ps', '$name: percentage score', FieldKind.learner),
        FormDataField('${c}_ws', '$name: weighted score', FieldKind.learner),
      ],
      const FormDataField('initial', 'Initial grade', FieldKind.learner),
      const FormDataField('term_grade', 'Term grade', FieldKind.learner),
    ];

const _sf9 = [
  FormDataField('learner_name', 'Learner name', FieldKind.single),
  FormDataField('learner_lrn', 'Learner LRN', FieldKind.single),
  FormDataField('learner_sex', 'Learner sex', FieldKind.single),
  FormDataField('learner_age', 'Learner age', FieldKind.single),
  FormDataField('ga', 'General average', FieldKind.single),
  FormDataField('ga_remarks', 'General average remarks', FieldKind.single),
  FormDataField('promotion', 'Promotion status', FieldKind.single),
  FormDataField('area_name', 'Learning area name', FieldKind.area),
  FormDataField('area_t1', 'Learning area: term 1', FieldKind.area),
  FormDataField('area_t2', 'Learning area: term 2', FieldKind.area),
  FormDataField('area_t3', 'Learning area: term 3', FieldKind.area),
  FormDataField('area_t4', 'Learning area: quarter 4', FieldKind.area),
  FormDataField('area_final', 'Learning area: final grade', FieldKind.area),
  FormDataField('area_remarks', 'Learning area: remarks', FieldKind.area),
  FormDataField(
      'att_months', 'Attendance: months (goes right)', FieldKind.across),
  FormDataField(
      'att_days', 'Attendance: school days (goes right)', FieldKind.across),
  FormDataField(
      'att_present', 'Attendance: days present (goes right)', FieldKind.across),
  FormDataField(
      'att_absent', 'Attendance: days absent (goes right)', FieldKind.across),
  FormDataField('value_t1', 'Core values: term 1', FieldKind.value),
  FormDataField('value_t2', 'Core values: term 2', FieldKind.value),
  FormDataField('value_t3', 'Core values: term 3', FieldKind.value),
  FormDataField('value_t4', 'Core values: quarter 4', FieldKind.value),
];

/// Everything that can be placed on a layout of this form.
List<FormDataField> fieldsFor(String form) => switch (form) {
      'sf4' || 'sf6' || 'sf7' || 'sf10' => [
          ..._about,
          if (form == 'sf10') ...[
            const FormDataField('learner_name', 'Learner name (record header)',
                FieldKind.single),
            const FormDataField(
                'learner_lrn', 'LRN (record header)', FieldKind.single)
          ],
          for (final e in recordFields[form]!.entries)
            FormDataField(e.key, e.value, FieldKind.record)
        ],
      'sf1' => [..._about, ..._learnerRows, ..._sf1, ...extraFieldsFor(form)],
      'sf3' => [
          ..._about,
          ..._learnerRows,
          ...extraFieldsFor(form),
          const FormDataField('remarks', 'Remarks', FieldKind.learner)
        ],
      'sf8' => [..._about, ..._learnerRows, ..._sf1, ...extraFieldsFor(form)],
      'sf2' => [..._about, ..._sf2, ..._learnerRows],
      'sf5' => [..._about, ..._learnerRows, ..._sf5()],
      'sf9' => [..._about, ..._sf9],
      'record' => [..._about, ..._record(), ..._learnerRows],
      _ => [..._about, ..._learnerRows, ..._grades],
    };

/// One assignment: this cell is where this data goes (or starts). [group] says which learners a
/// learner field holds: 'all', 'M' or 'F'.
class CellMap {
  final String sheet;
  final int row;
  final int col;
  final String field;
  final String group;
  const CellMap(this.sheet, this.row, this.col, this.field,
      [this.group = 'all']);

  Map<String, Object> toJson() =>
      {'s': sheet, 'r': row, 'c': col, 'f': field, 'g': group};
  factory CellMap.fromJson(Map<String, dynamic> m) => CellMap(
      m['s'] as String,
      m['r'] as int,
      m['c'] as int,
      m['f'] as String,
      (m['g'] as String?) ?? 'all');

  static String encode(List<CellMap> maps) =>
      jsonEncode([for (final m in maps) m.toJson()]);
  static List<CellMap> decode(String text) => [
        for (final m in jsonDecode(text) as List)
          CellMap.fromJson(m as Map<String, dynamic>)
      ];
}

class LearnerValues {
  final String sex;
  final Map<String, String> cells;
  final Map<String, List<String>> across;
  const LearnerValues(this.sex, this.cells, [this.across = const {}]);
}

/// The data for one filled form.
class FormValues {
  final List<Map<String, String>> records;
  final Map<String, String> singles;
  final Map<String, List<String>> across;
  final List<LearnerValues> learners;
  final List<Map<String, String>> areas;
  final List<Map<String, String>> behaviors;
  const FormValues(
      {this.singles = const {},
      this.across = const {},
      this.learners = const [],
      this.areas = const [],
      this.behaviors = const [],
      this.records = const []});
}

class FillResult {
  final Uint8List bytes;

  /// Learners who had no row left on the layout.
  final int notFitted;
  const FillResult(this.bytes, this.notFitted);
}

/// Identifiers that look like numbers but must stay exactly as written.
const _textOnly = {
  'lrn',
  'learner_lrn',
  'record_lrn',
  'person_id',
  'contact',
  'school_id',
  'sy'
};

/// Writes the values into a copy of the teacher's own Excel file. Only the assigned cells change, so
/// the layout, wording and formulas of the form stay theirs.
FillResult fillXlsx(
    Uint8List bytes, List<CellMap> maps, String form, FormValues v) {
  if (maps.isEmpty)
    throw const FormatException('This layout has no assigned input cells.');
  final edits = <String, Map<String, String>>{};
  final textCells = <String>{};
  final book = xl.Excel.decodeBytes(bytes);
  final kinds = {for (final f in fieldsFor(form)) f.id: f.kind};

  /// True when the form has its own wording in this cell, such as "TOTAL" or "FEMALE".
  bool hasWording(String sheet, int row, int col) {
    final s = book.tables[sheet];
    final value = s
        ?.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
        .value;
    if (value is! xl.TextCellValue) return false;
    final text = value.toString().trim();
    return text.isNotEmpty && num.tryParse(text) == null;
  }

  void put(String sheet, int row, int col, String field, String? value) {
    final s = book.tables[sheet];
    if (s == null || value == null) return;
    final address =
        xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row).cellId;
    (edits[sheet] ??= {})[address] = value;
    if (_textOnly.contains(field)) textCells.add('$sheet!$address');
    final cell =
        s.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    final number = _textOnly.contains(field) ? null : num.tryParse(value);
    cell.value = number is int
        ? xl.IntCellValue(number)
        : number is double
            ? xl.DoubleCellValue(number)
            : xl.TextCellValue(value);
  }

  for (final m in maps) {
    switch (kinds[m.field]) {
      case FieldKind.record:
        for (var i = 0; i < v.records.length; i++) {
          if (i > 0 && hasWording(m.sheet, m.row + i, m.col))
            throw const FormatException(
                'Administrative or historical rows do not fit. Expand the mapped layout before exporting.');
          put(m.sheet, m.row + i, m.col, m.field, v.records[i][m.field]);
        }
      case FieldKind.single:
        put(m.sheet, m.row, m.col, m.field, v.singles[m.field]);
      case FieldKind.across:
        final list = v.across[m.field] ?? const <String>[];
        for (var i = 0; i < list.length; i++) {
          put(m.sheet, m.row, m.col + i, m.field, list[i]);
        }
      case FieldKind.area:
        for (var i = 0; i < v.areas.length; i++) {
          put(m.sheet, m.row + i, m.col, m.field, v.areas[i][m.field]);
        }
      case FieldKind.value:
        for (var i = 0; i < v.behaviors.length; i++) {
          put(m.sheet, m.row + i, m.col, m.field, v.behaviors[i][m.field]);
        }
      default:
        break;
    }
  }

  // Learner rows: each group runs down until the next group starts or the form's own text is reached.
  var notFitted = 0;
  final groups = <String, List<CellMap>>{};
  for (final m in maps) {
    final k = kinds[m.field];
    if (k == FieldKind.learner || k == FieldKind.learnerAcross)
      (groups['${m.sheet}|${m.group}'] ??= []).add(m);
  }
  groups.forEach((_, list) {
    final first = list.first;
    final rows = [
      for (final l in v.learners)
        if (first.group == 'all' || l.sex == first.group) l
    ];
    final start = list.map((m) => m.row).reduce((a, b) => a < b ? a : b);
    final others = [
      for (final o in groups.values)
        if (o.first.sheet == first.sheet && o.first.group != first.group)
          o.map((m) => m.row).reduce((a, b) => a < b ? a : b),
    ].where((r) => r > start);
    final stop = others.isEmpty ? null : others.reduce((a, b) => a < b ? a : b);
    for (var i = 0; i < rows.length; i++) {
      final blocked =
          i > 0 && list.any((m) => hasWording(m.sheet, m.row + i, m.col));
      if ((stop != null && start + i >= stop) || blocked) {
        notFitted += rows.length - i;
        break;
      }
      for (final m in list) {
        if (kinds[m.field] == FieldKind.learner) {
          put(m.sheet, m.row + i, m.col, m.field, rows[i].cells[m.field]);
        } else {
          final series = rows[i].across[m.field] ?? const <String>[];
          for (var c = 0; c < series.length; c++) {
            put(m.sheet, m.row + i, m.col + c, m.field, series[c]);
          }
        }
      }
    }
  });
  return FillResult(
      patchWorkbook(bytes, edits, textFields: textCells), notFitted);
}

/// The cells of each sheet as text, for showing the layout on screen.
Map<String, List<List<String>>> previewXlsx(Uint8List bytes,
    {int maxRows = 150, int maxCols = 60}) {
  final book = xl.Excel.decodeBytes(bytes);
  return {
    for (final e in book.tables.entries)
      e.key: [
        for (final row in e.value.rows.take(maxRows))
          [
            for (final c in row.take(maxCols)) c?.value?.toString().trim() ?? ''
          ],
      ],
  };
}

const _singleLabels = <String, String>{
  r'^(name of )?school( name)?$': 'school_name',
  r'^school id$': 'school_id',
  r'^region$': 'region',
  r'^(schools )?division$': 'division',
  r'^district$': 'district',
  r'^school year$': 'sy',
  r'^(grade|grade level)$': 'grade',
  r'^section$': 'section',
  r'^(teacher|adviser|class adviser|name of adviser|name of teacher)$':
      'teacher',
  r'^(subject|learning area)$': 'subject',
  r'^(school head|principal)$': 'school_head',
  r'^(month|report for the month of)$': 'month',
};

const _columnLabels = <String, String>{
  r'^lrn\b': 'lrn',
  r"(learner'?s?|student'?s?)?\s*names?\b": 'name',
  r'^sex\b|^gender\b': 'sex',
  r'^birth ?date\b|^date of birth\b': 'birth',
  r'^age\b': 'age',
  r'^address\b': 'address',
  r'guardian\b': 'guardian',
  r'^contact\b': 'contact',
  r'^remarks?\b': 'remarks',
  r'^general average\b': 'ga',
  r'^action taken\b': 'action',
  r'^final( grade)?\b': 'final',
  r'^initial grade\b': 'initial',
  r'^(quarterly|term) grade\b': 'term_grade',
};

/// Finds what it can from the wording on the form: a value beside each label such as "School Name",
/// and learner rows under headings such as "LRN" and "Name". The teacher checks and corrects it.
List<CellMap> autoMapXlsx(Uint8List bytes, String form) {
  final allowed = {for (final f in fieldsFor(form)) f.id};
  final out = <CellMap>[];
  final used = <String>{};
  final book = xl.Excel.decodeBytes(bytes);
  for (final entry in book.tables.entries) {
    final sheet = entry.key;
    final rows = [
      for (final row in entry.value.rows.take(80))
        [for (final c in row) c?.value?.toString().trim() ?? ''],
    ];
    // Label cells that span several columns: the value starts after the span.
    final spanEnd = <String, int>{};
    for (final span in entry.value.spannedItems) {
      final parts = span.split(':');
      if (parts.length != 2) continue;
      final a = xl.CellIndex.indexByString(parts[0]),
          b = xl.CellIndex.indexByString(parts[1]);
      spanEnd['${a.rowIndex}|${a.columnIndex}'] = b.columnIndex;
    }
    String clean(String t) => t
        .toLowerCase()
        .replaceAll(RegExp(r"[:*_.]+"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Values beside labels
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        final text = clean(rows[r][c]);
        if (text.isEmpty) continue;
        for (final e in _singleLabels.entries) {
          if (!allowed.contains(e.value) ||
              used.contains(e.value) ||
              !RegExp(e.key).hasMatch(text)) continue;
          for (var x = (spanEnd['$r|$c'] ?? c) + 1; x < c + 12; x++) {
            if (x >= rows[r].length || rows[r][x].isEmpty) {
              out.add(CellMap(sheet, r, x, e.value));
              used.add(e.value);
              break;
            }
          }
        }
      }
    }

    // A heading row with both an identifier and a name column
    for (var r = 0; r < rows.length; r++) {
      final heads = <int, String>{};
      for (var c = 0; c < rows[r].length; c++) {
        final text = clean(rows[r][c]);
        if (text.isEmpty) continue;
        for (final e in _columnLabels.entries) {
          if (allowed.contains(e.value) &&
              !heads.containsValue(e.value) &&
              RegExp(e.key).hasMatch(text)) {
            heads[c] = e.value;
            break;
          }
        }
      }
      if (!heads.containsValue('name') || heads.length < 2) continue;
      final nameCol = heads.entries.firstWhere((e) => e.value == 'name').key;
      String at(int row) => row < rows.length && nameCol < rows[row].length
          ? clean(rows[row][nameCol])
          : '';
      var start = r + 1;
      var skipped = 0;
      var group = 'all';
      while (at(start).isNotEmpty && skipped < 4) {
        if (at(start).contains('female')) break;
        if (at(start).contains('male')) group = 'M';
        start++;
        skipped++;
      }
      heads.forEach(
          (c, field) => out.add(CellMap(sheet, start, c, field, group)));
      if (group == 'M') {
        for (var f = start + 1; f < rows.length; f++) {
          if (at(f) == 'female' || at(f).startsWith('female ')) {
            heads.forEach(
                (c, field) => out.add(CellMap(sheet, f + 1, c, field, 'F')));
            break;
          }
        }
      }
      break;
    }
    if (out.isNotEmpty)
      break; // The first sheet with a match is the form itself.
  }
  return out;
}
