import 'package:flutter/material.dart';

import '../../core/analysis.dart';
import '../../core/export/pdf_docs.dart';
import '../../core/models.dart';
import '../pdf_preview_screen.dart';
import '../../core/omr/sheet_layout.dart';
import '../scan/scan_roster_screen.dart';
import '../scan/manual_check_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import '../forms/archive_info.dart';
import 'exam_editor_screen.dart';
import 'exams_screen.dart';
import 'import_quiz_screen.dart';
import 'item_analysis_screen.dart';

class ExamBundle {
  final Exam exam;
  final SchoolClass cls;
  final List<ExamItem> items;
  final Map<String, ExamResponse> responses;
  final List<Learner> learners;
  ExamBundle(this.exam, this.cls, this.items, this.responses, this.learners);

  List<Learner> get unchecked => learners.where((l) => !responses.containsKey(l.id)).toList();
}

Future<ExamBundle?> loadExamBundle(String examId) async {
  final repo = store.repo;
  final e = await repo.examById(examId);
  if (e == null) return null;
  final cls = await repo.classById(e.classId);
  if (cls == null) return null;
  return ExamBundle(e, cls, await repo.items(examId), await repo.responses(examId), (await repo.learners(cls.id)).where((l) => l.isActive).toList());
}

class ExamDetailScreen extends StatefulWidget {
  const ExamDetailScreen({super.key, required this.examId, this.openEditor = false});
  final String examId;
  final bool openEditor;

  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.openEditor) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final b = await loadExamBundle(widget.examId);
        if (b != null && mounted) push(context, ExamEditorScreen(exam: b.exam));
      });
    }
  }

  Future<void> _import(ExamBundle b) async {
    final added = await push<List<ExamItem>>(context, ImportQuizScreen(exam: b.exam, existingCount: b.items.length));
    if (added == null || added.isEmpty) return;
    await store.repo.saveItems(b.exam.id, [...b.items, ...added]);
    store.changed();
    if (mounted) toast(context, 'Added ${added.length} items to ${b.exam.title}.', success: true);
  }

  void _printMenu(ExamBundle b) {
    void open(BuildContext ctx, VoidCallback action) {
      Navigator.pop(ctx);
      action();
    }

    final fits = b.items.length <= BoxLayout.quarter.maxItems;
    var quarter = fits && store.profile.sheetSize == 'quarter';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(value: false, label: Text('Full page')),
                ButtonSegment(value: true, label: const Text('1/4 page'), enabled: fits),
              ],
              selected: {quarter},
              onSelectionChanged: (s) {
                setSheet(() => quarter = s.first);
                final p = SchoolProfile.fromSettings(store.profile.toSettings())..sheetSize = s.first ? 'quarter' : 'full';
                store.saveProfile(p);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
            child: Text(
              fits ? (quarter ? 'Four answer sheets on each page, to cut along the lines. Saves paper.' : 'One answer sheet on each page.') : 'A 1/4 sheet holds up to ${BoxLayout.quarter.maxItems} items, so this exam needs full pages.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Test paper'),
            subtitle: const Text('The questions for learners'),
            onTap: () => open(ctx, () => _printTest(b)),
          ),
          if (b.learners.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Answer sheets with names'),
              subtitle: Text('${b.learners.length} sheets, names and learner numbers filled in. Fastest to scan.'),
              onTap: () => open(ctx, () => _openSheets(b, [for (final l in b.learners) SheetTarget(l)], quarter)),
            ),
          ListTile(
            leading: const Icon(Icons.note_outlined),
            title: const Text('Blank answer sheets'),
            subtitle: const Text('Learners write their name and shade their number.'),
            onTap: () => open(ctx, () => _openSheets(b, List.filled(b.learners.isEmpty ? 1 : b.learners.length, const SheetTarget(null)), quarter)),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Answer key'),
            subtitle: const Text('For your file'),
            onTap: () => open(ctx, () => _printTest(b, key: true)),
          ),
          const SizedBox(height: 8),
        ]),
      )),
    );
  }

  void _openSheets(ExamBundle b, List<SheetTarget> targets, bool quarter) {
    if (b.items.isEmpty) {
      toast(context, 'Add the answer key first so the sheet has the right number of items.');
      return;
    }
    push(
      context,
      PdfPreviewScreen(
        title: 'Answer sheets',
        archive: ArchiveInfo(b.cls, 'sheets', term: b.exam.term),
        fileName: 'Answer sheets ${b.exam.title}.pdf',
        build: () => buildAnswerSheets(profile: store.profile, cls: b.cls, exam: b.exam, itemCount: b.items.length, targets: targets, quarter: quarter),
      ),
    );
  }

  void _printTest(ExamBundle b, {bool key = false}) {
    if (b.items.isEmpty) {
      toast(context, 'This exam has no items yet.');
      return;
    }
    if (!key && b.items.every((i) => i.question.trim().isEmpty)) {
      toast(context, 'This exam only has an answer key. Add questions to print a test paper.');
      return;
    }
    push(
      context,
      PdfPreviewScreen(
        title: key ? 'Answer key' : 'Test paper',
        archive: ArchiveInfo(b.cls, 'test', term: b.exam.term),
        fileName: '${b.exam.title}${key ? ' answer key' : ''}.pdf',
        build: () => buildTestPaper(profile: store.profile, cls: b.cls, exam: b.exam, items: b.items, answerKey: key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Loader<ExamBundle?>(
      load: () => loadExamBundle(widget.examId),
      builder: (context, b) {
        if (b == null) return const Scaffold(body: Center(child: Text('This exam was deleted.')));
        final stats = b.items.isEmpty ? null : analyzeExam(b.items, b.responses.values.toList());
        final ready = b.items.isNotEmpty;
        return Scaffold(
          appBar: AppBar(
            title: Text(b.exam.title),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'details') {
                    showNewExamSheet(context, b.cls, existing: b.exam);
                  } else if (v == 'delete') {
                    final ok = await confirm(context, title: 'Delete this exam?', message: 'The items, checked papers and its column in the class record will be removed.');
                    if (ok) {
                      await store.repo.deleteExam(b.exam.id);
                      store.changed();
                      if (context.mounted) Navigator.pop(context);
                    }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'details', child: Text('Title, term and type')),
                  PopupMenuItem(value: 'delete', child: Text('Delete exam', style: TextStyle(color: penRed))),
                ],
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            AppCard(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${b.cls.subject} · ${b.cls.title}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                        '${store.profile.termName(b.exam.term)} · ${b.exam.comp == 'ex' && b.exam.sub.isNotEmpty ? exSubLabels[b.exam.sub] : compLabels[b.exam.comp]} · ${b.items.length} items',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text('${b.responses.length} of ${b.learners.length} papers checked', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
                if (stats != null && stats.n > 0)
                  Column(children: [
                    PenScore('${stats.mps.toStringAsFixed(1)}%', size: 26),
                    Text('MPS', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ]),
              ]),
            ),
            const SectionTitle('1 · Prepare'),
            _step(Icons.edit_note, ready ? 'Edit items and answer key' : 'Add items and answer key', ready ? '${b.items.length} items' : 'Type them, or enter just the answer key',
                () => push(context, ExamEditorScreen(exam: b.exam)),
                highlight: !ready),
            if (!ready) _step(Icons.file_download_outlined, 'Import questions', 'From a photo, Word, PDF or pasted text', () => _import(b), color: teal),
            if (ready) ...[
              _step(Icons.print_outlined, 'Print', 'Test paper, answer sheets and answer key', () => _printMenu(b)),
              const SectionTitle('2 · Check'),
              _step(Icons.document_scanner_outlined, 'Scan papers', b.unchecked.isEmpty ? 'All papers checked' : 'Tap a name, scan, and the score is recorded. ${b.unchecked.length} left.',
                  () => push(context, ScanRosterScreen(examId: b.exam.id)),
                  highlight: b.unchecked.isNotEmpty),
              _step(Icons.touch_app_outlined, 'Check by tapping', 'Enter answers by hand, without the camera', () => push(context, ManualCheckScreen(examId: b.exam.id))),
            ],
            if (stats != null && stats.n > 0) ...[
              const SectionTitle('3 · Results'),
              _step(Icons.insights_outlined, 'Results, MPS and item analysis', stats.masteryLevel, () => push(context, ItemAnalysisScreen(examId: b.exam.id))),
            ],
            if (b.responses.isNotEmpty) ...[
              const SectionTitle('Scores'),
              for (final l in b.learners)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  dense: true,
                  title: Text(l.fullName),
                  leading: Text(two(l.num), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  trailing: b.responses[l.id] == null
                      ? Pill('Not yet', color: lateAmber)
                      : PenScore('${b.responses[l.id]!.score}/${b.items.length}', size: 18),
                  onTap: ready ? () => push(context, ManualCheckScreen(examId: b.exam.id, learnerId: l.id)) : null,
                ),
            ],
          ]),
        );
      },
    );
  }

  Widget _step(IconData icon, String title, String subtitle, VoidCallback onTap, {bool highlight = false, Color? color}) =>
      NavRow(icon: icon, title: title, subtitle: subtitle, onTap: onTap, highlight: highlight, color: color);
}
