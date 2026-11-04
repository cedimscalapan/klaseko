import 'package:flutter/material.dart';

import '../../core/analysis.dart';
import '../../core/export/pdf_docs.dart';
import '../../core/export/share.dart';
import '../../core/export/xlsx_docs.dart';
import '../../core/models.dart';
import '../forms/archive_info.dart';
import '../pdf_preview_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'exam_detail_screen.dart';

class ItemAnalysisScreen extends StatelessWidget {
  const ItemAnalysisScreen({super.key, required this.examId});
  final String examId;

  @override
  Widget build(BuildContext context) {
    return Loader<ExamBundle?>(
      load: () => loadExamBundle(examId),
      builder: (context, b) {
        if (b == null) return const Scaffold(body: Center(child: Text('This exam was deleted.')));
        final checked = b.learners.where((l) => b.responses.containsKey(l.id)).map((l) => b.responses[l.id]!).toList();
        final s = analyzeExam(b.items, checked);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Results and item analysis'),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.ios_share),
                onSelected: (v) async {
                  if (v == 'pdf') {
                    push(
                      context,
                      PdfPreviewScreen(
                        title: 'Item analysis',
                        archive: ArchiveInfo(b.cls, 'analysis', term: b.exam.term),
                        fileName: 'Item analysis ${b.exam.title}.pdf',
                        build: () => buildItemAnalysisPdf(profile: store.profile, cls: b.cls, exam: b.exam, stats: s, enrolled: b.learners.length),
                      ),
                    );
                  } else {
                    await withProgress(context, 'Making the Excel file...', () async {
                      final bytes = buildItemAnalysisXlsx(store.profile, b.cls, b.exam, s, b.learners, b.responses, b.items);
                      await shareAndArchive(ArchiveInfo(b.cls, 'analysis', term: b.exam.term), bytes, 'Item analysis ${b.exam.title}.xlsx', xlsxMime);
                    });
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('MPS report (PDF)'))),
                  PopupMenuItem(value: 'xlsx', child: ListTile(leading: Icon(Icons.table_view_outlined), title: Text('Item analysis (Excel)'))),
                ],
              ),
            ],
          ),
          body: s.n == 0
              ? const EmptyState(icon: Icons.insights_outlined, title: 'No checked papers yet', message: 'Scan or check papers first. The analysis updates as you go.')
              : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.45,
                    children: [
                      StatTile(label: 'Mean percentage score', value: '${s.mps.toStringAsFixed(2)}%', sub: s.masteryLevel, pen: true),
                      StatTile(label: 'Learners tested', value: '${s.n}/${b.learners.length}', sub: '${s.k} items'),
                      StatTile(label: 'Mean score', value: s.mean.toStringAsFixed(2), sub: 'SD ${s.sd.toStringAsFixed(2)}'),
                      StatTile(label: 'Highest / lowest', value: '${s.highest} / ${s.lowest}', sub: 'out of ${s.k}'),
                    ],
                  ),
                  const SectionTitle('Least-mastered competencies'),
                  if (s.competencies.every((c) => c.percent >= 75))
                    const Text('Every competency reached 75% correct.')
                  else
                    for (final c in s.competencies.where((c) => c.percent < 75))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: AppCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text('Items ${c.items.map((i) => i + 1).join(', ')}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              ]),
                            ),
                            Pill('${c.percent.toStringAsFixed(0)}%', color: c.percent < 50 ? penRed : lateAmber),
                          ]),
                        ),
                      ),
                  const SectionTitle('Items'),
                  for (final it in s.items) _itemCard(context, it),
                  const SizedBox(height: 8),
                  Text(
                    'Difficulty = share of learners who got the item right. Discrimination compares the top and bottom 27% of scorers; 0.20 and up is acceptable. '
                    'Retain good items, revise or reject the rest before reusing the test.',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ]),
        );
      },
    );
  }

  Widget _itemCard(BuildContext context, ItemStat it) {
    final decisionColor = it.decision == 'Retain' ? goodGreen : it.decision == 'Revise' ? lateAmber : penRed;
    final top = it.topDistractor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${it.index + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(it.item.competency.isEmpty ? (it.item.question.isEmpty ? 'Item ${it.index + 1}' : it.item.question) : it.item.competency,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            Pill(it.decision, color: decisionColor),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: it.difficulty,
              minHeight: 8,
              color: it.percent < 50 ? penRed : brandBlue,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${it.correct}/${it.n} correct (${it.percent.toStringAsFixed(0)}%) · ${it.difficultyLabel} · discrimination ${it.discrimination.toStringAsFixed(2)} (${it.discriminationLabel})',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 10, children: [
            for (var c = 0; c < it.item.choiceCount; c++)
              Text('${'ABCD'[c]}: ${it.counts[c]}',
                  style: TextStyle(fontWeight: c == it.item.answer ? FontWeight.w800 : FontWeight.w400, color: c == it.item.answer ? goodGreen : null)),
            if (it.blanks > 0) Text('Blank: ${it.blanks}'),
          ]),
          if (top != null && it.counts[top] > it.correct)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('More learners chose ${'ABCD'[top]} than the correct answer. Check for a misconception or a wrong key.',
                  style: TextStyle(fontSize: 12, color: penRed)),
            ),
        ]),
      ),
    );
  }
}
