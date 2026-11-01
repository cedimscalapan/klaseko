import 'package:flutter/material.dart';

import '../../core/export/pdf_docs.dart';
import '../../core/export/share.dart';
import '../../core/export/xlsx_docs.dart';
import '../../core/models.dart';
import '../grades/class_record_screen.dart';
import '../pdf_preview_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'sf2_screen.dart';
import 'sf9_screen.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.cls});
  final SchoolClass cls;

  @override
  Widget build(BuildContext context) {
    final advisory = cls.advisory;
    return Scaffold(
      appBar: AppBar(title: const Text('Reports and school forms')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        if (!advisory)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Text('SF1 and SF9 are made by the class adviser. Turn on "This is my advisory class" in Edit class if this is your advisory section.'),
            ),
          ),
        const SectionTitle('School forms'),
        if (advisory)
          _tile(context, Icons.how_to_reg_outlined, 'SF1 · School Register', 'Excel, learners grouped by sex with LRN and details', () async {
            await withProgress(context, 'Making SF1...', () async {
              final learners = await store.repo.learners(cls.id);
              await saveAndShare(buildSf1Xlsx(store.profile, cls, learners), 'SF1 ${cls.title}.xlsx', xlsxMime);
            });
          }),
        _tile(context, Icons.calendar_month_outlined, 'SF2 · Daily Attendance Report', 'Monthly, with totals and summary · PDF or Excel',
            () => push(context, Sf2Screen(cls: cls, initialMonth: DateTime.now()))),
        if (advisory)
          _tile(context, Icons.contact_page_outlined, 'SF9 · Report Card', 'Grades, attendance and core values per learner · PDF', () => push(context, Sf9Screen(cls: cls))),
        const SectionTitle('Grades'),
        _tile(context, Icons.table_view_outlined, 'Class record (Excel)', 'One sheet per term with scores, PS, WS, initial and term grades', () async {
          await withProgress(context, 'Making the class record...', () async {
            final d = await loadRecord(cls);
            await saveAndShare(buildClassRecordXlsx(store.profile, d.engine.cls, d.learners, d.engine), 'Class Record ${cls.subject} ${cls.title}.xlsx', xlsxMime);
          });
        }),
        _tile(context, Icons.summarize_outlined, 'Summary of grades (PDF)', 'Term grades, final grade, descriptor and remarks', () async {
          push(
            context,
            PdfPreviewScreen(
              title: 'Summary of grades',
              fileName: 'Grades ${cls.subject} ${cls.title}.pdf',
              build: () async {
                final d = await loadRecord(cls);
                return buildGradeSheetPdf(profile: store.profile, cls: d.engine.cls, learners: d.learners, engine: d.engine);
              },
            ),
          );
        }),
        const SizedBox(height: 12),
        Text(
          'Files are made on your phone. Use Share to save them to Files or Google Drive, or send them to your school head. '
          'Check the form versions your division requires before submitting.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          onTap: onTap,
          child: Row(children: [
            Icon(icon, color: brandBlue),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      );
}
