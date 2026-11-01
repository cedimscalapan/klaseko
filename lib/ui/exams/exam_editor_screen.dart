import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/omr/sheet_layout.dart';
import '../theme.dart';
import '../widgets.dart';

/// Edit the questions and the answer key. The answer key alone is enough for checking papers;
/// questions and choices are only needed to print the test paper.
class ExamEditorScreen extends StatefulWidget {
  const ExamEditorScreen({super.key, required this.exam});
  final Exam exam;

  @override
  State<ExamEditorScreen> createState() => _ExamEditorScreenState();
}

class _ExamEditorScreenState extends State<ExamEditorScreen> {
  List<ExamItem> _items = [];
  bool _loading = true;
  bool _dirty = false;
  bool _keyOnly = false;

  @override
  void initState() {
    super.initState();
    store.repo.items(widget.exam.id).then((list) {
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _keyOnly = list.isNotEmpty && list.every((i) => i.question.trim().isEmpty);
      });
    });
  }

  ExamItem _blank() => ExamItem(id: newId(), examId: widget.exam.id, idx: _items.length);

  void _add([int count = 1]) {
    if (_items.length + count > SheetLayout.maxItems) {
      toast(context, 'An answer sheet holds up to ${SheetLayout.maxItems} items.');
      count = SheetLayout.maxItems - _items.length;
      if (count <= 0) return;
    }
    setState(() {
      for (var i = 0; i < count; i++) {
        _items.add(_blank());
      }
      _dirty = true;
    });
  }

  Future<bool> _save() async {
    await store.repo.saveItems(widget.exam.id, _items);
    store.changed();
    _dirty = false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (_dirty) await _save();
        nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${_items.length} items'),
          actions: [
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                await _save();
                if (mounted) toast(context, 'Saved. Checked papers were re-scored.');
                nav.pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _add(),
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
                AppCard(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _keyOnly,
                    onChanged: (v) => setState(() => _keyOnly = v),
                    title: const Text('Answer key only', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Turn on if your test is already printed. Just tap the correct letter for each item.'),
                  ),
                ),
                const SizedBox(height: 8),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      const Text('How many items?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                        for (final n in [10, 15, 20, 25, 30, 40, 50, 60]) OutlinedButton(onPressed: () => _add(n), child: Text('$n')),
                      ]),
                    ]),
                  ),
                if (_keyOnly) _keyGrid() else for (var i = 0; i < _items.length; i++) _itemCard(i),
              ]),
      ),
    );
  }

  Widget _keyGrid() => AppCard(
        child: Column(children: [
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 36, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800))),
                for (var c = 0; c < 4; c++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _Bubble(
                      letter: 'ABCD'[c],
                      selected: _items[i].answer == c,
                      onTap: () => setState(() {
                        _items[i].answer = c;
                        _items[i].type = 'mc';
                        _dirty = true;
                      }),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    _items.removeAt(i);
                    _dirty = true;
                  }),
                ),
              ]),
            ),
        ]),
      );

  Widget _itemCard(int i) {
    final it = _items[i];
    return Padding(
      key: ValueKey(it.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('Item ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            PopupMenuButton<String>(
              onSelected: (v) => setState(() {
                if (v == 'dup') {
                  _items.insert(i + 1, ExamItem(id: newId(), examId: it.examId, idx: i + 1, type: it.type, question: it.question, choices: [...it.choices], answer: it.answer, competency: it.competency));
                } else if (v == 'up' && i > 0) {
                  _items.insert(i - 1, _items.removeAt(i));
                } else if (v == 'down' && i < _items.length - 1) {
                  _items.insert(i + 1, _items.removeAt(i));
                } else if (v == 'delete') {
                  _items.removeAt(i);
                }
                _dirty = true;
              }),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'up', child: Text('Move up')),
                PopupMenuItem(value: 'down', child: Text('Move down')),
                PopupMenuItem(value: 'dup', child: Text('Duplicate')),
                PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: penRed))),
              ],
            ),
          ]),
          Wrap(spacing: 6, children: [
            ChoiceChip(
              label: const Text('Multiple choice'),
              selected: it.type == 'mc',
              onSelected: (_) => setState(() {
                it.type = 'mc';
                _dirty = true;
              }),
            ),
            ChoiceChip(
              label: const Text('True/False'),
              selected: it.type == 'tf',
              onSelected: (_) => setState(() {
                it.type = 'tf';
                if (it.answer > 1) it.answer = 0;
                _dirty = true;
              }),
            ),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: it.question,
            minLines: 1,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Question'),
            onChanged: (v) {
              it.question = v;
              _dirty = true;
            },
          ),
          const SizedBox(height: 8),
          for (var c = 0; c < it.choiceCount; c++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                _Bubble(
                  letter: 'ABCD'[c],
                  selected: it.answer == c,
                  onTap: () => setState(() {
                    it.answer = c;
                    _dirty = true;
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: it.type == 'tf'
                      ? Text(c == 0 ? 'True' : 'False', style: const TextStyle(fontSize: 16))
                      : TextFormField(
                          initialValue: it.choices[c],
                          decoration: InputDecoration(isDense: true, hintText: 'Choice ${'ABCD'[c]}'),
                          onChanged: (v) {
                            it.choices[c] = v;
                            _dirty = true;
                          },
                        ),
                ),
              ]),
            ),
          Text('Tap a letter to mark the correct answer.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: it.competency,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(isDense: true, labelText: 'Competency (for item analysis)', hintText: 'e.g. Slope of a line'),
            onChanged: (v) {
              it.competency = v;
              _dirty = true;
            },
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.letter, required this.selected, required this.onTap});
  final String letter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? goodGreen : Colors.transparent,
            border: Border.all(color: selected ? goodGreen : Theme.of(context).colorScheme.outline, width: 1.5),
          ),
          child: Text(letter, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}
