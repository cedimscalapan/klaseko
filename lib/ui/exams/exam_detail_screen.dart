import 'package:flutter/material.dart';

import '../../core/analysis.dart';
import '../../core/export/pdf_docs.dart';
import '../../core/models.dart';
import '../pdf_preview_screen.dart';
import '../scan/camera_scan_screen.dart';
import '../scan/manual_check_screen.dart';
import '../theme.dart';
import '../widgets.dart';
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

  void _printSheets(ExamBundle b) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('One sheet per learner'),
            subtitle: Text('${b.learners.length} sheets with names and learner numbers already filled in. Fastest to scan.'),
            onTap: () {
              Navigator.pop(ctx);
              _openSheets(b, [for (final l in b.learners) SheetTarget(l)]);
            },
          ),
          ListTile(
            leading: const Icon(Icons.note_outlined),
            title: const Text('Blank sheets'),
            subtitle: const Text('Learners write their name and shade their learner number.'),
            onTap: () {
              Navigator.pop(ctx);
              _openSheets(b, List.filled(b.learners.isEmpty ? 1 : b.learners.length, const SheetTarget(null)));
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _openSheets(ExamBundle b, List<SheetTarget> targets) {
    if (b.items.isEmpty) {
      toast(context, 'Add the answer key first so the sheet has the right number of items.');
      return;
    }
    push(
      context,
      PdfPreviewScreen(
        title: 'Answer sheets',
        fileName: 'Answer sheets ${b.exam.title}.pdf',
        build: () => buildAnswerSheets(profile: store.profile, cls: b.cls, exam: b.exam, itemCount: b.items.length, targets: targets),
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
            _step(Icons.edit_note, ready ? 'Edit items and answer key' : 'Add items and answer key', ready ? '${b.items.length} items' : 'Required before printing and checking',
                () => push(context, ExamEditorScreen(exam: b.exam)),
                highlight: !ready),
            _step(Icons.file_download_outlined, 'Import questions', 'From a photo, Word, PDF or pasted text', () => _import(b), color: teal),
            _step(Icons.article_outlined, 'Print test paper', 'PDF of the questions for learners', () => _printTest(b)),
            _step(Icons.grading_outlined, 'Print answer sheets', 'Bubble sheets that the camera can read', () => _printSheets(b)),
            _step(Icons.key_outlined, 'Print answer key', 'For your file', () => _printTest(b, key: true)),
            const SectionTitle('2 · Check'),
            _step(Icons.document_scanner_outlined, 'Scan papers with the camera', b.unchecked.isEmpty ? 'All papers checked' : '${b.unchecked.length} left to check',
                ready ? () => push(context, CameraScanScreen(examId: b.exam.id)) : () => toast(context, 'Add the answer key first.'),
                highlight: ready && b.unchecked.isNotEmpty),
            _step(Icons.touch_app_outlined, 'Check by tapping', 'Enter answers by hand, without the camera',
                ready ? () => push(context, ManualCheckScreen(examId: b.exam.id)) : () => toast(context, 'Add the answer key first.')),
            const SectionTitle('3 · Analyze'),
            _step(Icons.insights_outlined, 'Results, MPS and item analysis', stats == null || stats.n == 0 ? 'Available after checking papers' : stats.masteryLevel,
                () => push(context, ItemAnalysisScreen(examId: b.exam.id))),
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

  Widget _step(IconData icon, String title, String subtitle, VoidCallback onTap, {bool highlight = false, Color color = brandBlue}) =>
      NavRow(icon: icon, title: title, subtitle: subtitle, onTap: onTap, highlight: highlight, color: color);
}
