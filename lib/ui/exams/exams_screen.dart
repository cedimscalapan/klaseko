import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../widgets.dart';
import 'exam_detail_screen.dart';

class _ExamRow {
  final Exam exam;
  final int items;
  final int checked;
  _ExamRow(this.exam, this.items, this.checked);
}

class ExamsScreen extends StatelessWidget {
  const ExamsScreen({super.key, required this.cls});
  final SchoolClass cls;

  Future<(List<_ExamRow>, int)> _load() async {
    final out = <_ExamRow>[];
    for (final e in await store.repo.exams(classId: cls.id)) {
      out.add(_ExamRow(e, (await store.repo.items(e.id)).length, (await store.repo.responses(e.id)).length));
    }
    final learners = (await store.repo.learners(cls.id)).where((l) => l.isActive).length;
    return (out, learners);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: ClassTitle('Exams and quizzes', cls)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showNewExamSheet(context, cls),
        icon: const Icon(Icons.add),
        label: const Text('New exam'),
      ),
      body: Loader<(List<_ExamRow>, int)>(
        load: _load,
        builder: (context, data) {
          final (rows, learners) = data;
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.quiz_outlined,
              title: 'No exams yet',
              message: 'Make a quiz or exam, print the test and answer sheets, then check the papers with your camera.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = rows[i];
              final e = r.exam;
              return AppCard(
                onTap: () => push(context, ExamDetailScreen(examId: e.id)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(
                        '${store.profile.termName(e.term)} · ${e.comp == 'ex' && e.sub.isNotEmpty ? exSubLabels[e.sub] : compLabels[e.comp]} · ${r.items} items',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    PenScore('${r.checked}/$learners', size: 20),
                    Text('checked', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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

Future<void> showNewExamSheet(BuildContext context, SchoolClass cls, {Exam? existing}) async {
  final title = TextEditingController(text: existing?.title ?? '');
  final instructions = TextEditingController(text: existing?.instructions ?? '');
  final acts = existing == null ? await store.repo.activities(cls.id) : const <Activity>[];
  if (!context.mounted) return;
  var term = existing?.term ?? min(latestTerm(acts), store.profile.terms);
  var comp = existing?.comp ?? 'ex';
  var sub = existing?.sub.isNotEmpty == true ? existing!.sub : 'te';
  // The title follows the choices below until the teacher types their own.
  var titleEdited = existing != null;
  String suggestedTitle() {
    final name = store.profile.termName(term);
    if (comp == 'ww') return 'Quiz ${acts.where((a) => a.term == term && a.comp == 'ww').length + 1}';
    return !cls.exSplit || sub == 'te' ? '$name Examination' : '$name ${exSubLabels[sub]}';
  }

  void retitle() {
    if (!titleEdited) title.text = suggestedTitle();
  }

  retitle();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(existing == null ? 'New exam or quiz' : 'Exam details', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Term 1 Examination'),
              onChanged: (_) => titleEdited = true,
            ),
            const SizedBox(height: 12),
            const Text('Term', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [for (var t = 1; t <= store.profile.terms; t++) ButtonSegment(value: t, label: Text(store.profile.termLabel(t)))],
              selected: {term},
              onSelectionChanged: (s) => setSheet(() {
                term = s.first;
                retitle();
              }),
            ),
            const SizedBox(height: 12),
            const Text('Counts in the class record as', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'ww', label: Text('Written Work')),
                ButtonSegment(value: 'ex', label: Text('Examination')),
              ],
              selected: {comp},
              onSelectionChanged: (s) => setSheet(() {
                comp = s.first;
                retitle();
              }),
            ),
            if (comp == 'ex' && cls.exSplit) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: sub,
                decoration: const InputDecoration(labelText: 'Examination part'),
                items: [for (final e in exSubLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setSheet(() {
                  sub = v!;
                  retitle();
                }),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: instructions,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Directions (optional)', hintText: 'Shown at the top of the test paper'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) {
                  toast(ctx, 'Enter a title.');
                  return;
                }
                final e = existing ?? Exam(id: newId(), classId: cls.id, term: term, comp: comp, title: '', created: now());
                e
                  ..title = title.text.trim()
                  ..term = term
                  ..comp = comp
                  ..sub = comp == 'ex' ? (cls.exSplit ? sub : 'te') : ''
                  ..instructions = instructions.text.trim();
                await store.repo.saveExam(e);
                store.changed();
                if (ctx.mounted) Navigator.pop(ctx);
                if (existing == null && context.mounted) push(context, ExamDetailScreen(examId: e.id, openEditor: true));
              },
              child: Text(existing == null ? 'Create and add items' : 'Save'),
            ),
          ]),
        ),
      ),
    ),
  );
}
