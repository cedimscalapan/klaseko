import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/omr/omr.dart';
import '../../core/omr/sheet_layout.dart';
import '../exams/exam_detail_screen.dart';
import '../exams/item_analysis_screen.dart';
import 'manual_check_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import 'answer_grid.dart';

/// Point the camera at a KlaseKo answer sheet, take the photo, review, save, repeat.
/// Reading happens on the phone in a background isolate; no internet is used.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key, required this.examId, this.learnerId, this.inOrder = false});
  final String examId;

  /// Whose paper this is, when the teacher chose the name first. Otherwise the learner number decides.
  final String? learnerId;

  /// Goes down the class list: after each saved paper, the next learner without a score.
  final bool inOrder;

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> with WidgetsBindingObserver {
  CameraController? _cam;
  ExamBundle? _b;
  String? _cameraError;
  bool _busy = false;
  bool _flash = false;
  String? _lastError;
  String? _saved;
  String? _target;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _target = widget.learnerId;
    _init();
  }

  Future<void> _init() async {
    _b = await loadExamBundle(widget.examId);
    final unchecked = _b?.unchecked ?? const <Learner>[];
    if (widget.inOrder && unchecked.isNotEmpty) _target = unchecked.first.id;
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'No camera found on this phone.');
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final cam = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await cam.initialize();
      await cam.setFlashMode(FlashMode.off);
      try {
        await cam.setFocusMode(FocusMode.auto);
      } catch (_) {}
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
    setState(() {
      _busy = true;
      _lastError = null;
      _saved = null;
    });
    final result = await compute(readAnswerSheet, OmrRequest(bytes, b.items.length));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      HapticFeedback.heavyImpact();
      setState(() => _lastError = result.error ?? 'Could not read the sheet. Try again.');
      return;
    }
    HapticFeedback.mediumImpact();
    final target = _target;
    final byNumber = result.learnerNum == null ? const <Learner>[] : b.learners.where((l) => l.num == result.learnerNum).toList();
    final lid = target ?? (byNumber.isEmpty ? null : byNumber.first.id);
    final otherNumber = target != null && result.learnerNum != null && !byNumber.any((l) => l.id == target);
    final blanks = result.answers.where((a) => a == ansBlank).length;
    // A clear reading goes straight to the record. Anything the teacher should see first goes to the
    // result screen: unsure marks, a sheet numbered for someone else, a mostly blank sheet.
    final clear = lid != null && !otherNumber && result.review.isEmpty && !result.lightMarks && blanks * 2 <= result.answers.length && (target != null || !b.responses.containsKey(lid));
    if (lid != null && clear) {
      final answers = List.generate(b.items.length, (i) => i < result.answers.length ? result.answers[i] : ansBlank);
      final score = scoreAnswers(b.items, answers);
      await store.repo.saveResponse(ExamResponse(examId: b.exam.id, learnerId: lid, answers: answers, score: score, source: 'scan', updated: now()));
      store.changed();
      await _afterSaved(lid, score);
      return;
    }
    final saved = await push<(String, int)>(context, ScanReviewScreen(bundle: b, result: result, learnerId: target));
    if (saved != null) {
      await _afterSaved(saved.$1, saved.$2);
    } else {
      _b = await loadExamBundle(widget.examId);
      if (mounted) setState(() {});
    }
  }

  /// Tells the teacher the score is in the class record, then moves on.
  Future<void> _afterSaved(String learnerId, int score) async {
    final name = _b!.learners.firstWhere((l) => l.id == learnerId).fullName;
    final message = '$name: $score/${_b!.items.length} recorded';
    HapticFeedback.mediumImpact();
    _b = await loadExamBundle(widget.examId);
    if (!mounted) return;
    if (widget.learnerId != null) {
      toast(context, message, success: true);
      Navigator.pop(context);
      return;
    }
    if (widget.inOrder) {
      final left = _b?.unchecked ?? const <Learner>[];
      if (left.isEmpty) {
        toast(context, '$message. All papers are checked.', success: true);
        Navigator.pop(context);
        return;
      }
      _target = left.first.id;
    }
    setState(() => _saved = message);
  }

  void _skip() {
    final left = _b?.unchecked ?? const <Learner>[];
    if (left.isEmpty) return;
    final at = left.indexWhere((l) => l.id == _target);
    setState(() {
      _target = left[(at + 1) % left.length].id;
      _saved = null;
      _lastError = null;
    });
  }

  Future<void> _shoot() async {
    final cam = _cam;
    if (cam == null || _busy || cam.value.isTakingPicture) return;
    HapticFeedback.lightImpact();
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

  Future<void> _enterByHand() async {
    await push(context, ManualCheckScreen(examId: widget.examId, learnerId: _target));
    _b = await loadExamBundle(widget.examId);
    if (mounted) setState(() => _lastError = null);
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
    final hits = b == null ? const <Learner>[] : b.learners.where((l) => l.id == _target).toList();
    final targeted = hits.isEmpty ? null : hits.first;
    final layout = store.profile.sheetSize == 'quarter' && (b?.items.length ?? 0) <= BoxLayout.quarter.maxItems ? BoxLayout.quarter : BoxLayout.full;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(fontFamily: 'Lexend', fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        title: Text(targeted?.fullName ?? b?.exam.title ?? 'Scan papers'),
        actions: [
          if (widget.inOrder && (b?.unchecked.length ?? 0) > 1)
            TextButton(onPressed: _skip, style: TextButton.styleFrom(foregroundColor: Colors.white), child: const Text('Skip')),
          if (cam != null)
            IconButton(
              tooltip: 'Flashlight',
              icon: Icon(_flash ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded),
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
        if (b != null && cam != null && cam.value.isInitialized)
          IgnorePointer(
            child: CustomPaint(
              painter: _ScanGuide(
                (layout.right(b.items.length) + layout.marker) / (layout.bottom(b.items.length) - layout.top + layout.marker),
              ),
            ),
          ),
        Positioned(
          left: 16,
          right: 16,
          top: 10,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Container(
              key: ValueKey(_lastError),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _lastError != null ? const Color(0xE6B07400) : _saved != null ? const Color(0xE62B7348) : Colors.black.withAlpha(150),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Icon(_lastError != null ? Icons.refresh_rounded : _saved != null ? Icons.check_circle_rounded : Icons.lightbulb_outline_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _lastError ?? _saved ?? 'Fit the answer box inside the corners. It does not have to be exact, and any angle works.',
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
                  ),
                ),
                if (_lastError != null)
                  TextButton(
                    onPressed: _enterByHand,
                    style: TextButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(48, 40)),
                    child: const Text('Enter by hand', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
        ),
        if (_busy)
          Container(
            color: Colors.black.withAlpha(150),
            child: const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 46, height: 46, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
                SizedBox(height: 16),
                Text('Reading the answer sheet...', style: TextStyle(color: Colors.white, fontSize: 15)),
              ]),
            ),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (total > 0) ...[
              Row(children: [
                Text('$checked of $total checked', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (checked == total)
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ItemAnalysisScreen(examId: widget.examId))),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF7CDBA2), minimumSize: const Size(48, 36)),
                    child: const Text('All done · See results', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 8),
              SlimProgress(value: total == 0 ? 0 : checked / total, color: const Color(0xFF7CDBA2), height: 6),
              const SizedBox(height: 14),
            ],
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _roundButton(Icons.photo_library_rounded, 'Gallery', _busy ? null : _gallery),
              GestureDetector(
                onTap: _shoot,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                  padding: const EdgeInsets.all(5),
                  child: Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: cam == null ? Colors.white24 : Colors.white),
                    child: Icon(Icons.document_scanner_rounded, color: brandBlue, size: 30),
                  ),
                ),
              ),
              _roundButton(Icons.close_rounded, 'Done', () => Navigator.pop(context)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, String label, VoidCallback? onTap) => SizedBox(
        width: 64,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          IconButton.filledTonal(
            onPressed: onTap,
            style: IconButton.styleFrom(backgroundColor: Colors.white.withAlpha(30), foregroundColor: Colors.white, minimumSize: const Size(52, 52)),
            icon: Icon(icon),
          ),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
        ]),
      );
}

/// Corner brackets showing roughly where the answer box goes. They are only a guide: the scanner
/// finds the sheet by itself, at any angle.
class _ScanGuide extends CustomPainter {
  const _ScanGuide(this.aspect);
  final double aspect; // width / height

  @override
  void paint(Canvas canvas, Size size) {
    final maxW = size.width * 0.9, maxH = size.height * 0.76;
    final w = maxW / maxH > aspect ? maxH * aspect : maxW;
    final h = w / aspect;
    final r = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2 + size.height * 0.05), width: w, height: h);
    final paint = Paint()
      ..color = Colors.white.withAlpha(220)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    const len = 30.0;
    for (final (corner, dx, dy) in [(r.topLeft, 1.0, 1.0), (r.topRight, -1.0, 1.0), (r.bottomRight, -1.0, -1.0), (r.bottomLeft, 1.0, -1.0)]) {
      canvas.drawLine(corner, corner + Offset(dx * len, 0), paint);
      canvas.drawLine(corner, corner + Offset(0, dy * len), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanGuide old) => old.aspect != aspect;
}

/// Shows what the scanner read. Items the reader is unsure about must be confirmed or corrected
/// before saving, so an uncertain mark never becomes a score without the teacher seeing it.
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({super.key, required this.bundle, required this.result, this.learnerId});
  final ExamBundle bundle;
  final OmrResult result;

  /// The learner the teacher chose before scanning.
  final String? learnerId;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  late List<int> _answers;
  late Set<int> _toCheck;
  late bool _onlyToCheck;
  bool _comparedLight = false;
  String? _lid;

  @override
  void initState() {
    super.initState();
    final b = widget.bundle;
    _answers = List.generate(b.items.length, (i) => i < widget.result.answers.length ? widget.result.answers[i] : ansBlank);
    _toCheck = {...widget.result.review};
    _onlyToCheck = _toCheck.isNotEmpty;
    final num = widget.result.learnerNum;
    final matches = num == null ? const <Learner>[] : b.learners.where((l) => l.num == num).toList();
    _lid = widget.learnerId ?? (matches.isNotEmpty ? matches.first.id : (b.unchecked.length == 1 ? b.unchecked.first.id : null));
  }

  Future<void> _save() async {
    final b = widget.bundle;
    final lid = _lid;
    if (lid == null) {
      toast(context, 'Choose whose paper this is.');
      return;
    }
    if (_toCheck.isNotEmpty) {
      setState(() => _onlyToCheck = true);
      toast(context, 'Please check the ${_toCheck.length} highlighted item(s) first.');
      return;
    }
    if (widget.result.lightMarks && !_comparedLight) {
      toast(context, 'This paper was shaded lightly. Compare it with the answers below, then tick the box.');
      return;
    }
    if (b.responses.containsKey(lid) && widget.learnerId == null) {
      final name = b.learners.firstWhere((l) => l.id == lid).fullName;
      final ok = await confirm(context, title: 'Replace the saved paper?', message: '$name already has a checked paper for this exam.', action: 'Replace', danger: false);
      if (!ok) return;
    }
    final score = scoreAnswers(b.items, _answers);
    await store.repo.saveResponse(ExamResponse(examId: b.exam.id, learnerId: lid, answers: [..._answers], score: score, source: 'scan', updated: now()));
    store.changed();
    if (mounted) Navigator.pop(context, (lid, score));
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bundle;
    final r = widget.result;
    final score = scoreAnswers(b.items, _answers);
    final numRead = r.learnerNum;
    final unmatched = numRead != null && !b.learners.any((l) => l.num == numRead);
    final ready = _toCheck.isEmpty && _lid != null && (!r.lightMarks || _comparedLight);
    return Scaffold(
      appBar: AppBar(title: const Text('Check the result')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Retake'))),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _save,
                style: ready ? null : FilledButton.styleFrom(backgroundColor: lateAmber),
                icon: Icon(ready ? Icons.check_rounded : Icons.rule_rounded),
                label: Text(ready
                    ? 'Save $score/${b.items.length}'
                    : _lid == null
                        ? 'Choose learner'
                        : _toCheck.isNotEmpty
                            ? 'Check ${_toCheck.length} first'
                            : 'Compare first'),
              ),
            ),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        AppCard(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_lid == null ? 'Whose paper is this?' : b.learners.firstWhere((l) => l.id == _lid).fullName, style: Theme.of(context).textTheme.titleMedium),
                if (numRead != null && _lid != null && !unmatched && b.learners.firstWhere((l) => l.id == _lid).num != numRead)
                  Text('This sheet is shaded as learner no. ${two(numRead)}. Check that this is the right paper.', style: TextStyle(color: penRed, fontSize: 13)),
                if (unmatched) Text('No learner has number ${two(numRead ?? 0)}. Choose below.', style: TextStyle(color: penRed, fontSize: 13)),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(_toCheck.isEmpty ? Icons.verified_rounded : Icons.error_outline_rounded, size: 18, color: _toCheck.isEmpty ? goodGreen : lateAmber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_toCheck.isEmpty ? 'All items read clearly' : '${_toCheck.length} item(s) need your check',
                        style: TextStyle(fontWeight: FontWeight.w600, color: _toCheck.isEmpty ? goodGreen : lateAmber)),
                  ),
                ]),
              ]),
            ),
            PenScore('$score/${b.items.length}', size: 32),
          ]),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _lid,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Whose paper is this?', prefixIcon: Icon(Icons.person_outline_rounded)),
          items: [
            // Learners still waiting come first: that is usually whose paper this is.
            for (final l in [...b.unchecked, ...b.learners.where((l) => b.responses.containsKey(l.id))])
              DropdownMenuItem(
                value: l.id,
                child: Text('${two(l.num)}  ${l.fullName}${b.responses.containsKey(l.id) ? '  (checked)' : ''}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _lid = v),
        ),
        if (r.lightMarks) ...[
          const SizedBox(height: 14),
          AppCard(
            color: lateAmber.withAlpha(isDark(context) ? 46 : 24),
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: CheckboxListTile(
              value: _comparedLight,
              onChanged: (v) => setState(() => _comparedLight = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('I compared these answers with the paper', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('This learner shaded very lightly, so an erased mark can look like an answer. A quick look at the paper keeps the score right.'),
            ),
          ),
        ],
        if (widget.result.review.isNotEmpty) ...[
          const SizedBox(height: 14),
          AppCard(
            color: lateAmber.withAlpha(isDark(context) ? 46 : 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Please look at the paper for the highlighted items',
                  style: TextStyle(fontWeight: FontWeight.w700, color: lateAmber)),
              const SizedBox(height: 4),
              const Text(
                  'The mark was faint, erased, doubled or had a stray dot. Tap the correct bubble, or tap the check icon if it is already right.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Row(children: [
                if (_toCheck.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _toCheck.clear()),
                    icon: const Icon(Icons.done_all_rounded),
                    label: const Text('All look right'),
                  ),
                const Spacer(),
                FilterChip(
                  label: const Text('Only these'),
                  selected: _onlyToCheck,
                  onSelected: (v) => setState(() => _onlyToCheck = v),
                ),
              ]),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        AnswerGrid(
          items: b.items,
          answers: _answers,
          review: _toCheck,
          only: _onlyToCheck ? (widget.result.review.toList()..sort()) : null,
          onChanged: (i, c) => setState(() {
            _answers[i] = c;
            _toCheck.remove(i);
          }),
          onConfirm: (i) => setState(() => _toCheck.remove(i)),
        ),
        const SizedBox(height: 8),
        Text('Green rings mark the answer key. Tap any bubble to correct what was read.',
            style: TextStyle(fontSize: 12, color: mutedText(context))),
      ]),
    );
  }
}
