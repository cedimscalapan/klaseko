import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:klaseko/core/forms/template_fill.dart';

Uint8List _layout() {
  final book = xl.Excel.createExcel();
  final name = book.getDefaultSheet()!;
  final s = book[name];
  void text(int col, int row, String t) => s.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value = xl.TextCellValue(t);
  text(0, 0, 'School Name:');
  text(0, 1, 'School ID');
  text(3, 1, 'Section');
  text(0, 3, 'LRN');
  text(1, 3, "LEARNER'S NAME");
  text(2, 3, 'SEX');
  text(1, 4, 'MALE');
  text(1, 7, 'FEMALE');
  text(1, 10, 'TOTAL');
  return Uint8List.fromList(book.encode()!);
}

String _at(xl.Excel book, int col, int row) =>
    book.tables[book.getDefaultSheet()!]!.cell(xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row)).value?.toString() ?? '';

void main() {
  test('finds labels and learner rows from the wording of the form', () {
    final maps = autoMapXlsx(_layout(), 'sf1');
    CellMap find(String field, [String group = 'all']) => maps.firstWhere((m) => m.field == field && m.group == group);
    expect(find('school_name').row, 0);
    expect(find('school_name').col, 1);
    expect(find('school_id').col, 1);
    expect(find('section').col, 4);
    expect(find('name', 'M').row, 5);
    expect(find('name', 'M').col, 1);
    expect(find('lrn', 'M').col, 0);
    expect(find('name', 'F').row, 8);
  });

  test('fills a layout: each learner under the right heading, numbers staying as written', () {
    final maps = autoMapXlsx(_layout(), 'sf1');
    const values = FormValues(
      singles: {'school_name': 'Calapan NHS', 'school_id': '301234', 'section': 'Rizal'},
      learners: [
        LearnerValues('M', {'name': 'Cruz, Juan', 'lrn': '109345120031', 'sex': 'M'}),
        LearnerValues('M', {'name': 'Reyes, Ben', 'lrn': '009345120032', 'sex': 'M'}),
        LearnerValues('F', {'name': 'Santos, Liza', 'lrn': '109345120033', 'sex': 'F'}),
      ],
    );
    final r = fillXlsx(_layout(), maps, 'sf1', values);
    expect(r.notFitted, 0);
    final book = xl.Excel.decodeBytes(r.bytes);
    expect(_at(book, 1, 0), 'Calapan NHS');
    expect(_at(book, 1, 1), '301234');
    expect(_at(book, 1, 5), 'Cruz, Juan');
    expect(_at(book, 1, 6), 'Reyes, Ben');
    expect(_at(book, 0, 6), '009345120032');
    expect(_at(book, 1, 8), 'Santos, Liza');
    // The form's own wording is untouched.
    expect(_at(book, 1, 3), "LEARNER'S NAME");
    expect(_at(book, 1, 7), 'FEMALE');
    expect(_at(book, 1, 10), 'TOTAL');
  });

  test('stops at the form\'s own text and reports who did not fit', () {
    final maps = autoMapXlsx(_layout(), 'sf1');
    final values = FormValues(learners: [for (var i = 0; i < 5; i++) LearnerValues('M', {'name': 'Learner $i'})]);
    final r = fillXlsx(_layout(), maps, 'sf1', values);
    expect(r.notFitted, 3); // rows 5 and 6 are free; row 7 says FEMALE
    expect(_at(xl.Excel.decodeBytes(r.bytes), 1, 7), 'FEMALE');
  });

  test('series go right, on one row and on each learner\'s row', () {
    const maps = [
      CellMap('Sheet1', 0, 2, 'day_numbers'),
      CellMap('Sheet1', 2, 0, 'name'),
      CellMap('Sheet1', 2, 2, 'day_marks'),
    ];
    final book = xl.Excel.createExcel();
    final base = book.getDefaultSheet()!;
    final fixed = [for (final m in maps) CellMap(base, m.row, m.col, m.field)];
    book[base].cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = xl.TextCellValue('Attendance');
    const values = FormValues(
      across: {'day_numbers': ['3', '4', '5']},
      learners: [
        LearnerValues('M', {'name': 'Cruz, Juan'}, {'day_marks': ['', 'x', 'T']}),
      ],
    );
    final filled = xl.Excel.decodeBytes(fillXlsx(Uint8List.fromList(book.encode()!), fixed, 'sf2', values).bytes);
    expect(_at(filled, 2, 0), '3');
    expect(_at(filled, 4, 0), '5');
    expect(_at(filled, 0, 2), 'Cruz, Juan');
    expect(_at(filled, 2, 2), '');
    expect(_at(filled, 3, 2), 'x');
    expect(_at(filled, 4, 2), 'T');
  });

  test('assignments survive being saved and read back', () {
    const maps = [CellMap('SF2', 7, 2, 'name', 'F')];
    final back = CellMap.decode(CellMap.encode(maps)).single;
    expect(back.sheet, 'SF2');
    expect(back.row, 7);
    expect(back.col, 2);
    expect(back.field, 'name');
    expect(back.group, 'F');
  });
}
