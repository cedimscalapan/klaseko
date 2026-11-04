import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/grading.dart';
import '../../core/models.dart';
import '../../core/plan.dart';
import '../settings/plan_screen.dart';
import '../widgets.dart';
import 'class_detail_screen.dart';

const gradeLevels = ['Kindergarten', 'Grade 1', 'Grade 2', 'Grade 3', 'Grade 4', 'Grade 5', 'Grade 6', 'Grade 7', 'Grade 8', 'Grade 9', 'Grade 10', 'Grade 11', 'Grade 12'];

const commonSubjects = [
  'Filipino', 'English', 'Mathematics', 'Science', 'Araling Panlipunan', 'GMRC', 'Values Education', 'MAPEH', 'Music and Arts',
  'Physical Education and Health', 'EPP', 'Technology and Livelihood Education', 'Makabansa', 'Language', 'Reading and Literacy',
];

/// Suggests the DO 015, s. 2026 preset for a subject.
String suggestPreset(String grade, String subject) {
  final g = int.tryParse(grade.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  final s = subject.toLowerCase();
  if (g >= 11) return 'shs_core';
  if (s.contains('mapeh') || s.contains('music') || s.contains('physical') || s.contains('health') || s.contains('epp') || s.contains('tle') ||
      s.contains('technology')) {
    return 'mapeh';
  }
  if (s.contains('makabansa')) return 'makabansa';
  return 'core';
}

class ClassFormScreen extends StatefulWidget {
  const ClassFormScreen({super.key, this.existing});
  final SchoolClass? existing;

  @override
  State<ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends State<ClassFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _grade;
  late final TextEditingController _section;
  late final TextEditingController _subject;
  late String _preset;
  late double _ww, _pt, _ex;
  late bool _exSplit;
  late String _transmute;
  late String _mode;
  late bool _advisory;
  bool _presetTouched = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _grade = c?.grade ?? 'Grade 7';
    _section = TextEditingController(text: c?.section ?? '');
    _subject = TextEditingController(text: c?.subject ?? '');
    _preset = c?.preset ?? 'core';
    _ww = c?.ww ?? 20;
    _pt = c?.pt ?? 50;
    _ex = c?.ex ?? 30;
    _exSplit = c?.exSplit ?? true;
    _transmute = c?.transmute ?? 'table2026';
    _mode = c?.mode ?? 'numeric';
    _advisory = c?.advisory ?? false;
    _presetTouched = c != null;
    if (c == null) _startFromLastClass();
  }

  /// Teachers often have several sections of one subject, so a new class starts like the last one.
  Future<void> _startFromLastClass() async {
    final classes = await store.repo.classes();
    final plan = await Plan.status();
    if (!mounted) return;
    if (!plan.plus && classes.where((c) => !c.section.contains('(Sample)')).length >= freeClasses) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PlanScreen(reason: 'The free plan has $freeClasses classes. Get Plus to add more. Your classes stay as they are.')),
      );
      return;
    }
    if (classes.isEmpty || _subject.text.isNotEmpty) return;
    setState(() {
      _setGrade(classes.last.grade);
      _subject.text = classes.last.subject;
    });
    _autoPreset();
  }

  void _setGrade(String grade) {
    _grade = grade;
    _mode = grade == 'Grade 1' || grade == 'Kindergarten' ? 'descriptive' : 'numeric';
  }

  @override
  void dispose() {
    _section.dispose();
    _subject.dispose();
    super.dispose();
  }

  void _applyPreset(String id) {
    final p = presetById(id);
    setState(() {
      _preset = id;
      if (id != 'custom') {
        _ww = p.ww;
        _pt = p.pt;
        _ex = p.ex;
        _exSplit = p.exSplit;
        _transmute = p.transmute;
      }
    });
  }

  void _autoPreset() {
    if (_presetTouched) return;
    _applyPreset(suggestPreset(_grade, _subject.text));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if ((_ww + _pt + _ex - 100).abs() > 0.01) {
      toast(context, 'Weights must add up to 100%. They add up to ${(_ww + _pt + _ex).toStringAsFixed(0)}%.');
      return;
    }
    final c = widget.existing ??
        SchoolClass(
          id: newId(),
          sy: store.profile.sy,
          grade: _grade,
          section: '',
          subject: '',
          preset: _preset,
          ww: _ww,
          pt: _pt,
          ex: _ex,
          exSplit: _exSplit,
          transmute: _transmute,
          mode: _mode,
          advisory: _advisory,
          created: now(),
        );
    c
      ..grade = _grade
      ..section = _section.text.trim()
      ..subject = _subject.text.trim()
      ..preset = _preset
      ..ww = _ww
      ..pt = _pt
      ..ex = _ex
      ..exSplit = _exSplit
      ..transmute = _transmute
      ..mode = _mode
      ..advisory = _advisory;
    await store.repo.saveClass(c);
    store.changed();
    if (!mounted) return;
    if (widget.existing != null) {
      Navigator.pop(context, c);
    } else {
      // The next step for a new class is adding its learners, which starts on the class page.
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ClassDetailScreen(classId: c.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit class' : 'New class')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          DropdownButtonFormField<String>(
            value: _grade,
            decoration: const InputDecoration(labelText: 'Grade level'),
            items: [for (final g in gradeLevels) DropdownMenuItem(value: g, child: Text(g))],
            onChanged: (v) {
              setState(() => _setGrade(v!));
              _autoPreset();
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _section,
            autofocus: !editing,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Section *', hintText: 'e.g. Sampaguita'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter the section' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _subject,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Subject / learning area *', hintText: 'e.g. Mathematics'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter the subject' : null,
            onChanged: (_) => _autoPreset(),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final s in commonSubjects)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(s),
                    onPressed: () {
                      setState(() => _subject.text = s);
                      _autoPreset();
                    },
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _advisory,
            onChanged: (v) => setState(() => _advisory = v),
            title: const Text('This is my advisory class', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Turns on SF1, SF2 and SF9 for this class.'),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            maintainState: true,
            initiallyExpanded: _preset == 'custom',
            title: const Text('Grading rules', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('WW ${_ww.toInt()} / PT ${_pt.toInt()} / EX ${_ex.toInt()} · ${_mode == 'descriptive' ? 'letter grades' : 'numerical grades'}. Set for you from the grade and subject.'),
            children: [
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                value: _preset,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Learning area weights'),
                items: [
                  for (final p in weightPresets)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.id == 'custom' ? p.label : '${p.label} (${p.ww.toInt()}/${p.pt.toInt()}/${p.ex.toInt()})', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  _presetTouched = true;
                  _applyPreset(v!);
                },
              ),
              const SizedBox(height: 4),
              Text('Source: ${presetById(_preset).group}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (_preset == 'custom') ...[
                const SizedBox(height: 12),
                Row(children: [
                  for (final (label, value, setter) in [
                    ('Written Work %', _ww, (double v) => _ww = v),
                    ('Perf. Tasks %', _pt, (double v) => _pt = v),
                    ('Exams %', _ex, (double v) => _ex = v),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: TextFormField(
                          key: ValueKey('$label$_preset'),
                          initialValue: value.toStringAsFixed(0),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: label),
                          onChanged: (v) => setState(() => setter(double.tryParse(v) ?? 0)),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _exSplit,
                  onChanged: (v) => setState(() => _exSplit = v),
                  title: const Text('Split exams into ST1 30%, ST2 30%, Term Exam 40%'),
                  subtitle: const Text('Required by DO 015, s. 2026 for most learning areas.'),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _transmute,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Transmutation'),
                items: [for (final e in transmuteLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _transmute = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _mode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Report as'),
                items: const [
                  DropdownMenuItem(value: 'numeric', child: Text('Numerical grades (Grades 2-12)')),
                  DropdownMenuItem(value: 'descriptive', child: Text('Letter grades A-E (Key Stage 1, Grade 1)')),
                ],
                onChanged: (v) => setState(() => _mode = v!),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: Text(editing ? 'Save changes' : 'Create class')),
        ]),
      ),
    );
  }
}
