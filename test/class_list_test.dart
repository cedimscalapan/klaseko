import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:klaseko/core/class_list.dart';

void main() {
  test('reads the standard format', () {
    final r = parseClassList('Dela Cruz, Juan, Santos, M, 109345120031\nReyes, Liza, , F\nTorres, Ben, Lopez, Male');
    expect(r.rows.length, 3);
    expect(r.rows[0].last, 'Dela Cruz');
    expect(r.rows[0].middle, 'Santos');
    expect(r.rows[0].lrn, '109345120031');
    expect(r.rows[1].sex, 'F');
    expect(r.rows[2].sex, 'M');
  });

  test('uses MALE and FEMALE headings and strips numbering', () {
    final r = parseClassList('MALE\n1. Dela Cruz, Juan\n2) Santos, Pedro\nFEMALE (2)\n3 Reyes, Liza\n4. Cruz, Ana');
    expect([for (final x in r.rows) x.sex], ['M', 'M', 'F', 'F']);
    expect(r.rows[0].last, 'Dela Cruz');
    expect(r.rows[2].last, 'Reyes');
    expect(r.skipped, isEmpty);
  });

  test('leaves sex empty when the list does not say', () {
    final r = parseClassList('Dela Cruz, Juan');
    expect(r.rows.single.sex, isNull);
  });

  test('ignores column titles, totals, ages and dates', () {
    final r = parseClassList('LRN\tName\tSex\tBirth Date\tAge\n'
        '109345120031\tDela Cruz, Juan, Santos\tM\t01/02/2012\t14\n'
        'TOTAL MALE\t1');
    expect(r.rows.length, 1);
    expect(r.rows.single.first, 'Juan');
    expect(r.rows.single.lrn, '109345120031');
    expect(r.skipped, isEmpty);
  });

  test('reports lines without a Last, First name', () {
    final r = parseClassList('Juan Dela Cruz\nReyes, Liza, , F');
    expect(r.rows.length, 1);
    expect(r.skipped, ['Juan Dela Cruz']);
  });

  test('reads an Excel file', () {
    final book = xl.Excel.createExcel();
    final sheet = book[book.getDefaultSheet()!];
    sheet.appendRow([xl.TextCellValue('LRN'), xl.TextCellValue('Name'), xl.TextCellValue('Sex')]);
    sheet.appendRow([xl.TextCellValue('109345120031'), xl.TextCellValue('Dela Cruz, Juan, Santos'), xl.TextCellValue('M')]);
    final r = parseClassList(xlsxToText(Uint8List.fromList(book.encode()!)));
    expect(r.rows.length, 1);
    expect(r.rows.single.last, 'Dela Cruz');
    expect(r.rows.single.sex, 'M');
  });
}
