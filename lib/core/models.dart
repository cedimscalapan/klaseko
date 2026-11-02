import 'dart:convert';

/// Grade components under DO 015, s. 2026: Written Work, Performance Tasks, Examinations.
const compLabels = {'ww': 'Written Work', 'pt': 'Performance Tasks', 'ex': 'Examinations'};
const compShort = {'ww': 'WW', 'pt': 'PT', 'ex': 'EX'};

/// Examination parts. Under DO 015, s. 2026 the EX weight is split ST1 30%, ST2 30%, Term Exam 40%.
const exSubLabels = {'st1': 'Summative Test 1', 'st2': 'Summative Test 2', 'te': 'Term Examination'};

class SchoolClass {
  final String id;
  String sy;
  String grade;
  String section;
  String subject;
  String preset;
  double ww;
  double pt;
  double ex;
  bool exSplit;

  /// 'table2026' (adjusted SY 2026-2027 table), 'do8' (DO 8, s. 2015 formula), 'none' (zero-based).
  String transmute;

  /// 'numeric' or 'descriptive' (Key Stage 1 letter grades).
  String mode;
  bool advisory;
  int created;
  bool archived;

  SchoolClass({
    required this.id,
    required this.sy,
    required this.grade,
    required this.section,
    required this.subject,
    required this.preset,
    required this.ww,
    required this.pt,
    required this.ex,
    required this.exSplit,
    required this.transmute,
    required this.mode,
    required this.advisory,
    required this.created,
    this.archived = false,
  });

  String get title => '$grade - $section';
  bool get legacyRules => preset.startsWith('do8');

  Map<String, Object?> toMap() => {
        'id': id,
        'sy': sy,
        'grade': grade,
        'section': section,
        'subject': subject,
        'preset': preset,
        'ww': ww,
        'pt': pt,
        'ex': ex,
        'ex_split': exSplit ? 1 : 0,
        'transmute': transmute,
        'mode': mode,
        'advisory': advisory ? 1 : 0,
        'created': created,
        'archived': archived ? 1 : 0,
      };

  factory SchoolClass.fromMap(Map<String, Object?> m) => SchoolClass(
        id: m['id'] as String,
        sy: (m['sy'] ?? '') as String,
        grade: (m['grade'] ?? '') as String,
        section: (m['section'] ?? '') as String,
        subject: (m['subject'] ?? '') as String,
        preset: (m['preset'] ?? 'core') as String,
        ww: (m['ww'] as num).toDouble(),
        pt: (m['pt'] as num).toDouble(),
        ex: (m['ex'] as num).toDouble(),
        exSplit: (m['ex_split'] ?? 1) == 1,
        transmute: (m['transmute'] ?? 'table2026') as String,
        mode: (m['mode'] ?? 'numeric') as String,
        advisory: (m['advisory'] ?? 0) == 1,
        created: (m['created'] ?? 0) as int,
        archived: (m['archived'] ?? 0) == 1,
      );
}

class Learner {
  final String id;
  final String classId;
  int num;
  String lrn;
  String last;
  String first;
  String middle;
  String sex; // 'M' or 'F'
  String birth; // yyyy-mm-dd
  String address;
  String guardian;
  String contact;
  String status; // active, dropped, transferred_out, transferred_in
  String remarks;

  Learner({
    required this.id,
    required this.classId,
    required this.num,
    this.lrn = '',
    required this.last,
    required this.first,
    this.middle = '',
    required this.sex,
    this.birth = '',
    this.address = '',
    this.guardian = '',
    this.contact = '',
    this.status = 'active',
    this.remarks = '',
  });

  String get fullName {
    final mi = middle.trim().isEmpty ? '' : ' ${middle.trim()[0].toUpperCase()}.';
    return '${last.trim()}, ${first.trim()}$mi';
  }

  String get sf1Name => '${last.trim()}, ${first.trim()}${middle.trim().isEmpty ? '' : ', ${middle.trim()}'}';

  bool get isActive => status == 'active' || status == 'transferred_in';

  Map<String, Object?> toMap() => {
        'id': id,
        'class_id': classId,
        'num': num,
        'lrn': lrn,
        'last': last,
        'first': first,
        'middle': middle,
        'sex': sex,
        'birth': birth,
        'address': address,
        'guardian': guardian,
        'contact': contact,
        'status': status,
        'remarks': remarks,
      };

  factory Learner.fromMap(Map<String, Object?> m) => Learner(
        id: m['id'] as String,
        classId: m['class_id'] as String,
        num: (m['num'] ?? 0) as int,
        lrn: (m['lrn'] ?? '') as String,
        last: (m['last'] ?? '') as String,
        first: (m['first'] ?? '') as String,
        middle: (m['middle'] ?? '') as String,
        sex: (m['sex'] ?? 'M') as String,
        birth: (m['birth'] ?? '') as String,
        address: (m['address'] ?? '') as String,
        guardian: (m['guardian'] ?? '') as String,
        contact: (m['contact'] ?? '') as String,
        status: (m['status'] ?? 'active') as String,
        remarks: (m['remarks'] ?? '') as String,
      );
}

/// Sorts learners the way DepEd forms list them: males first, then females, alphabetical.
List<Learner> sortForForms(Iterable<Learner> list) {
  final l = list.toList();
  l.sort((a, b) {
    if (a.sex != b.sex) return a.sex == 'M' ? -1 : 1;
    final c = a.last.toLowerCase().compareTo(b.last.toLowerCase());
    if (c != 0) return c;
    return a.first.toLowerCase().compareTo(b.first.toLowerCase());
  });
  return l;
}

class Activity {
  final String id;
  final String classId;
  int term;
  String comp; // ww, pt, ex
  String sub; // for ex: st1, st2, te
  String title;
  double hps;
  String day;
  String? examId;
  int created;

  Activity({
    required this.id,
    required this.classId,
    required this.term,
    required this.comp,
    this.sub = '',
    required this.title,
    required this.hps,
    this.day = '',
    this.examId,
    required this.created,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'class_id': classId,
        'term': term,
        'comp': comp,
        'sub': sub,
        'title': title,
        'hps': hps,
        'day': day,
        'exam_id': examId,
        'created': created,
      };

  factory Activity.fromMap(Map<String, Object?> m) => Activity(
        id: m['id'] as String,
        classId: m['class_id'] as String,
        term: (m['term'] ?? 1) as int,
        comp: (m['comp'] ?? 'ww') as String,
        sub: (m['sub'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        hps: (m['hps'] as num).toDouble(),
        day: (m['day'] ?? '') as String,
        examId: m['exam_id'] as String?,
        created: (m['created'] ?? 0) as int,
      );
}

class Exam {
  final String id;
  final String classId;
  int term;
  String comp;
  String sub;
  String title;
  String instructions;
  int created;

  Exam({
    required this.id,
    required this.classId,
    required this.term,
    required this.comp,
    this.sub = '',
    required this.title,
    this.instructions = '',
    required this.created,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'class_id': classId,
        'term': term,
        'comp': comp,
        'sub': sub,
        'title': title,
        'instructions': instructions,
        'created': created,
      };

  factory Exam.fromMap(Map<String, Object?> m) => Exam(
        id: m['id'] as String,
        classId: m['class_id'] as String,
        term: (m['term'] ?? 1) as int,
        comp: (m['comp'] ?? 'ex') as String,
        sub: (m['sub'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        instructions: (m['instructions'] ?? '') as String,
        created: (m['created'] ?? 0) as int,
      );
}

class ExamItem {
  final String id;
  final String examId;
  int idx;
  String type; // 'mc' (A-D) or 'tf' (A = True, B = False)
  String question;
  List<String> choices;
  int answer;
  String competency;

  ExamItem({
    required this.id,
    required this.examId,
    required this.idx,
    this.type = 'mc',
    this.question = '',
    List<String>? choices,
    this.answer = 0,
    this.competency = '',
  }) : choices = choices ?? ['', '', '', ''];

  int get choiceCount => type == 'tf' ? 2 : 4;

  Map<String, Object?> toMap() => {
        'id': id,
        'exam_id': examId,
        'idx': idx,
        'type': type,
        'question': question,
        'choices': jsonEncode(choices),
        'answer': answer,
        'competency': competency,
      };

  factory ExamItem.fromMap(Map<String, Object?> m) => ExamItem(
        id: m['id'] as String,
        examId: m['exam_id'] as String,
        idx: (m['idx'] ?? 0) as int,
        type: (m['type'] ?? 'mc') as String,
        question: (m['question'] ?? '') as String,
        choices: (jsonDecode((m['choices'] ?? '[]') as String) as List).map((e) => e.toString()).toList(),
        answer: (m['answer'] ?? 0) as int,
        competency: (m['competency'] ?? '') as String,
      );
}

/// Answer codes stored per item: 0..3 = A..D, -1 = blank, -2 = more than one shaded.
const ansBlank = -1;
const ansMulti = -2;

class ExamResponse {
  final String examId;
  final String learnerId;
  List<int> answers;
  int score;
  String source; // scan or manual
  int updated;

  ExamResponse({
    required this.examId,
    required this.learnerId,
    required this.answers,
    required this.score,
    required this.source,
    required this.updated,
  });

  Map<String, Object?> toMap() => {
        'exam_id': examId,
        'learner_id': learnerId,
        'answers': jsonEncode(answers),
        'score': score,
        'source': source,
        'updated': updated,
      };

  factory ExamResponse.fromMap(Map<String, Object?> m) => ExamResponse(
        examId: m['exam_id'] as String,
        learnerId: m['learner_id'] as String,
        answers: (jsonDecode((m['answers'] ?? '[]') as String) as List).map((e) => (e as num).toInt()).toList(),
        score: (m['score'] ?? 0) as int,
        source: (m['source'] ?? 'manual') as String,
        updated: (m['updated'] ?? 0) as int,
      );
}

int scoreAnswers(List<ExamItem> items, List<int> answers) {
  var s = 0;
  for (var i = 0; i < items.length; i++) {
    if (i < answers.length && answers[i] == items[i].answer) s++;
  }
  return s;
}

String letterOf(int code) => code >= 0 && code < 4 ? 'ABCD'[code] : (code == ansMulti ? '*' : '-');

/// School profile used on every DepEd form header.
class SchoolProfile {
  String teacher;
  String schoolName;
  String schoolId;
  String region;
  String division;
  String district;
  String schoolHead;
  String sy;
  int terms;
  String paper; // letter, long, a4
  String themeMode; // system, light, dark

  SchoolProfile({
    this.teacher = '',
    this.schoolName = '',
    this.schoolId = '',
    this.region = '',
    this.division = '',
    this.district = '',
    this.schoolHead = '',
    this.sy = '2026-2027',
    this.terms = 3,
    this.paper = 'letter',
    this.themeMode = 'system',
  });

  Map<String, String> toSettings() => {
        'teacher': teacher,
        'school_name': schoolName,
        'school_id': schoolId,
        'region': region,
        'division': division,
        'district': district,
        'school_head': schoolHead,
        'sy': sy,
        'terms': '$terms',
        'paper': paper,
        'theme_mode': themeMode,
      };

  factory SchoolProfile.fromSettings(Map<String, String> s) => SchoolProfile(
        teacher: s['teacher'] ?? '',
        schoolName: s['school_name'] ?? '',
        schoolId: s['school_id'] ?? '',
        region: s['region'] ?? '',
        division: s['division'] ?? '',
        district: s['district'] ?? '',
        schoolHead: s['school_head'] ?? '',
        sy: s['sy'] ?? '2026-2027',
        terms: int.tryParse(s['terms'] ?? '') ?? 3,
        paper: s['paper'] ?? 'letter',
        themeMode: s['theme_mode'] ?? 'system',
      );

  String termLabel(int t) => terms == 4 ? 'Q$t' : 'T$t';
  String termName(int t) => terms == 4 ? 'Quarter $t' : 'Term $t';
}
