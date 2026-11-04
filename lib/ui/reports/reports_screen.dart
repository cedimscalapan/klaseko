import 'package:flutter/material.dart';

import '../../core/export/form_data.dart';
import '../../core/export/pdf_docs.dart';
import '../../core/export/share.dart';
import '../../core/export/xlsx_docs.dart';
import '../../core/forms/template_fill.dart';
import '../../core/models.dart';
import '../forms/archive_info.dart';
import '../forms/archive_screen.dart';
import '../forms/fill_form.dart';
import '../forms/templates_screen.dart';
import '../grades/class_record_screen.dart';
import '../pdf_preview_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'sf2_screen.dart';
import 'sf9_screen.dart';

class _FormStatus {
  final int learners;
  final int noLrn;
  final int daysThisMonth;
  final int activities;
  final int gradesComplete;
  final List<FormTemplate> layouts;
  _FormStatus(this.learners, this.noLrn, this.daysThisMonth, this.activities, this.gradesComplete, this.layouts);
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.cls});
  final SchoolClass cls;

  Future<_FormStatus> _load() async {
    final repo = store.repo;
    final learners = (await repo.learners(cls.id)).where((l) => l.isActive).toList();
    final today = DateTime.now();
    final days = await repo.attendance(cls.id, from: dayKey(DateTime(today.year, today.month)), to: dayKey(today));
    var complete = 0;
    if (cls.advisory && learners.isNotEmpty) {
      final cards = await buildSf9Data(repo, store.profile, cls, learners, await loadAreas(cls));
      complete = cards.where((c) => c.generalAverage != null).length;
    }
    return _FormStatus(learners.length, learners.where((l) => l.lrn.trim().isEmpty).length, days.length, (await repo.activities(cls.id)).length, complete, await repo.templates());
  }

  Future<void> _sf5Excel(BuildContext context) => withProgress(context, 'Making SF5...', () async {
        final d = await buildSf5Data(store.repo, store.profile, cls, await loadAreas(cls));
        await shareAndArchive(ArchiveInfo(cls, 'sf5'), buildSf5Xlsx(d), 'SF5 ${cls.title}.xlsx', xlsxMime);
      });

  @override
  Widget build(BuildContext context) {
    final advisory = cls.advisory;
    return Scaffold(
      appBar: AppBar(title: ClassTitle('Reports and school forms', cls)),
      body: Loader<_FormStatus>(
        load: _load,
        builder: (context, st) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          AppCard(
            color: goodGreen.withAlpha(isDark(context) ? 46 : 24),
            child: const Text('These forms fill themselves from what you already entered: learners, attendance, scanned scores and activities. Nothing is typed twice.'),
          ),
          if (!advisory)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AppCard(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Text('SF1, SF5 and SF9 are made by the class adviser. Turn on "This is my advisory class" in Edit class if this is your advisory section.'),
              ),
            ),
          const SizedBox(height: 10),
          NavRow(
            icon: Icons.folder_rounded,
            title: 'Forms archive',
            subtitle: 'Everything you made for this class, sorted by term, week and form',
            color: gold,
            onTap: () => push(context, ArchiveScreen(cls: cls)),
          ),
          SectionTitle('Your own layouts', trailing: TextButton(onPressed: () => push(context, const TemplatesScreen()), child: const Text('Manage'))),
          if (st.layouts.isEmpty)
            NavRow(
              icon: Icons.upload_file_rounded,
              title: 'Use your school\'s own forms',
              subtitle: 'Upload an Excel form once. KlaseKo fills it for every class.',
              onTap: () => push(context, const TemplatesScreen()),
            ),
          for (final t in st.layouts)
            if (advisory || (t.form != 'sf1' && t.form != 'sf5' && t.form != 'sf9'))
              NavRow(
                icon: Icons.table_view_rounded,
                title: t.name,
                subtitle: 'Fill your ${templateForms[t.form] ?? 'form'} layout · Excel',
                onTap: () => fillAndShare(context, cls, t),
              ),
          const SectionTitle('School forms'),
          if (advisory)
            _tile(context, Icons.how_to_reg_outlined, 'SF1 · School Register',
                st.noLrn == 0 ? 'Ready: ${st.learners} learners, all with LRN · Excel' : 'Ready, but ${st.noLrn} of ${st.learners} learners have no LRN yet · Excel', () async {
              await withProgress(context, 'Making SF1...', () async {
                final learners = await store.repo.learners(cls.id);
                await shareAndArchive(ArchiveInfo(cls, 'sf1'), buildSf1Xlsx(store.profile, cls, learners), 'SF1 ${cls.title}.xlsx', xlsxMime);
              });
            }),
          _tile(context, Icons.calendar_month_outlined, 'SF2 · Daily Attendance Report',
              st.daysThisMonth == 0 ? 'No attendance this month yet · PDF or Excel' : '${st.daysThisMonth} ${st.daysThisMonth == 1 ? 'day' : 'days'} filled in this month · PDF or Excel',
              () => push(context, Sf2Screen(cls: cls, initialMonth: DateTime.now()))),
          if (advisory) ...[
            _tile(context, Icons.contact_page_outlined, 'SF9 · Report Card', '${st.gradesComplete} of ${st.learners} learners have complete grades · PDF', () => push(context, Sf9Screen(cls: cls))),
            _tile(context, Icons.emoji_events_outlined, 'SF5 · Promotion and Proficiency', '${st.gradesComplete} of ${st.learners} learners complete · PDF', () {
              push(
                context,
                PdfPreviewScreen(
                  title: 'SF5',
                  archive: ArchiveInfo(cls, 'sf5'),
                  fileName: 'SF5 ${cls.title}.pdf',
                  build: () async => buildSf5Pdf(await buildSf5Data(store.repo, store.profile, cls, await loadAreas(cls))),
                ),
              );
            }),
            _tile(context, Icons.table_chart_outlined, 'SF5 in Excel', 'The same report as an Excel file', () => _sf5Excel(context)),
          ],
          const SectionTitle('Grades'),
          _tile(context, Icons.table_view_outlined, 'Class record (Excel)', '${st.activities} activities, with PS, WS, initial and term grades', () async {
            await withProgress(context, 'Making the class record...', () async {
              final d = await loadRecord(cls);
              await shareAndArchive(ArchiveInfo(cls, 'record'), buildClassRecordXlsx(store.profile, d.engine.cls, d.learners, d.engine), 'Class Record ${cls.subject} ${cls.title}.xlsx', xlsxMime);
            });
          }),
          _tile(context, Icons.summarize_outlined, 'Summary of grades (PDF)', 'Term grades, final grade, descriptor and remarks', () async {
            push(
              context,
              PdfPreviewScreen(
                title: 'Summary of grades',
                archive: ArchiveInfo(cls, 'grades'),
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
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) =>
      NavRow(icon: icon, title: title, subtitle: subtitle, onTap: onTap, color: brandBlue);
}
