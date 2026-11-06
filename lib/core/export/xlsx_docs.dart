import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;

import '../analysis.dart';
import '../grading.dart';
import '../models.dart';
import 'form_data.dart';

/// Small helper around the excel package so every form is written the same way.
class _Book {
  final xl.Excel book = xl.Excel.createExcel();
  late xl.Sheet sheet;
  bool _first = true;

  static final _thin = xl.Border(borderStyle: xl.BorderStyle.Thin);

  void addSheet(String name) {
    if (_first) {
      final def = book.getDefaultSheet() ?? 'Sheet1';
      book.rename(def, name);
      _first = false;
    }
    sheet = book[name];
  }

  xl.CellIndex at(int c, int r) => xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);

  void put(int c, int r, Object? v, {bool bold = false, bool center = false, bool border = false, bool wrap = false, int size = 10}) {
    final cell = sheet.cell(at(c, r));
    if (v == null || (v is String && v.isEmpty)) {
      cell.value = null;
    } else if (v is int) {
      cell.value = xl.IntCellValue(v);
    } else if (v is double) {
      cell.value = xl.DoubleCellValue(v);
    } else {
      cell.value = xl.TextCellValue(v.toString());
    }
    cell.cellStyle = xl.CellStyle(
      bold: bold,
      fontSize: size,
      horizontalAlign: center ? xl.HorizontalAlign.Center : xl.HorizontalAlign.Left,
      verticalAlign: xl.VerticalAlign.Center,
      textWrapping: wrap ? xl.TextWrapping.WrapText : null,
      leftBorder: border ? _thin : null,
      rightBorder: border ? _thin : null,
      topBorder: border ? _thin : null,
      bottomBorder: border ? _thin : null,
    );
  }

  void merge(int c0, int r0, int c1, int r1, String text, {bool bold = true, bool center = true, int size = 10, bool border = false}) {
    sheet.merge(at(c0, r0), at(c1, r1), customValue: xl.TextCellValue(text));
    put(c0, r0, text, bold: bold, center: center, size: size, border: border, wrap: true);
  }

  void width(int c, double w) => sheet.setColumnWidth(c, w);

  Uint8List bytes() => Uint8List.fromList(book.encode() ?? <int>[]);
}

void _header(_Book b, String title, SchoolProfile p, SchoolClass cls, int lastCol, {String? extra}) {
  b.merge(0, 0, lastCol, 0, title, size: 13);
  b.put(0, 2, 'School ID', bold: true);
  b.put(1, 2, p.schoolId);
  b.put(3, 2, 'Region', bold: true);
  b.put(4, 2, p.region);
  b.put(6, 2, 'Division', bold: true);
  b.put(7, 2, p.division);
  b.put(0, 3, 'School Name', bold: true);
  b.put(1, 3, p.schoolName);
  b.put(3, 3, 'School Year', bold: true);
  b.put(4, 3, p.sy);
  b.put(6, 3, 'Grade & Section', bold: true);
  b.put(7, 3, cls.title);
  if (extra != null) b.put(0, 4, extra, bold: true);
}

// ---------------------------------------------------------------------------
// SF1 School Register
// ---------------------------------------------------------------------------

Uint8List buildSf1Xlsx(SchoolProfile p, SchoolClass cls, List<Learner> learners) {
  final b = _Book()..addSheet('SF1');
  const heads = ['LRN', "NAME (Last Name, First Name, Middle Name)", 'Sex (M/F)', 'BIRTH DATE (yyyy-mm-dd)', 'AGE as of Oct 31',
    'ADDRESS', "PARENT / GUARDIAN", 'CONTACT NUMBER', 'REMARKS'];
  _header(b, 'School Form 1 (SF1) School Register', p, cls, heads.length - 1);
  const r0 = 6;
  for (var c = 0; c < heads.length; c++) {
    b.put(c, r0, heads[c], bold: true, center: true, border: true, wrap: true, size: 9);
  }
  final syStart = int.tryParse(p.sy.split('-').first) ?? DateTime.now().year;
  var r = r0 + 1;
  for (final sex in ['M', 'F']) {
    final group = learners.where((l) => l.sex == sex).toList();
    for (final l in group) {
      final remarks = switch (l.status) {
        'dropped' => 'DRP',
        'transferred_out' => 'T/O',
        'transferred_in' => 'T/I',
        _ => '',
      };
      final row = [l.lrn, l.sf1Name, l.sex, l.birth, ageOn(l.birth, DateTime(syStart, 10, 31)), l.address, l.guardian, l.contact,
        [remarks, l.remarks].where((s) => s.isNotEmpty).join(' ')];
      for (var c = 0; c < row.length; c++) {
        b.put(c, r, row[c], border: true, center: c == 2 || c == 4);
      }
      r++;
    }
    b.put(1, r, '<=== ${sex == 'M' ? 'MALE' : 'FEMALE'} TOTAL: ${group.length}', bold: true, border: true);
    r += 2;
  }
  b.put(1, r, 'COMBINED TOTAL: ${learners.length}', bold: true);
  b.put(1, r + 3, 'Prepared by: ${p.teacher}', bold: true);
  b.put(5, r + 3, 'Certified correct: ${p.schoolHead}', bold: true);
  for (final (c, w) in [(0, 15.0), (1, 34.0), (2, 8.0), (3, 13.0), (4, 9.0), (5, 32.0), (6, 26.0), (7, 15.0), (8, 18.0)]) {
    b.width(c, w);
  }
  return b.bytes();
}

// ---------------------------------------------------------------------------
// SF2 Daily Attendance Report of Learners
// ---------------------------------------------------------------------------

Uint8List buildSf2Xlsx(Sf2Data d) {
  final b = _Book()..addSheet('SF2');
  final nDays = d.days.length;
  final last = 2 + nDays + 2;
  _header(b, 'School Form 2 (SF2) Daily Attendance Report of Learners', d.profile, d.cls, last, extra: 'Report for the Month of: ${d.monthLabel}');
  const r0 = 6;
  b.put(0, r0, 'No.', bold: true, center: true, border: true);
  b.put(1, r0, "LEARNER'S NAME (Last Name, First Name, Middle Name)", bold: true, center: true, border: true, wrap: true, size: 9);
  for (var i = 0; i < nDays; i++) {
    b.put(2 + i, r0, '${d.days[i].day}\n${d.weekdayLetter(d.days[i])}', bold: true, center: true, border: true, wrap: true, size: 8);
    b.width(2 + i, 4.2);
  }
  b.put(2 + nDays, r0, 'ABSENT', bold: true, center: true, border: true, size: 8);
  b.put(3 + nDays, r0, 'TARDY', bold: true, center: true, border: true, size: 8);
  b.put(4 + nDays, r0, 'REMARKS', bold: true, center: true, border: true, size: 8);

  var r = r0 + 1, no = 0;
  void learnerRow(Sf2Row row) {
    b.put(0, r, ++no, center: true, border: true);
    b.put(1, r, row.learner.sf1Name, border: true);
    for (var i = 0; i < nDays; i++) {
      final m = row.marks[i];
      b.put(2 + i, r, m == 'A' ? 'x' : m == 'L' ? 'T' : '', center: true, border: true, bold: true);
    }
    b.put(2 + nDays, r, row.absent, center: true, border: true);
    b.put(3 + nDays, r, row.tardy, center: true, border: true);
    b.put(4 + nDays, r, row.remarks, border: true, size: 9);
    r++;
  }

  void totalRow(String label, List<int> perDay) {
    b.put(1, r, label, bold: true, border: true);
    for (var i = 0; i < nDays; i++) {
      b.put(2 + i, r, perDay[i], bold: true, center: true, border: true);
    }
    r++;
  }

  for (final row in d.rows.where((x) => x.learner.sex == 'M')) {
    learnerRow(row);
  }
  totalRow('MALE | TOTAL Per Day', d.presentPerDay('M'));
  for (final row in d.rows.where((x) => x.learner.sex == 'F')) {
    learnerRow(row);
  }
  totalRow('FEMALE | TOTAL Per Day', d.presentPerDay('F'));
  totalRow('Combined TOTAL PER DAY', d.presentPerDay(null));

  r += 1;
  b.put(1, r, 'Month: ${d.monthLabel}   No. of Days of Classes: ${d.schoolDays}', bold: true);
  b.put(2, r, 'M', bold: true, center: true);
  b.put(5, r, 'F', bold: true, center: true);
  b.put(8, r, 'TOTAL', bold: true, center: true);
  r++;
  for (final s in d.summary) {
    b.put(1, r, s.label, border: true);
    b.put(2, r, s.male, center: true, border: true);
    b.put(5, r, s.female, center: true, border: true);
    b.put(8, r, s.total, center: true, border: true);
    r++;
  }
  r++;
  b.put(1, r, 'Codes: (blank) Present; (x) Absent; (T) Tardy');
  r += 2;
  b.put(1, r, 'Prepared and certified true and correct by: ${d.profile.teacher}', bold: true);
  b.put(2 + nDays ~/ 2, r, 'Attested by: ${d.profile.schoolHead}', bold: true);
  b.width(0, 5);
  b.width(1, 36);
  b.width(2 + nDays, 8);
  b.width(3 + nDays, 8);
  b.width(4 + nDays, 22);
  return b.bytes();
}

// ---------------------------------------------------------------------------
// Class record (one sheet per term plus a summary)
// ---------------------------------------------------------------------------

Uint8List buildClassRecordXlsx(SchoolProfile p, SchoolClass cls, List<Learner> learners, GradeEngine engine) {
  final b = _Book();
  for (var t = 1; t <= p.terms; t++) {
    b.addSheet(p.termLabel(t));
    final acts = engine.activities.where((a) => a.term == t).toList();
    final ww = acts.where((a) => a.comp == 'ww').toList();
    final pt = acts.where((a) => a.comp == 'pt').toList();
    final ex = acts.where((a) => a.comp == 'ex').toList();
    final cols = 1 + ww.length + 3 + pt.length + 3 + ex.length + 2 + 2;
    _header(b, 'CLASS RECORD - ${p.termName(t)}', p, cls, cols, extra: 'Subject: ${cls.subject}   Teacher: ${p.teacher}');
    const r0 = 6;
    var c = 1;
    void group(String title, List<Activity> list, bool withTotal) {
      final span = list.length + (withTotal ? 3 : 2) - 1;
      b.merge(c, r0, c + span, r0, title, size: 9, border: true);
      for (final a in list) {
        b.put(c, r0 + 1, a.sub.isNotEmpty ? '${exSubLabels[a.sub] ?? a.sub}: ${a.title}' : a.title, bold: true, center: true, border: true, wrap: true, size: 8);
        b.put(c, r0 + 2, a.hps, center: true, border: true, bold: true);
        b.width(c, 7);
        c++;
      }
      if (withTotal) {
        b.put(c, r0 + 1, 'Total', bold: true, center: true, border: true, size: 8);
        b.put(c, r0 + 2, list.fold<double>(0, (s, a) => s + a.hps), center: true, border: true, bold: true);
        c++;
      }
      b.put(c, r0 + 1, 'PS', bold: true, center: true, border: true, size: 8);
      b.put(c, r0 + 2, 100.0, center: true, border: true);
      c++;
      b.put(c, r0 + 1, 'WS', bold: true, center: true, border: true, size: 8);
      c++;
    }

    b.put(0, r0, "LEARNERS' NAMES", bold: true, center: true, border: true);
    b.put(0, r0 + 2, 'HIGHEST POSSIBLE SCORE', bold: true, border: true, size: 8);
    group('WRITTEN WORK (${cls.ww.toStringAsFixed(0)}%)', ww, true);
    group('PERFORMANCE TASKS (${cls.pt.toStringAsFixed(0)}%)', pt, true);
    group('EXAMINATIONS (${cls.ex.toStringAsFixed(0)}%)', ex, false);
    b.put(c, r0 + 1, 'Initial Grade', bold: true, center: true, border: true, wrap: true, size: 8);
    b.put(c + 1, r0 + 1, cls.mode == 'descriptive' ? 'Letter' : 'Term Grade', bold: true, center: true, border: true, wrap: true, size: 8);

    var r = r0 + 3;
    for (final sex in ['M', 'F']) {
      b.put(0, r, sex == 'M' ? 'MALE' : 'FEMALE', bold: true);
      r++;
      for (final l in learners.where((l) => l.sex == sex)) {
        final res = engine.term(l.id, t);
        var cc = 1;
        b.put(0, r, l.fullName, border: true);
        void scores(List<Activity> list, String comp, bool withTotal) {
          for (final a in list) {
            final s = engine.scores[a.id]?[l.id];
            b.put(cc++, r, a.workStates[l.id] == 'excused' ? 'EXC' : s == null ? '' : (s == s.roundToDouble() ? s.toInt() : s), center: true, border: true);
          }
          final cs = res.comps[comp]!;
          if (withTotal) b.put(cc++, r, cs.got == cs.got.roundToDouble() ? cs.got.toInt() : cs.got, center: true, border: true);
          b.put(cc++, r, cs.ps == null ? '' : round2(cs.ps!), center: true, border: true);
          b.put(cc++, r, cs.ps == null ? '' : round2(cs.ps! * engine.weightOf(comp) / 100), center: true, border: true, bold: true);
        }

        scores(ww, 'ww', true);
        scores(pt, 'pt', true);
        scores(ex, 'ex', false);
        b.put(cc++, r, res.hasData ? res.initialGrade : '', center: true, border: true);
        b.put(cc, r, '${res.display}${res.hasData && res.incomplete ? ' (running)' : ''}', center: true, border: true, bold: true);
        r++;
      }
    }
    b.put(0, r + 1, 'Blank = pending; EXC = excused. Running grades exclude pending and excused work and are not final.', size: 8);
    b.width(0, 32);
  }

  // Summary sheet
  b.addSheet('Summary');
  final last = 2 + p.terms + 2;
  _header(b, 'SUMMARY OF GRADES - ${cls.subject}', p, cls, last);
  const r0 = 6;
  final heads = ['No.', "Learner's Name", for (var t = 1; t <= p.terms; t++) p.termLabel(t), 'Final Grade', 'Descriptor', 'Remarks'];
  for (var c = 0; c < heads.length; c++) {
    b.put(c, r0, heads[c], bold: true, center: true, border: true);
  }
  var r = r0 + 1, no = 0;
  for (final l in learners) {
    final f = engine.finalGrade(l.id, p.terms);
    b.put(0, r, ++no, center: true, border: true);
    b.put(1, r, l.fullName, border: true);
    for (var t = 0; t < p.terms; t++) {
      final result = f.terms[t];
      final d = '${result.display}${result.hasData && result.incomplete ? ' (running)' : ''}';
      b.put(2 + t, r, int.tryParse(d) ?? d, center: true, border: true);
    }
    b.put(2 + p.terms, r, f.partial ? 'In progress' : f.finalGrade ?? f.letter ?? '', center: true, border: true, bold: true);
    b.put(3 + p.terms, r, f.partial || f.finalGrade == null ? '' : descriptor(f.finalGrade!, legacy: cls.legacyRules), center: true, border: true);
    b.put(4 + p.terms, r, f.remarks, center: true, border: true);
    r++;
  }
  b.width(1, 32);
  b.width(3 + p.terms, 16);
  return b.bytes();
}

// ---------------------------------------------------------------------------
// Item analysis
// ---------------------------------------------------------------------------

Uint8List buildItemAnalysisXlsx(SchoolProfile p, SchoolClass cls, Exam exam, ExamStats s, List<Learner> learners, Map<String, ExamResponse> responses,
    List<ExamItem> items) {
  final b = _Book()..addSheet('Item Analysis');
  _header(b, 'ITEM ANALYSIS AND MPS - ${exam.title}', p, cls, 10, extra: 'Subject: ${cls.subject}   ${p.termName(exam.term)}');
  var r = 6;
  final summary = [
    ['Learners tested', s.n],
    ['Number of items', s.k],
    ['Mean', round2(s.mean)],
    ['Standard deviation', round2(s.sd)],
    ['Highest score', s.highest],
    ['Lowest score', s.lowest],
    ['MPS', round2(s.mps)],
    ['Mastery level', s.masteryLevel],
  ];
  for (final row in summary) {
    b.put(0, r, row[0], bold: true, border: true);
    b.put(1, r, row[1], border: true, center: true);
    r++;
  }
  r++;
  const heads = ['Item', 'Competency', 'Key', 'Correct', '% Correct', 'A', 'B', 'C', 'D', 'Blank', 'Difficulty', 'Discrimination', 'Decision', 'Mastery'];
  for (var c = 0; c < heads.length; c++) {
    b.put(c, r, heads[c], bold: true, center: true, border: true);
  }
  r++;
  for (final it in s.items) {
    final row = <Object>[it.index + 1, it.item.competency, 'ABCD'[it.item.answer], it.correct, round2(it.percent), ...it.counts, it.blanks,
      '${round2(it.difficulty)} (${it.difficultyLabel})', round2(it.discrimination), it.decision, it.mastery];
    for (var c = 0; c < row.length; c++) {
      b.put(c, r, row[c], border: true, center: c != 1);
    }
    r++;
  }

  // Learner responses sheet
  b.addSheet('Responses');
  b.put(0, 0, 'No.', bold: true, border: true);
  b.put(1, 0, "Learner's Name", bold: true, border: true);
  b.put(2, 0, 'Score', bold: true, border: true);
  for (var i = 0; i < items.length; i++) {
    b.put(3 + i, 0, i + 1, bold: true, center: true, border: true);
    b.width(3 + i, 4);
  }
  var rr = 1;
  for (final l in learners) {
    final resp = responses[l.id];
    if (resp == null) continue;
    b.put(0, rr, l.num, center: true, border: true);
    b.put(1, rr, l.fullName, border: true);
    b.put(2, rr, resp.score, center: true, border: true, bold: true);
    for (var i = 0; i < items.length; i++) {
      final a = i < resp.answers.length ? resp.answers[i] : ansBlank;
      b.put(3 + i, rr, letterOf(a), center: true, border: true, bold: a == items[i].answer);
    }
    rr++;
  }
  b.width(1, 30);
  return b.bytes();
}

/// School Form 5: Report on Promotion and Level of Proficiency.
Uint8List buildSf5Xlsx(Sf5Data d) {
  final b = _Book()..addSheet('SF5');
  const heads = ['LRN', "LEARNER'S NAME", 'GENERAL AVERAGE', 'ACTION TAKEN', 'LEARNING AREAS BELOW 75'];
  _header(b, 'School Form 5 (SF5) Report on Promotion and Level of Proficiency', d.profile, d.cls, heads.length - 1);
  const r0 = 6;
  for (var c = 0; c < heads.length; c++) {
    b.put(c, r0, heads[c], bold: true, center: true, border: true, wrap: true, size: 9);
  }
  var r = r0 + 1;
  for (final sex in const ['M', 'F']) {
    b.put(1, r, sex == 'M' ? 'MALE' : 'FEMALE', bold: true, border: true);
    r++;
    for (final row in d.rows.where((x) => x.learner.sex == sex)) {
      b.put(0, r, row.learner.lrn, border: true);
      b.put(1, r, row.learner.fullName, border: true);
      b.put(2, r, int.tryParse(row.generalAverage ?? '') ?? row.generalAverage, center: true, border: true);
      b.put(3, r, row.action, center: true, border: true);
      b.put(4, r, row.belowPassing.join(', '), border: true, wrap: true);
      r++;
    }
  }
  r++;
  for (final (title, counts) in [('SUMMARY', d.actions), ('LEVEL OF PROFICIENCY', d.levels)]) {
    b.put(1, r, title, bold: true, border: true);
    b.put(2, r, 'MALE', bold: true, center: true, border: true);
    b.put(3, r, 'FEMALE', bold: true, center: true, border: true);
    b.put(4, r, 'TOTAL', bold: true, center: true, border: true);
    r++;
    for (final c in counts) {
      b.put(1, r, c.label, border: true);
      b.put(2, r, c.male, center: true, border: true);
      b.put(3, r, c.female, center: true, border: true);
      b.put(4, r, c.total, center: true, border: true);
      r++;
    }
    r++;
  }
  b.width(0, 16);
  b.width(1, 36);
  b.width(2, 12);
  b.width(3, 24);
  b.width(4, 34);
  return b.bytes();
}

