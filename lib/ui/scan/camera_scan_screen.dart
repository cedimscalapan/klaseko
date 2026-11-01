import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/omr/omr.dart';
import '../../core/omr/sheet_layout.dart';
import '../exams/exam_detail_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'answer_grid.dart';

/// Point the camera at a KlaseKo answer sheet, take the photo, review, save, repeat.
/// Reading happens on the phone in a background isolate; no internet is used.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key, required this.examId});
  final String examId;

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> with WidgetsBindingObserver {
  CameraController? _cam;
  ExamBundle? _b;
  String? _cameraError;
  bool _busy = false;
  bool _flash = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    _b = await loadExamBundle(widget.examId);
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'No camera found on this phone.');
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final cam = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await cam.initialize();
      await cam.setFlashMode(FlashMode.off);
      await cam.setFocusMode(FocusMode.auto);
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() => _cam = cam);
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _cameraError = e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt'
            ? 'Camera permission is off. Allow it in Settings > Apps > KlaseKo > Permissions, or pick photos from the gallery.'
            : (e.description ?? e.code));
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      setState(() => _cam = null);
      cam.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _process(Uint8List bytes) async {
    final b = _b;
    if (b == null) return;
    setState(() => _busy = true);
    final result = await compute(readAnswerSheet, OmrRequest(bytes, b.items.length));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      toast(context, result.error ?? 'Could not read the sheet.');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanReviewScreen(bundle: b, result: result)));
    _b = await loadExamBundle(widget.examId);
    if (mounted) setState(() {});
  }

  Future<void> _shoot() async {
    final cam = _cam;
    if (cam == null || _busy || cam.value.isTakingPicture) return;
    try {
      final file = await cam.takePicture();
      final bytes = await file.readAsBytes();
      // The photo is only needed for reading; remove it so learner papers are not kept on the phone.
      try {
        await File(file.path).delete();
      } catch (_) {}
      await _process(bytes);
    } on CameraException catch (e) {
      if (mounted) toast(context, 'Camera error: ${e.description ?? e.code}');
    }
  }

  Future<void> _gallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    await _process(await file.readAsBytes());
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    final checked = b == null ? 0 : b.responses.length;
    final total = b?.learners.length ?? 0;
    final cam = _cam;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(b == null ? 'Scan papers' : '${b.exam.title} · $checked/$total'),
        actions: [
          if (cam != null)
            IconButton(
              tooltip: 'Flash',
              icon: Icon(_flash ? Icons.flash_on : Icons.flash_off),
              onPressed: () async {
                _flash = !_flash;
                await cam.setFlashMode(_flash ? FlashMode.torch : FlashMode.off);
                setState(() {});
              },
            ),
        ],
      ),
      body: Stack(fit: StackFit.expand, children: [
        if (cam != null && cam.value.isInitialized)
          Center(child: CameraPreview(cam))
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_cameraError ?? 'Starting the camera...', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            ),
          ),
        // Sheet guide: the four corner squares should sit inside this frame.
        IgnorePointer(
          child: Center(
            child: AspectRatio(
              aspectRatio: (SheetLayout.frameW + 20) / (SheetLayout.frameH + 20),
              child: Container(
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 2), borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
            child: const Text(
              'Lay the sheet flat in good light. Fit all 4 black squares inside the frame, hold steady, then tap the button.',
              style: TextStyle(color: Colors.white, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        if (_busy)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 14),
                Text('Reading the answer sheet...', style: TextStyle(color: Colors.white)),
              ]),
            ),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(
              iconSize: 30,
              color: Colors.white,
              tooltip: 'Pick a photo',
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: _busy ? null : _gallery,
            ),
            GestureDetector(
              onTap: _shoot,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                padding: const EdgeInsets.all(5),
                child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: cam == null ? Colors.white24 : Colors.white)),
              ),
            ),
            const SizedBox(width: 48),
          ]),
        ),
      ),
    );
  }
}

/// Shows what the scanner read, lets the teacher fix anything, then saves the paper.
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({super.key, required this.bundle, required this.result});
  final ExamBundle bundle;
  final OmrResult result;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  late List<int> _answers;
  String? _lid;

  @override
  void initState() {
    super.initState();
    final b = widget.bundle;
    _answers = List.generate(b.items.length, (i) => i < widget.result.answers.length ? widget.result.answers[i] : ansBlank);
    final num = widget.result.learnerNum;
    final matches = num == null ? const <Learner>[] : b.learners.where((l) => l.num == num).toList();
    _lid = matches.isNotEmpty ? matches.first.id : (b.unchecked.length == 1 ? b.unchecked.first.id : null);
  }

  Future<void> _save() async {
    final b = widget.bundle;
    final lid = _lid;
    if (lid == null) {
      toast(context, 'Choose whose paper this is.');
      return;
    }
    if (b.responses.containsKey(lid)) {
      final name = b.learners.firstWhere((l) => l.id == lid).fullName;
      final ok = await confirm(context, title: 'Replace the saved paper?', message: '$name already has a checked paper for this exam.', action: 'Replace', danger: false);
      if (!ok) return;
    }
    final score = scoreAnswers(b.items, _answers);
    await store.repo.saveResponse(ExamResponse(examId: b.exam.id, learnerId: lid, answers: [..._answers], score: score, source: 'scan', updated: now()));
    store.changed();
    if (mounted) {
      toast(context, 'Saved $score/${b.items.length}. Scan the next paper.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bundle;
    final r = widget.result;
    final problems = _answers.where((a) => a < 0).length;
    final score = scoreAnswers(b.items, _answers);
    final numRead = r.learnerNum;
    final unmatched = numRead != null && !b.learners.any((l) => l.num == numRead);
    return Scaffold(
      appBar: AppBar(title: const Text('Check the result')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Retake'))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: FilledButton(onPressed: _save, child: Text('Save $score/${b.items.length}'))),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        AppCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(numRead == null ? 'Learner number not shaded' : 'Learner number read: ${two(numRead)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (unmatched) const Text('No learner has this number. Choose the learner below.', style: TextStyle(color: penRed)),
                Text(problems == 0 ? 'All items read clearly.' : '$problems item(s) blank or with two shades. Check the highlighted rows.',
                    style: TextStyle(color: problems == 0 ? goodGreen : lateAmber)),
              ]),
            ),
            PenScore('$score/${b.items.length}', size: 30),
          ]),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _lid,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Whose paper is this?'),
          items: [
            for (final l in b.learners)
              DropdownMenuItem(
                value: l.id,
                child: Text('${two(l.num)}  ${l.fullName}${b.responses.containsKey(l.id) ? '  (checked)' : ''}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _lid = v),
        ),
        const SizedBox(height: 12),
        AnswerGrid(items: b.items, answers: _answers, fills: r.fills, onChanged: (i, c) => setState(() => _answers[i] = c)),
        const SizedBox(height: 8),
        Text('Tap a bubble to correct a misread answer. Green rings are the answer key.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}
