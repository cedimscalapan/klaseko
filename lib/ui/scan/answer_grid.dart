import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../theme.dart';

/// One row per item: number, A-D bubbles, and a red check or cross like a teacher's pen.
/// Tapping a bubble changes the learner's answer (tap again to clear).
/// Items in [review] are highlighted until the teacher taps a bubble or confirms them.
class AnswerGrid extends StatelessWidget {
  const AnswerGrid({
    super.key,
    required this.items,
    required this.answers,
    required this.onChanged,
    this.review = const {},
    this.onConfirm,
    this.only,
  });
  final List<ExamItem> items;
  final List<int> answers;
  final void Function(int item, int code) onChanged;
  final Set<int> review;
  final void Function(int item)? onConfirm;

  /// Show only these items (for the "items to check" view).
  final Iterable<int>? only;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final indexes = only?.toList() ?? List<int>.generate(items.length, (i) => i);
    return Column(children: [
      for (final i in indexes)
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          decoration: BoxDecoration(
            color: review.contains(i) ? lateAmber.withAlpha(isDark(context) ? 50 : 28) : null,
            borderRadius: BorderRadius.circular(14),
            border: review.contains(i) ? Border.all(color: lateAmber.withAlpha(120)) : null,
          ),
          child: Row(children: [
            SizedBox(width: 30, child: Text('${i + 1}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            for (var c = 0; c < items[i].choiceCount; c++)
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(i, answers[i] == c ? ansBlank : c);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: answers[i] == c ? scheme.onSurface : Colors.transparent,
                      border: Border.all(color: c == items[i].answer ? goodGreen : scheme.outline, width: c == items[i].answer ? 2.4 : 1.3),
                    ),
                    child: Text('ABCD'[c], style: TextStyle(fontWeight: FontWeight.w700, color: answers[i] == c ? scheme.surface : scheme.onSurfaceVariant)),
                  ),
                ),
              ),
            if (items[i].choiceCount == 2) const SizedBox(width: 94),
            const Spacer(),
            if (review.contains(i) && onConfirm != null)
              IconButton(
                tooltip: 'Looks right',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.check_circle_outline_rounded, color: lateAmber),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onConfirm!(i);
                },
              )
            else
              SizedBox(
                width: 48,
                child: Text(
                  answers[i] == ansMulti
                      ? 'Two?'
                      : answers[i] == ansBlank
                          ? 'Blank'
                          : answers[i] == items[i].answer
                              ? '✓'
                              : '✗',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: answers[i] < 0 ? lateAmber : penRed,
                    fontWeight: FontWeight.w800,
                    fontSize: answers[i] < 0 ? 12.5 : 22,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ]),
        ),
    ]);
  }
}
