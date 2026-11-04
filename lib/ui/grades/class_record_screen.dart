import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/export/share.dart';
import '../../core/export/xlsx_docs.dart';
import '../../core/grading.dart';
import '../../core/models.dart';
import '../exams/exam_detail_screen.dart';
import '../forms/archive_info.dart';
import '../theme.dart';
import '../widgets.dart';
import 'score_entry_screen.dart';

class RecordData {
  final List<Learner> learners;
  final List<Activity> activities;
  final GradeEngine engine;
  RecordData(this.learners, this.activities, this.engine);
}

Future<RecordData> loadRecord(SchoolClass cls) async {
  final repo = store.repo;
  final fresh = await repo.classById(cls.id) ?? cls;
  final acts = await repo.activities(cls.id);
  final learners = (await repo.learners(cls.id)).where((l) => l.isActive).toList();
  return RecordData(learners, acts, GradeEngine(fresh, acts, await repo.scores(cls.id), overrides: await repo.overrides(cls.id)));
}

class ClassRecordScreen extends StatefulWidget {
  const ClassRecordScreen({super.key, required this.cls});
  final SchoolClass cls;

  @override
  State<ClassRecordScreen> createState() => _ClassRecordScreenState();
}

class _ClassRecordScreenState extends State<ClassRecordScreen> {
  int? _term; // null = the latest term with activities, 0 = final

  int _shown(RecordData d) => _term ?? min(latestTerm(d.activities), store.profile.terms);

  Future<void> _export(RecordData d) async {
    await withProgress(context, 'Making the class record...', () async {
      final bytes = buildClassRecordXlsx(store.profile, d.engine.cls, d.learners, d.engine);
      await shareAndArchive(ArchiveInfo(widget.cls, 'record'), bytes, 'Class Record ${widget.cls.subject} ${widget.cls.title}.xlsx', xlsxMime);
    });
  }

  @override
  Widget build(BuildContext context) {
    final terms = store.profile.terms;
    return Loader<RecordData>(
      load: () => loadRecord(widget.cls),
      builder: (context, d) => Scaffold(
        appBar: AppBar(
          title: ClassTitle('Class record', widget.cls),
          actions: [IconButton(tooltip: 'Export to Excel', icon: const Icon(Icons.ios_share), onPressed: () => _export(d))],
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 28), children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (var t = 1; t <= terms; t++) ButtonSegment(value: t, label: Text(store.profile.termLabel(t))),
              const ButtonSegment(value: 0, label: Text('Final')),
            ],
            selected: {_shown(d)},
            onSelectionChanged: (s) => setState(() => _term = s.first),
          ),
          if (_shown(d) == 0) ..._finalView(context, d) else ..._termView(context, d, _shown(d)),
        ]),
      ),
    );
  }

  List<Widget> _termView(BuildContext context, RecordData d, int term) {
    final cls = d.engine.cls;
    final acts = d.activities.where((a) => a.term == term).toList();
    return [
      for (final comp in ['ww', 'pt', 'ex'])
        if (d.engine.weightOf(comp) > 0) ...[
          SectionTitle(
            '${compLabels[comp]} · ${d.engine.weightOf(comp).toInt()}%',
            trailing: TextButton.icon(
              onPressed: () => showActivitySheet(context, cls, term: term, comp: comp),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ),
          if (acts.where((a) => a.comp == comp).isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(comp == 'ex' && cls.exSplit ? 'No exams yet. Add Summative Test 1, Summative Test 2 and the Term Examination.' : 'No activities yet.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          for (final a in acts.where((a) => a.comp == comp))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                onTap: a.examId != null
                    ? () => push(context, ExamDetailScreen(examId: a.examId!))
                    : () => push(context, ScoreEntryScreen(cls: cls, activity: a)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        [
                          if (a.sub.isNotEmpty) exSubLabels[a.sub] ?? a.sub,
                          'HPS ${fmtScore(a.hps)}',
                          '${d.learners.where((l) => d.engine.scores[a.id]?[l.id] != null).length}/${d.learners.length} scored',
                          if (a.examId != null) 'from exam',
                        ].join(' · '),
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ]),
                  ),
                  if (a.examId == null)
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          showActivitySheet(context, cls, term: term, existing: a);
                        } else if (v == 'delete') {
                          final ok = await confirm(context, title: 'Delete "${a.title}"?', message: 'All scores in this column will be removed.');
                          if (ok) {
                            await store.repo.deleteActivity(a.id);
                            store.changed();
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    )
                  else
                    const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.document_scanner_outlined, size: 20)),
                ]),
              ),
            ),
        ],
      SectionTitle('${store.profile.termName(term)} grades'),
      if (d.learners.isEmpty) const Text('Add learners to see grades.'),
      for (final l in d.learners) _gradeRow(context, d, l, term),
      const SizedBox(height: 8),
      Text(
        'Blank scores count as zero. A grade marked "running" leaves out components with no activities yet. '
        '${transmuteLabels[cls.transmute]}.',
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ];
  }

  Widget _gradeRow(BuildContext context, RecordData d, Learner l, int term) {
    final r = d.engine.term(l.id, term);
    final tg = r.termGrade;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        onTap: () => showBreakdown(context, d, l, term),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                r.hasData
                    ? 'WW ${_ps(r, 'ww')} · PT ${_ps(r, 'pt')} · EX ${_ps(r, 'ex')} · IG ${r.initialGrade.toStringAsFixed(2)}${r.incomplete ? ' · running' : ''}'
                    : 'No scores yet',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ]),
          ),
          if (r.missing > 0) Padding(padding: const EdgeInsets.only(right: 8), child: Pill('${r.missing} blank', color: lateAmber)),
          SizedBox(
            width: 52,
            child: Text(
              r.display,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: tg != null ? gradeColor(tg) : (r.letter == 'D' || r.letter == 'E' ? penRed : brandBlue)),
            ),
          ),
        ]),
      ),
    );
  }

  String _ps(TermResult r, String comp) {
    final ps = r.comps[comp]?.ps;
    return ps == null ? '-' : ps.toStringAsFixed(0);
  }

  List<Widget> _finalView(BuildContext context, RecordData d) {
    final terms = store.profile.terms;
    return [
      const SectionTitle('Final grades'),
      AppCard(
        padding: EdgeInsets.zero,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 18,
            headingRowHeight: 40,
            columns: [
              const DataColumn(label: Text('Learner')),
              for (var t = 1; t <= terms; t++) DataColumn(label: Text(store.profile.termLabel(t)), numeric: true),
              const DataColumn(label: Text('Final'), numeric: true),
              const DataColumn(label: Text('Remarks')),
            ],
            rows: [
              for (final l in d.learners)
                () {
                  final f = d.engine.finalGrade(l.id, terms);
                  return DataRow(cells: [
                    DataCell(Text(l.fullName)),
                    for (final t in f.terms) DataCell(Text(t.display)),
                    DataCell(Text(f.finalGrade?.toString() ?? f.letter ?? '',
                        style: TextStyle(fontWeight: FontWeight.w800, color: f.finalGrade == null ? null : gradeColor(f.finalGrade)))),
                    DataCell(Text(f.remarks)),
                  ]);
                }(),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('Final grade = average of the term grades, rounded to a whole number. Passing is 75 (DO 015, s. 2026).',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ];
  }
}

void showBreakdown(BuildContext context, RecordData d, Learner l, int term) {
  final r = d.engine.term(l.id, term);
  final cls = d.engine.cls;
  final controller = TextEditingController(text: d.engine.overrides[l.id]?[term] ?? '');
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text(store.profile.termName(term), style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        for (final c in ['ww', 'pt', 'ex'])
          if (d.engine.weightOf(c) > 0)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${compLabels[c]} (${d.engine.weightOf(c).toInt()}%)'),
              subtitle: Text(r.comps[c]!.hps == 0
                  ? 'No activities yet'
                  : '${fmtScore(r.comps[c]!.got)} / ${fmtScore(r.comps[c]!.hps)} · PS ${r.comps[c]!.ps!.toStringAsFixed(2)}'),
              trailing: Text(r.comps[c]!.ps == null ? '-' : 'WS ${(r.comps[c]!.ps! * d.engine.weightOf(c) / 100).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        const Divider(),
        Row(children: [
          const Expanded(child: Text('Initial grade', style: TextStyle(fontWeight: FontWeight.w600))),
          Text(r.initialGrade.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text(cls.mode == 'descriptive' ? 'Letter grade' : 'Term grade', style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(r.display, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: gradeColor(r.termGrade))),
        ]),
        if (r.termGrade != null) Text(descriptor(r.termGrade!, legacy: cls.legacyRules), style: TextStyle(color: gradeColor(r.termGrade))),
        if (cls.mode == 'descriptive') Text(ks1Letters[r.letter] ?? ''),
        const SizedBox(height: 14),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: cls.mode == 'descriptive' ? 'Set letter grade (A-E), blank = computed' : 'Override term grade, blank = computed',
            helperText: 'Use only for an approved adjustment. It is marked in your records.',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            final v = controller.text.trim().toUpperCase();
            if (v.isNotEmpty) {
              final ok = cls.mode == 'descriptive' ? ks1Letters.containsKey(v) : (int.tryParse(v) != null && int.parse(v) >= 60 && int.parse(v) <= 100);
              if (!ok) {
                toast(ctx, cls.mode == 'descriptive' ? 'Enter A, B, C, D or E.' : 'Enter a whole number from 60 to 100.');
                return;
              }
            }
            await store.repo.setOverride(cls.id, l.id, term, v);
            store.changed();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ]),
    ),
  );
}

Future<void> showActivitySheet(BuildContext context, SchoolClass cls, {required int term, String comp = 'ww', Activity? existing}) async {
  final title = TextEditingController(text: existing?.title ?? '');
  final hps = TextEditingController(text: existing == null ? '' : fmtScore(existing.hps));
  var c = existing?.comp ?? comp;
  var sub = existing?.sub.isNotEmpty == true ? existing!.sub : 'st1';
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(existing == null ? 'New activity · ${store.profile.termName(term)}' : 'Edit activity',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [for (final e in compShort.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {c},
            onSelectionChanged: (s) => setSheet(() => c = s.first),
          ),
          if (c == 'ex' && cls.exSplit) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: sub,
              decoration: const InputDecoration(labelText: 'Examination part'),
              items: [for (final e in exSubLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setSheet(() => sub = v!),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: title,
            autofocus: existing == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Title', hintText: c == 'ww' ? 'e.g. Quiz 1' : c == 'pt' ? 'e.g. Group project' : 'e.g. Summative Test 1'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: hps,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Highest possible score (HPS)'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final h = double.tryParse(hps.text.trim());
              if (title.text.trim().isEmpty || h == null || h <= 0) {
                toast(ctx, 'Enter a title and an HPS above 0.');
                return;
              }
              final a = existing ?? Activity(id: newId(), classId: cls.id, term: term, comp: c, title: '', hps: h, created: now());
              a
                ..comp = c
                ..sub = c == 'ex' ? (cls.exSplit ? sub : 'te') : ''
                ..title = title.text.trim()
                ..hps = h;
              await store.repo.saveActivity(a);
              store.changed();
              if (ctx.mounted) Navigator.pop(ctx);
              if (existing == null && context.mounted) push(context, ScoreEntryScreen(cls: cls, activity: a));
            },
            child: Text(existing == null ? 'Save and enter scores' : 'Save'),
          ),
        ]),
      ),
    ),
  );
}
