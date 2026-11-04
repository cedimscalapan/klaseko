import 'package:flutter/material.dart';

import '../../core/plan.dart';
import '../exams/exam_detail_screen.dart';
import '../exams/item_analysis_screen.dart';
import '../settings/plan_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'camera_scan_screen.dart';
import 'manual_check_screen.dart';

/// The class list for one exam: tap a name, scan that learner's paper, and the score is recorded.
class ScanRosterScreen extends StatelessWidget {
  const ScanRosterScreen({super.key, required this.examId});
  final String examId;

  void _openChecked(BuildContext context, String learnerId, String name) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(name, style: Theme.of(ctx).textTheme.titleLarge)),
          ListTile(
            leading: const Icon(Icons.document_scanner_outlined),
            title: const Text('Scan again'),
            subtitle: const Text('The new scan replaces the saved score.'),
            onTap: () {
              Navigator.pop(ctx);
              push(context, CameraScanScreen(examId: examId, learnerId: learnerId));
            },
          ),
          ListTile(
            leading: const Icon(Icons.touch_app_outlined),
            title: const Text('See or change the answers'),
            onTap: () {
              Navigator.pop(ctx);
              push(context, ManualCheckScreen(examId: examId, learnerId: learnerId));
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Loader<ExamBundle?>(
      load: () => loadExamBundle(examId),
      builder: (context, b) {
        if (b == null) return const Scaffold(body: Center(child: Text('This exam was deleted.')));
        final left = b.unchecked;
        final done = b.responses.length;
        final total = b.learners.length;
        return Scaffold(
          appBar: AppBar(title: ClassTitle(b.exam.title, b.cls)),
          body: b.learners.isEmpty
              ? const EmptyState(icon: Icons.people_outline, title: 'No learners', message: 'Add learners to this class first.')
              : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('$done of $total papers checked', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      SlimProgress(value: total == 0 ? 0 : done / total, color: goodGreen),
                      const SizedBox(height: 12),
                      if (left.isNotEmpty)
                        FilledButton.icon(
                          onPressed: () => push(context, CameraScanScreen(examId: examId, inOrder: true)),
                          icon: const Icon(Icons.document_scanner_rounded),
                          label: Text('Scan next: ${left.first.fullName}', overflow: TextOverflow.ellipsis),
                        )
                      else
                        FilledButton.icon(
                          onPressed: () => push(context, ItemAnalysisScreen(examId: examId)),
                          icon: const Icon(Icons.insights_rounded),
                          label: const Text('See results'),
                        ),
                      TextButton(
                        onPressed: () => push(context, CameraScanScreen(examId: examId)),
                        child: const Text('Scan in any order, using the learner number'),
                      ),
                      Loader<PlanStatus>(
                        load: Plan.status,
                        builder: (context, st) => st.plus
                            ? const SizedBox()
                            : InkWell(
                                onTap: () => push(context, const PlanScreen()),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Text('Free plan: ${st.scansLeft} scans left this month', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: st.scansLeft <= 5 ? lateAmber : mutedText(context))),
                                ),
                              ),
                      ),
                    ]),
                  ),
                  const SectionTitle('Tap a name to scan'),
                  for (var i = 0; i < b.learners.length; i++) ...[
                    if (i == 0 || b.learners[i - 1].sex != b.learners[i].sex)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                        child: Text(b.learners[i].sex == 'M' ? 'Male' : 'Female', style: TextStyle(fontWeight: FontWeight.w700, color: mutedText(context))),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AppCard(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        onTap: () {
                          final l = b.learners[i];
                          if (b.responses.containsKey(l.id)) {
                            _openChecked(context, l.id, l.fullName);
                          } else {
                            push(context, CameraScanScreen(examId: examId, learnerId: l.id));
                          }
                        },
                        child: Row(children: [
                          SizedBox(width: 30, child: Text(two(b.learners[i].num), style: TextStyle(color: mutedText(context)))),
                          Expanded(child: Text(b.learners[i].fullName, style: const TextStyle(fontWeight: FontWeight.w600))),
                          if (b.responses[b.learners[i].id] != null)
                            PenScore('${b.responses[b.learners[i].id]!.score}/${b.items.length}', size: 20)
                          else
                            Icon(Icons.document_scanner_outlined, color: brandBlue),
                        ]),
                      ),
                    ),
                  ],
                ]),
        );
      },
    );
  }
}
