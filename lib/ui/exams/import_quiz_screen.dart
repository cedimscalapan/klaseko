import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/omr/sheet_layout.dart';
import '../../core/quiz_import/extract.dart';
import '../../core/quiz_import/quiz_parser.dart';
import '../theme.dart';
import '../widgets.dart';

/// Import questions from a photo of a printed quiz, a Word/PDF/text file, or pasted text.
/// Pops with the new items (List<ExamItem>) for the exam, or null when cancelled.
class ImportQuizScreen extends StatefulWidget {
  const ImportQuizScreen({super.key, required this.exam, required this.existingCount});
  final Exam exam;
  final int existingCount;

  @override
  State<ImportQuizScreen> createState() => _ImportQuizScreenState();
}

class _ImportQuizScreenState extends State<ImportQuizScreen> {
  final _text = TextEditingController();
  ParseResult? _result;
  bool _busy = false;
  String _status = '';
  String? _source;
  bool _showText = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(String source, Future<String> Function() extract) async {
    setState(() {
      _busy = true;
      _status = 'Reading...';
      _source = source;
    });
    try {
      final text = await extract();
      if (!mounted) return;
      _text.text = text;
      _parse();
      if ((_result?.items.isEmpty ?? true)) setState(() => _showText = true);
    } on FormatException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Could not read it: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _parse() {
    setState(() => _result = parseQuiz(_text.text));
  }

  Future<void> _photo(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 95, maxWidth: 3000);
    if (file == null) return;
    await _run(source == ImageSource.camera ? 'Photo' : 'Gallery', () async {
      final text = await QuizExtractor.fromImagePath(file.path);
      if (source == ImageSource.camera) {
        try {
          await File(file.path).delete();
        } catch (_) {}
      }
      return text;
    });
  }

  Future<void> _file() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const [...QuizExtractor.supported, 'doc'], withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) return;
    await _run(f.name, () => QuizExtractor.fromFile(f.name, bytes, progress: (s) {
          if (mounted) setState(() => _status = s);
        }));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    setState(() {
      _source = 'Pasted text';
      _showText = true;
      if ((data?.text ?? '').trim().isNotEmpty && _text.text.trim().isEmpty) _text.text = data!.text!;
    });
    if (_text.text.trim().isNotEmpty) _parse();
  }

  void _add() {
    final r = _result;
    if (r == null || r.items.isEmpty) return;
    final room = SheetLayout.maxItems - widget.existingCount;
    var items = r.items;
    if (items.length > room) {
      items = items.take(room).toList();
      toast(context, 'An answer sheet holds ${SheetLayout.maxItems} items, so only the first $room were added.');
    }
    final out = [
      for (var i = 0; i < items.length; i++)
        ExamItem(
          id: newId(),
          examId: widget.exam.id,
          idx: widget.existingCount + i,
          type: items[i].type,
          question: items[i].question,
          choices: items[i].choices,
          answer: items[i].answer ?? 0,
        ),
    ];
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final withAnswer = r?.items.where((i) => i.answer != null).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Import questions')),
      bottomNavigationBar: r == null || r.items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: FilledButton.icon(
                  onPressed: withAnswer == r.items.length ? _add : () => toast(context, 'Tap the correct letter for the items marked "No answer" first.'),
                  style: withAnswer == r.items.length ? null : FilledButton.styleFrom(backgroundColor: lateAmber),
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: Text(withAnswer == r.items.length ? 'Add ${r.items.length} items to the exam' : '${r.items.length - withAnswer} need an answer'),
                ),
              ),
            ),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
          if (r == null && !_showText) ...[
            Text('Bring in a quiz you already have. KlaseKo finds the questions, choices and answer key, then you check them.',
                style: TextStyle(color: mutedText(context))),
            const SizedBox(height: 14),
            NavRow(icon: Icons.photo_camera_rounded, title: 'Take a photo of a printed quiz', subtitle: 'One page at a time, flat and in good light', onTap: () => _photo(ImageSource.camera)),
            NavRow(icon: Icons.photo_library_rounded, title: 'Choose a photo', subtitle: 'From your gallery or a screenshot', color: violet, onTap: () => _photo(ImageSource.gallery)),
            NavRow(icon: Icons.description_rounded, title: 'Word, PDF or text file', subtitle: '.docx, .pdf, .txt', color: teal, onTap: _file),
            NavRow(icon: Icons.content_paste_rounded, title: 'Paste or type text', subtitle: 'From Messenger, email or anywhere', color: gold, onTap: _paste),
            const SizedBox(height: 10),
            AppCard(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                'Tips: number your questions (1., 2.) and label choices a, b, c, d. Put the answer key at the end ("Answer key: 1. B 2. C"), '
                'write "Answer: B" under a question, or make the correct choice bold in Word. Everything runs on your phone, without internet.',
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
            ),
          ] else ...[
            Row(children: [
              Expanded(child: Text(_source ?? 'Text', style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                onPressed: () => setState(() {
                  _result = null;
                  _showText = false;
                  _text.clear();
                }),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Start over'),
              ),
            ]),
            AppCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                initiallyExpanded: _showText,
                onExpansionChanged: (v) => setState(() => _showText = v),
                shape: const Border(),
                leading: const Icon(Icons.notes_rounded),
                title: const Text('Text found', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Fix any misread words here, then tap Find questions'),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  TextField(controller: _text, minLines: 6, maxLines: 18, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                  const SizedBox(height: 10),
                  FilledButton.icon(onPressed: _parse, icon: const Icon(Icons.auto_fix_high_rounded), label: const Text('Find questions')),
                ],
              ),
            ),
            if (r != null) ...[
              const SizedBox(height: 12),
              AppCard(
                child: Row(children: [
                  IconBadge(r.items.isEmpty ? Icons.search_off_rounded : Icons.fact_check_rounded, color: r.items.isEmpty ? lateAmber : goodGreen),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.items.isEmpty ? 'No questions found' : '${r.items.length} questions found', style: Theme.of(context).textTheme.titleMedium),
                      Text(r.items.isEmpty ? 'Check that questions are numbered and choices start with a, b, c, d.' : '$withAnswer with an answer',
                          style: TextStyle(color: mutedText(context), fontSize: 13)),
                    ]),
                  ),
                ]),
              ),
              for (final w in r.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: lateAmber),
                    const SizedBox(width: 8),
                    Expanded(child: Text(w, style: const TextStyle(fontSize: 13))),
                  ]),
                ),
              const SizedBox(height: 6),
              for (var i = 0; i < r.items.length; i++) _itemCard(r.items[i], i),
            ],
          ],
        ]),
        if (_busy)
          Container(
            color: Colors.black.withAlpha(90),
            child: Center(
              child: AppCard(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 16),
                  Text(_status),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _itemCard(ParsedItem it, int i) {
    final scheme = Theme.of(context).colorScheme;
    final count = it.type == 'tf' ? 2 : it.choices.where((c) => c.isNotEmpty).length.clamp(2, 4);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: AppCard(
        color: it.answer == null ? lateAmber.withAlpha(isDark(context) ? 40 : 20) : null,
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Expanded(child: Text(it.question.isEmpty ? '(no question text)' : it.question, style: const TextStyle(fontWeight: FontWeight.w600))),
            IconButton(
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _edit(it),
            ),
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => setState(() => _result!.items.removeAt(i)),
            ),
          ]),
          const SizedBox(height: 6),
          for (var c = 0; c < count; c++)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => it.answer = c),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: it.answer == c ? goodGreen : Colors.transparent,
                      border: Border.all(color: it.answer == c ? goodGreen : scheme.outline, width: 1.4),
                    ),
                    child: Text('ABCD'[c], style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: it.answer == c ? Colors.white : scheme.onSurfaceVariant)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(it.type == 'tf' ? (c == 0 ? 'True / Tama' : 'False / Mali') : it.choices[c])),
                ]),
              ),
            ),
          if (it.answer == null)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('No answer found. Tap the correct letter.', style: TextStyle(color: lateAmber, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }

  Future<void> _edit(ParsedItem it) async {
    final q = TextEditingController(text: it.question);
    final cs = [for (var c = 0; c < 4; c++) TextEditingController(text: it.choices[c])];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Edit question', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: q, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Question')),
            if (it.type == 'mc')
              for (var c = 0; c < 4; c++)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(controller: cs[c], decoration: InputDecoration(labelText: 'Choice ${'ABCD'[c]}')),
                ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                setState(() {
                  it.question = q.text.trim();
                  if (it.type == 'mc') it.choices = [for (final c in cs) c.text.trim()];
                });
                Navigator.pop(ctx);
              },
              child: const Text('Done'),
            ),
          ]),
        ),
      ),
    );
  }
}
