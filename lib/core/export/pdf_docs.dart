import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../analysis.dart';
import '../grading.dart';
import '../models.dart';
import '../omr/sheet_layout.dart';
import 'form_data.dart';

const double mm = PdfPageFormat.mm;

PdfPageFormat paperFormat(String paper) {
  switch (paper) {
    case 'long':
      return const PdfPageFormat(215.9 * mm, 330.2 * mm);
    case 'a4':
      return PdfPageFormat.a4;
    default:
      return PdfPageFormat.letter;
  }
}

/// The built-in PDF fonts cover Latin-1 only; replace the few characters that fall outside it.
String clean(String s) => s
    .replaceAll('–', '-')
    .replaceAll('—', '-')
    .replaceAll('‘', "'")
    .replaceAll('’', "'")
    .replaceAll('“', '"')
    .replaceAll('”', '"')
    .replaceAll('₱', 'PHP ')
    .replaceAll('…', '...')
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '?');

pw.Widget _t(String s, {double size = 8, bool bold = false, PdfColor? color, pw.TextAlign? align}) => pw.Text(
      clean(s),
      textAlign: align,
      style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
    );

pw.Widget _cell(String s, {double size = 6.5, bool bold = false, pw.Alignment align = pw.Alignment.center, PdfColor? bg, PdfColor? color}) =>
    pw.Container(
      alignment: align,
      color: bg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
      child: _t(s, size: size, bold: bold, color: color),
    );

// ---------------------------------------------------------------------------
// Answer sheets
// ---------------------------------------------------------------------------

class SheetTarget {
  final Learner? learner;
  const SheetTarget(this.learner);
}

Future<Uint8List> buildAnswerSheets({
  required SchoolProfile profile,
  required SchoolClass cls,
  required Exam exam,
  required int itemCount,
  required List<SheetTarget> targets,
}) async {
  final doc = pw.Document(title: 'Answer sheets - ${exam.title}', author: 'KlaseKo');
  final format = paperFormat(profile.paper);
  final pageW = format.width / mm, pageH = format.height / mm;
  final ox = (pageW - SheetLayout.frameW) / 2;
  final oy = (pageH - SheetLayout.frameH) / 2;
  final n = itemCount.clamp(1, SheetLayout.maxItems);

  pw.Widget at(double x, double y, pw.Widget child) => pw.Positioned(left: (ox + x) * mm, top: (oy + y) * mm, child: child);

  pw.Widget bubble(double cx, double cy, double r, String label, {bool filled = false}) => at(
        cx - r,
        cy - r,
        pw.Container(
          width: 2 * r * mm,
          height: 2 * r * mm,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            shape: pw.BoxShape.circle,
            color: filled ? PdfColors.black : null,
            border: pw.Border.all(color: PdfColors.grey700, width: 0.7),
          ),
          child: filled ? null : pw.Text(label, style: pw.TextStyle(fontSize: 6.5, color: PdfColors.grey400)),
        ),
      );

  for (final target in targets) {
    final l = target.learner;
    final children = <pw.Widget>[];
    // Coded markers: black border plus a 4 x 4 pattern that names each marker.
    const cell = SheetLayout.markerCell;
    for (var id = 0; id < SheetLayout.markerCenters.length; id++) {
      final c = SheetLayout.markerCenters[id];
      final x0 = c.x - SheetLayout.marker / 2, y0 = c.y - SheetLayout.marker / 2;
      children.add(at(x0, y0, pw.Container(width: SheetLayout.marker * mm, height: SheetLayout.marker * mm, color: PdfColors.white)));
      for (var r = 0; r < 6; r++) {
        for (var col = 0; col < 6; col++) {
          final border = r == 0 || col == 0 || r == 5 || col == 5;
          if (!border && !SheetLayout.markerBit(id, r - 1, col - 1)) continue;
          // Slight overlap so neighbouring black cells print as one solid area.
          children.add(at(x0 + col * cell, y0 + r * cell, pw.Container(width: (cell + 0.05) * mm, height: (cell + 0.05) * mm, color: PdfColors.black)));
        }
      }
    }

    // Header
    children.add(at(
      6,
      6,
      pw.SizedBox(
        width: 128 * mm,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _t('KlaseKo Answer Sheet', size: 12, bold: true),
          pw.SizedBox(height: 2),
          _t(exam.title, size: 9, bold: true),
          _t('${cls.subject} | ${cls.title} | ${profile.termName(exam.term)} | ${n} items', size: 8),
          if (profile.schoolName.isNotEmpty) _t(profile.schoolName, size: 8, color: PdfColors.grey700),
          pw.SizedBox(height: 6),
          _line('Name', l?.fullName ?? ''),
          pw.SizedBox(height: 4),
          pw.Row(children: [
            pw.Expanded(child: _line('LRN', l?.lrn ?? '')),
            pw.SizedBox(width: 8),
            pw.Expanded(child: _line('Date', '')),
          ]),
          pw.SizedBox(height: 4),
          pw.Row(children: [
            pw.Expanded(child: _line('Learner No.', l == null ? '' : l.num.toString().padLeft(2, '0'))),
            pw.SizedBox(width: 8),
            pw.Expanded(child: _line('Score', '')),
          ]),
          pw.SizedBox(height: 6),
          _t('Shade one circle fully for each item using a dark pen or pencil. Do not fold or write on the black markers.', size: 6.5, color: PdfColors.grey700),
        ]),
      ),
    ));

    // Learner number block
    children.add(at(SheetLayout.idX0 - 7, 6, _t('LEARNER NO.', size: 6.5, bold: true)));
    final tens = l == null ? -1 : (l.num ~/ 10) % 10;
    final ones = l == null ? -1 : l.num % 10;
    for (var col = 0; col < 2; col++) {
      for (var d = 0; d < 10; d++) {
        final c = SheetLayout.idBubble(col, d);
        final filled = (col == 0 && d == tens) || (col == 1 && d == ones);
        children.add(bubble(c.x, c.y, SheetLayout.idR, '$d', filled: filled));
      }
    }
    for (var d = 0; d < 10; d++) {
      final c = SheetLayout.idBubble(0, d);
      children.add(at(c.x - 8, c.y - 1.6, _t('$d', size: 6, color: PdfColors.grey600)));
    }

    // Item bubbles
    for (var i = 0; i < n; i++) {
      final lab = SheetLayout.itemLabel(i);
      children.add(at(lab.x - 4, lab.y - 1.7, pw.SizedBox(width: 6 * mm, child: _t('${i + 1}', size: 7.5, bold: true, align: pw.TextAlign.right))));
      for (var c = 0; c < SheetLayout.choices; c++) {
        final b = SheetLayout.itemBubble(i, c);
        children.add(bubble(b.x, b.y, SheetLayout.bubbleR, 'ABCD'[c]));
      }
    }

    doc.addPage(pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.SizedBox(width: format.width, height: format.height, child: pw.Stack(children: children)),
    ));
  }
  return doc.save();
}

pw.Widget _line(String label, String value) => pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      _t('$label: ', size: 8),
      pw.Expanded(
        child: pw.Container(
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
          padding: const pw.EdgeInsets.only(bottom: 1),
          child: _t(value, size: 9, bold: true),
        ),
      ),
    ]);

// ---------------------------------------------------------------------------
// Test paper
// ---------------------------------------------------------------------------

Future<Uint8List> buildTestPaper({
  required SchoolProfile profile,
  required SchoolClass cls,
  required Exam exam,
  required List<ExamItem> items,
  bool answerKey = false,
}) async {
  final doc = pw.Document(title: exam.title, author: 'KlaseKo');
  doc.addPage(pw.MultiPage(
    pageFormat: paperFormat(profile.paper),
    margin: const pw.EdgeInsets.fromLTRB(18 * mm, 14 * mm, 18 * mm, 14 * mm),
    header: (ctx) => ctx.pageNumber == 1
        ? pw.Column(children: [
            if (profile.schoolName.isNotEmpty) _t(profile.schoolName, size: 11, bold: true),
            _t(answerKey ? '${exam.title} - ANSWER KEY' : exam.title, size: 12, bold: true),
            _t('${cls.subject} | ${cls.title} | ${profile.termName(exam.term)} | SY ${profile.sy}', size: 9),
            pw.SizedBox(height: 8),
            if (!answerKey)
              pw.Row(children: [
                pw.Expanded(flex: 3, child: _line('Name', '')),
                pw.SizedBox(width: 10),
                pw.Expanded(child: _line('Date', '')),
                pw.SizedBox(width: 10),
                pw.Expanded(child: _line('Score', '')),
              ]),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: _t(
                  exam.instructions.trim().isNotEmpty
                      ? 'Directions: ${exam.instructions.trim()}'
                      : 'Directions: Read each item carefully. Shade the circle of the correct answer on your answer sheet.',
                  size: 9),
            ),
            pw.SizedBox(height: 8),
          ])
        : pw.SizedBox(),
    footer: (ctx) => pw.Row(children: [
      _t('Prepared with KlaseKo', size: 7, color: PdfColors.grey500),
      pw.Spacer(),
      _t('Page ${ctx.pageNumber} of ${ctx.pagesCount}', size: 7, color: PdfColors.grey600),
    ]),
    build: (ctx) => [
      for (var i = 0; i < items.length; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 7),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _t('${i + 1}. ${items[i].question}', size: 10),
            pw.SizedBox(height: 2),
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 12),
              child: pw.Wrap(spacing: 18, runSpacing: 2, children: [
                for (var c = 0; c < items[i].choiceCount; c++)
                  pw.SizedBox(
                    width: 75 * mm,
                    child: _t(
                      '${'ABCD'[c]}. ${items[i].type == 'tf' ? (c == 0 ? 'True' : 'False') : items[i].choices[c]}',
                      size: 9.5,
                      bold: answerKey && c == items[i].answer,
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      if (answerKey) ...[
        pw.SizedBox(height: 10),
        _t('Answer key', size: 10, bold: true),
        pw.Wrap(spacing: 12, runSpacing: 4, children: [
          for (var i = 0; i < items.length; i++) _t('${i + 1}. ${'ABCD'[items[i].answer]}', size: 9),
        ]),
      ],
    ],
  ));
  return doc.save();
}

// ---------------------------------------------------------------------------
// School Form 2: Daily Attendance Report of Learners
// ---------------------------------------------------------------------------

Future<Uint8List> buildSf2Pdf(Sf2Data d) async {
  final doc = pw.Document(title: 'SF2 ${d.monthLabel}', author: 'KlaseKo');
  final format = PdfPageFormat(13 * PdfPageFormat.inch, 8.5 * PdfPageFormat.inch);
  final dayCols = d.days.length;
  final widths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(16),
    1: const pw.FixedColumnWidth(150),
    for (var i = 0; i < dayCols; i++) 2 + i: const pw.FixedColumnWidth(18),
    2 + dayCols: const pw.FixedColumnWidth(30),
    3 + dayCols: const pw.FixedColumnWidth(30),
    4 + dayCols: const pw.FixedColumnWidth(110),
  };
  final border = pw.TableBorder.all(width: 0.4, color: PdfColors.grey700);
  final headBg = PdfColors.grey200;

  List<pw.Widget> headRow1() => [
        _cell('No.', bold: true, bg: headBg),
        _cell("LEARNER'S NAME\n(Last Name, First Name, Middle Name)", bold: true, bg: headBg),
        for (final day in d.days) _cell('${day.day}\n${d.weekdayLetter(day)}', bold: true, bg: headBg),
        _cell('ABSENT', bold: true, bg: headBg),
        _cell('TARDY', bold: true, bg: headBg),
        _cell('REMARKS', bold: true, bg: headBg),
      ];

  pw.TableRow learnerRow(int no, Sf2Row r) => pw.TableRow(children: [
        _cell('$no'),
        _cell(r.learner.sf1Name, align: pw.Alignment.centerLeft),
        for (final s in r.marks) _cell(s == 'A' ? 'x' : s == 'L' ? 'T' : '', bold: true, color: s == 'A' ? PdfColors.red800 : PdfColors.black),
        _cell('${r.absent}', bold: true),
        _cell('${r.tardy}', bold: true),
        _cell(r.remarks, align: pw.Alignment.centerLeft, size: 6),
      ]);

  pw.TableRow totalRow(String label, List<int> perDay) => pw.TableRow(
        decoration: pw.BoxDecoration(color: headBg),
        children: [
          _cell(''),
          _cell(label, bold: true, align: pw.Alignment.centerLeft),
          for (final v in perDay) _cell('$v', bold: true),
          _cell(''),
          _cell(''),
          _cell(''),
        ],
      );

  final males = d.rows.where((r) => r.learner.sex == 'M').toList();
  final females = d.rows.where((r) => r.learner.sex == 'F').toList();
  var no = 0;

  doc.addPage(pw.MultiPage(
    pageFormat: format,
    margin: const pw.EdgeInsets.all(18),
    header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Center(child: _t('School Form 2 (SF2) Daily Attendance Report of Learners', size: 11, bold: true)),
      pw.Center(child: _t('(This replaces Form 1, Form 2 & STS Form 4 - Absenteeism and Dropout Profile)', size: 7)),
      pw.SizedBox(height: 6),
      pw.Row(children: [
        _labeled('School ID', d.profile.schoolId, 80),
        _labeled('School Year', d.profile.sy, 70),
        _labeled('Report for the Month of', d.monthLabel, 110),
      ]),
      pw.SizedBox(height: 3),
      pw.Row(children: [
        _labeled('Name of School', d.profile.schoolName, 240),
        _labeled('Grade Level', d.cls.grade, 70),
        _labeled('Section', d.cls.section, 90),
      ]),
      pw.SizedBox(height: 6),
    ]),
    build: (ctx) => [
      pw.Table(border: border, columnWidths: widths, children: [
        pw.TableRow(children: headRow1()),
        for (final r in males) learnerRow(++no, r),
        totalRow('MALE | TOTAL Per Day', d.presentPerDay('M')),
        for (final r in females) learnerRow(++no, r),
        totalRow('FEMALE | TOTAL Per Day', d.presentPerDay('F')),
        totalRow('Combined TOTAL PER DAY', d.presentPerDay(null)),
      ]),
      pw.SizedBox(height: 8),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          flex: 3,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _t('GUIDELINES:', size: 7, bold: true),
            _t('1. The attendance shall be accomplished daily. Refer to the codes for checking learners\' attendance.', size: 6.5),
            _t('2. Dates shall be written in the columns after Learner\'s Name.', size: 6.5),
            _t('3. Percentage of Enrolment = Registered Learners as of end of the month / Enrolment as of 1st Friday of the school year x 100', size: 6.5),
            _t('4. Average Daily Attendance = Total Daily Attendance / Number of School Days in reporting month', size: 6.5),
            _t('5. Percentage of Attendance for the month = Average daily attendance / Registered Learners as of end of the month x 100', size: 6.5),
            _t('6. Every end of the month, the class adviser submits this form to the office of the principal for recording of summary table into SF4.', size: 6.5),
            pw.SizedBox(height: 4),
            _t('CODES FOR CHECKING ATTENDANCE: (blank) Present; (x) Absent; (T) Tardy', size: 6.5, bold: true),
          ]),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          flex: 2,
          child: pw.Table(border: border, columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(1),
          }, children: [
            pw.TableRow(decoration: pw.BoxDecoration(color: headBg), children: [
              _cell('Month: ${d.monthLabel}   No. of Days of Classes: ${d.schoolDays}', bold: true, align: pw.Alignment.centerLeft),
              _cell('M', bold: true),
              _cell('F', bold: true),
              _cell('TOTAL', bold: true),
            ]),
            for (final s in d.summary)
              pw.TableRow(children: [
                _cell(s.label, align: pw.Alignment.centerLeft),
                _cell(s.male),
                _cell(s.female),
                _cell(s.total),
              ]),
          ]),
        ),
      ]),
      pw.SizedBox(height: 14),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
        _signature('Prepared and certified true and correct by:', d.profile.teacher, 'Teacher'),
        _signature('Attested by:', d.profile.schoolHead, 'School Head'),
      ]),
    ],
  ));
  return doc.save();
}

pw.Widget _labeled(String label, String value, double width) => pw.Padding(
      padding: const pw.EdgeInsets.only(right: 14),
      child: pw.Row(children: [
        _t('$label ', size: 7.5),
        pw.Container(
          width: width,
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
          child: _t(value, size: 8, bold: true),
        ),
      ]),
    );

pw.Widget _signature(String caption, String name, String role) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      _t(caption, size: 7),
      pw.SizedBox(height: 14),
      pw.Container(
        width: 170,
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
        alignment: pw.Alignment.center,
        child: _t(name.toUpperCase(), size: 8, bold: true),
      ),
      _t('(Signature of $role over Printed Name)', size: 6.5),
    ]);

// ---------------------------------------------------------------------------
// School Form 9: Learner's Progress / Performance Report
// ---------------------------------------------------------------------------

const coreValues = <List<String>>[
  ['Maka-Diyos', "Expresses one's spiritual beliefs while respecting the spiritual beliefs of others."],
  ['Maka-Diyos', 'Shows adherence to ethical principles by upholding truth.'],
  ['Makatao', 'Is sensitive to individual, social, and cultural differences.'],
  ['Makatao', 'Demonstrates contributions toward solidarity.'],
  ['Maka-kalikasan', 'Cares for the environment and utilizes resources wisely, judiciously, and economically.'],
  ['Makabansa', 'Demonstrates pride in being a Filipino; exercises the rights and responsibilities of a Filipino citizen.'],
  ['Makabansa', 'Demonstrates appropriate behavior in carrying out activities in the school, community, and country.'],
];

Future<Uint8List> buildSf9Pdf(List<Sf9Data> cards) async {
  final doc = pw.Document(title: 'SF9', author: 'KlaseKo');
  final format = PdfPageFormat.letter.landscape;
  final border = pw.TableBorder.all(width: 0.5, color: PdfColors.grey800);
  final headBg = PdfColors.grey200;

  for (final c in cards) {
    final p = c.profile;
    final terms = p.terms;
    final descriptive = c.cls.mode == 'descriptive';

    // Front: attendance (left) and cover (right)
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(22),
      build: (_) => pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Center(child: _t('REPORT ON ATTENDANCE', size: 10, bold: true)),
            pw.SizedBox(height: 6),
            pw.Table(border: border, children: [
              pw.TableRow(decoration: pw.BoxDecoration(color: headBg), children: [
                _cell('', size: 6),
                for (final m in c.months) _cell(m.label, size: 6, bold: true),
                _cell('Total', size: 6, bold: true),
              ]),
              pw.TableRow(children: [
                _cell('No. of School Days', size: 6, align: pw.Alignment.centerLeft),
                for (final m in c.months) _cell(m.schoolDays == 0 ? '' : '${m.schoolDays}', size: 6.5),
                _cell('${c.months.fold<int>(0, (a, m) => a + m.schoolDays)}', size: 6.5, bold: true),
              ]),
              pw.TableRow(children: [
                _cell('No. of Days Present', size: 6, align: pw.Alignment.centerLeft),
                for (final m in c.months) _cell(m.schoolDays == 0 ? '' : '${m.present}', size: 6.5),
                _cell('${c.months.fold<int>(0, (a, m) => a + m.present)}', size: 6.5, bold: true),
              ]),
              pw.TableRow(children: [
                _cell('No. of Days Absent', size: 6, align: pw.Alignment.centerLeft),
                for (final m in c.months) _cell(m.schoolDays == 0 ? '' : '${m.absent}', size: 6.5),
                _cell('${c.months.fold<int>(0, (a, m) => a + m.absent)}', size: 6.5, bold: true),
              ]),
            ]),
            pw.SizedBox(height: 24),
            pw.Center(child: _t("PARENT / GUARDIAN'S SIGNATURE", size: 9, bold: true)),
            pw.SizedBox(height: 10),
            for (var t = 1; t <= terms; t++) ...[
              pw.Row(children: [
                pw.SizedBox(width: 60, child: _t(p.termName(t), size: 8)),
                pw.Expanded(child: pw.Container(height: 14, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6))))),
              ]),
              pw.SizedBox(height: 8),
            ],
          ]),
        ),
        pw.SizedBox(width: 26),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            _t('SF9', size: 8, bold: true),
            _t('Republic of the Philippines', size: 8),
            _t('DEPARTMENT OF EDUCATION', size: 9, bold: true),
            if (p.region.isNotEmpty) _t('Region ${p.region}', size: 8),
            if (p.division.isNotEmpty) _t('Division of ${p.division}', size: 8),
            if (p.district.isNotEmpty) _t('District of ${p.district}', size: 8),
            _t(p.schoolName.toUpperCase(), size: 10, bold: true),
            if (p.schoolId.isNotEmpty) _t('School ID: ${p.schoolId}', size: 8),
            pw.SizedBox(height: 10),
            _t(descriptive ? "LEARNER'S PROGRESS REPORT" : "LEARNER'S PERFORMANCE REPORT", size: 12, bold: true),
            pw.SizedBox(height: 10),
            _line('Name', c.learner.sf1Name),
            pw.SizedBox(height: 5),
            pw.Row(children: [
              pw.Expanded(child: _line('LRN', c.learner.lrn)),
              pw.SizedBox(width: 8),
              pw.SizedBox(width: 60, child: _line('Age', c.age)),
              pw.SizedBox(width: 8),
              pw.SizedBox(width: 60, child: _line('Sex', c.learner.sex == 'M' ? 'Male' : 'Female')),
            ]),
            pw.SizedBox(height: 5),
            pw.Row(children: [
              pw.Expanded(child: _line('Grade', c.cls.grade)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _line('Section', c.cls.section)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _line('School Year', p.sy)),
            ]),
            pw.SizedBox(height: 12),
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: _t(
                  'Dear Parent,\n     This report card shows the ability and the progress your child has made in the different learning areas as well as his/her progress in core values.\n     The school welcomes you should you desire to know more about your child\'s progress.',
                  size: 8),
            ),
            pw.SizedBox(height: 14),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
              _signatureSmall(p.schoolHead, 'School Head'),
              _signatureSmall(p.teacher, 'Teacher'),
            ]),
            pw.SizedBox(height: 14),
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Center(child: _t('CERTIFICATE OF TRANSFER', size: 8, bold: true)),
                pw.SizedBox(height: 4),
                _t('Admitted to Grade: ____________  Section: ____________', size: 7.5),
                _t('Eligibility for Admission to Grade: ____________', size: 7.5),
                pw.SizedBox(height: 10),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
                  _signatureSmall(p.schoolHead, 'School Head'),
                  _signatureSmall(p.teacher, 'Teacher'),
                ]),
              ]),
            ),
          ]),
        ),
      ]),
    ));

    // Back: learning progress (left) and observed values (right)
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(22),
      build: (_) => pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Center(child: _t('REPORT ON LEARNING PROGRESS AND ACHIEVEMENT', size: 9.5, bold: true)),
            pw.SizedBox(height: 6),
            pw.Table(border: border, columnWidths: {
              0: const pw.FlexColumnWidth(3.4),
              for (var t = 1; t <= terms; t++) t: const pw.FlexColumnWidth(0.8),
              terms + 1: const pw.FlexColumnWidth(1.1),
              terms + 2: const pw.FlexColumnWidth(1.3),
            }, children: [
              pw.TableRow(decoration: pw.BoxDecoration(color: headBg), children: [
                _cell('Learning Areas', bold: true, size: 7),
                for (var t = 1; t <= terms; t++) _cell(p.termLabel(t), bold: true, size: 7),
                _cell('Final Grade', bold: true, size: 7),
                _cell('Remarks', bold: true, size: 7),
              ]),
              for (final a in c.areas)
                pw.TableRow(children: [
                  _cell(a.name, size: 7, align: pw.Alignment.centerLeft, bold: !a.isComponent),
                  for (var t = 1; t <= terms; t++) _cell(a.terms[t] ?? '', size: 7.5),
                  _cell(a.finalGrade ?? '', size: 7.5, bold: true),
                  _cell(a.remarks, size: 7),
                ]),
              pw.TableRow(decoration: pw.BoxDecoration(color: headBg), children: [
                _cell('General Average', size: 7.5, bold: true, align: pw.Alignment.centerLeft),
                for (var t = 1; t <= terms; t++) _cell(''),
                _cell(c.generalAverage ?? '', size: 8, bold: true),
                _cell(c.generalRemarks, size: 7, bold: true),
              ]),
            ]),
            pw.SizedBox(height: 8),
            if (descriptive) ...[
              _t('Descriptors', size: 7.5, bold: true),
              for (final e in ks1Letters.entries) _t('${e.key} - ${e.value}', size: 7),
            ] else ...[
              pw.Table(border: border, children: [
                pw.TableRow(decoration: pw.BoxDecoration(color: headBg), children: [
                  _cell('Descriptors', bold: true, size: 7),
                  _cell('Grading Scale', bold: true, size: 7),
                  _cell('Remarks', bold: true, size: 7),
                ]),
                for (final row in c.cls.legacyRules ? _legacyScale : _scale2026)
                  pw.TableRow(children: [_cell(row[0], size: 7), _cell(row[1], size: 7), _cell(row[2], size: 7)]),
              ]),
            ],
            if (c.promotion.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              _t('Status: ${c.promotion}', size: 8, bold: true),
            ],
          ]),
        ),
        pw.SizedBox(width: 24),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Center(child: _t("REPORT ON LEARNER'S OBSERVED VALUES", size: 9.5, bold: true)),
            pw.SizedBox(height: 6),
            pw.Table(border: border, columnWidths: {
              0: const pw.FlexColumnWidth(1.3),
              1: const pw.FlexColumnWidth(3.6),
              for (var t = 1; t <= terms; t++) t + 1: const pw.FlexColumnWidth(0.55),
            }, children: [
              pw.TableRow(decoration: pw.BoxDecoration(color: headBg), children: [
                _cell('Core Values', bold: true, size: 7),
                _cell('Behavior Statements', bold: true, size: 7),
                for (var t = 1; t <= terms; t++) _cell(p.termLabel(t), bold: true, size: 7),
              ]),
              for (var i = 0; i < coreValues.length; i++)
                pw.TableRow(children: [
                  _cell(i > 0 && coreValues[i - 1][0] == coreValues[i][0] ? '' : coreValues[i][0], size: 7, bold: true),
                  _cell(coreValues[i][1], size: 6.5, align: pw.Alignment.centerLeft),
                  for (var t = 1; t <= terms; t++) _cell(c.values[i]?[t] ?? '', size: 7),
                ]),
            ]),
            pw.SizedBox(height: 8),
            _t('Marking   Non-numerical Rating', size: 7.5, bold: true),
            _t('AO   Always Observed', size: 7),
            _t('SO   Sometimes Observed', size: 7),
            _t('RO   Rarely Observed', size: 7),
            _t('NO   Not Observed', size: 7),
          ]),
        ),
      ]),
    ));
  }
  return doc.save();
}

const _scale2026 = [
  ['Advancing', '90-100', 'Passed'],
  ['Benchmarking', '80-89', 'Passed'],
  ['Connecting', '75-79', 'Passed'],
  ['Developing', '65-74', 'Failed'],
  ['Emerging', 'Below 65', 'Failed'],
];

const _legacyScale = [
  ['Outstanding', '90-100', 'Passed'],
  ['Very Satisfactory', '85-89', 'Passed'],
  ['Satisfactory', '80-84', 'Passed'],
  ['Fairly Satisfactory', '75-79', 'Passed'],
  ['Did Not Meet Expectations', 'Below 75', 'Failed'],
];

pw.Widget _signatureSmall(String name, String role) => pw.Column(children: [
      pw.Container(
        width: 140,
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
        alignment: pw.Alignment.center,
        child: _t(name.toUpperCase(), size: 7.5, bold: true),
      ),
      _t(role, size: 7),
    ]);

// ---------------------------------------------------------------------------
// Item analysis and MPS report
// ---------------------------------------------------------------------------

Future<Uint8List> buildItemAnalysisPdf({
  required SchoolProfile profile,
  required SchoolClass cls,
  required Exam exam,
  required ExamStats stats,
  required int enrolled,
}) async {
  final doc = pw.Document(title: 'Item analysis - ${exam.title}', author: 'KlaseKo');
  final border = pw.TableBorder.all(width: 0.4, color: PdfColors.grey700);
  final headBg = PdfColors.grey200;
  doc.addPage(pw.MultiPage(
    pageFormat: paperFormat(profile.paper),
    margin: const pw.EdgeInsets.all(28),
    build: (ctx) => [
      if (profile.schoolName.isNotEmpty) pw.Center(child: _t(profile.schoolName, size: 10, bold: true)),
      pw.Center(child: _t('ITEM ANALYSIS AND MEAN PERCENTAGE SCORE (MPS)', size: 11, bold: true)),
      pw.Center(child: _t('${exam.title} | ${cls.subject} | ${cls.title} | ${profile.termName(exam.term)} | SY ${profile.sy}', size: 8.5)),
      pw.SizedBox(height: 10),
      pw.Table(border: border, children: [
        pw.TableRow(decoration: pw.BoxDecoration(color: headBg), children: [
          for (final h in ['Enrolled', 'Tested', 'Items', 'Total Score', 'Mean', 'SD', 'Highest', 'Lowest', 'MPS', 'Mastery Level'])
            _cell(h, bold: true, size: 7),
        ]),
        pw.TableRow(children: [
          _cell('$enrolled', size: 8),
          _cell('${stats.n}', size: 8),
          _cell('${stats.k}', size: 8),
          _cell((stats.mean * stats.n).round().toString(), size: 8),
          _cell(stats.mean.toStringAsFixed(2), size: 8),
          _cell(stats.sd.toStringAsFixed(2), size: 8),
          _cell('${stats.highest}', size: 8),
          _cell('${stats.lowest}', size: 8),
          _cell(stats.mps.toStringAsFixed(2), size: 8, bold: true),
          _cell(stats.masteryLevel, size: 7),
        ]),
      ]),
      pw.SizedBox(height: 10),
      pw.Table(border: border, columnWidths: const {
        0: pw.FixedColumnWidth(24),
        1: pw.FlexColumnWidth(3),
        2: pw.FixedColumnWidth(34),
        3: pw.FixedColumnWidth(30),
        4: pw.FixedColumnWidth(18),
        5: pw.FixedColumnWidth(18),
        6: pw.FixedColumnWidth(18),
        7: pw.FixedColumnWidth(18),
        8: pw.FixedColumnWidth(52),
        9: pw.FixedColumnWidth(30),
        10: pw.FixedColumnWidth(40),
      }, children: [
        pw.TableRow(decoration: pw.BoxDecoration(color: headBg), children: [
          for (final h in ['Item', 'Competency', 'Correct', '%', 'A', 'B', 'C', 'D', 'Difficulty', 'Disc.', 'Decision']) _cell(h, bold: true, size: 6.5),
        ]),
        for (final s in stats.items)
          pw.TableRow(children: [
            _cell('${s.index + 1}', size: 7, bold: true),
            _cell(s.item.competency, size: 6.5, align: pw.Alignment.centerLeft),
            _cell('${s.correct}/${s.n}', size: 7),
            _cell(s.percent.toStringAsFixed(0), size: 7, color: s.percent < 50 ? PdfColors.red800 : null, bold: s.percent < 50),
            for (var c = 0; c < 4; c++) _cell('${s.counts[c]}', size: 7, bold: c == s.item.answer),
            _cell(s.difficultyLabel, size: 6.5),
            _cell(s.discrimination.toStringAsFixed(2), size: 7),
            _cell(s.decision, size: 6.5),
          ]),
      ]),
      pw.SizedBox(height: 10),
      _t('Least-mastered competencies (below 75% correct)', size: 9, bold: true),
      pw.SizedBox(height: 4),
      pw.Table(border: border, columnWidths: const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(1.2), 2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1.6)}, children: [
        pw.TableRow(decoration: pw.BoxDecoration(color: headBg), children: [
          _cell('Competency', bold: true, size: 7),
          _cell('Items', bold: true, size: 7),
          _cell('% Correct', bold: true, size: 7),
          _cell('Status', bold: true, size: 7),
        ]),
        for (final c in stats.competencies.where((c) => c.percent < 75))
          pw.TableRow(children: [
            _cell(c.name, size: 7, align: pw.Alignment.centerLeft),
            _cell(c.items.map((i) => '${i + 1}').join(', '), size: 7),
            _cell(c.percent.toStringAsFixed(1), size: 7),
            _cell(c.mastery, size: 7),
          ]),
      ]),
      pw.SizedBox(height: 18),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
        _signature('Prepared by:', profile.teacher, 'Teacher'),
        _signature('Noted by:', profile.schoolHead, 'School Head'),
      ]),
    ],
  ));
  return doc.save();
}

// ---------------------------------------------------------------------------
// Grade summary (per term and final)
// ---------------------------------------------------------------------------

Future<Uint8List> buildGradeSheetPdf({
  required SchoolProfile profile,
  required SchoolClass cls,
  required List<Learner> learners,
  required GradeEngine engine,
}) async {
  final doc = pw.Document(title: 'Grades - ${cls.subject} ${cls.title}', author: 'KlaseKo');
  final border = pw.TableBorder.all(width: 0.4, color: PdfColors.grey700);
  final headBg = PdfColors.grey200;
  final terms = profile.terms;
  pw.TableRow row(Learner l, int no) {
    final f = engine.finalGrade(l.id, terms);
    return pw.TableRow(children: [
      _cell('$no', size: 7),
      _cell(l.fullName, size: 7, align: pw.Alignment.centerLeft),
      for (final t in f.terms) _cell(t.display, size: 7.5),
      _cell(f.finalGrade?.toString() ?? f.letter ?? '', size: 7.5, bold: true),
      _cell(f.finalGrade == null ? '' : descriptor(f.finalGrade!, legacy: cls.legacyRules), size: 6.5),
      _cell(f.remarks, size: 6.5, color: f.remarks == 'Failed' ? PdfColors.red800 : null),
    ]);
  }

  var no = 0;
  doc.addPage(pw.MultiPage(
    pageFormat: paperFormat(profile.paper),
    margin: const pw.EdgeInsets.all(28),
    build: (ctx) => [
      if (profile.schoolName.isNotEmpty) pw.Center(child: _t(profile.schoolName, size: 10, bold: true)),
      pw.Center(child: _t('SUMMARY OF GRADES', size: 11, bold: true)),
      pw.Center(child: _t('${cls.subject} | ${cls.title} | SY ${profile.sy} | Teacher: ${profile.teacher}', size: 8.5)),
      pw.Center(child: _t('Weights: WW ${cls.ww.toStringAsFixed(0)}%, PT ${cls.pt.toStringAsFixed(0)}%, EX ${cls.ex.toStringAsFixed(0)}% | ${transmuteLabels[cls.transmute] ?? ''}', size: 7.5)),
      pw.SizedBox(height: 8),
      pw.Table(border: border, columnWidths: {
        0: const pw.FixedColumnWidth(20),
        1: const pw.FlexColumnWidth(3),
        for (var t = 0; t < terms; t++) 2 + t: const pw.FixedColumnWidth(34),
        2 + terms: const pw.FixedColumnWidth(40),
        3 + terms: const pw.FixedColumnWidth(70),
        4 + terms: const pw.FixedColumnWidth(50),
      }, children: [
        pw.TableRow(decoration: pw.BoxDecoration(color: headBg), children: [
          _cell('No.', bold: true, size: 7),
          _cell("Learner's Name", bold: true, size: 7),
          for (var t = 1; t <= terms; t++) _cell(profile.termLabel(t), bold: true, size: 7),
          _cell('Final', bold: true, size: 7),
          _cell('Descriptor', bold: true, size: 7),
          _cell('Remarks', bold: true, size: 7),
        ]),
        pw.TableRow(children: [_cell(''), _cell('MALE', bold: true, size: 7, align: pw.Alignment.centerLeft), for (var i = 0; i < terms + 3; i++) _cell('')]),
        for (final l in learners.where((l) => l.sex == 'M')) row(l, ++no),
        pw.TableRow(children: [_cell(''), _cell('FEMALE', bold: true, size: 7, align: pw.Alignment.centerLeft), for (var i = 0; i < terms + 3; i++) _cell('')]),
        for (final l in learners.where((l) => l.sex == 'F')) row(l, ++no),
      ]),
      pw.SizedBox(height: 18),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
        _signature('Prepared by:', profile.teacher, 'Teacher'),
        _signature('Noted by:', profile.schoolHead, 'School Head'),
      ]),
    ],
  ));
  return doc.save();
}
