import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../exams/exam_detail_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'answer_grid.dart';

/// Check a paper by tapping the learner's answers. Also used to correct a scanned paper.
class ManualCheckScreen extends StatefulWidget {
  const ManualCheckScreen({super.key, required this.examId, this.learnerId});
  final String examId;
  final String? learnerId;

  @override
  State<ManualCheckScreen> createState() => _ManualCheckScreenState();
}

class _ManualCheckScreenState extends State<ManualCheckScreen> {
  ExamBundle? _b;
  String? _lid;
  List<int> _answers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await loadExamBundle(widget.examId);
    if (!mounted || b == null) return;
    setState(() {
      _b = b;
      _select(widget.learnerId ?? (b.unchecked.isNotEmpty ? b.unchecked.first.id : (b.learners.isEmpty ? null : b.learners.first.id)));
    });
  }

  void _select(String? id) {
    _lid = id;
    final b = _b!;
    final existing = id == null ? null : b.responses[id];
    _answers = List.generate(b.items.length, (i) => existing != null && i < existing.answers.length ? existing.answers[i] : ansBlank);
  }

  Future<void> _save({bool next = false}) async {
    final b = _b!;
    final lid = _lid;
    if (lid == null) return;
    final score = scoreAnswers(b.items, _answers);
    await store.repo.saveResponse(ExamResponse(examId: b.exam.id, learnerId: lid, answers: [..._answers], score: score, source: 'manual', updated: now()));
    store.changed();
    if (!mounted) return;
    toast(context, 'Saved: $score/${b.items.length}');
    final fresh = await loadExamBundle(widget.examId);
    if (!mounted || fresh == null) return;
    if (next && fresh.unchecked.isEmpty) {
      toast(context, 'All papers are checked.');
      Navigator.pop(context);
      return;
    }
    setState(() {
      _b = fresh;
      _select(next ? fresh.unchecked.first.id : lid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    if (b == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final score = scoreAnswers(b.items, _answers);
    final checked = _lid != null && b.responses.containsKey(_lid);
    return Scaffold(
      appBar: AppBar(title: const Text('Check by tapping')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: _lid == null ? null : () => _save(), child: const Text('Save'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: _lid == null ? null : () => _save(next: true), child: const Text('Save and next'))),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        DropdownButtonFormField<String>(
          value: _lid,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Learner'),
          items: [
            for (final l in b.learners)
              DropdownMenuItem(
                value: l.id,
                child: Text('${two(l.num)}  ${l.fullName}${b.responses.containsKey(l.id) ? '  (checked)' : ''}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _select(v)),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.exam.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(checked ? 'Already checked. Changes replace the saved paper.' : 'Not checked yet',
                    style: TextStyle(color: checked ? lateAmber : Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            PenScore('$score/${b.items.length}', size: 30),
          ]),
        ),
        const SizedBox(height: 12),
        AnswerGrid(items: b.items, answers: _answers, onChanged: (i, c) => setState(() => _answers[i] = c)),
        const SizedBox(height: 8),
        Text('Green rings mark the correct answers.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        if (checked)
          TextButton.icon(
            onPressed: () async {
              final ok = await confirm(context, title: 'Remove this checked paper?', message: 'The score is also removed from the class record.', action: 'Remove');
              if (!ok) return;
              await store.repo.deleteResponse(b.exam.id, _lid!);
              store.changed();
              _load();
            },
            icon: const Icon(Icons.delete_outline, color: penRed),
            label: const Text('Remove checked paper', style: TextStyle(color: penRed)),
          ),
      ]),
    );
  }
}
