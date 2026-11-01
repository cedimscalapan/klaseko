import 'package:flutter_test/flutter_test.dart';
import 'package:klaseko/core/analysis.dart';
import 'package:klaseko/core/grading.dart';
import 'package:klaseko/core/models.dart';

SchoolClass _cls({String preset = 'core'}) {
  final p = presetById(preset);
  return SchoolClass(
    id: 'c',
    sy: '2026-2027',
    grade: 'Grade 8',
    section: 'A',
    subject: 'Mathematics',
    preset: preset,
    ww: p.ww,
    pt: p.pt,
    ex: p.ex,
    exSplit: p.exSplit,
    transmute: p.transmute,
    mode: 'numeric',
    advisory: false,
    created: 0,
  );
}

Activity _a(String id, String comp, double hps, {String sub = ''}) =>
    Activity(id: id, classId: 'c', term: 1, comp: comp, sub: sub, title: id, hps: hps, created: 0);

void main() {
  group('Transmutation, SY 2026-2027 table (DO 015, s. 2026)', () {
    test('boundaries', () {
      expect(transmute(100, 'table2026'), 100);
      expect(transmute(99.50, 'table2026'), 100);
      expect(transmute(99.49, 'table2026'), 99);
      expect(transmute(70.00, 'table2026'), 75);
      expect(transmute(69.99, 'table2026'), 74);
      expect(transmute(4.68, 'table2026'), 61);
      expect(transmute(0, 'table2026'), 60);
    });
    test('DO 8, s. 2015 formula', () {
      expect(transmute(100, 'do8'), 100);
      expect(transmute(98.40, 'do8'), 99);
      expect(transmute(60, 'do8'), 75);
      expect(transmute(59.99, 'do8'), 74);
    });
    test('zero-based keeps a minimum of 60', () {
      expect(transmute(45, 'none'), 60);
      expect(transmute(88.5, 'none'), 89);
    });
  });

  test('descriptors', () {
    expect(descriptor(92), 'Advancing');
    expect(descriptor(80), 'Benchmarking');
    expect(descriptor(75), 'Connecting');
    expect(descriptor(70), 'Developing');
    expect(descriptor(60), 'Emerging');
    expect(descriptor(86, legacy: true), 'Very Satisfactory');
  });

  test('term grade with the exam split 30/30/40', () {
    final acts = [
      _a('ww1', 'ww', 20),
      _a('pt1', 'pt', 50),
      _a('st1', 'ex', 30, sub: 'st1'),
      _a('st2', 'ex', 30, sub: 'st2'),
      _a('te', 'ex', 50, sub: 'te'),
    ];
    final scores = {
      'ww1': {'L': 16.0}, // 80%
      'pt1': {'L': 45.0}, // 90%
      'st1': {'L': 21.0}, // 70%
      'st2': {'L': 24.0}, // 80%
      'te': {'L': 30.0}, // 60%
    };
    final r = GradeEngine(_cls(), acts, scores).term('L', 1);
    // EX = .3*70 + .3*80 + .4*60 = 69; IG = .2*80 + .5*90 + .3*69 = 81.70
    expect(r.comps['ex']!.ps, closeTo(69, 1e-9));
    expect(r.initialGrade, closeTo(81.70, 1e-9));
    expect(r.termGrade, 84); // 80.62-81.79 transmutes to 84
    expect(r.incomplete, isFalse);
  });

  test('running grade leaves out empty components', () {
    final r = GradeEngine(_cls(), [_a('ww1', 'ww', 10)], {'ww1': {'L': 10.0}}).term('L', 1);
    expect(r.initialGrade, 100);
    expect(r.incomplete, isTrue);
  });

  test('promotion and honors', () {
    expect(promotionStatus([80, 85, 90]), 'Promoted');
    expect(promotionStatus([74, 80, 72]), 'For Summer Remedial Class');
    expect(promotionStatus([70, 71, 72, 90]), 'Retained');
    expect(generalAverage([90, 91, 92]), 91);
    expect(withHonors([95, 79, 96]), isFalse);
    expect(withHonors([90, 91, 92]), isTrue);
  });

  test('item analysis and MPS', () {
    final items = [
      ExamItem(id: '1', examId: 'e', idx: 0, answer: 0),
      ExamItem(id: '2', examId: 'e', idx: 1, answer: 1),
    ];
    final responses = [
      ExamResponse(examId: 'e', learnerId: 'a', answers: [0, 1], score: 2, source: 'manual', updated: 0),
      ExamResponse(examId: 'e', learnerId: 'b', answers: [0, 2], score: 1, source: 'manual', updated: 0),
      ExamResponse(examId: 'e', learnerId: 'c', answers: [3, 2], score: 0, source: 'manual', updated: 0),
      ExamResponse(examId: 'e', learnerId: 'd', answers: [0, 1], score: 2, source: 'manual', updated: 0),
    ];
    final s = analyzeExam(items, responses);
    expect(s.mps, closeTo(62.5, 1e-9));
    expect(s.items[0].correct, 3);
    expect(s.items[1].counts, [0, 2, 2, 0]);
    expect(masteryLevelOf(s.mps), 'Average');
  });
}
