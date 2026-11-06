import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/db.dart';
import '../core/models.dart';
import '../core/teaching.dart';
import '../core/grading.dart';
import '../core/export/share.dart';
import 'widgets.dart';
import 'grades/score_entry_screen.dart';
import 'forms/official_forms_screen.dart';
import 'forms/forms_assistant_screen.dart';

class TeachingScreen extends StatefulWidget {
  const TeachingScreen({super.key, required this.cls});
  final SchoolClass cls;
  @override
  State<TeachingScreen> createState() => _TeachingScreenState();
}

class _TeachingScreenState extends State<TeachingScreen> {
  Map<String, dynamic> data = {};
  TeachingPolicy policy = TeachingPolicy();
  List<Activity> acts = [];
  List<Learner> learners = [];
  Map<String, Map<String, double>> scores = {};
  bool ready = false;
  String get key => 'teaching_${widget.cls.id}';
  List<Map<String, dynamic>> rows(String name) => ((data[name] as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final settings = await store.repo.settings();
    data = jsonDecode(settings[key] ?? '{}') as Map<String, dynamic>;
    policy = TeachingPolicy.decode(settings['policy_${widget.cls.id}']);
    if (!settings.containsKey('policy_${widget.cls.id}'))
      policy.periods = store.profile.terms;
    acts = await store.repo.activities(widget.cls.id);
    learners = (await store.repo.learners(widget.cls.id))
        .where((l) => l.isActive)
        .toList();
    scores = await store.repo.scores(widget.cls.id);
    if (mounted) setState(() => ready = true);
  }

  Future<void> save() async {
    widget.cls.teachingPolicy = policy.encode();
    await store.repo.putSettings({
      key: jsonEncode(data),
      'policy_${widget.cls.id}': policy.encode(),
    });
    store.changed();
    await load();
  }

  Future<Map<String, String>?> form(
    String title,
    Map<String, String> initial,
  ) async {
    final controllers = initial.map(
      (k, v) => MapEntry(k, TextEditingController(text: v)),
    );
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in controllers.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: e.key.startsWith('Sector') ||
                            e.key.startsWith('Component') ||
                            e.key.startsWith('Type (') ||
                            e.key.startsWith('Status (')
                        ? DropdownButtonFormField<String>(
                            initialValue: e.value.text,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: e.key.startsWith('Sector')
                                  ? 'School setting'
                                  : e.key.startsWith('Component')
                                      ? 'Grade component'
                                      : e.key.startsWith('Type (')
                                          ? 'Assessment type'
                                          : 'Status',
                            ),
                            items: [
                              for (final value in e.key.startsWith('Sector')
                                  ? [
                                      'DepEd',
                                      'Private K–12',
                                      'Higher Education',
                                    ]
                                  : e.key.startsWith('Component')
                                      ? ['ww', 'pt', 'ex']
                                      : e.key.startsWith('Type (')
                                          ? [
                                              'assignment',
                                              'project',
                                              'laboratory',
                                              'recitation',
                                              'practical',
                                              'group',
                                            ]
                                          : ['open', 'resolved'])
                                DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) e.value.text = v;
                            },
                          )
                        : TextField(
                            controller: e.value,
                            maxLines: e.key.contains('lines') ? 5 : 1,
                            decoration: InputDecoration(labelText: e.key),
                          ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              controllers.map((k, v) => MapEntry(k, v.text.trim())),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Dialog closing animations can still reference controllers.
    return result;
  }

  void error(String text) => toast(context, text);
  Future<void> editPolicy() async {
    final r = await form('School and grading policy', {
      'Sector (DepEd / Private K–12 / Higher Education)': policy.sector,
      'Institution': policy.institution,
      'Policy reference': policy.source,
      'Periods (1–6)': '${policy.periods}',
      'Passing percent': '${policy.passing}',
      'WW weight': '${widget.cls.ww}',
      'PT weight': '${widget.cls.pt}',
      'Exam weight': '${widget.cls.ex}',
      'Grade bands: minimum=grade (lines)':
          policy.bands.map((b) => '${b['minimum']}=${b['grade']}').join('\n'),
      'Type CONFIRM after checking school policy':
          policy.confirmed ? 'CONFIRM' : '',
    });
    if (r == null) return;
    try {
      final sector = r.values.first;
      if (!['DepEd', 'Private K–12', 'Higher Education'].contains(sector))
        throw const FormatException('Choose one of the three sector names.');
      final periods = int.parse(r['Periods (1–6)']!);
      final passing = double.parse(r['Passing percent']!);
      final weights = [
        double.parse(r['WW weight']!),
        double.parse(r['PT weight']!),
        double.parse(r['Exam weight']!),
      ];
      if (periods < 1 ||
          periods > 6 ||
          !passing.isFinite ||
          passing < 0 ||
          passing > 100 ||
          weights.any((v) => !v.isFinite || v < 0) ||
          (weights.reduce((a, b) => a + b) - 100).abs() > .001)
        throw const FormatException(
          'Check periods, passing mark and weights (must total 100).',
        );
      final bands = <Map<String, dynamic>>[];
      for (final line in r['Grade bands: minimum=grade (lines)']!
          .split('\n')
          .where((s) => s.trim().isNotEmpty)) {
        final parts = line.split('=');
        final min = double.parse(parts.first);
        if (parts.length != 2 ||
            !min.isFinite ||
            min < 0 ||
            min > 100 ||
            parts.last.trim().isEmpty)
          throw const FormatException('Use minimum=grade on each line.');
        bands.add({'minimum': min, 'grade': parts.last.trim()});
      }
      if (bands.isNotEmpty && !bands.any((b) => b['minimum'] == 0))
        throw const FormatException('Grade bands must include a minimum of 0.');
      policy = TeachingPolicy(
        sector: sector,
        institution: r['Institution']!,
        source: r['Policy reference']!,
        periods: periods,
        passing: passing,
        bands: bands,
        confirmed: r['Type CONFIRM after checking school policy'] == 'CONFIRM',
      );
      widget.cls
        ..ww = weights[0]
        ..pt = weights[1]
        ..ex = weights[2];
      if (sector != 'DepEd') {
        widget.cls
          ..preset = 'custom'
          ..exSplit = false
          ..transmute = 'raw'
          ..mode = 'numeric'
          ..advisory = false;
      }
      await store.repo.saveClass(widget.cls);
      await save();
    } catch (e) {
      error('$e');
    }
  }

  Future<void> addActivity() async {
    final outcomes = rows('outcomes');
    final r = await form('New assessment', {
      'Title': '',
      'Type (assignment/project/laboratory/recitation/practical/group)':
          'assignment',
      'Period': '1',
      'Component (ww/pt/ex)': 'ww',
      'Maximum score': '100',
      'Outcome codes (comma separated)': '',
      'Rubric: criterion=max points (lines)': '',
    });
    if (r == null) return;
    try {
      final term = int.parse(r['Period']!);
      final hps = double.parse(r['Maximum score']!);
      final comp = r['Component (ww/pt/ex)']!;
      if (r['Title']!.isEmpty ||
          term < 1 ||
          term > policy.periods ||
          !hps.isFinite ||
          hps <= 0 ||
          !['ww', 'pt', 'ex'].contains(comp))
        throw const FormatException(
          'Check title, period, component and maximum score.',
        );
      final codes = r['Outcome codes (comma separated)']!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (codes.any((c) => !outcomes.any((o) => o['code'] == c)))
        throw const FormatException('Add the outcome codes first.');
      final rubric = <Map<String, dynamic>>[];
      for (final line in r['Rubric: criterion=max points (lines)']!
          .split('\n')
          .where((s) => s.trim().isNotEmpty)) {
        final p = line.split('=');
        final max = double.parse(p.last);
        if (p.length != 2 ||
            p.first.trim().isEmpty ||
            !max.isFinite ||
            max <= 0) throw const FormatException('Check rubric criteria.');
        rubric.add({'name': p.first.trim(), 'max': max});
      }
      if (rubric.isNotEmpty &&
          (rubric.fold<double>(0, (s, c) => s + (c['max'] as num)) - hps)
                  .abs() >
              .001)
        throw const FormatException(
          'Rubric points must equal the maximum score.',
        );
      final a = Activity(
        id: newId(),
        classId: widget.cls.id,
        term: term,
        comp: comp,
        title: r['Title']!,
        hps: hps,
        created: now(),
      );
      await store.repo.saveActivity(a);
      data[a.id] = {
        'kind': r.values.elementAt(1),
        'outcomes': codes,
        'rubric': rubric,
      };
      await save();
    } catch (e) {
      error('$e');
    }
  }

  Future<void> scoreRubric(Activity a) async {
    final meta = Map<String, dynamic>.from((data[a.id] as Map?) ?? {});
    final rubric = (meta['rubric'] as List?) ?? [];
    if (rubric.isEmpty) {
      await push(context, ScoreEntryScreen(cls: widget.cls, activity: a));
      await load();
      return;
    }
    if (!mounted) return;
    final learner = await showDialog<Learner>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Score learner'),
        children: [
          for (final l in learners)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, l),
              child: Text(l.fullName),
            ),
        ],
      ),
    );
    if (learner == null) return;
    final existing = Map<String, dynamic>.from((meta['ratings'] as Map?) ?? {});
    final previous = (existing[learner.id] as Map?) ?? {};
    final fields = <String, String>{
      for (final c in rubric)
        '${c['name']} (max ${c['max']})': '${previous[c['name']] ?? ''}',
    };
    fields['Also apply to learner numbers (comma separated, group work)'] = '';
    final r = await form('Rubric: ${learner.fullName}', fields);
    if (r == null) return;
    try {
      double total = 0;
      final ratings = <String, double>{};
      var i = 0;
      for (final c in rubric) {
        final v = double.parse(r.values.elementAt(i++));
        if (!v.isFinite || v < 0 || v > (c['max'] as num))
          throw const FormatException('A rating is outside its range.');
        ratings[c['name'] as String] = v;
        total += v;
      }
      final targets = <String>{learner.id};
      for (final number
          in r['Also apply to learner numbers (comma separated, group work)']!
              .split(',')
              .where((s) => s.trim().isNotEmpty)) {
        final matches = learners
            .where((l) => l.num == int.tryParse(number.trim()))
            .toList();
        if (matches.length != 1)
          throw const FormatException(
            'A group learner number was not found or is ambiguous.',
          );
        targets.add(matches.single.id);
      }
      for (final id in targets) {
        existing[id] = ratings;
      }
      meta['ratings'] = existing;
      data[a.id] = meta;
      await store.repo.setScores(a.id, {for (final id in targets) id: total});
      await save();
    } catch (e) {
      error('$e');
    }
  }

  Future<void> addOutcome() async {
    final r = await form('Course outcome / competency', {
      'Code': '',
      'Description': '',
      'Program outcome / syllabus reference': '',
      'Target percent': '75',
    });
    if (r == null) return;
    final target = double.tryParse(r['Target percent']!);
    if (r['Code']!.isEmpty ||
        r['Description']!.isEmpty ||
        target == null ||
        !target.isFinite ||
        target < 0 ||
        target > 100 ||
        rows('outcomes').any((o) => o['code'] == r['Code'])) {
      error('Use a unique code, description and target from 0 to 100.');
      return;
    }
    data['outcomes'] = [
      ...rows('outcomes'),
      {
        'code': r['Code'],
        'description': r['Description'],
        'reference': r['Program outcome / syllabus reference'],
        'target': target,
      },
    ];
    await save();
  }

  Future<void> reportTemplate() async {
    final r = await form('Reusable report template', {
      'Title': data['reportTitle'] as String? ?? 'Grade sheet',
      'Columns (name,id,periods,final,status)':
          (data['columns'] as String?) ?? 'name,id,periods,final,status',
    });
    if (r == null) return;
    final columns = r['Columns (name,id,periods,final,status)']!
        .split(',')
        .map((s) => s.trim())
        .toList();
    if (columns.isEmpty ||
        columns.any(
          (s) => !['name', 'id', 'periods', 'final', 'status'].contains(s),
        )) {
      error('Choose columns from the listed names.');
      return;
    }
    data['reportTitle'] = r['Title'];
    data['columns'] = columns.join(',');
    await save();
  }

  Future<void> reusePolicy() async {
    final classes = (await store.repo.classes())
        .where((c) => c.id != widget.cls.id && c.teachingPolicy.isNotEmpty)
        .toList();
    if (!mounted) return;
    final chosen = await showDialog<SchoolClass>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Reuse school policy'),
        children: [
          for (final c in classes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: Text('${c.subject} · ${c.title}'),
            ),
          if (classes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Configure a policy in another class first.'),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    policy = TeachingPolicy.decode(chosen.teachingPolicy)..confirmed = false;
    widget.cls
      ..ww = chosen.ww
      ..pt = chosen.pt
      ..ex = chosen.ex
      ..preset = chosen.preset
      ..transmute = chosen.transmute
      ..mode = chosen.mode
      ..exSplit = chosen.exSplit;
    await store.repo.saveClass(widget.cls);
    await save();
  }

  Future<void> importTemplate() async {
    try {
      final picked = await FilePicker.platform.pickFiles(withData: true);
      if (picked == null) return;
      final file = picked.files.single;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final m = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (m['format'] != 'KlaseKoReportTemplate' ||
          m['title'] is! String ||
          m['columns'] is! String ||
          (m['columns'] as String).split(',').any(
                (c) => ![
                  'name',
                  'id',
                  'periods',
                  'final',
                  'status',
                ].contains(c.trim()),
              ))
        throw const FormatException('Invalid KlaseKo report template.');
      data['reportTitle'] = m['title'];
      data['columns'] = m['columns'];
      await save();
    } catch (e) {
      error('$e');
    }
  }

  Future<void> export(bool template) async {
    if (!template && !policy.confirmed) {
      error('Confirm the institution grading policy first.');
      return;
    }
    final ok = await confirm(
      context,
      title: template ? 'Share report layout?' : 'Share student grades?',
      message: template
          ? 'This layout contains no student records.'
          : 'The exported file contains names and grades. Share it only with an authorized recipient.',
    );
    if (!ok) return;
    if (template) {
      await saveAndShare(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'format': 'KlaseKoReportTemplate',
              'title': data['reportTitle'] ?? 'Grade sheet',
              'columns': data['columns'] ?? 'name,id,periods,final,status',
            }),
          ),
        ),
        'report-template.json',
        'application/json',
      );
      return;
    }
    final cols =
        ((data['columns'] as String?) ?? 'name,id,periods,final,status').split(
      ',',
    );
    String cell(Object? v) {
      var s = '$v';
      if (RegExp(r'^[=+@\-\t\r]').hasMatch(s)) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    final lines = <String>[cols.map(cell).join(',')];
    final engine = GradeEngine(
      widget.cls,
      acts,
      scores,
      overrides: await store.repo.overrides(widget.cls.id),
    );
    for (final l in learners) {
      final values = <double>[];
      final periods = <String>[];
      for (var t = 1; t <= policy.periods; t++) {
        double weighted = 0;
        bool complete = true;
        for (final comp in ['ww', 'pt', 'ex']) {
          final w = comp == 'ww'
              ? widget.cls.ww
              : comp == 'pt'
                  ? widget.cls.pt
                  : widget.cls.ex;
          if (w == 0) continue;
          final selected = acts.where((a) => a.term == t && a.comp == comp);
          final p = outcomePercent(selected, scores, l.id);
          if (p == null || selected.any((a) => scores[a.id]?[l.id] == null)) {
            complete = false;
          } else {
            weighted += p * w / 100;
          }
        }
        if (complete) {
          final result = engine.term(l.id, t);
          final value = policy.sector == 'DepEd'
              ? result.termGrade?.toDouble() ?? weighted
              : weighted;
          values.add(value);
          periods.add(
            policy.sector == 'DepEd' ? result.display : policy.convert(value),
          );
        } else {
          periods.add('Incomplete');
        }
      }
      final finalPercent = values.length == policy.periods
          ? values.reduce((a, b) => a + b) / values.length
          : null;
      final row = {
        'name': l.fullName,
        'id': l.lrn,
        'periods': periods.join(' / '),
        'final':
            finalPercent == null ? 'Incomplete' : policy.convert(finalPercent),
        'status': finalPercent == null
            ? 'Incomplete'
            : finalPercent >= policy.passing
                ? 'Passed'
                : 'Below target',
      };
      lines.add(cols.map((c) => cell(row[c])).join(','));
    }
    await saveAndShare(
      Uint8List.fromList(utf8.encode('\uFEFF${lines.join('\r\n')}')),
      '${data['reportTitle'] ?? 'Grade sheet'}.csv',
      'text/csv',
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Teaching workspace'),
            bottom: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: Icon(Icons.tune_rounded, size: 20), text: 'Policy'),
                Tab(
                  icon: Icon(Icons.assignment_outlined, size: 20),
                  text: 'Assessments',
                ),
                Tab(
                  icon: Icon(Icons.track_changes_rounded, size: 20),
                  text: 'Outcomes',
                ),
                Tab(
                  icon: Icon(Icons.description_outlined, size: 20),
                  text: 'Reports',
                ),
              ],
            ),
          ),
          body: !ready
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  children: [
                    ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                      children: [
                        ListTile(
                          title:
                              Text('${policy.sector} · ${policy.institution}'),
                          subtitle: Text(
                            '${policy.periods} periods · ${policy.confirmed ? 'Policy confirmed' : 'Confirm school policy'}',
                          ),
                          trailing: const Icon(Icons.settings),
                          onTap: editPolicy,
                        ),
                        TextButton(
                          onPressed: reusePolicy,
                          child: const Text('Reuse policy from another class'),
                        ),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                      children: [
                        const Text(
                          'Assessments',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: addActivity,
                          icon: const Icon(Icons.add),
                          label: const Text('Add assessment and rubric'),
                        ),
                        for (final a in acts)
                          ListTile(
                            title: Text(a.title),
                            subtitle: Text(
                              'Period ${a.term} · ${a.comp} · ${a.hps} points',
                            ),
                            onTap: () => scoreRubric(a),
                          ),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                      children: [
                        const Text(
                          'Outcomes and competencies',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: addOutcome,
                          child:
                              const Text('Add syllabus outcome / competency'),
                        ),
                        for (final o in rows('outcomes'))
                          ExpansionTile(
                            title: Text('${o['code']}: ${o['description']}'),
                            subtitle: Text(
                              '${o['reference']} · target ${o['target']}%',
                            ),
                            children: [
                              for (final l in learners)
                                Builder(
                                  builder: (context) {
                                    final selected = acts.where(
                                      (a) => ((data[a.id] as Map?)?['outcomes']
                                                  as List? ??
                                              [])
                                          .contains(o['code']),
                                    );
                                    final p = outcomePercent(
                                      selected,
                                      scores,
                                      l.id,
                                    );
                                    return ListTile(
                                      title: Text(l.fullName),
                                      subtitle: Text(
                                        p == null
                                            ? 'No assessed evidence'
                                            : '${p.toStringAsFixed(1)}% · ${p >= (o['target'] as num) ? 'Target met' : 'Below target'}',
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                      children: [
                        const Text(
                          'Reusable reports',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        NavRow(
                            icon: Icons.auto_awesome_outlined,
                            title: 'Forms Assistant',
                            subtitle: 'Reusable inputs and reviewed form packs',
                            onTap: () => push(context,
                                FormsAssistantScreen(cls: widget.cls))),
                        NavRow(
                            icon: Icons.verified_outlined,
                            title: 'Official DepEd templates',
                            subtitle:
                                'For basic education classes; match grade and curriculum',
                            onTap: () => push(
                                context, OfficialFormsScreen(cls: widget.cls))),
                        TextButton(
                          onPressed: reportTemplate,
                          child: const Text('Configure grade sheet columns'),
                        ),
                        TextButton(
                          onPressed: importTemplate,
                          child: const Text('Import KlaseKo report layout'),
                        ),
                        TextButton(
                          onPressed: () => export(true),
                          child: const Text('Share reusable layout'),
                        ),
                        FilledButton(
                          onPressed: () => export(false),
                          child: const Text(
                              'Export institution grade sheet (CSV)'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      );
}
