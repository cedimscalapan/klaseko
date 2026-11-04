import 'package:intl/intl.dart';

import '../db.dart';
import '../export/form_data.dart';
import '../grading.dart';
import '../models.dart';
import 'template_fill.dart';

String _num(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2));

Map<String, String> _about(SchoolProfile p, SchoolClass c, List<Learner> learners) => {
      'school_name': p.schoolName,
      'school_id': p.schoolId,
      'region': p.region,
      'division': p.division,
      'district': p.district,
      'school_head': p.schoolHead,
      'sy': p.sy,
      'teacher': p.teacher,
      'grade': c.grade,
      'section': c.section,
      'subject': c.subject,
      'today': DateFormat('MMMM d, y').format(DateTime.now()),
      'male_count': '${learners.where((l) => l.sex == 'M').length}',
      'female_count': '${learners.where((l) => l.sex == 'F').length}',
      'total_count': '${learners.length}',
    };

Map<String, String> _learner(Learner l, String sy) {
  final start = int.tryParse(sy.split('-').first) ?? DateTime.now().year;
  return {
    'no': '${l.num}',
    'name': l.fullName,
    'last': l.last,
    'first': l.first,
    'middle': l.middle,
    'lrn': l.lrn,
    'sex': l.sex,
    'birth': l.birth,
    'age': ageOn(l.birth, DateTime(start, 10, 31)),
    'address': l.address,
    'guardian': l.guardian,
    'contact': l.contact,
    'remarks': l.remarks,
  };
}

/// Gathers the app's data for one form, ready to place on a teacher's layout.
/// [month] is for SF2, [term] for the class record, [learner] for one report card.
Future<FormValues> buildFormValues(Repo repo, SchoolProfile p, SchoolClass c, String form, {DateTime? month, int? term, Learner? learner, List<String>? areas}) async {
  final all = await repo.learners(c.id);
  final active = all.where((l) => l.isActive).toList();
  switch (form) {
    case 'sf1':
      return FormValues(singles: _about(p, c, all), learners: [for (final l in all) LearnerValues(l.sex, _learner(l, p.sy))]);
    case 'sf2':
      final at = month ?? DateTime.now();
      final d = await buildSf2Data(repo, p, c, at.year, at.month);
      return FormValues(
        singles: {..._about(p, c, all), 'month': d.monthLabel, 'school_days': '${d.schoolDays}'},
        across: {
          'day_numbers': [for (final day in d.days) '${day.day}'],
          'day_letters': [for (final day in d.days) d.weekdayLetter(day)],
          'present_m': [for (final n in d.presentPerDay('M')) '$n'],
          'present_f': [for (final n in d.presentPerDay('F')) '$n'],
          'present_all': [for (final n in d.presentPerDay(null)) '$n'],
        },
        learners: [
          for (final r in d.rows)
            LearnerValues(
              r.learner.sex,
              {..._learner(r.learner, p.sy), 'absent': '${r.absent}', 'tardy': '${r.tardy}', 'remarks': r.remarks},
              {'day_marks': [for (final m in r.marks) m == 'A' ? 'x' : (m == 'L' ? 'T' : '')]},
            ),
        ],
      );
    case 'sf5':
      final d = await buildSf5Data(repo, p, c, areas ?? defaultAreas(c.grade));
      final counts = <String, String>{};
      void add(String id, Sf5Count n) {
        counts['${id}_m'] = '${n.male}';
        counts['${id}_f'] = '${n.female}';
        counts['${id}_t'] = '${n.total}';
      }

      add('promoted', d.actions[0]);
      add('remedial', d.actions[1]);
      add('retained', d.actions[2]);
      for (var i = 0; i < d.levels.length; i++) {
        add('level${i + 1}', d.levels[i]);
      }
      return FormValues(
        singles: {..._about(p, c, active), ...counts},
        learners: [
          for (final r in d.rows)
            LearnerValues(r.learner.sex, {..._learner(r.learner, p.sy), 'ga': r.generalAverage ?? '', 'action': r.action, 'below': r.belowPassing.join(', ')}),
        ],
      );
    case 'sf9':
      final who = learner ?? active.first;
      final card = (await buildSf9Data(repo, p, c, [who], areas ?? defaultAreas(c.grade))).first;
      return FormValues(
        singles: {
          ..._about(p, c, active),
          'learner_name': who.fullName,
          'learner_lrn': who.lrn,
          'learner_sex': who.sex,
          'learner_age': card.age,
          'ga': card.generalAverage ?? '',
          'ga_remarks': card.generalRemarks,
          'promotion': card.promotion,
        },
        across: {
          'att_months': [for (final m in card.months) m.label],
          'att_days': [for (final m in card.months) m.schoolDays == 0 ? '' : '${m.schoolDays}'],
          'att_present': [for (final m in card.months) m.schoolDays == 0 ? '' : '${m.present}'],
          'att_absent': [for (final m in card.months) m.schoolDays == 0 ? '' : '${m.absent}'],
        },
        areas: [
          for (final a in card.areas)
            {
              'area_name': a.name.trim(),
              for (var t = 1; t <= 4; t++) 'area_t$t': a.terms[t] ?? '',
              'area_final': a.finalGrade ?? '',
              'area_remarks': a.remarks,
            },
        ],
        behaviors: [
          for (final b in [for (var i = 0; i < 7; i++) i])
            {for (var t = 1; t <= 4; t++) 'value_t$t': card.values[b]?[t] ?? ''},
        ],
      );
  }
  final activities = await repo.activities(c.id);
  final engine = GradeEngine(c, activities, await repo.scores(c.id), overrides: await repo.overrides(c.id));
  if (form == 'record') {
    final t = term ?? latestTerm(activities);
    final across = <String, List<String>>{};
    final extra = <String, String>{'term': p.termName(t)};
    final inComp = {for (final comp in const ['ww', 'pt', 'ex']) comp: activities.where((a) => a.term == t && a.comp == comp).toList()};
    inComp.forEach((comp, acts) {
      across['${comp}_titles'] = [for (final a in acts) a.title];
      across['${comp}_hps'] = [for (final a in acts) _num(a.hps)];
      extra['${comp}_hps_total'] = _num(acts.fold<double>(0, (s, a) => s + a.hps));
      extra['${comp}_weight'] = '${engine.weightOf(comp).toInt()}%';
    });
    return FormValues(
      singles: {..._about(p, c, active), ...extra},
      across: across,
      learners: [
        for (final l in active)
          () {
            final r = engine.term(l.id, t);
            return LearnerValues(
              l.sex,
              {
                ..._learner(l, p.sy),
                for (final comp in const ['ww', 'pt', 'ex']) ...{
                  '${comp}_total': _num(r.comps[comp]?.got),
                  '${comp}_ps': _num(r.comps[comp]?.ps),
                  '${comp}_ws': r.comps[comp]?.ps == null ? '' : _num(r.comps[comp]!.ps! * engine.weightOf(comp) / 100),
                },
                'initial': r.hasData ? r.initialGrade.toStringAsFixed(2) : '',
                'term_grade': r.display,
              },
              {
                for (final comp in const ['ww', 'pt', 'ex']) '${comp}_scores': [for (final a in inComp[comp]!) _num(engine.scores[a.id]?[l.id])],
              },
            );
          }(),
      ],
    );
  }
  // Summary of grades
  return FormValues(
    singles: _about(p, c, active),
    learners: [
      for (final l in active)
        () {
          final f = engine.finalGrade(l.id, p.terms);
          return LearnerValues(l.sex, {
            ..._learner(l, p.sy),
            for (var t = 1; t <= f.terms.length; t++) 'term_$t': f.terms[t - 1].display,
            'final': f.finalGrade?.toString() ?? f.letter ?? '',
            'descriptor': f.finalGrade == null ? '' : descriptor(f.finalGrade!, legacy: c.legacyRules),
            'remarks': f.remarks,
          });
        }(),
    ],
  );
}
