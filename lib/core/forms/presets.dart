import 'dart:typed_data';
import '../models.dart';
import 'template_fill.dart';
import 'workbook_patch.dart';

const presetSourceIds = {
  'sf1': 'official_aa2bb44d854c',
  'sf2': 'official_aa2bb44d854c',
  'sf3': 'official_aa2bb44d854c',
  'sf8': 'official_15c8cf36a37a'
};

String columnName(int n) {
  var s = '';
  for (n++; n > 0; n = (n - 1) ~/ 26) {
    s = String.fromCharCode(65 + (n - 1) % 26) + s;
  }
  return s;
}

/// Fixed cell locations inspected in the pinned, unmodified source editions.
/// Fails before writing if the roster cannot fit; never silently drops learners.
Uint8List fillPreset(Uint8List source, String form, FormValues values,
    {required DateTime ageDate}) {
  final sheet = form == 'sf8'
      ? 'Nutritional Status'
      : {
          'sf1': 'School Form 1 (SF1)',
          'sf2': 'School Form 2 (SF2)',
          'sf3': 'School Form 3 (SF3)'
        }[form];
  if (sheet == null)
    throw const FormatException('No verified preset for this form.');
  final changes = <String, String>{};
  final texts = <String>{};
  if (form == 'sf2' && (values.across['day_numbers']?.length ?? 0) > 25)
    throw const FormatException(
        'This reference SF2 has 25 date columns. Use an expanded school-approved layout for this month.');
  void put(String cell, String? value, {bool text = true}) {
    changes[cell] = value ?? '';
    if (text) texts.add('$sheet!$cell');
  }

  final headers = <String, Map<String, String>>{
    'sf1': {
      'school_id': 'F4',
      'region': 'J4',
      'division': 'M4',
      'district': 'S4',
      'school_name': 'F6',
      'sy': 'O6',
      'grade': 'S6',
      'section': 'V6'
    },
    'sf2': {
      'school_id': 'C6',
      'sy': 'K6',
      'month': 'X6',
      'school_name': 'F8',
      'grade': 'X8',
      'section': 'AC8'
    },
    'sf3': {
      'school_id': 'D5',
      'sy': 'K5',
      'school_name': 'C7',
      'grade': 'K7',
      'section': 'N7'
    },
    'sf8': {
      'school_name': 'E5',
      'district': 'I5',
      'division': 'L5',
      'region': 'O5',
      'school_id': 'C7',
      'grade': 'F7',
      'section': 'H7',
      'sy': 'O7'
    },
  };
  headers[form]!.forEach((field, cell) => put(cell, values.singles[field]));
  final groups = form == 'sf1'
      ? [(10, 56, 'all')]
      : form == 'sf2'
          ? [(14, 34, 'M'), (36, 60, 'F')]
          : form == 'sf3'
              ? [(12, 35, 'M'), (37, 60, 'F')]
              : [(12, 63, 'M'), (65, 108, 'F')];
  for (final group in groups) {
    final learners = values.learners
        .where((l) => group.$3 == 'all' || l.sex == group.$3)
        .toList();
    if (learners.length > group.$2 - group.$1 + 1)
      throw FormatException(
          'The ${group.$3} roster has ${learners.length} learners; this source edition has ${group.$2 - group.$1 + 1} rows. Use an expanded school-approved layout. No learners were exported.');
    for (var i = 0; i <= group.$2 - group.$1; i++) {
      final r = group.$1 + i;
      final l = i < learners.length ? learners[i] : const LearnerValues('', {});
      final v = l.cells;
      if (form == 'sf1') {
        put('A$r', i < learners.length ? '${i + 1}' : '', text: false);
        for (final entry in {
          'B': 'lrn',
          'C': 'name',
          'G': 'sex',
          'H': 'birth',
          'J': 'birth_place',
          'K': 'mother_tongue',
          'L': 'ethnic_group',
          'M': 'religion',
          'N': 'street',
          'O': 'barangay',
          'P': 'city',
          'Q': 'province',
          'R': 'father',
          'T': 'mother',
          'V': 'guardian',
          'W': 'guardian_relation',
          'X': 'contact',
          'Y': 'remarks'
        }.entries) {
          put('${entry.key}$r', v[entry.value]);
        }
        if (v['street']?.isNotEmpty != true) put('N$r', v['address']);
        final birth = DateTime.tryParse(v['birth'] ?? '');
        put(
            'H$r',
            birth == null
                ? ''
                : '${DateTime.utc(birth.year, birth.month, birth.day).difference(DateTime.utc(1899, 12, 30)).inDays}',
            text: false);
        final age = birth == null
            ? ''
            : '${ageDate.year - birth.year - ((ageDate.month < birth.month || ageDate.month == birth.month && ageDate.day < birth.day) ? 1 : 0)}';
        put('I$r', age, text: false);
      } else if (form == 'sf2') {
        put('A$r', v['name']);
        put('AE$r', v['remarks']);
        final marks = l.across['day_marks'] ?? [];
        for (var day = 0; day < 25; day++)
          put('${columnName(3 + day)}$r', day < marks.length ? marks[day] : '');
        put('AC$r', v['absent'], text: false);
        put('AD$r', v['tardy'], text: false);
      } else if (form == 'sf3') {
        put('A$r', i < learners.length ? '${i + 1}' : '', text: false);
        put('B$r', v['name']);
        put('T$r', v['remarks']);
        for (var n = 1; n <= 8; n++) {
          put('${columnName(1 + n * 2)}$r', v['book_${n}_issued']);
          put('${columnName(2 + n * 2)}$r', v['book_${n}_returned']);
        }
      } else {
        put('A$r', i < learners.length ? '${i + 1}' : '', text: false);
        put('B$r', v['lrn']);
        put('C$r', v['name']);
        final birth = DateTime.tryParse(v['birth'] ?? '');
        put(
            'G$r',
            birth == null
                ? ''
                : '${birth.month.toString().padLeft(2, '0')}/${birth.day.toString().padLeft(2, '0')}/${birth.year}');
        put('I$r', v['weight'], text: false);
        put('J$r', v['height'], text: false);
        final date = DateTime.tryParse(v['measured_on'] ?? '');
        final weight = double.tryParse(v['weight'] ?? '');
        final height = double.tryParse(v['height'] ?? '');
        final age = birth == null || date == null
            ? ''
            : '${date.year - birth.year - ((date.month < birth.month || date.month == birth.month && date.day < birth.day) ? 1 : 0)}';
        put('H$r', age, text: false);
        put('K$r', height == null ? '' : '${height * height}', text: false);
        put(
            'L$r',
            weight == null || height == null || height <= 0
                ? ''
                : (weight / (height * height)).toStringAsFixed(2),
            text: false);
        put('M$r', v['bmi_category']);
        put('N$r', v['hfa']);
        put('O$r', v['health_remarks']);
      }
    }
  }
  if (form == 'sf8' && values.learners.isNotEmpty) {
    put('A119', values.learners.first.cells['measured_on']);
    put(
        'E119',
        values.learners
            .map((l) => l.cells['assessment_by'] ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
            .join(', '));
  }
  if (form == 'sf2')
    for (var i = 0; i < 25; i++) {
      final numbers = values.across['day_numbers'] ?? [];
      final letters = values.across['day_letters'] ?? [];
      put('${columnName(3 + i)}11', i < numbers.length ? numbers[i] : '',
          text: false);
      put('${columnName(3 + i)}12', i < letters.length ? letters[i] : '');
    }
  if (form == 'sf3')
    for (var n = 1; n <= 8; n++)
      put('${columnName(1 + n * 2)}8', values.singles['book_${n}_title']);
  return patchWorkbook(source, {sheet: changes}, textFields: texts);
}
