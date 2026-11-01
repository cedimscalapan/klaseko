import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../theme.dart';

/// One row per item: number, A-D bubbles, and a red check or cross like a teacher's pen.
/// Tapping a bubble changes the learner's answer (tap again to clear).
class AnswerGrid extends StatelessWidget {
  const AnswerGrid({super.key, required this.items, required this.answers, required this.onChanged, this.fills});
  final List<ExamItem> items;
  final List<int> answers;
  final void Function(int item, int code) onChanged;
  final List<List<double>>? fills;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      for (var i = 0; i < items.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: answers[i] == ansMulti || answers[i] == ansBlank ? lateAmber.withAlpha(22) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            SizedBox(width: 34, child: Text('${i + 1}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            for (var c = 0; c < items[i].choiceCount; c++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onChanged(i, answers[i] == c ? ansBlank : c),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: answers[i] == c ? scheme.onSurface : Colors.transparent,
                      border: Border.all(color: c == items[i].answer ? goodGreen : scheme.outline, width: c == items[i].answer ? 2.2 : 1.3),
                    ),
                    child: Text('ABCD'[c], style: TextStyle(fontWeight: FontWeight.w700, color: answers[i] == c ? scheme.surface : scheme.onSurfaceVariant)),
                  ),
                ),
              ),
            if (items[i].choiceCount == 2) const SizedBox(width: 96),
            const Spacer(),
            SizedBox(
              width: 64,
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
                  fontSize: answers[i] < 0 ? 13 : 22,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}
