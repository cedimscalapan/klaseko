import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../exams/exam_detail_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'camera_scan_screen.dart';

class _HubRow {
  final Exam exam;
  final SchoolClass cls;
  final int items;
  final int checked;
  final int learners;
  _HubRow(this.exam, this.cls, this.items, this.checked, this.learners);
}

/// Every exam across all classes, unchecked papers first.
class CheckHubScreen extends StatelessWidget {
  const CheckHubScreen({super.key});

  Future<List<_HubRow>> _load() async {
    final repo = store.repo;
    final classes = {for (final c in await repo.classes()) c.id: c};
    final out = <_HubRow>[];
    for (final e in await repo.exams()) {
      final c = classes[e.classId];
      if (c == null) continue;
      final learners = (await repo.learners(c.id)).where((l) => l.isActive).length;
      out.add(_HubRow(e, c, (await repo.items(e.id)).length, (await repo.responses(e.id)).length, learners));
    }
    out.sort((a, b) => (b.learners - b.checked).compareTo(a.learners - a.checked));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check papers')),
      body: Loader<List<_HubRow>>(
        load: _load,
        builder: (context, rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.document_scanner_outlined,
              title: 'No exams yet',
              message: 'Open a class, go to Exams and quizzes, and make an exam. Print its answer sheets, then come back here to scan them.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = rows[i];
              final left = r.learners - r.checked;
              return AppCard(
                onTap: () => push(context, ExamDetailScreen(examId: r.exam.id)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.exam.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        Text('${r.cls.subject} · ${r.cls.title} · ${r.items} items', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ]),
                    ),
                    PenScore('${r.checked}/${r.learners}', size: 20),
                  ]),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: r.learners == 0 ? 0 : r.checked / r.learners, minHeight: 6),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    if (left > 0) Pill('$left left', color: lateAmber) else Pill('All checked', color: goodGreen),
                    const Spacer(),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(40, 40)),
                      onPressed: r.items == 0
                          ? () => toast(context, 'Add the answer key to this exam first.')
                          : () => push(context, CameraScanScreen(examId: r.exam.id)),
                      icon: const Icon(Icons.document_scanner_outlined, size: 18),
                      label: const Text('Scan'),
                    ),
                  ]),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
