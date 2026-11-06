import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../db.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../models.dart';
import 'template_fill.dart';

const extraLearnerFields = <String, String>{
  'birth_place': 'Birth place (province)',
  'mother_tongue': 'Mother tongue',
  'ethnic_group': 'Indigenous group (if applicable)',
  'religion': 'Religion (if provided)',
  'street': 'House / street / sitio',
  'barangay': 'Barangay',
  'city': 'Municipality / city',
  'province': 'Province',
  'father': 'Father name',
  'mother': 'Mother name',
  'guardian_relation': 'Guardian relationship',
  'weight': 'Measured weight (kg)',
  'height': 'Measured height (m)',
  'measured_on': 'Measurement date (YYYY-MM-DD)',
  'assessment_by': 'Health assessment recorded by',
  'bmi_category': 'Recorded BMI category (from health assessment)',
  'hfa': 'Recorded height-for-age assessment',
  'health_remarks': 'Health remarks',
};

const recordFields = <String, Map<String, String>>{
  'sf4': {
    'record_grade': 'Grade level',
    'record_section': 'Section',
    'record_adviser': 'Adviser',
    'registered_m': 'Registered male',
    'registered_f': 'Registered female',
    'transferred_in_m': 'Transferred in male',
    'transferred_in_f': 'Transferred in female',
    'transferred_out_m': 'Transferred out male',
    'transferred_out_f': 'Transferred out female',
    'dropped_m': 'Dropped male',
    'dropped_f': 'Dropped female',
    'attendance_m': 'Average daily attendance male',
    'attendance_f': 'Average daily attendance female',
    'record_period': 'Reporting month (YYYY-MM)',
    'record_source': 'Verified attendance / movement reference'
  },
  'sf6': {
    'record_grade': 'Grade level',
    'promoted_m': 'Promoted male',
    'promoted_f': 'Promoted female',
    'retained_m': 'Retained male',
    'retained_f': 'Retained female',
    'remedial_m': 'For remediation male',
    'remedial_f': 'For remediation female',
    'record_source': 'Verified section-summary reference'
  },
  'sf7': {
    'person_id': 'Employee identifier',
    'person_name': 'Personnel name',
    'person_sex': 'Sex',
    'fund_source': 'Fund source',
    'position': 'Position / designation',
    'employment': 'Employment status',
    'degree': 'Degree',
    'major': 'Major / specialization',
    'assignment': 'Subjects, grades and sections',
    'duty_days': 'Duty days',
    'time_from': 'Time from',
    'time_to': 'Time to',
    'weekly_minutes': 'Actual teaching minutes per week',
    'record_source': 'Assignment reference'
  },
  'sf10': {
    'record_lrn': 'LRN',
    'record_name': 'Learner name',
    'record_year': 'Historical school year',
    'record_grade': 'Historical grade level',
    'record_school': 'School attended',
    'record_area': 'Learning area',
    'record_t1': 'Period 1 grade',
    'record_t2': 'Period 2 grade',
    'record_t3': 'Period 3 grade',
    'record_t4': 'Period 4 grade (if applicable)',
    'record_final': 'Verified final grade',
    'record_remarks': 'Remarks',
    'record_source': 'Verified source record reference'
  },
};

const recordRequired = <String, List<String>>{
  'sf4': [
    'record_grade',
    'record_section',
    'registered_m',
    'registered_f',
    'transferred_in_m',
    'transferred_in_f',
    'transferred_out_m',
    'transferred_out_f',
    'dropped_m',
    'dropped_f',
    'attendance_m',
    'attendance_f',
    'record_period',
    'record_source'
  ],
  'sf6': [
    'record_grade',
    'promoted_m',
    'promoted_f',
    'retained_m',
    'retained_f',
    'remedial_m',
    'remedial_f',
    'record_source'
  ],
  'sf7': [
    'person_name',
    'position',
    'employment',
    'assignment',
    'weekly_minutes',
    'record_source'
  ],
  'sf10': [
    'record_lrn',
    'record_name',
    'record_year',
    'record_grade',
    'record_school',
    'record_area',
    'record_final',
    'record_source'
  ],
};

String recordStoreKey(SchoolProfile p, String sy, String form,
        {String? period}) =>
    'forms_records_${p.schoolId.isEmpty ? p.schoolName : p.schoolId}_${sy}_${form}${period == null ? '' : '_$period'}';

String learnerExtraKey(Learner l, String sy) =>
    'forms_person_${sy}_${RegExp(r'^\d{12}$').hasMatch(l.lrn) ? '${l.lrn}_${sha256.convert(utf8.encode('${l.last.trim().toLowerCase()}|${l.first.trim().toLowerCase()}|${l.birth}')).toString().substring(0, 12)}' : l.id}';
Map<String, String> readStringMap(String? value) =>
    value == null ? {} : Map<String, String>.from(jsonDecode(value) as Map);

/// Only identity-matched records with the same valid LRN may reuse demographics.
bool sameLearner(Learner a, Learner b) =>
    RegExp(r'^\d{12}$').hasMatch(a.lrn) &&
    a.lrn == b.lrn &&
    a.last.trim().toLowerCase() == b.last.trim().toLowerCase() &&
    a.first.trim().toLowerCase() == b.first.trim().toLowerCase() &&
    (a.birth.isEmpty || b.birth.isEmpty || a.birth == b.birth);

Future<int> saveSharedLearner(Repo repo, Learner learner, SchoolClass cls,
    Map<String, String> extra) async {
  var reused = 0;
  await repo.db.transaction((tx) async {
    await tx.insert('learners', learner.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (RegExp(r'^\d{12}$').hasMatch(learner.lrn)) {
      final rows = await tx.rawQuery(
          'SELECT l.* FROM learners l JOIN classes c ON c.id=l.class_id WHERE l.lrn=? AND c.sy=? AND l.id<>?',
          [learner.lrn, cls.sy, learner.id]);
      for (final row in rows) {
        final other = Learner.fromMap(row);
        if (!sameLearner(learner, other)) continue;
        other
          ..birth = learner.birth
          ..address = learner.address
          ..guardian = learner.guardian
          ..contact = learner.contact
          ..middle = learner.middle
          ..sex = learner.sex;
        await tx.insert('learners', other.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
        reused++;
      }
    }
    await tx.insert('settings',
        {'key': learnerExtraKey(learner, cls.sy), 'value': jsonEncode(extra)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  });
  return reused;
}

class FormIssue {
  final String message;
  final String? learnerId;
  const FormIssue(this.message, {this.learnerId});
}

List<FormIssue> inspectFormInputs(String form, SchoolProfile profile,
    List<Learner> learners, Map<String, Map<String, String>> extras) {
  final issues = <FormIssue>[];
  if (profile.schoolName.trim().isEmpty)
    issues.add(const FormIssue('School name'));
  if (profile.schoolId.trim().isEmpty) issues.add(const FormIssue('School ID'));
  if (profile.teacher.trim().isEmpty)
    issues.add(const FormIssue('Teacher / adviser name'));
  if (learners.isEmpty) issues.add(const FormIssue('Add a class roster'));
  final seen = <String>{};
  for (final l in learners) {
    void issue(String s) =>
        issues.add(FormIssue('${l.fullName}: $s', learnerId: l.id));
    if (l.first.isEmpty || l.last.isEmpty) issue('learner name');
    if (!RegExp(r'^\d{12}$').hasMatch(l.lrn))
      issue('valid 12-digit LRN');
    else if (!seen.add(l.lrn)) issue('duplicate LRN in this class');
    if (!['M', 'F'].contains(l.sex))
      issue('sex required by the selected layout');
    final e = extras[l.id] ?? {};
    if (['sf1', 'sf8', 'sf9', 'sf10'].contains(form) &&
        DateTime.tryParse(l.birth) == null) issue('birth date');
    if (form == 'sf1') {
      if (l.address.isEmpty && e['street']?.isNotEmpty != true)
        issue('address');
      if (l.guardian.isEmpty &&
          e['father']?.isNotEmpty != true &&
          e['mother']?.isNotEmpty != true) issue('parent / guardian');
    }
    if (form == 'sf8') {
      final w = double.tryParse(e['weight'] ?? '');
      final h = double.tryParse(e['height'] ?? '');
      if (w == null || !w.isFinite || w <= 0 || w > 400) issue('weight in kg');
      if (h == null || !h.isFinite || h < .3 || h > 3)
        issue('height in metres');
      if (DateTime.tryParse(e['measured_on'] ?? '') == null)
        issue('measurement date');
      if (e['bmi_category']?.trim().isNotEmpty != true)
        issue('recorded BMI category from the health assessment');
      if (e['hfa']?.trim().isNotEmpty != true)
        issue('recorded height-for-age assessment');
      if (e['assessment_by']?.trim().isNotEmpty != true)
        issue('health assessor name');
    }
  }
  return issues;
}

List<String> inspectRecordRows(String form, List<Map<String, String>> rows) {
  final problems = <String>[];
  for (final item in rows.indexed) {
    for (final field in recordRequired[form] ?? <String>[]) {
      if (item.$2[field]?.trim().isNotEmpty != true)
        problems.add(
            'Row ${item.$1 + 1}: ${recordFields[form]![field]} is missing.');
    }
    for (final e in item.$2.entries) {
      if (RegExp(r'_(m|f)$').hasMatch(e.key) || e.key == 'weekly_minutes') {
        final n = num.tryParse(e.value);
        if (e.value.isNotEmpty && (n == null || !n.isFinite || n < 0))
          problems.add(
              'Row ${item.$1 + 1}: ${e.key} must be a non-negative number.');
      }
    }
    if (form == 'sf10' &&
        !RegExp(r'^\d{12}$').hasMatch(item.$2['record_lrn'] ?? ''))
      problems.add('Row ${item.$1 + 1}: valid LRN required.');
  }
  return problems;
}

/// Reads a local Excel copy/paste grid. Headers can use field IDs or their labels.
/// Quoted tabs, commas and newlines remain part of the original cell value.
List<Map<String, String>> parseInputGrid(
    String text, Map<String, String> fields) {
  final delimiter = text.split('\n').first.contains('\t') ? '\t' : ',';
  final table = <List<String>>[];
  var row = <String>[];
  var value = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        value.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && (c == delimiter || c == '\n')) {
      row.add(value.toString().replaceAll('\r', '').trim());
      value = StringBuffer();
      if (c == '\n') {
        if (row.any((v) => v.isNotEmpty)) table.add(row);
        row = [];
      }
    } else {
      value.write(c);
    }
  }
  if (quoted) throw const FormatException('A quoted cell is incomplete.');
  row.add(value.toString().trim());
  if (row.any((v) => v.isNotEmpty)) table.add(row);
  if (table.length < 2)
    throw const FormatException(
        'Paste column headers and at least one data row.');
  if (table.length > 2001)
    throw const FormatException('Import at most 2000 rows at a time.');
  String normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final lookup = {
    for (final e in fields.entries) ...{
      normalize(e.key): e.key,
      normalize(e.value): e.key
    }
  };
  final headers = <String>[];
  for (final h in table.first) {
    final key = lookup[normalize(h)];
    if (key == null)
      throw FormatException(
          'Unknown column: $h. Use the displayed header names.');
    if (headers.contains(key)) throw FormatException('Duplicate column: $h');
    headers.add(key);
  }
  return [
    for (final entry in table.skip(1).indexed)
      if (entry.$2.length != headers.length)
        throw FormatException(
            'Row ${entry.$1 + 2} has ${entry.$2.length} cells; ${headers.length} were expected.')
      else
        {for (var c = 0; c < headers.length; c++) headers[c]: entry.$2[c]}
  ];
}

List<FormDataField> extraFieldsFor(String form) => [
      if (form == 'sf1')
        for (final e in extraLearnerFields.entries.where((e) => ![
              'weight',
              'height',
              'measured_on',
              'assessment_by',
              'bmi_category',
              'hfa',
              'health_remarks'
            ].contains(e.key)))
          FormDataField(e.key, e.value, FieldKind.learner),
      if (form == 'sf8')
        for (final e in extraLearnerFields.entries.where((e) => [
              'weight',
              'height',
              'measured_on',
              'assessment_by',
              'bmi_category',
              'hfa',
              'health_remarks'
            ].contains(e.key)))
          FormDataField(e.key, e.value, FieldKind.learner),
      if (form == 'sf3')
        for (var n = 1; n <= 8; n++) ...[
          FormDataField('book_${n}_title', 'Book $n title', FieldKind.single),
          FormDataField(
              'book_${n}_issued', 'Book $n date issued', FieldKind.learner),
          FormDataField(
              'book_${n}_returned', 'Book $n date returned', FieldKind.learner),
        ],
    ];
