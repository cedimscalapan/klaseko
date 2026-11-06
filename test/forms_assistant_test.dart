import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klaseko/core/models.dart';
import 'package:klaseko/core/forms/assistant.dart';
import 'package:klaseko/core/forms/template_fill.dart';
import 'package:klaseko/core/forms/presets.dart';
import 'package:klaseko/core/forms/workbook_patch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Learner learner(String id,
          {String first = 'Juan', String lrn = '009345120031'}) =>
      Learner(
          id: id,
          classId: 'c',
          num: 1,
          last: 'Cruz',
          first: first,
          sex: 'M',
          lrn: lrn,
          birth: '2016-01-01',
          address: 'Calapan',
          guardian: 'Parent');
  Future<Uint8List> asset(String id) async {
    final data = await rootBundle.load('assets/deped_forms/$id.xlsx');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  test('Shared demographics require matching identity, not just an LRN', () {
    final a = learner('a');
    expect(sameLearner(a, learner('b')), isTrue);
    expect(sameLearner(a, learner('b', first: 'Pedro')), isFalse);
    expect(learnerExtraKey(a, '2026-2027'),
        isNot(learnerExtraKey(learner('b', first: 'Pedro'), '2026-2027')));
    expect(learnerExtraKey(a, '2026-2027'),
        learnerExtraKey(learner('b'), '2026-2027'));
  });
  test('Readiness distinguishes missing health assessments and zero counts',
      () {
    final p = SchoolProfile()
      ..teacher = 'Teacher'
      ..schoolName = 'School'
      ..schoolId = '123456';
    expect(inspectFormInputs('sf8', p, [learner('a')], {}), isNotEmpty);
    final row = {
      for (final f in recordRequired['sf6']!)
        f: f == 'record_source'
            ? 'Verified SF5'
            : f == 'record_grade'
                ? 'Grade 6'
                : '0'
    };
    expect(inspectRecordRows('sf6', [row]), isEmpty);
    row['retained_m'] = '';
    expect(inspectRecordRows('sf6', [row]), isNotEmpty);
  });
  test(
      'SF1 preset writes identities without replacing other worksheets or styles',
      () async {
    final original = await asset('official_aa2bb44d854c');
    final output = fillPreset(
        original,
        'sf1',
        const FormValues(singles: {
          'school_name': 'Test School',
          'school_id': '001234',
          'sy': '2026-2027'
        }, learners: [
          LearnerValues('M', {
            'name': 'Cruz, Juan',
            'lrn': '009345120031',
            'birth': '2016-01-01',
            'sex': 'M'
          })
        ]),
        ageDate: DateTime(2026, 6, 5));
    final before = ZipDecoder().decodeBytes(original),
        after = ZipDecoder().decodeBytes(output);
    for (final entry in before) {
      if (entry.name != 'xl/workbook.xml' &&
          entry.name != 'xl/worksheets/sheet1.xml')
        expect(after.findFile(entry.name)!.content, entry.content,
            reason: entry.name);
    }
    final xml = utf8.decode(
        after.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(xml, contains('009345120031'));
    expect(xml, contains('Cruz, Juan'));
    expect(xml, contains('Test School'));
    expect(utf8.decode(after.findFile('xl/workbook.xml')!.content as List<int>),
        contains('fullCalcOnLoad="1"'));
  });
  test('Preset capacity failure prevents silent roster omission', () async {
    final original = await asset('official_aa2bb44d854c');
    expect(
        () => fillPreset(
            original,
            'sf2',
            FormValues(learners: [
              for (var n = 0; n < 22; n++)
                LearnerValues('M', {'name': 'Learner $n'})
            ]),
            ageDate: DateTime(2026)),
        throwsFormatException);
  });
  test('Record mapping fills verified personnel and keeps identifiers as text',
      () {
    final b = xl.Excel.createExcel();
    final name = b.getDefaultSheet()!;
    b[name].cell(xl.CellIndex.indexByString('A1')).value =
        xl.TextCellValue('Personnel');
    final out = fillXlsx(
        Uint8List.fromList(b.encode()!),
        [CellMap(name, 1, 0, 'person_name'), CellMap(name, 1, 1, 'person_id')],
        'sf7',
        const FormValues(records: [
          {'person_name': 'Teacher One', 'person_id': '00123'}
        ]));
    final decoded = xl.Excel.decodeBytes(out.bytes);
    expect(
        decoded[name].cell(xl.CellIndex.indexByString('A2')).value.toString(),
        'Teacher One');
    expect(
        decoded[name].cell(xl.CellIndex.indexByString('B2')).value.toString(),
        '00123');
  });
  test(
      'Unknown worksheet and formula-like input cannot silently alter a workbook',
      () {
    final b = xl.Excel.createExcel();
    final name = b.getDefaultSheet()!;
    final bytes = Uint8List.fromList(b.encode()!);
    expect(
        () => patchWorkbook(bytes, {
              'Missing': {'A1': 'data'}
            }),
        throwsFormatException);
    final output = patchWorkbook(bytes, {
      name: {'A1': '=HYPERLINK("external")'}
    });
    final value = xl.Excel.decodeBytes(output)[name]
        .cell(xl.CellIndex.indexByString('A1'))
        .value;
    expect(value, isA<xl.TextCellValue>());
  });

  test(
      'Spreadsheet paste preserves identifiers, quoted cells and explicit zeros',
      () {
    final rows = parseInputGrid('LRN,Address\n009345120031,"Street, Barangay"',
        {'lrn': 'LRN', 'address': 'Address'});
    expect(rows.single['lrn'], '009345120031');
    expect(rows.single['address'], 'Street, Barangay');
    expect(() => parseInputGrid('Unknown\nvalue', {'lrn': 'LRN'}),
        throwsFormatException);
    expect(
        () => parseInputGrid(
            'LRN,Address\n009345120031', {'lrn': 'LRN', 'address': 'Address'}),
        throwsFormatException);
  });
  test(
      'Health preset keeps birthdates readable in its general-format source cells',
      () async {
    final bytes = await asset('official_15c8cf36a37a');
    final output = fillPreset(
        bytes,
        'sf8',
        const FormValues(learners: [
          LearnerValues('M', {
            'name': 'Cruz, Juan',
            'lrn': '009345120031',
            'birth': '2016-01-01',
            'weight': '30',
            'height': '1.3',
            'measured_on': '2026-06-05',
            'bmi_category': 'Recorded category',
            'hfa': 'Recorded HFA',
            'assessment_by': 'School assessor'
          })
        ]),
        ageDate: DateTime(2026));
    final sheet = xl.Excel.decodeBytes(output)['Nutritional Status'];
    expect(sheet.cell(xl.CellIndex.indexByString('G12')).value.toString(),
        '01/01/2016');
    expect(
        sheet.cell(xl.CellIndex.indexByString('H12')).value.toString(), '10');
    expect(sheet.cell(xl.CellIndex.indexByString('M12')).value.toString(),
        'Recorded category');
    expect(sheet.cell(xl.CellIndex.indexByString('N12')).value.toString(),
        'Recorded HFA');
  });
}
