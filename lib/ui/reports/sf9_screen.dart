import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/export/form_data.dart';
import '../../core/export/pdf_docs.dart';
import '../../core/models.dart';
import '../pdf_preview_screen.dart';
import '../theme.dart';
import '../widgets.dart';

Future<List<String>> loadAreas(SchoolClass cls) async {
  final s = await store.repo.settings();
  final raw = s['sf9_areas_${cls.id}'];
  if (raw == null || raw.isEmpty) return defaultAreas(cls.grade);
  return (jsonDecode(raw) as List).map((e) => e.toString()).toList();
}

Future<void> saveAreas(SchoolClass cls, List<String> areas) => store.repo.putSettings({'sf9_areas_${cls.id}': jsonEncode(areas)});

class Sf9Screen extends StatelessWidget {
  const Sf9Screen({super.key, required this.cls});
  final SchoolClass cls;

  Future<(List<Learner>, List<String>, Map<String, Map<String, Map<int, String>>>)> _load() async {
    final learners = (await store.repo.learners(cls.id)).where((l) => l.status != 'dropped').toList();
    return (learners, await loadAreas(cls), await store.repo.sf9Grades(learners.map((l) => l.id).toList()));
  }

  void _pdf(BuildContext context, List<Learner> learners, List<String> areas, String name) {
    push(
      context,
      PdfPreviewScreen(
        title: 'SF9 report cards',
        fileName: 'SF9 $name.pdf',
        build: () async => buildSf9Pdf(await buildSf9Data(store.repo, store.profile, cls, learners, areas)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Loader<(List<Learner>, List<String>, Map<String, Map<String, Map<int, String>>>)>(
      load: _load,
      builder: (context, data) {
        final (learners, areas, grades) = data;
        final other = areas.where((a) => a.trim().toLowerCase() != cls.subject.trim().toLowerCase()).length;
        return Scaffold(
          appBar: AppBar(
            title: ClassTitle('SF9 · Report cards', cls),
            actions: [
              IconButton(
                tooltip: 'Learning areas',
                icon: const Icon(Icons.list_alt_outlined),
                onPressed: () => push(context, AreasScreen(cls: cls, areas: areas)),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: FilledButton.icon(
                onPressed: learners.isEmpty ? null : () => _pdf(context, learners, areas, cls.title),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text('Report cards for all ${learners.length} learners'),
              ),
            ),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            AppCard(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                'Attendance and every subject you handle in this section fill in by themselves from the class records. '
                'Type only the grades co-teachers give you for other learning areas, and rate the core values each term.',
              ),
            ),
            const SectionTitle('Learners'),
            for (final l in learners)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  onTap: () => push(context, Sf9LearnerScreen(cls: cls, learner: l, areas: areas)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${grades[l.id]?.length ?? 0} of $other other areas entered',
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Report card PDF',
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      onPressed: () => _pdf(context, [l], areas, l.fullName),
                    ),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}

/// Edit the learning areas printed on the report card. Indented lines are MAPEH components.
class AreasScreen extends StatefulWidget {
  const AreasScreen({super.key, required this.cls, required this.areas});
  final SchoolClass cls;
  final List<String> areas;

  @override
  State<AreasScreen> createState() => _AreasScreenState();
}

class _AreasScreenState extends State<AreasScreen> {
  late final _text = TextEditingController(text: widget.areas.map((a) => a.startsWith('  ') ? '- ${a.trim()}' : a).join('\n'));

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Learning areas'),
        actions: [
          TextButton(
            onPressed: () async {
              final list = _text.text
                  .split('\n')
                  .map((s) => s.trimRight())
                  .where((s) => s.trim().isNotEmpty)
                  .map((s) => s.trimLeft().startsWith('-') ? '  ${s.trimLeft().substring(1).trim()}' : s.trim())
                  .toList();
              await saveAreas(widget.cls, list);
              store.changed();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('One learning area per line, in report card order. Start a line with "-" for a MAPEH component; components are shown but not counted in the general average.'),
        const SizedBox(height: 12),
        TextField(controller: _text, minLines: 10, maxLines: 20),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => setState(() => _text.text = defaultAreas(widget.cls.grade).map((a) => a.startsWith('  ') ? '- ${a.trim()}' : a).join('\n')),
          child: Text('Reset to ${widget.cls.grade} defaults'),
        ),
      ]),
    );
  }
}

const valueRatings = ['AO', 'SO', 'RO', 'NO'];

class Sf9LearnerScreen extends StatefulWidget {
  const Sf9LearnerScreen({super.key, required this.cls, required this.learner, required this.areas});
  final SchoolClass cls;
  final Learner learner;
  final List<String> areas;

  @override
  State<Sf9LearnerScreen> createState() => _Sf9LearnerScreenState();
}

class _Sf9LearnerScreenState extends State<Sf9LearnerScreen> {
  Map<String, Map<int, String>> _grades = {};
  Map<int, Map<int, String>> _values = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Grades are saved as they are typed; refresh the other screens once on leaving.
    WidgetsBinding.instance.addPostFrameCallback((_) => store.changed());
    super.dispose();
  }

  Future<void> _load() async {
    final g = await store.repo.sf9Grades([widget.learner.id]);
    final v = await store.repo.sf9Values(widget.learner.id);
    if (!mounted) return;
    setState(() {
      _grades = g[widget.learner.id] ?? {};
      _values = v;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final terms = store.profile.terms;
    final descriptive = widget.cls.mode == 'descriptive';
    return Scaffold(
      appBar: AppBar(title: Text(widget.learner.fullName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
              const SectionTitle('Learning areas'),
              Text(descriptive ? 'Enter letter grades A to E.' : 'Enter whole-number grades. The final grade is computed when all terms are filled.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              for (final raw in widget.areas) _areaRow(raw.trim(), raw.startsWith('  '), terms),
              const SectionTitle("Learner's observed values"),
              for (var i = 0; i < coreValues.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(coreValues[i][0], style: TextStyle(fontWeight: FontWeight.w800, color: brandBlue)),
                      Text(coreValues[i][1], style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(children: [
                        for (var t = 1; t <= terms; t++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: DropdownButtonFormField<String>(
                                value: valueRatings.contains(_values[i]?[t]) ? _values[i]![t] : null,
                                isDense: true,
                                decoration: InputDecoration(labelText: store.profile.termLabel(t), isDense: true),
                                items: [for (final r in valueRatings) DropdownMenuItem(value: r, child: Text(r))],
                                onChanged: (v) async {
                                  if (v == null) return;
                                  (_values[i] ??= {})[t] = v;
                                  await store.repo.setSf9Value(widget.learner.id, i, t, v);
                                  store.changed();
                                },
                              ),
                            ),
                          ),
                      ]),
                    ]),
                  ),
                ),
              Text('AO Always Observed · SO Sometimes Observed · RO Rarely Observed · NO Not Observed',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
    );
  }

  Widget _areaRow(String area, bool component, int terms) {
    final own = area.toLowerCase() == widget.cls.subject.trim().toLowerCase();
    return Padding(
      padding: EdgeInsets.only(bottom: 8, left: component ? 16 : 0),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(area, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (own)
            Text('From your class record. You can still type an override below.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 8),
          Row(children: [
            for (var t = 1; t <= terms; t++) _gradeField(area, t, store.profile.termLabel(t)),
            _gradeField(area, 0, 'Final'),
          ]),
        ]),
      ),
    );
  }

  Widget _gradeField(String area, int term, String label) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: TextFormField(
            initialValue: _grades[area]?[term] ?? '',
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            keyboardType: widget.cls.mode == 'descriptive' ? TextInputType.text : TextInputType.number,
            decoration: InputDecoration(labelText: label, isDense: true, hintText: term == 0 ? 'auto' : null),
            onChanged: (v) async {
              final value = v.trim().toUpperCase();
              (_grades[area] ??= {})[term] = value;
              await store.repo.setSf9Grade(widget.learner.id, area, term, value);
            },
          ),
        ),
      );
}
