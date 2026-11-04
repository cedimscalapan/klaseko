import '../db.dart';
import '../grading.dart';
import '../models.dart';

const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Monday to Friday of a month.
List<DateTime> weekdaysOf(int year, int month) {
  final out = <DateTime>[];
  for (var d = DateTime(year, month, 1); d.month == month; d = DateTime(d.year, d.month, d.day + 1)) {
    if (d.weekday <= DateTime.friday) out.add(d);
  }
  return out;
}

// ---------------------------------------------------------------------------
// SF2
// ---------------------------------------------------------------------------

class Sf2Row {
  final Learner learner;
  final List<String> marks; // per day: P, L, A or ''
  final int absent;
  final int tardy;
  final String remarks;
  Sf2Row(this.learner, this.marks, this.absent, this.tardy, this.remarks);
}

class SummaryRow {
  final String label;
  final String male;
  final String female;
  final String total;
  SummaryRow(this.label, this.male, this.female, this.total);
}

class Sf2Data {
  final SchoolProfile profile;
  final SchoolClass cls;
  final int year;
  final int month;
  final List<DateTime> days;
  final List<Sf2Row> rows;
  final int schoolDays;
  final List<SummaryRow> summary;

  Sf2Data(this.profile, this.cls, this.year, this.month, this.days, this.rows, this.schoolDays, this.summary);

  String get monthLabel => '${monthNames[month - 1]} $year';
  String weekdayLetter(DateTime d) => const ['M', 'T', 'W', 'TH', 'F', 'S', 'S'][d.weekday - 1];

  List<int> presentPerDay(String? sex) => [
        for (var i = 0; i < days.length; i++)
          rows.where((r) => (sex == null || r.learner.sex == sex) && (r.marks[i] == 'P' || r.marks[i] == 'L')).length,
      ];
}

Future<Sf2Data> buildSf2Data(Repo repo, SchoolProfile profile, SchoolClass cls, int year, int month) async {
  final learners = await repo.learners(cls.id);
  final days = weekdaysOf(year, month);
  final from = dayKey(days.first), to = dayKey(days.last);
  final att = await repo.attendance(cls.id, from: from, to: to);
  final schoolDayKeys = days.map(dayKey).where((k) => att[k]?.isNotEmpty ?? false).toSet();

  final rows = <Sf2Row>[];
  for (final l in learners) {
    final marks = <String>[];
    var absent = 0, tardy = 0, streak = 0, maxStreak = 0;
    for (final d in days) {
      final k = dayKey(d);
      final s = att[k]?[l.id] ?? '';
      marks.add(s);
      if (s == 'A') {
        absent++;
        streak++;
        if (streak > maxStreak) maxStreak = streak;
      } else if (schoolDayKeys.contains(k)) {
        streak = 0;
      }
      if (s == 'L') tardy++;
    }
    var remarks = l.remarks;
    if (l.status == 'dropped') remarks = 'DRP ${l.remarks}'.trim();
    if (l.status == 'transferred_out') remarks = 'T/O ${l.remarks}'.trim();
    if (l.status == 'transferred_in') remarks = 'T/I ${l.remarks}'.trim();
    if (maxStreak >= 5 && remarks.isEmpty) remarks = '5 consecutive absences';
    rows.add(Sf2Row(l, marks, absent, tardy, remarks));
  }

  final schoolDays = schoolDayKeys.length;
  String cnt(bool Function(Learner) f, String sex) => '${learners.where((l) => (sex == 'T' || l.sex == sex) && f(l)).length}';
  final registered = (Learner l) => l.status != 'dropped' && l.status != 'transferred_out';

  String ada(String sex) {
    if (schoolDays == 0) return '0';
    var total = 0;
    for (final r in rows) {
      if (sex != 'T' && r.learner.sex != sex) continue;
      total += r.marks.where((m) => m == 'P' || m == 'L').length;
    }
    return (total / schoolDays).toStringAsFixed(2);
  }

  String pctAttendance(String sex) {
    final reg = learners.where((l) => (sex == 'T' || l.sex == sex) && registered(l)).length;
    if (reg == 0 || schoolDays == 0) return '0';
    return (double.parse(ada(sex)) / reg * 100).toStringAsFixed(2);
  }

  String consecutive(String sex) => '${rows.where((r) => (sex == 'T' || r.learner.sex == sex) && r.remarks.contains('5 consecutive')).length}';

  final summary = [
    SummaryRow('Enrolment as of (1st Friday of the school year)', cnt((_) => true, 'M'), cnt((_) => true, 'F'), cnt((_) => true, 'T')),
    SummaryRow('Late enrolment during the month', cnt((l) => l.status == 'transferred_in', 'M'), cnt((l) => l.status == 'transferred_in', 'F'),
        cnt((l) => l.status == 'transferred_in', 'T')),
    SummaryRow('Registered learners as of end of the month', cnt(registered, 'M'), cnt(registered, 'F'), cnt(registered, 'T')),
    SummaryRow('Percentage of enrolment as of end of the month', '100', '100', '100'),
    SummaryRow('Average daily attendance', ada('M'), ada('F'), ada('T')),
    SummaryRow('Percentage of attendance for the month', pctAttendance('M'), pctAttendance('F'), pctAttendance('T')),
    SummaryRow('Number of learners absent for 5 consecutive days', consecutive('M'), consecutive('F'), consecutive('T')),
    SummaryRow('Drop out', cnt((l) => l.status == 'dropped', 'M'), cnt((l) => l.status == 'dropped', 'F'), cnt((l) => l.status == 'dropped', 'T')),
    SummaryRow('Transferred out', cnt((l) => l.status == 'transferred_out', 'M'), cnt((l) => l.status == 'transferred_out', 'F'),
        cnt((l) => l.status == 'transferred_out', 'T')),
    SummaryRow('Transferred in', cnt((l) => l.status == 'transferred_in', 'M'), cnt((l) => l.status == 'transferred_in', 'F'),
        cnt((l) => l.status == 'transferred_in', 'T')),
  ];
  // Percentage of enrolment = registered / enrolment x 100
  final enrolT = learners.length, regT = learners.where(registered).length;
  final enrolM = learners.where((l) => l.sex == 'M').length, regM = learners.where((l) => l.sex == 'M' && registered(l)).length;
  final enrolF = learners.where((l) => l.sex == 'F').length, regF = learners.where((l) => l.sex == 'F' && registered(l)).length;
  String pct(int a, int b) => b == 0 ? '0' : (a / b * 100).toStringAsFixed(2);
  summary[3] = SummaryRow(summary[3].label, pct(regM, enrolM), pct(regF, enrolF), pct(regT, enrolT));

  return Sf2Data(profile, cls, year, month, days, rows, schoolDays, summary);
}

// ---------------------------------------------------------------------------
// SF9
// ---------------------------------------------------------------------------

class MonthAttendance {
  final String label;
  final int schoolDays;
  final int present;
  final int absent;
  MonthAttendance(this.label, this.schoolDays, this.present, this.absent);
}

class Sf9Area {
  final String name;
  final bool isComponent;
  final Map<int, String> terms;
  final String? finalGrade;
  final String remarks;
  Sf9Area(this.name, this.isComponent, this.terms, this.finalGrade, this.remarks);
}

class Sf9Data {
  final SchoolProfile profile;
  final SchoolClass cls;
  final Learner learner;
  final String age;
  final List<MonthAttendance> months;
  final List<Sf9Area> areas;
  final String? generalAverage;
  final String generalRemarks;
  final String promotion;
  final Map<int, Map<int, String>> values;

  Sf9Data(this.profile, this.cls, this.learner, this.age, this.months, this.areas, this.generalAverage, this.generalRemarks, this.promotion, this.values);
}

/// Default learning areas for the report card, by grade level. Lines starting with two spaces
/// are MAPEH components; they are shown but not counted in the general average.
List<String> defaultAreas(String grade) {
  final g = int.tryParse(RegExp(r'\d+').firstMatch(grade)?.group(0) ?? '') ?? 7;
  if (g == 1) return ['Language', 'Reading and Literacy', 'Mathematics', 'Makabansa', 'GMRC'];
  if (g <= 3) {
    return ['Filipino', 'English', 'Mathematics', if (g == 3) 'Science', 'Makabansa', 'GMRC'];
  }
  if (g <= 6) {
    return ['Filipino', 'English', 'Mathematics', 'Science', 'Araling Panlipunan', 'EPP', 'MAPEH', '  Music and Arts', '  Physical Education and Health', 'GMRC'];
  }
  return ['Filipino', 'English', 'Mathematics', 'Science', 'Araling Panlipunan', 'Technology and Livelihood Education', 'MAPEH', '  Music and Arts',
    '  Physical Education and Health', 'Values Education'];
}

String ageOn(String birth, DateTime asOf) {
  if (birth.isEmpty) return '';
  try {
    final b = parseDay(birth);
    var age = asOf.year - b.year;
    if (asOf.month < b.month || (asOf.month == b.month && asOf.day < b.day)) age--;
    return '$age';
  } catch (_) {
    return '';
  }
}

/// School year months, June to April (SY 2026-2027 runs June 8 to April 8).
List<(int, int)> schoolMonths(String sy) {
  final start = int.tryParse(sy.split('-').first) ?? DateTime.now().year;
  return [for (var m = 6; m <= 12; m++) (start, m), for (var m = 1; m <= 4; m++) (start + 1, m)];
}

/// The other classes of the same section: a teacher handling several subjects, or an adviser whose
/// co-teacher's class is on this phone.
Future<List<SchoolClass>> sectionClasses(Repo repo, SchoolClass cls) async {
  String section(SchoolClass c) => c.section.trim().toLowerCase();
  return [for (final c in await repo.classes()) if (c.id != cls.id && c.grade == cls.grade && section(c) == section(cls) && c.sy == cls.sy) c];
}

/// Finds the same learner in another class of the section: by LRN, or else by name.
String learnerKey(Learner l) => l.lrn.trim().isNotEmpty ? l.lrn.trim() : '${l.last.trim().toLowerCase()}|${l.first.trim().toLowerCase()}';

Future<List<Sf9Data>> buildSf9Data(Repo repo, SchoolProfile profile, SchoolClass cls, List<Learner> learners, List<String> areaNames) async {
  final att = await repo.attendance(cls.id);
  final extra = await repo.sf9Grades(learners.map((l) => l.id).toList());
  final engine = GradeEngine(cls, await repo.activities(cls.id), await repo.scores(cls.id), overrides: await repo.overrides(cls.id));
  final months = schoolMonths(profile.sy);
  final syStart = int.tryParse(profile.sy.split('-').first) ?? DateTime.now().year;
  final out = <Sf9Data>[];
  final bySubject = <String, (GradeEngine, Map<String, String>)>{};
  for (final c in await sectionClasses(repo, cls)) {
    final e = GradeEngine(c, await repo.activities(c.id), await repo.scores(c.id), overrides: await repo.overrides(c.id));
    bySubject[c.subject.trim().toLowerCase()] = (e, {for (final other in await repo.learners(c.id)) learnerKey(other): other.id});
  }

  for (final l in learners) {
    final monthRows = <MonthAttendance>[];
    for (final (y, m) in months) {
      final prefix = '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}';
      final days = att.keys.where((k) => k.startsWith(prefix) && att[k]!.isNotEmpty).toList();
      var present = 0, absent = 0;
      for (final k in days) {
        final s = att[k]![l.id];
        if (s == 'P' || s == 'L') present++;
        if (s == 'A') absent++;
      }
      monthRows.add(MonthAttendance(monthShort[m - 1], days.length, present, absent));
    }

    final areas = <Sf9Area>[];
    final finals = <int>[];
    final ownFinal = engine.finalGrade(l.id, profile.terms);
    for (final raw in areaNames) {
      final isComponent = raw.startsWith('  ');
      final name = raw.trim();
      final terms = <int, String>{};
      String? fin;
      final isOwnSubject = name.toLowerCase() == cls.subject.trim().toLowerCase();
      if (isOwnSubject) {
        for (var t = 1; t <= profile.terms; t++) {
          final d = ownFinal.terms[t - 1].display;
          if (d.isNotEmpty) terms[t] = d;
        }
        fin = ownFinal.partial ? null : (ownFinal.finalGrade?.toString() ?? ownFinal.letter);
      } else {
        final source = bySubject[name.toLowerCase()];
        final otherId = source?.$2[learnerKey(l)];
        if (source != null && otherId != null) {
          final f = source.$1.finalGrade(otherId, profile.terms);
          for (var t = 1; t <= profile.terms; t++) {
            final d = f.terms[t - 1].display;
            if (d.isNotEmpty) terms[t] = d;
          }
          fin = f.partial ? null : (f.finalGrade?.toString() ?? f.letter);
        }
      }
      final saved = extra[l.id]?[name];
      if (saved != null) {
        saved.forEach((t, g) {
          if (t == 0) {
            fin = g;
          } else {
            terms[t] = g;
          }
        });
      }
      if (fin == null && terms.length == profile.terms && cls.mode != 'descriptive') {
        final nums = terms.values.map(int.tryParse).whereType<int>().toList();
        if (nums.length == profile.terms) fin = (nums.reduce((a, b) => a + b) / nums.length).round().toString();
      }
      final finNum = int.tryParse(fin ?? '');
      if (!isComponent && finNum != null) finals.add(finNum);
      final remarks = finNum == null ? '' : (finNum >= 75 ? 'Passed' : 'Failed');
      areas.add(Sf9Area(isComponent ? '     $name' : name, isComponent, terms, fin, remarks));
    }

    final expectedAreas = areaNames.where((a) => !a.startsWith('  ')).length;
    final complete = finals.length == expectedAreas && expectedAreas > 0;
    final ga = complete ? generalAverage(finals) : null;
    final promotion = complete ? promotionStatus(finals) : '';
    final honors = complete && withHonors(finals) ? ' (With Honors)' : '';
    out.add(Sf9Data(
      profile,
      cls,
      l,
      ageOn(l.birth, DateTime(syStart, 10, 31)),
      monthRows,
      areas,
      ga?.toString(),
      ga == null ? '' : '${ga >= 75 ? 'Passed' : 'Failed'}$honors',
      promotion,
      await repo.sf9Values(l.id),
    ));
  }
  return out;
}

class Sf5Row {
  final Learner learner;
  final String? generalAverage;
  final String action;
  final List<String> belowPassing;
  Sf5Row(this.learner, this.generalAverage, this.action, this.belowPassing);
}

/// One line of an SF5 summary, with male, female and total counts.
class Sf5Count {
  final String label;
  final int male;
  final int female;
  Sf5Count(this.label, this.male, this.female);
  int get total => male + female;
}

class Sf5Data {
  final SchoolProfile profile;
  final SchoolClass cls;
  final List<Sf5Row> rows;
  final List<Sf5Count> actions;
  final List<Sf5Count> levels;
  Sf5Data(this.profile, this.cls, this.rows, this.actions, this.levels);
}

/// School Form 5, built entirely from the report card data.
Future<Sf5Data> buildSf5Data(Repo repo, SchoolProfile profile, SchoolClass cls, List<String> areaNames) async {
  final learners = (await repo.learners(cls.id)).where((l) => l.isActive).toList();
  final cards = await buildSf9Data(repo, profile, cls, learners, areaNames);
  final rows = [
    for (final c in cards)
      Sf5Row(c.learner, c.generalAverage, c.promotion, [
        for (final a in c.areas)
          if (!a.isComponent && (int.tryParse(a.finalGrade ?? '') ?? 100) < 75) a.name.trim(),
      ]),
  ];
  Sf5Count count(String label, bool Function(Sf5Row) test) =>
      Sf5Count(label, rows.where((r) => r.learner.sex == 'M' && test(r)).length, rows.where((r) => r.learner.sex == 'F' && test(r)).length);
  final actions = [for (final a in const ['Promoted', 'For Summer Remedial Class', 'Retained']) count(a, (r) => r.action == a)];
  final levels = [
    for (final (label, sample) in [for (final g in const [95, 85, 77, 70, 60]) (descriptor(g, legacy: cls.legacyRules), g)])
      count(label, (r) {
        final ga = int.tryParse(r.generalAverage ?? '');
        return ga != null && descriptor(ga, legacy: cls.legacyRules) == descriptor(sample, legacy: cls.legacyRules);
      }),
  ];
  return Sf5Data(profile, cls, rows, actions, levels);
}

