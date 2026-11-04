import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../widgets.dart';

class _BankItem {
  final ExamItem item;
  final String source;
  final bool sameSubject;
  _BankItem(this.item, this.source, this.sameSubject);
}

/// Every question from past exams, ready to reuse. Same-subject questions come first.
/// Pops with copies of the chosen items, numbered from [startAt].
class QuestionBankScreen extends StatefulWidget {
  const QuestionBankScreen({super.key, required this.exam, required this.startAt, required this.room});
  final Exam exam;
  final int startAt;
  final int room;

  @override
  State<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends State<QuestionBankScreen> {
  List<_BankItem>? _all;
  final Set<String> _picked = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = store.repo;
    final classes = {for (final c in await repo.classes()) c.id: c};
    final subject = classes[widget.exam.classId]?.subject.trim().toLowerCase();
    final seen = <String>{};
    final out = <_BankItem>[];
    for (final e in await repo.exams()) {
      if (e.id == widget.exam.id) continue;
      final c = classes[e.classId];
      if (c == null) continue;
      for (final it in await repo.items(e.id)) {
        final text = it.question.trim();
        if (text.isEmpty || !seen.add(text.toLowerCase())) continue; // the same question is listed once
        out.add(_BankItem(it, '${c.subject} · ${e.title}', c.subject.trim().toLowerCase() == subject));
      }
    }
    out.sort((a, b) => (b.sameSubject ? 1 : 0).compareTo(a.sameSubject ? 1 : 0));
    if (mounted) setState(() => _all = out);
  }

  void _toggle(ExamItem it) {
    setState(() {
      if (!_picked.remove(it.id)) {
        if (_picked.length >= widget.room) {
          toast(context, 'The answer sheet has room for ${widget.room} more items.');
        } else {
          _picked.add(it.id);
        }
      }
    });
  }

  void _add() {
    final chosen = [for (final b in _all ?? const <_BankItem>[]) if (_picked.contains(b.item.id)) b.item];
    Navigator.pop(context, [
      for (var i = 0; i < chosen.length; i++)
        ExamItem(
          id: newId(),
          examId: widget.exam.id,
          idx: widget.startAt + i,
          type: chosen[i].type,
          question: chosen[i].question,
          choices: [...chosen[i].choices],
          answer: chosen[i].answer,
          competency: chosen[i].competency,
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final q = _query.trim().toLowerCase();
    final shown = all == null
        ? const <_BankItem>[]
        : all.where((b) => q.isEmpty || b.item.question.toLowerCase().contains(q) || b.item.competency.toLowerCase().contains(q) || b.source.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Question bank')),
      bottomNavigationBar: _picked.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: FilledButton(onPressed: _add, child: Text(_picked.length == 1 ? 'Add 1 question' : 'Add ${_picked.length} questions')),
              ),
            ),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
              ? const EmptyState(
                  icon: Icons.library_books_outlined,
                  title: 'No questions yet',
                  message: 'Questions from your exams are kept here automatically, ready to reuse in new tests.',
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                  TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search questions, competencies or exams'),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 10),
                  if (shown.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No matching questions.'))),
                  for (final b in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AppCard(
                        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                        child: CheckboxListTile(
                          contentPadding: const EdgeInsets.only(left: 4),
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _picked.contains(b.item.id),
                          onChanged: (_) => _toggle(b.item),
                          title: Text(b.item.question, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Answer ${letterOf(b.item.answer)} · ${b.source}'),
                        ),
                      ),
                    ),
                ]),
    );
  }
}
