import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/db.dart';
import '../../core/models.dart';
import '../../core/grading.dart';
import '../../core/teaching.dart';
import '../../core/export/form_data.dart';
import '../../core/export/share.dart';
import '../../core/forms/assistant.dart';
import '../../core/forms/curriculum.dart';
import '../../core/forms/form_values.dart';
import '../../core/forms/official_catalog.dart';
import '../../core/forms/presets.dart';
import '../../core/forms/template_fill.dart';
import '../widgets.dart';
import '../theme.dart';
import '../teaching_screen.dart';
import '../attendance/attendance_screen.dart';
import '../grades/class_record_screen.dart';
import '../reports/sf9_screen.dart';
import '../settings/more_screen.dart' show ProfileScreen;
import 'archive_info.dart';
import 'templates_screen.dart';
import 'official_forms_screen.dart';

class FormsAssistantScreen extends StatefulWidget {
  const FormsAssistantScreen({super.key, required this.cls});
  final SchoolClass cls;
  @override
  State<FormsAssistantScreen> createState() => _FormsAssistantScreenState();
}

class _FormsAssistantScreenState extends State<FormsAssistantScreen> {
  List<Learner> learners = [];
  List<FormTemplate> templates = [];
  List<OfficialForm> sources = [];
  Map<String, String> settings = {}, classInputs = {};
  Map<String, Map<String, String>> extras = {};
  Map<String, dynamic> prefs = {};
  final selected = <String>{};
  Map<String, List<String>> problems = {};
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  bool ready = false, busy = false;
  Future<void> _writes = Future<void>.value();
  int _saveSequence = 0;
  Map<String, Map<String, dynamic>> recordData = {};
  String recordsForm = 'sf4';
  String recordKey(String form) =>
      recordStoreKey(store.profile, widget.cls.sy, form,
          period: form == 'sf4' ? monthKey : null);
  String get prefKey => 'forms_flow_${widget.cls.id}';
  String get monthKey =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';
  List<String> get classDays =>
      ((prefs['days_$monthKey'] as List?) ?? []).cast<String>();
  List<String> get members => ((prefs['members_$monthKey'] as List?) ??
          learners.where((l) => l.isActive).map((l) => l.id).toList())
      .cast<String>();
  List<DateTime> get monthDates => [
        for (var d = 1; d <= DateTime(month.year, month.month + 1, 0).day; d++)
          DateTime(month.year, month.month, d)
      ];
  SchoolProfile get scopedProfile => SchoolProfile.fromSettings({
        ...store.profile.toSettings(),
        'sy': widget.cls.sy,
        'terms': '$periods'
      });
  int get periods => widget.cls.teachingPolicy.isEmpty
      ? store.profile.terms
      : TeachingPolicy.decode(widget.cls.teachingPolicy).periods;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      settings = await store.repo.settings();
      prefs = jsonDecode(settings[prefKey] ?? '{}') as Map<String, dynamic>;
      classInputs = readStringMap(settings['forms_class_${widget.cls.id}']);
      learners = await store.repo.learners(widget.cls.id);
      templates = await store.repo.templates();
      sources = await OfficialForm.load();
      extras = {
        for (final l in learners)
          l.id: readStringMap(settings[learnerExtraKey(l, widget.cls.sy)])
      };
      recordData = {
        for (final form in recordFields.keys)
          form: jsonDecode(settings[recordKey(form)] ?? '{}')
              as Map<String, dynamic>
      };
      await check();
      if (mounted) setState(() => ready = true);
    } catch (e) {
      if (mounted) {
        toast(context, 'Unable to load form inputs: $e');
        setState(() => ready = true);
      }
    }
  }

  Future<void> persist() async {
    final sequence = ++_saveSequence;
    final snapshot = {
      prefKey: jsonEncode(prefs),
      'forms_class_${widget.cls.id}': jsonEncode(classInputs)
    };
    if (mounted) setState(() {});
    _writes = _writes
        .catchError((_) {})
        .then((_) => store.repo.putSettings(snapshot));
    await _writes;
    if (sequence == _saveSequence) {
      store.changed();
      await load();
    }
  }

  FormTemplate? layout(String form) => templates
      .where((t) => t.id == prefs['layout_$form'] && t.form == form)
      .firstOrNull;
  String reviewStamp(String form) =>
      layout(form)?.mapping ??
      sources
          .where((s) => s.id == presetSourceIds[form])
          .firstOrNull
          ?.data['sha256']
          ?.toString() ??
      'no-layout';
  bool presetAvailable(String form) {
    final g = gradeNumber(widget.cls.grade);
    return g != null &&
        (form == 'sf8' ||
            g >= 1 && g <= 10 && ['sf1', 'sf2', 'sf3'].contains(form));
  }

  Future<void> check() async {
    final active = learners.where((l) => l.isActive).toList();
    final acts = await store.repo.activities(widget.cls.id);
    final scores = await store.repo.scores(widget.cls.id);
    final attendance = await store.repo.attendance(widget.cls.id);
    final engine = GradeEngine(widget.cls, acts, scores,
        overrides: await store.repo.overrides(widget.cls.id));
    problems = {};
    for (final form in templateForms.keys) {
      final issues = recordFields.containsKey(form)
          ? <String>[]
          : inspectFormInputs(form, store.profile,
                  form == 'sf1' ? learners : active, extras)
              .map((i) => i.message)
              .toList();
      if (recordFields.containsKey(form)) {
        final data = recordData[form] ?? {};
        final rows = (data['rows'] as List?) ?? [];
        issues.addAll(inspectRecordRows(form,
            [for (final row in rows) Map<String, String>.from(row as Map)]));
        if (store.profile.schoolName.isEmpty || store.profile.schoolId.isEmpty)
          issues.add('Complete the shared school name and school ID.');
        if (form == 'sf10' &&
            active.any(
                (l) => !rows.any((r) => (r as Map)['record_lrn'] == l.lrn)))
          issues.add(
              'Verified history rows are missing for learners in this class.');
        if (form == 'sf10')
          issues.addAll(inspectFormInputs('sf10', store.profile, active, extras)
              .map((i) => i.message));
        if (rows.isEmpty)
          issues.add('Add verified rows in School / history records.');
        if (data['reviewed'] != true || data['expected_rows'] != rows.length)
          issues.add(
              'Confirm coverage and review all saved rows in School / history records.');
        if (rows.any((r) =>
            (r as Map)['record_source']?.toString().trim().isNotEmpty != true))
          issues.add(
              'Every school / history row needs a verified source reference.');
      }
      final t = layout(form);
      if (t == null && !presetAvailable(form))
        issues.add('Choose a school-approved Excel layout in Layouts.');
      if (prefs['review_$form'] != true ||
          prefs['review_stamp_$form'] != reviewStamp(form))
        issues.add(
            'Review and confirm this form edition / cell mapping in Layouts.');
      if (t != null) {
        final maps = CellMap.decode(t.mapping);
        final ids = maps.map((m) => m.field).toSet();
        if (maps.isEmpty ||
            (!recordFields.containsKey(form) &&
                !ids.any((id) => id == 'name' || id == 'learner_name')))
          issues.add('The layout needs a mapped learner name field.');
        if (recordFields.containsKey(form) &&
            !maps.any((m) => recordFields[form]!.containsKey(m.field)))
          issues.add('Map the saved school / history record fields.');
        if (recordFields.containsKey(form))
          for (final field
              in recordRequired[form]!.where((f) => f != 'record_source')) {
            if (!ids.contains(field))
              issues.add('Map ${recordFields[form]![field]} in this layout.');
          }
        if (form == 'sf10' && !ids.contains('learner_name'))
          issues.add('Map the individual learner header for SF10.');
        final required = {
              'sf1': ['lrn'],
              'sf2': ['day_marks'],
              'sf3': ['book_1_issued'],
              'sf8': ['weight', 'height'],
              'record': ['term_grade'],
              'grades': ['final'],
              'sf9': ['area_name', 'area_t1'],
              'sf5': ['ga', 'action']
            }[form] ??
            [];
        for (final field in required) {
          if (!ids.contains(field))
            issues.add('Map the required $field field in this layout.');
        }
      }
      if (form == 'sf2') {
        if (classDays.isEmpty)
          issues.add('Confirm the class days for $monthKey in Calendar.');
        var missing = 0;
        for (final day in classDays) {
          for (final l in learners.where((l) => members.contains(l.id))) {
            if (attendance[day]?[l.id] == null) missing++;
          }
        }
        if (missing > 0)
          issues.add(
              '$missing attendance marks are missing on confirmed class days.');
        if (prefs['review_members_$monthKey'] != true || members.isEmpty)
          issues.add(
              'Confirm the month-specific roster in Calendar, including transfers / dropouts where applicable.');
      }
      if (form == 'sf3' &&
          !classInputs.entries
              .any((e) => e.key.endsWith('_title') && e.value.isNotEmpty))
        issues.add(
            'Add the book titles in Books, then record issue / return dates.');
      if (['record', 'grades', 'sf5', 'sf9'].contains(form)) {
        if (acts.isEmpty) issues.add('Record assessments and scores first.');
        final count = active
            .where((l) => (form == 'record'
                    ? [engine.term(l.id, latestTerm(acts))]
                    : [for (var p = 1; p <= periods; p++) engine.term(l.id, p)])
                .any((r) => !r.hasData || r.incomplete || r.missing > 0))
            .length;
        if (count > 0)
          issues.add('$count learners have incomplete period scores.');
        if (widget.cls.teachingPolicy.isEmpty ||
            !TeachingPolicy.decode(widget.cls.teachingPolicy).confirmed)
          issues.add('Confirm the institution grading policy first.');
      }
      if (['sf5', 'sf9'].contains(form)) {
        if (!settings.containsKey('sf9_areas_${widget.cls.id}'))
          issues.add(
              'Review and save the actual learning areas / subjects in the report-card setup.');
        else {
          final cards = await buildSf9Data(store.repo, scopedProfile,
              widget.cls, active, await loadAreas(widget.cls));
          if (cards.any((c) => c.generalAverage == null))
            issues.add(
                'Subject grades are incomplete. Review report cards before generating.');
        }
      }
      if (form == 'sf8' &&
          active.map((l) => extras[l.id]?['measured_on']).toSet().length > 1)
        issues.add(
            'Measurements have different dates. Review the assessment period before using this layout.');
      problems[form] = issues;
    }
  }

  Future<Map<String, String>?> edit(String title, Map<String, String> fields,
      {String? note}) async {
    final key = GlobalKey<FormState>();
    final controls =
        fields.map((k, v) => MapEntry(k, TextEditingController(text: v)));
    return showDialog<Map<String, String>>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(title),
                content: SizedBox(
                    width: 500,
                    child: Form(
                        key: key,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              if (note != null)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Text(note)),
                              for (final e in controls.entries)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: TextFormField(
                                        controller: e.value,
                                        decoration:
                                            InputDecoration(labelText: e.key),
                                        validator: (value) {
                                          final v = (value ?? '').trim();
                                          if (v.isEmpty) return null;
                                          if (e.key.contains('YYYY-MM-DD') &&
                                              (DateTime.tryParse(v) == null ||
                                                  !RegExp(r'^\d{4}-\d{2}-\d{2}$')
                                                      .hasMatch(v) ||
                                                  dayKey(DateTime.parse(v)) !=
                                                      v))
                                            return 'Use YYYY-MM-DD';
                                          if (e.key == 'LRN' &&
                                              !RegExp(r'^\d{12}$').hasMatch(v))
                                            return 'Use 12 digits';
                                          if (e.key.contains('weight (kg)')) {
                                            final n = double.tryParse(v);
                                            if (n == null ||
                                                !n.isFinite ||
                                                n <= 0 ||
                                                n > 400)
                                              return 'Enter kg, greater than 0 and at most 400';
                                          }
                                          if (e.key.contains('height (m)')) {
                                            final n = double.tryParse(v);
                                            if (n == null ||
                                                !n.isFinite ||
                                                n < .3 ||
                                                n > 3)
                                              return 'Enter metres, between 0.3 and 3';
                                          }
                                          return null;
                                        }))
                            ])))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        if (key.currentState!.validate())
                          Navigator.pop(
                              ctx,
                              controls
                                  .map((k, v) => MapEntry(k, v.text.trim())));
                      },
                      child: const Text('Save and reuse'))
                ]));
  }

  Future<String?> pasteGrid(Map<String, String> fields) async {
    final controller = TextEditingController();
    return showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Paste from Excel or CSV'),
                content: SizedBox(
                    width: 550,
                    child: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          'Include the header row. Only the listed columns are accepted; identifiers stay as text. Dates must use YYYY-MM-DD.'),
                      TextButton(
                          onPressed: () => Clipboard.setData(
                              ClipboardData(text: fields.values.join('\t'))),
                          child: const Text('Copy supported column headers')),
                      SelectableText(fields.values.join(' · ')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: controller,
                          maxLines: 10,
                          decoration: const InputDecoration(
                              labelText: 'Paste table with headers'))
                    ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, controller.text),
                      child: const Text('Validate and import'))
                ]));
  }

  Future<void> importRecords() async {
    final form = recordsForm;
    final text = await pasteGrid(recordFields[form]!);
    if (text == null) return;
    try {
      final imported = parseInputGrid(text, recordFields[form]!);
      final issues = inspectRecordRows(form, imported);
      if (issues.isNotEmpty) throw FormatException(issues.take(6).join('\n'));
      final data = recordData[form] ?? {};
      data['previous_rows'] = data['rows'] ?? [];
      data['rows'] = [...(data['rows'] as List?) ?? [], ...imported];
      data['reviewed'] = false;
      await store.repo.putSettings({recordKey(form): jsonEncode(data)});
      await load();
      if (mounted)
        toast(context,
            'Imported ${imported.length} rows. Review coverage before generating.',
            success: true);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> importLearnerDetails() async {
    final fields = {
      'lrn': 'LRN',
      'birth': 'Birth date (YYYY-MM-DD)',
      'address': 'Address',
      'guardian': 'Parent / guardian',
      'contact': 'Contact number',
      ...extraLearnerFields
    };
    final text = await pasteGrid(fields);
    if (text == null) return;
    try {
      final rows = parseInputGrid(text, fields);
      final jobs = <(Learner, Map<String, String>)>[];
      final seen = <String>{};
      for (final row in rows) {
        final matches = learners
            .where((l) => l.lrn.isNotEmpty && l.lrn == row['lrn'])
            .toList();
        if (matches.length != 1 || !seen.add(row['lrn'] ?? ''))
          throw const FormatException(
              'Each row must have a unique LRN matching exactly one learner in this class.');
        final l = Learner.fromMap(matches.single.toMap());
        if (row['birth']?.isNotEmpty == true) {
          final date = DateTime.tryParse(row['birth']!);
          if (date == null || dayKey(date) != row['birth'])
            throw const FormatException('Use valid YYYY-MM-DD birth dates.');
          l.birth = row['birth']!;
        }
        if (row['address']?.isNotEmpty == true) l.address = row['address']!;
        if (row['guardian']?.isNotEmpty == true) l.guardian = row['guardian']!;
        if (row['contact']?.isNotEmpty == true) l.contact = row['contact']!;
        final e = {
          ...extras[l.id] ?? {},
          for (final item in row.entries.where((e) =>
              extraLearnerFields.containsKey(e.key) && e.value.isNotEmpty))
            item.key: item.value
        };
        jobs.add((l, e));
      }
      for (final job in jobs) {
        await saveSharedLearner(store.repo, job.$1, widget.cls, job.$2);
      }
      store.changed();
      await load();
      if (mounted)
        toast(context, 'Updated ${jobs.length} matched learner profiles.',
            success: true);
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> removeRecord(int index) async {
    final form = recordsForm;
    final data = recordData[form] ?? {};
    final rows = [...(data['rows'] as List?) ?? []];
    if (!await confirm(context,
        title: 'Remove this saved row?',
        message:
            'The previous row list can be restored with Undo last record change.'))
      return;
    data['previous_rows'] = [...rows];
    rows.removeAt(index);
    data['rows'] = rows;
    data['reviewed'] = false;
    await store.repo.putSettings({recordKey(form): jsonEncode(data)});
    await load();
  }

  Future<void> undoRecords() async {
    final data = recordData[recordsForm] ?? {};
    if (data['previous_rows'] == null) return;
    final current = data['rows'];
    data['rows'] = data['previous_rows'];
    data['previous_rows'] = current;
    data['reviewed'] = false;
    await store.repo.putSettings({recordKey(recordsForm): jsonEncode(data)});
    await load();
  }

  Future<void> editRecord({int? index}) async {
    final form = recordsForm;
    final data = recordData[form] ?? {};
    final rows = [
      for (final row in (data['rows'] as List?) ?? [])
        Map<String, String>.from(row as Map)
    ];
    var row = index == null ? <String, String>{} : rows[index];
    if (index == null && form == 'sf10') {
      final l = await showDialog<Learner>(
          context: context,
          builder: (ctx) => SimpleDialog(
                  title: const Text('Whose verified history?'),
                  children: [
                    for (final l in learners)
                      SimpleDialogOption(
                          onPressed: () => Navigator.pop(ctx, l),
                          child: Text(l.fullName))
                  ]));
      if (l == null) return;
      row = {'record_lrn': l.lrn, 'record_name': l.fullName};
    }
    final result = await edit(
        templateForms[form]!,
        {
          for (final field in recordFields[form]!.entries)
            field.value:
                row[field.key] ?? (field.key == 'record_period' ? monthKey : '')
        },
        note:
            'Copy verified values from source records. A blank is not zero. Provide the source reference for every row.');
    if (result == null) return;
    final updated = {
      for (final field in recordFields[form]!.entries)
        field.key: result[field.value]!
    };
    if (updated['record_source']?.isNotEmpty != true) {
      if (mounted) toast(context, 'A verified source reference is required.');
      return;
    }
    if (form == 'sf10' &&
        !learners
            .any((l) => l.lrn.isNotEmpty && l.lrn == updated['record_lrn'])) {
      if (mounted)
        toast(context, 'Choose a learner with a valid LRN from this class.');
      return;
    }
    for (final field in updated.entries) {
      if (RegExp(r'_(m|f)$').hasMatch(field.key) ||
          field.key == 'weekly_minutes') {
        final n = num.tryParse(field.value);
        if (field.value.isNotEmpty && (n == null || !n.isFinite || n < 0)) {
          if (mounted)
            toast(context,
                'Counts and attendance values must be non-negative numbers.');
          return;
        }
      }
    }
    if (index == null) {
      rows.add(updated);
    } else {
      rows[index] = updated;
    }
    data['previous_rows'] = data['rows'] ?? [];
    data['rows'] = rows;
    data['reviewed'] = false;
    await store.repo.putSettings({recordKey(form): jsonEncode(data)});
    await load();
  }

  Future<void> confirmRecords() async {
    final data = recordData[recordsForm] ?? {};
    final rows = (data['rows'] as List?) ?? [];
    final r = await edit(
        'Confirm coverage',
        {
          'Expected number of verified rows':
              '${data['expected_rows'] ?? rows.length}',
          'Type REVIEWED after checking source records': ''
        },
        note:
            'There are ${rows.length} rows. Confirm that all required sections / personnel / learner history entries are represented for this reporting period.');
    if (r == null) return;
    if (int.tryParse(r.values.first) != rows.length ||
        rows.isEmpty ||
        r.values.last != 'REVIEWED') {
      if (mounted)
        toast(context,
            'The expected count must match all saved rows and REVIEWED must be entered.');
      return;
    }
    data['expected_rows'] = rows.length;
    data['reviewed'] = true;
    data['reviewed_at'] = DateTime.now().toIso8601String();
    await store.repo.putSettings({recordKey(recordsForm): jsonEncode(data)});
    await load();
  }

  Future<void> captureCurrentGrades() async {
    await load();
    if (problems['sf9']?.isNotEmpty ?? true) {
      if (mounted)
        toast(context,
            'Complete the SF9 readiness checks first, including subjects, grades and the approved layout.');
      return;
    }
    final active = learners.where((l) => l.isActive).toList();
    final cards = await buildSf9Data(store.repo, scopedProfile, widget.cls,
        active, await loadAreas(widget.cls));
    if (!mounted) return;
    if (!await confirm(context,
        title: 'Capture current report-card results?',
        message:
            'This creates history rows from the completed grades for ${cards.length} learners. Existing history rows will not be overwritten. Review the source references and coverage before generating SF10.',
        action: 'Capture rows')) return;
    final data = recordData['sf10'] ?? {};
    final rows = [
      for (final row in (data['rows'] as List?) ?? [])
        Map<String, String>.from(row as Map)
    ];
    final before = [...rows];
    var added = 0;
    for (final card in cards) {
      for (final area in card.areas) {
        if (area.finalGrade == null) continue;
        if (rows.any((r) =>
            r['record_lrn'] == card.learner.lrn &&
            r['record_year'] == widget.cls.sy &&
            r['record_area'] == area.name.trim())) continue;
        rows.add({
          'record_lrn': card.learner.lrn,
          'record_name': card.learner.sf1Name,
          'record_year': widget.cls.sy,
          'record_grade': widget.cls.grade,
          'record_school': store.profile.schoolName,
          'record_area': area.name.trim(),
          for (var t = 1; t <= 4; t++) 'record_t$t': area.terms[t] ?? '',
          'record_final': area.finalGrade!,
          'record_remarks': area.remarks,
          'record_source':
              'Reviewed KlaseKo SF9 snapshot · ${dayKey(DateTime.now())}'
        });
        added++;
      }
    }
    data['previous_rows'] = before;
    data['rows'] = rows;
    data['reviewed'] = false;
    await store.repo.putSettings({recordKey('sf10'): jsonEncode(data)});
    await load();
    if (mounted)
      toast(context,
          'Captured $added new history rows. Existing history was preserved.',
          success: true);
  }

  Future<void> editLearner(Learner l) async {
    final e = extras[l.id] ?? {};
    final result = await edit(
        l.fullName,
        {
          'LRN': l.lrn,
          'Birth date (YYYY-MM-DD)': l.birth,
          'Address': l.address,
          'Parent / guardian': l.guardian,
          'Contact number': l.contact,
          for (final f in extraLearnerFields.entries) f.value: e[f.key] ?? ''
        },
        note:
            'These details are reused in forms. Demographics also update identity-matched records with the same LRN in this school year. Leave optional details blank when not provided.');
    if (result == null) return;
    final updated = Learner.fromMap(l.toMap())
      ..lrn = result['LRN']!
      ..birth = result['Birth date (YYYY-MM-DD)']!
      ..address = result['Address']!
      ..guardian = result['Parent / guardian']!
      ..contact = result['Contact number']!;
    if (learners.any((other) =>
        other.id != l.id &&
        updated.lrn.isNotEmpty &&
        other.lrn == updated.lrn)) {
      if (mounted)
        toast(context,
            'This LRN is already used by another learner in this class.');
      return;
    }
    final extra = {
      ...e,
      for (final f in extraLearnerFields.entries) f.key: result[f.value]!
    };
    final reused =
        await saveSharedLearner(store.repo, updated, widget.cls, extra);
    store.changed();
    await load();
    if (mounted)
      toast(context, 'Saved; reused in $reused other class records.',
          success: true);
  }

  Future<void> editBooks() async {
    final r = await edit('Book list', {
      for (var n = 1; n <= 8; n++)
        'Book $n title': classInputs['book_${n}_title'] ?? ''
    });
    if (r == null) return;
    for (var n = 1; n <= 8; n++) {
      classInputs['book_${n}_title'] = r['Book $n title']!;
    }
    await persist();
  }

  Future<void> bookDates(Learner l) async {
    final e = extras[l.id] ?? {};
    final fields = <String, String>{};
    for (var n = 1; n <= 8; n++) {
      if (classInputs['book_${n}_title']?.isNotEmpty == true) {
        fields['Book $n issued (YYYY-MM-DD)'] =
            e['book_${widget.cls.id}_${n}_issued'] ?? '';
        fields['Book $n returned (YYYY-MM-DD)'] =
            e['book_${widget.cls.id}_${n}_returned'] ?? '';
      }
    }
    if (fields.isEmpty) {
      await editBooks();
      return;
    }
    final r = await edit('Book dates · ${l.fullName}', fields);
    if (r == null) return;
    for (var n = 1; n <= 8; n++) {
      for (final action in ['issued', 'returned']) {
        final label = 'Book $n $action (YYYY-MM-DD)';
        if (r.containsKey(label))
          e['book_${widget.cls.id}_${n}_$action'] = r[label]!;
      }
    }
    await store.repo
        .putSettings({learnerExtraKey(l, widget.cls.sy): jsonEncode(e)});
    await load();
  }

  Future<void> issueAll() async {
    final r = await edit(
        'Issue books to class',
        {
          'Book number (1–8)': '1',
          'Issue date (YYYY-MM-DD)': dayKey(DateTime.now())
        },
        note:
            'Fills only empty issue dates for active learners. Existing issue and return dates stay as recorded.');
    if (r == null) return;
    final n = int.tryParse(r.values.first);
    if (n == null ||
        n < 1 ||
        n > 8 ||
        classInputs['book_${n}_title']?.isNotEmpty != true ||
        r.values.last.isEmpty) {
      if (mounted)
        toast(context, 'Choose a listed book and enter its issue date.');
      return;
    }
    final updates = <String, String>{};
    for (final l in learners.where((l) => l.isActive)) {
      final e = {...extras[l.id] ?? {}};
      final field = 'book_${widget.cls.id}_${n}_issued';
      if (e[field]?.isNotEmpty != true) e[field] = r.values.last;
      updates[learnerExtraKey(l, widget.cls.sy)] = jsonEncode(e);
    }
    await store.repo.putSettings(updates);
    await load();
  }

  Future<void> chooseMonth() async {
    final picked = await showDatePicker(
        context: context,
        initialDate: month,
        firstDate: DateTime(2015),
        lastDate: DateTime(2100));
    if (picked != null) {
      setState(() => month = DateTime(picked.year, picked.month));
      await load();
    }
  }

  Future<FormValues> values(String form, {Learner? learner}) async {
    final v = await buildFormValues(store.repo, store.profile, widget.cls, form,
        month: month,
        learner: learner,
        areas:
            ['sf5', 'sf9'].contains(form) ? await loadAreas(widget.cls) : null,
        calendarDates:
            form == 'sf2' ? classDays.map(DateTime.parse).toList() : null);
    if (form != 'sf2') return v;
    final rows = v.learners
        .where((l) => members.contains(l.cells['_learner_id']))
        .toList();
    return FormValues(singles: {
      ...v.singles,
      'school_days': '${classDays.length}',
      'total_count': '${rows.length}',
      'male_count': '${rows.where((l) => l.sex == 'M').length}',
      'female_count': '${rows.where((l) => l.sex == 'F').length}'
    }, across: v.across, learners: rows);
  }

  Future<void> fixIssue(BuildContext ctx, String issue) async {
    if (issue.contains('grading policy')) {
      await push(context, TeachingScreen(cls: widget.cls));
      await load();
      return;
    }
    final learner =
        learners.where((l) => issue.startsWith('${l.fullName}:')).firstOrNull;
    if (learner != null) {
      await editLearner(learner);
      return;
    }
    if (issue.toLowerCase().contains('school name') ||
        issue == 'School ID' ||
        issue == 'Teacher / adviser name') {
      await push(context, const ProfileScreen());
      await load();
      return;
    }
    if (issue.contains('attendance marks')) {
      await push(context, AttendanceScreen(cls: widget.cls));
      await load();
      return;
    }
    if (issue.contains('scores') || issue.contains('assessments')) {
      await push(context, ClassRecordScreen(cls: widget.cls));
      await load();
      return;
    }
    if (issue.contains('learning areas') || issue.contains('Subject grades')) {
      await push(context,
          AreasScreen(cls: widget.cls, areas: await loadAreas(widget.cls)));
      await load();
      return;
    }
    final index = issue.contains('Calendar') ||
            issue.contains('class days') ||
            issue.contains('month-specific')
        ? 3
        : issue.contains('book titles')
            ? 2
            : issue.contains('Row ') ||
                    issue.contains('history') ||
                    issue.contains('coverage')
                ? 5
                : 4;
    if (ctx.mounted) DefaultTabController.of(ctx).animateTo(index);
  }

  Future<bool> previewInputs() async {
    return await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
                child: SizedBox(
                    height: MediaQuery.sizeOf(ctx).height * .8,
                    child: Column(children: [
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                              'Review ${selected.length} forms · ${widget.cls.title}',
                              style: Theme.of(ctx).textTheme.titleLarge)),
                      Expanded(
                          child: ListView(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              children: [
                            Text(
                                '${store.profile.schoolName}\nSchool ID ${store.profile.schoolId} · ${widget.cls.sy}\nTeacher: ${store.profile.teacher}'),
                            for (final form in selected)
                              ListTile(
                                  title: Text(templateForms[form]!),
                                  subtitle: Text(layout(form)?.name ??
                                      'Pinned reference edition · ${presetSourceIds[form]}')),
                            if (selected.contains('sf2'))
                              Text(
                                  'Attendance month: $monthKey\nClass days: ${classDays.join(', ')}\nRoster: ${members.length} learners'),
                            for (final l in learners.where((l) => l.isActive))
                              ExpansionTile(
                                  title: Text(l.fullName),
                                  subtitle: Text(l.lrn),
                                  children: [
                                    ListTile(
                                        title: Text(
                                            'Birth date: ${l.birth}\nAddress: ${l.address}\nGuardian: ${l.guardian}\nContact: ${l.contact}')),
                                    if (selected.contains('sf8'))
                                      ListTile(
                                          title: Text(
                                              'Weight ${extras[l.id]?['weight']} kg · Height ${extras[l.id]?['height']} m\nAssessment: ${extras[l.id]?['measured_on']}\nRecorded category: ${extras[l.id]?['bmi_category']}\nRecorded HFA: ${extras[l.id]?['hfa']}'))
                                  ]),
                            for (final form
                                in selected.where(recordFields.containsKey))
                              ExpansionTile(
                                  title: Text(
                                      '${templateForms[form]} · verified rows'),
                                  children: [
                                    for (final row in (recordData[form]?['rows']
                                            as List?) ??
                                        [])
                                      ListTile(
                                          title: Text((row as Map)
                                              .entries
                                              .map((e) =>
                                                  '${recordFields[form]![e.key] ?? e.key}: ${e.value}')
                                              .join('\n')))
                                  ]),
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                    'These copies contain learner and possibly personnel information. Generate for authorized school use. Open the exported spreadsheet to recalculate formulas and review its printed layout before submission.')),
                          ])),
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: FilledButton.icon(
                              onPressed: () => Navigator.pop(ctx, true),
                              icon: const Icon(Icons.folder_zip_outlined),
                              label:
                                  const Text('Generate reviewed form pack'))),
                    ])))) ??
        false;
  }

  Future<void> generate() async {
    if (busy || selected.isEmpty) return;
    setState(() => busy = true);
    try {
      await _writes;
      await load();
      final blocked =
          selected.where((f) => problems[f]?.isNotEmpty ?? true).toList();
      if (blocked.isNotEmpty) {
        if (mounted)
          toast(context,
              'Resolve the missing inputs for ${blocked.join(', ')} first.');
        return;
      }
      if (!mounted) return;
      final accepted = await previewInputs();
      if (!accepted || !mounted) return;
      final outputs = <String, Uint8List>{};
      for (final form in selected) {
        final t = layout(form);
        if (t != null) {
          final bytes = await store.repo.templateBytes(t);
          if (bytes == null)
            throw const FormatException('A saved layout file is missing.');
          final who = ['sf9', 'sf10'].contains(form)
              ? learners.where((l) => l.isActive).cast<Learner?>().toList()
              : <Learner?>[null];
          for (final l in who) {
            final filled = fillXlsx(bytes, CellMap.decode(t.mapping), form,
                await values(form, learner: l));
            if (filled.notFitted > 0)
              throw FormatException(
                  '${t.name}: ${filled.notFitted} learners do not fit. Expand the layout before generating.');
            outputs['$form ${l == null ? widget.cls.title : '${l.fullName} ${l.lrn.isEmpty ? l.id : l.lrn}'}.xlsx'] =
                filled.bytes;
          }
        } else {
          final source =
              sources.firstWhere((s) => s.id == presetSourceIds[form]);
          final b = await rootBundle.load(source.asset!);
          final start =
              int.tryParse(widget.cls.sy.split('-').first) ?? month.year;
          var date = DateTime(start, 6, 1);
          while (date.weekday != DateTime.friday) {
            date = date.add(const Duration(days: 1));
          }
          outputs['$form ${widget.cls.title}.xlsx'] = fillPreset(
              b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes),
              form,
              await values(form),
              ageDate: date);
        }
      }
      final zip = Archive();
      for (final e in outputs.entries) {
        zip.addFile(ArchiveFile(safeFileName(e.key), e.value.length, e.value));
      }
      final note = utf8.encode(
          'KlaseKo reviewed working copies\nClass: ${widget.cls.title}\nSchool year: ${widget.cls.sy}\nGenerated: ${DateTime.now().toIso8601String()}\nPeriod: $monthKey\nFiles: ${outputs.keys.join(', ')}\nOriginal source editions and school-approved mappings require final teacher review. Excel formulas must recalculate in the spreadsheet app.');
      zip.addFile(ArchiveFile('Review notes.txt', note.length, note));
      // Persist only after every selected form has passed capacity and fill checks.
      for (final e in outputs.entries) {
        await archiveForm(
            ArchiveInfo(widget.cls, e.key.split(' ').first, period: monthKey),
            e.key,
            e.value,
            xlsxMime);
      }
      final result = await saveAndShare(
          Uint8List.fromList(ZipEncoder().encode(zip)!),
          'Forms ${widget.cls.title} $monthKey.zip',
          'application/zip');
      prefs['last_generated'] = DateTime.now().toIso8601String();
      await persist();
      if (mounted)
        toast(
            context,
            result
                ? 'Form pack generated and saved to the archive.'
                : 'Form pack saved in the archive.',
            success: true);
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget section(List<Widget> children) =>
      ListView(padding: const EdgeInsets.all(20), children: children);
  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 6,
      child: Scaffold(
          appBar: AppBar(
              title: ClassTitle('Forms Assistant', widget.cls),
              bottom: const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Ready & generate'),
                    Tab(text: 'Learner details'),
                    Tab(text: 'Books'),
                    Tab(text: 'Calendar'),
                    Tab(text: 'Layouts'),
                    Tab(text: 'School / history records')
                  ])),
          body: !ready
              ? const Center(child: CircularProgressIndicator())
              : AbsorbPointer(
                  absorbing: busy,
                  child: TabBarView(children: [
                    section([
                      AppCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Enter once. Reuse across forms.',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            const Text(
                                'Review missing details, confirm the required layout, and generate a class form pack. No empty scores or unrecorded attendance are treated as completed inputs.'),
                            if (prefs['last_generated'] != null)
                              Text('Last generated: ${prefs['last_generated']}')
                          ])),
                      NavRow(
                          icon: Icons.account_balance_outlined,
                          title: 'School and teacher details',
                          subtitle: 'Shared across your forms',
                          onTap: () async {
                            await push(context, const ProfileScreen());
                            await load();
                          }),
                      NavRow(
                          icon: Icons.fact_check_outlined,
                          title: 'Attendance · $monthKey',
                          subtitle:
                              'Record missing marks after confirming class days',
                          onTap: () async {
                            await push(
                                context, AttendanceScreen(cls: widget.cls));
                            await load();
                          }),
                      NavRow(
                          icon: Icons.grid_on_outlined,
                          title: 'Scores and subject grades',
                          subtitle: 'Reuse existing class records',
                          onTap: () async {
                            await push(
                                context, ClassRecordScreen(cls: widget.cls));
                            await load();
                          }),
                      for (final form in templateForms.keys)
                        AppCard(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(children: [
                              CheckboxListTile(
                                  value: selected.contains(form),
                                  onChanged: busy
                                      ? null
                                      : (v) => setState(() => v == true
                                          ? selected.add(form)
                                          : selected.remove(form)),
                                  title: Text(templateForms[form]!),
                                  subtitle: Text(problems[form]!.isEmpty
                                      ? 'Inputs ready · teacher review required'
                                      : '${problems[form]!.length} items to resolve')),
                              if (problems[form]!.isNotEmpty)
                                ExpansionTile(
                                    title: const Text('See missing inputs'),
                                    children: [
                                      for (final issue in problems[form]!)
                                        Builder(
                                            builder: (ctx) => ListTile(
                                                onTap: () =>
                                                    fixIssue(ctx, issue),
                                                trailing: const Icon(
                                                    Icons.arrow_forward_rounded,
                                                    size: 18),
                                                dense: true,
                                                leading: Icon(
                                                    Icons.info_outline,
                                                    size: 18,
                                                    color: lateAmber),
                                                title: Text(issue)))
                                    ])
                            ])),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                          onPressed: busy || selected.isEmpty ? null : generate,
                          icon: const Icon(Icons.folder_zip_outlined),
                          label: Text(busy
                              ? 'Generating…'
                              : 'Review and generate selected forms')),
                      const SectionTitle(
                          'Forms needing additional verified records'),
                      const Text(
                          'Use School / history records for verified school-wide summaries, personnel assignments and historical records. Each form needs its matching school-approved Excel layout. These records are shared within this school year and require explicit coverage review.'),
                      TextButton(
                          onPressed: () => push(
                              context, OfficialFormsScreen(cls: widget.cls)),
                          child: const Text('Open official template library')),
                    ]),
                    section([
                      const Text(
                          'Tap a learner to fix details once. Matching LRN records in other classes reuse the demographic update; book dates remain specific to this class.'),
                      TextButton.icon(
                          onPressed: importLearnerDetails,
                          icon: const Icon(Icons.content_paste_outlined),
                          label:
                              const Text('Paste learner details from Excel')),
                      for (final l in learners)
                        NavRow(
                            icon: Icons.person_outline,
                            title: l.fullName,
                            subtitle:
                                '${l.lrn.isEmpty ? 'LRN missing' : l.lrn} · ${l.birth.isEmpty ? 'Birth date missing' : l.birth}',
                            onTap: () => editLearner(l)),
                      if (learners.isEmpty)
                        const Text('Add the class roster first.')
                    ]),
                    section([
                      FilledButton.icon(
                          onPressed: editBooks,
                          icon: const Icon(Icons.menu_book_outlined),
                          label: const Text('Set book titles once')),
                      TextButton(
                          onPressed: issueAll,
                          child: const Text(
                              'Record one issue date for the class')),
                      for (var n = 1; n <= 8; n++)
                        if (classInputs['book_${n}_title']?.isNotEmpty == true)
                          ListTile(
                              title: Text(
                                  'Book $n · ${classInputs['book_${n}_title']}')),
                      for (final l in learners.where((l) => l.isActive))
                        NavRow(
                            icon: Icons.event_note_outlined,
                            title: l.fullName,
                            subtitle: 'Issue and return dates',
                            onTap: () => bookDates(l))
                    ]),
                    section([
                      TextButton.icon(
                          onPressed: chooseMonth,
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text('Month: $monthKey')),
                      const Text(
                          'Select only actual class days. Unselected dates receive a dash in the SF2 working copy. Selecting dates does not invent or delete attendance. Include weekend make-up days when applicable.'),
                      for (final day in monthDates)
                        CheckboxListTile(
                            title: Text(dayKey(day)),
                            value: classDays.contains(dayKey(day)),
                            onChanged: (value) async {
                              final dates = classDays.toSet();
                              if (value == true) {
                                dates.add(dayKey(day));
                              } else {
                                dates.remove(dayKey(day));
                              }
                              prefs['days_$monthKey'] = dates.toList()..sort();
                              await persist();
                            }),
                      const SectionTitle('Month-specific roster'),
                      for (final l in learners)
                        CheckboxListTile(
                            title: Text(l.fullName),
                            subtitle: Text(l.status.replaceAll('_', ' ')),
                            value: members.contains(l.id),
                            onChanged: (v) async {
                              final list = members.toSet();
                              if (v == true) {
                                list.add(l.id);
                              } else {
                                list.remove(l.id);
                              }
                              prefs['members_$monthKey'] = list.toList();
                              prefs['review_members_$monthKey'] = false;
                              await persist();
                            }),
                      CheckboxListTile(
                          title: const Text(
                              'I checked the roster and membership dates for this month.'),
                          value: prefs['review_members_$monthKey'] == true,
                          onChanged: (v) async {
                            prefs['review_members_$monthKey'] = v;
                            await persist();
                          })
                    ]),
                    section([
                      NavRow(
                          icon: Icons.upload_file_outlined,
                          title: 'Import or map school-approved layouts',
                          subtitle: 'Map once; reuse with each class',
                          onTap: () async {
                            await push(context, const TemplatesScreen());
                            await load();
                          }),
                      for (final form in templateForms.keys)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: AppCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                  Text(templateForms[form]!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                      key: ValueKey(
                                          '$form-${prefs['layout_$form']}'),
                                      initialValue: layout(form)?.id ?? '',
                                      isExpanded: true,
                                      items: [
                                        DropdownMenuItem(
                                            value: '',
                                            child: Text(presetAvailable(form)
                                                ? 'Pinned official reference edition'
                                                : 'Choose an imported layout')),
                                        for (final t in templates
                                            .where((t) => t.form == form))
                                          DropdownMenuItem(
                                              value: t.id,
                                              child: Text(t.name,
                                                  overflow:
                                                      TextOverflow.ellipsis))
                                      ],
                                      onChanged: (v) async {
                                        prefs['layout_$form'] = v;
                                        prefs['review_$form'] = false;
                                        await persist();
                                      }),
                                  if (presetAvailable(form) &&
                                      layout(form) == null)
                                    const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 8),
                                        child: Text(
                                            'This is a published reference edition, not a guarantee of current-year applicability. Confirm with your school before using it. Fixed row capacity is checked before export.')),
                                  if (layout(form) != null)
                                    TextButton(
                                        onPressed: () async {
                                          final t = layout(form)!;
                                          final bytes =
                                              await store.repo.templateBytes(t);
                                          if (bytes == null || !mounted) return;
                                          await push(
                                              context,
                                              TemplateMapScreen(
                                                  template: t,
                                                  bytes: bytes,
                                                  existing: true));
                                          prefs['review_$form'] = false;
                                          await persist();
                                        },
                                        child:
                                            const Text('Review cell mapping')),
                                  CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: prefs['review_$form'] == true &&
                                          prefs['review_stamp_$form'] ==
                                              reviewStamp(form),
                                      onChanged: (v) async {
                                        prefs['review_$form'] = v;
                                        prefs['review_stamp_$form'] =
                                            reviewStamp(form);
                                        await persist();
                                      },
                                      title: const Text(
                                          'I checked that this edition and mapping match my school requirements.'))
                                ]))),
                    ]),
                    section([
                      DropdownButtonFormField<String>(
                          initialValue: recordsForm,
                          decoration: const InputDecoration(
                              labelText: 'Verified record type'),
                          items: [
                            for (final f in recordFields.keys)
                              DropdownMenuItem(
                                  value: f, child: Text(templateForms[f]!))
                          ],
                          onChanged: (v) => setState(() => recordsForm = v!)),
                      const SizedBox(height: 12),
                      const Text(
                          'Store verified source records once, then reuse them in a mapped school-approved layout. Include all required sections, personnel or learner history rows. A class roster alone cannot establish school-wide coverage.'),
                      FilledButton.icon(
                          onPressed: () => editRecord(),
                          icon: const Icon(Icons.add),
                          label: const Text('Add verified row')),
                      if (recordsForm == 'sf10')
                        TextButton.icon(
                            onPressed: captureCurrentGrades,
                            icon: const Icon(Icons.history_edu_outlined),
                            label: const Text(
                                'Reuse completed report-card grades')),
                      TextButton.icon(
                          onPressed: importRecords,
                          icon: const Icon(Icons.content_paste_outlined),
                          label: const Text('Paste verified rows from Excel')),
                      if (recordData[recordsForm]?['previous_rows'] != null)
                        TextButton(
                            onPressed: undoRecords,
                            child: const Text('Undo last record change')),
                      TextButton(
                          onPressed: confirmRecords,
                          child:
                              const Text('Review coverage and confirm rows')),
                      for (final entry
                          in ((recordData[recordsForm]?['rows'] as List?) ?? [])
                              .indexed)
                        NavRow(
                            icon: Icons.fact_check_outlined,
                            title: (entry.$2 as Map)
                                .entries
                                .where((e) => [
                                      'record_section',
                                      'person_name',
                                      'record_name',
                                      'record_grade',
                                      'record_area'
                                    ].contains(e.key))
                                .map((e) => e.value)
                                .join(' · '),
                            subtitle:
                                'Source: ${(entry.$2 as Map)['record_source'] ?? 'Missing'}',
                            trailing: IconButton(
                                tooltip: 'Remove saved row',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => removeRecord(entry.$1)),
                            onTap: () => editRecord(index: entry.$1)),
                    ]),
                  ]))));
}
