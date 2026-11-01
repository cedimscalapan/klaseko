import 'dart:math';

import 'db.dart';
import 'export/form_data.dart';
import 'models.dart';

/// Creates a realistic sample class so a teacher can explore every feature before entering real data.
/// Names are fictional.
Future<void> createSampleClass(Repo repo, SchoolProfile profile) async {
  final r = Random(11);
  final cls = SchoolClass(
    id: newId(),
    sy: profile.sy,
    grade: 'Grade 8',
    section: 'Sampaguita (Sample)',
    subject: 'Mathematics',
    preset: 'core',
    ww: 20,
    pt: 50,
    ex: 30,
    exSplit: true,
    transmute: 'table2026',
    mode: 'numeric',
    advisory: true,
    created: now(),
  );
  await repo.saveClass(cls);

  const names = [
    ['Aquino', 'Mark Anthony', 'Reyes', 'M'], ['Bautista', 'Jericho', 'Lim', 'M'], ['Cruz', 'Paolo', 'Santos', 'M'],
    ['Dela Cruz', 'Juan Miguel', 'Ramos', 'M'], ['Garcia', 'Rafael', 'Torres', 'M'], ['Mendoza', 'Carlo', 'Villar', 'M'],
    ['Castillo', 'Angelica', 'Perez', 'F'], ['Flores', 'Princess Joy', 'Navarro', 'F'], ['Navarro', 'Kristine', 'Lopez', 'F'],
    ['Ramos', 'Andrea Mae', 'Cruz', 'F'], ['Santos', 'Maria Clara', 'Diaz', 'F'], ['Villanueva', 'Jasmine', 'Gomez', 'F'],
  ];
  const ability = [.86, .62, .72, .9, .5, .76, .95, .8, .66, .88, .93, .58];
  final learners = <Learner>[];
  for (var i = 0; i < names.length; i++) {
    final n = names[i];
    learners.add(Learner(
      id: newId(),
      classId: cls.id,
      num: i + 1,
      lrn: '1093451${(20031 + i * 377).toString().padLeft(5, '0')}',
      last: n[0],
      first: n[1],
      middle: n[2],
      sex: n[3],
      birth: '2012-${_two(1 + i % 12)}-${_two(3 + i * 2)}',
      address: 'Calapan City, Oriental Mindoro',
      guardian: '${n[2]}, Parent',
      contact: '0917${(1000000 + i * 4321).toString()}',
    ));
  }
  await repo.addLearners(cls.id, learners);
  final saved = await repo.learners(cls.id);

  // Attendance for October 2026
  for (final d in weekdaysOf(2026, 10)) {
    final day = <String, String>{};
    for (var i = 0; i < saved.length; i++) {
      final x = r.nextDouble();
      day[saved[i].id] = (saved[i].last == 'Garcia' && x < .25) ? 'A' : x < .04 ? 'A' : x < .1 ? 'L' : 'P';
    }
    await repo.setAttendance(cls.id, dayKey(d), day);
  }

  double abilityOf(Learner l) => ability[names.indexWhere((n) => n[0] == l.last && n[1] == l.first)];
  final acts = [
    Activity(id: newId(), classId: cls.id, term: 1, comp: 'ww', title: 'Quiz 1 - Factoring', hps: 20, created: now()),
    Activity(id: newId(), classId: cls.id, term: 1, comp: 'ww', title: 'Quiz 2 - Rational expressions', hps: 15, created: now() + 1),
    Activity(id: newId(), classId: cls.id, term: 1, comp: 'pt', title: 'Problem-solving task', hps: 50, created: now() + 2),
    Activity(id: newId(), classId: cls.id, term: 1, comp: 'pt', title: 'Group project', hps: 40, created: now() + 3),
    Activity(id: newId(), classId: cls.id, term: 1, comp: 'ex', sub: 'st1', title: 'Summative Test 1', hps: 30, created: now() + 4),
    Activity(id: newId(), classId: cls.id, term: 1, comp: 'ex', sub: 'st2', title: 'Summative Test 2', hps: 30, created: now() + 5),
  ];
  for (final a in acts) {
    await repo.saveActivity(a);
    final values = <String, double?>{};
    for (final l in saved) {
      final v = (a.hps * (abilityOf(l) + (r.nextDouble() - .5) * .22)).roundToDouble();
      values[l.id] = v.clamp(0, a.hps).toDouble();
    }
    await repo.setScores(a.id, values);
  }

  // Term examination with 10 items and checked papers
  final exam = Exam(id: newId(), classId: cls.id, term: 1, comp: 'ex', sub: 'te', title: 'Term 1 Examination', created: now() + 6);
  await repo.saveExam(exam);
  final items = <ExamItem>[
    _item(exam.id, 'Which of the following is a linear equation in two variables?', ['x^2 + y = 5', '2x + 3y = 6', 'xy = 4', 'y = 1/x'], 1, 'Linear equations in two variables'),
    _item(exam.id, 'What is the slope of the line through (1, 2) and (3, 8)?', ['2', '3', '4', '6'], 1, 'Slope of a line'),
    _item(exam.id, 'What is the slope of y = -4x + 7?', ['7', '4', '-4', '-7'], 2, 'Slope of a line'),
    _item(exam.id, 'What is the y-intercept of 2x + y = 10?', ['10', '2', '5', '-2'], 0, 'Intercepts and graphs'),
    _item(exam.id, 'What is the x-intercept of 3x - 6y = 12?', ['-2', '2', '4', '12'], 2, 'Intercepts and graphs'),
    _item(exam.id, 'Which ordered pair is a solution of x + y = 7?', ['(3, 5)', '(2, 4)', '(4, 3)', '(6, 2)'], 2, 'Linear equations in two variables'),
    _item(exam.id, 'Which set of ordered pairs is a function?', ['{(1,2), (1,3)}', '{(2,4), (3,4)}', '{(5,1), (5,2)}', '{(0,0), (0,1)}'], 1, 'Functions and relations'),
    _item(exam.id, 'If f(x) = 2x - 5, what is f(4)?', ['3', '13', '-3', '8'], 0, 'Functions and relations'),
    _item(exam.id, 'What is the solution of x + y = 10 and x - y = 2?', ['(4, 6)', '(6, 4)', '(8, 2)', '(5, 5)'], 1, 'Systems of linear equations'),
    _item(exam.id, 'Which system of equations has no solution?', ['y = 2x + 1 and y = 2x - 3', 'y = x and y = -x', 'y = 3x and y = x + 2', 'x + y = 2 and x - y = 0'], 0,
        'Systems of linear equations'),
  ];
  await repo.saveItems(exam.id, items);
  const ease = [.97, .82, .86, .84, .62, .9, .72, .8, .42, .36];
  for (final l in saved.take(saved.length - 1)) {
    final ans = <int>[];
    for (var k = 0; k < items.length; k++) {
      final p = min(.98, ease[k] * (abilityOf(l) / .76));
      ans.add(r.nextDouble() < p ? items[k].answer : (items[k].answer + 1 + r.nextInt(3)) % 4);
    }
    await repo.saveResponse(ExamResponse(examId: exam.id, learnerId: l.id, answers: ans, score: scoreAnswers(items, ans), source: 'manual', updated: now()));
  }
}

ExamItem _item(String examId, String q, List<String> c, int a, String comp) =>
    ExamItem(id: newId(), examId: examId, idx: 0, question: q, choices: c, answer: a, competency: comp);

String _two(int n) => n.toString().padLeft(2, '0');
