import 'package:flutter/material.dart';

import '../../core/export/form_data.dart';
import '../../core/export/pdf_docs.dart';
import '../../core/export/share.dart';
import '../../core/export/xlsx_docs.dart';
import '../../core/models.dart';
import '../pdf_preview_screen.dart';
import '../theme.dart';
import '../widgets.dart';

class Sf2Screen extends StatefulWidget {
  const Sf2Screen({super.key, required this.cls, required this.initialMonth});
  final SchoolClass cls;
  final DateTime initialMonth;

  @override
  State<Sf2Screen> createState() => _Sf2ScreenState();
}

class _Sf2ScreenState extends State<Sf2Screen> {
  late DateTime _month = DateTime(widget.initialMonth.year, widget.initialMonth.month);

  Future<Sf2Data> _load() => buildSf2Data(store.repo, store.profile, widget.cls, _month.year, _month.month);

  void _shift(int m) => setState(() => _month = DateTime(_month.year, _month.month + m));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SF2 · Attendance')),
      body: Column(children: [
        Row(children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text('${monthNames[_month.month - 1]} ${_month.year}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        ]),
        Expanded(
          child: Loader<Sf2Data>(
            key: ValueKey(_month),
            load: _load,
            builder: (context, d) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => push(
                      context,
                      PdfPreviewScreen(title: 'SF2 ${d.monthLabel}', fileName: 'SF2 ${widget.cls.title} ${d.monthLabel}.pdf', build: () => buildSf2Pdf(d)),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => withProgress(context, 'Making SF2...', () => saveAndShare(buildSf2Xlsx(d), 'SF2 ${widget.cls.title} ${d.monthLabel}.xlsx', xlsxMime)),
                    icon: const Icon(Icons.table_view_outlined),
                    label: const Text('Excel'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Text('${d.schoolDays} school day(s) with attendance this month. x = absent, T = tardy, blank = present.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              AppCard(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 10,
                    horizontalMargin: 12,
                    headingRowHeight: 40,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 40,
                    columns: [
                      const DataColumn(label: Text('Learner')),
                      for (final day in d.days) DataColumn(label: Text('${day.day}'), numeric: true),
                      const DataColumn(label: Text('Abs'), numeric: true),
                      const DataColumn(label: Text('Tdy'), numeric: true),
                    ],
                    rows: [
                      for (final r in d.rows)
                        DataRow(cells: [
                          DataCell(Text(r.learner.fullName)),
                          for (final m in r.marks)
                            DataCell(Text(m == 'A' ? 'x' : m == 'L' ? 'T' : '',
                                style: TextStyle(fontWeight: FontWeight.w800, color: m == 'A' ? penRed : lateAmber))),
                          DataCell(Text('${r.absent}', style: const TextStyle(fontWeight: FontWeight.w700))),
                          DataCell(Text('${r.tardy}')),
                        ]),
                    ],
                  ),
                ),
              ),
              const SectionTitle('Summary'),
              AppCard(
                child: Column(children: [
                  for (final s in d.summary)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text(s.label)),
                        SizedBox(width: 52, child: Text('M ${s.male}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                        SizedBox(width: 52, child: Text('F ${s.female}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                        SizedBox(width: 58, child: Text(s.total, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
                      ]),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
