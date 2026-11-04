import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/class_list.dart';
import '../../core/db.dart';
import '../../core/export/form_data.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../widgets.dart';

const statusLabels = {
  'active': 'Active',
  'transferred_in': 'Transferred in',
  'transferred_out': 'Transferred out',
  'dropped': 'Dropped out',
};

class LearnersScreen extends StatelessWidget {
  const LearnersScreen({super.key, required this.cls});
  final SchoolClass cls;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ClassTitle('Learners', cls),
        actions: [
          IconButton(
            tooltip: 'Add class list',
            icon: const Icon(Icons.content_paste_go_outlined),
            onPressed: () => push(context, ImportLearnersScreen(cls: cls)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => push(context, LearnerFormScreen(cls: cls)),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add learner'),
      ),
      body: Loader<List<Learner>>(
        load: () => store.repo.learners(cls.id),
        builder: (context, list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.people_alt_outlined,
              title: 'No learners yet',
              message: 'Add the whole class list from an Excel file, SF1 or LIS, or add learners one by one.',
              action: FilledButton.icon(
                onPressed: () => push(context, ImportLearnersScreen(cls: cls)),
                icon: const Icon(Icons.content_paste_go_outlined),
                label: const Text('Add class list'),
              ),
            );
          }
          final males = list.where((l) => l.sex == 'M').toList();
          final females = list.where((l) => l.sex == 'F').toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
            SectionTitle('Male (${males.length})'),
            for (final l in males) _tile(context, l),
            SectionTitle('Female (${females.length})'),
            for (final l in females) _tile(context, l),
          ]);
        },
      ),
    );
  }

  Widget _tile(BuildContext context, Learner l) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          onTap: () => push(context, LearnerFormScreen(cls: cls, existing: l)),
          child: Row(children: [
            SizedBox(
              width: 34,
              child: Text(two(l.num), style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(l.lrn.isEmpty ? 'No LRN yet' : 'LRN ${l.lrn}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            if (l.status != 'active') Pill(statusLabels[l.status] ?? l.status, color: l.isActive ? goodGreen : penRed),
          ]),
        ),
      );
}

class LearnerFormScreen extends StatefulWidget {
  const LearnerFormScreen({super.key, required this.cls, this.existing});
  final SchoolClass cls;
  final Learner? existing;

  @override
  State<LearnerFormScreen> createState() => _LearnerFormScreenState();
}

class _LearnerFormScreenState extends State<LearnerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late Learner _l;
  late final TextEditingController _birth;

  Learner _blank(String sex) => Learner(id: newId(), classId: widget.cls.id, num: 0, last: '', first: '', sex: sex);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _l = e == null ? _blank('M') : Learner.fromMap(e.toMap());
    _birth = TextEditingController(text: _l.birth);
  }

  @override
  void dispose() {
    _birth.dispose();
    super.dispose();
  }

  Future<void> _save({bool another = false}) async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    if (widget.existing == null) {
      await store.repo.addLearners(widget.cls.id, [_l]);
    } else {
      await store.repo.saveLearner(_l);
    }
    store.changed();
    if (!mounted) return;
    if (another) {
      toast(context, 'Added ${_l.fullName}.', success: true);
      setState(() => _l = _blank(_l.sex));
      _birth.clear();
      _formKey.currentState!.reset();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _pickBirth() async {
    final today = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_birth.text) ?? DateTime(today.year - 12),
      firstDate: DateTime(today.year - 70),
      lastDate: today,
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (d != null) setState(() => _birth.text = dayKey(d));
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: 'Remove ${_l.fullName}?',
        message: 'This deletes the learner with all attendance, scores and checked papers. To keep records of a learner who left, set the status to Transferred out or Dropped out instead.');
    if (!ok) return;
    await store.repo.deleteLearner(_l.id);
    store.changed();
    if (mounted) Navigator.pop(context);
  }

  Widget _text(String label, String value, void Function(String) save, {bool required = false, TextInputType? type, String? hint, String? Function(String?)? check}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          initialValue: value,
          keyboardType: type,
          textCapitalization: type == null ? TextCapitalization.words : TextCapitalization.none,
          decoration: InputDecoration(labelText: required ? '$label *' : label, hintText: hint),
          validator: check ?? (required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null),
          onSaved: (v) => save((v ?? '').trim()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit learner' : 'Add learner'),
        actions: [if (editing) IconButton(onPressed: _delete, icon: Icon(Icons.delete_outline, color: penRed), tooltip: 'Delete')],
      ),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          _text('Last name', _l.last, (v) => _l.last = v, required: true),
          _text('First name', _l.first, (v) => _l.first = v, required: true),
          _text('Middle name', _l.middle, (v) => _l.middle = v),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'M', label: Text('Male')), ButtonSegment(value: 'F', label: Text('Female'))],
            selected: {_l.sex},
            onSelectionChanged: (s) => setState(() => _l.sex = s.first),
          ),
          const SizedBox(height: 12),
          _text('LRN (12 digits)', _l.lrn, (v) => _l.lrn = v,
              type: TextInputType.number, check: (v) => (v ?? '').trim().isEmpty || RegExp(r'^\d{12}$').hasMatch(v!.trim()) ? null : 'An LRN has 12 digits'),
          if (editing) ...[
            DropdownButtonFormField<String>(
              value: _l.status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: [for (final e in statusLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _l.status = v!),
            ),
            const SizedBox(height: 4),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            maintainState: true,
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            title: const Text('More details', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Birth date, address and guardian, used in SF1'),
            children: [
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _birth,
                  readOnly: true,
                  onTap: _pickBirth,
                  decoration: InputDecoration(
                    labelText: 'Birth date',
                    suffixIcon: _birth.text.isEmpty
                        ? const Icon(Icons.calendar_today_outlined)
                        : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close), onPressed: () => setState(_birth.clear)),
                  ),
                  onSaved: (v) => _l.birth = (v ?? '').trim(),
                ),
              ),
              _text('Address', _l.address, (v) => _l.address = v),
              _text('Parent / guardian', _l.guardian, (v) => _l.guardian = v),
              _text('Contact number', _l.contact, (v) => _l.contact = v, type: TextInputType.phone),
              _text('Remarks', _l.remarks, (v) => _l.remarks = v),
            ],
          ),
          const SizedBox(height: 12),
          if (editing)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Learner number ${two(_l.num)} is printed on answer sheets so the scanner knows whose paper it is.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          FilledButton(onPressed: _save, child: Text(editing ? 'Save' : 'Add learner')),
          if (!editing) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => _save(another: true), child: const Text('Add and enter another')),
          ],
        ]),
      ),
    );
  }
}

/// Adds a class list from an Excel, CSV or text file, or from pasted text. Names already on the
/// list are left out, so adding the same list twice is harmless.
class ImportLearnersScreen extends StatefulWidget {
  const ImportLearnersScreen({super.key, required this.cls});
  final SchoolClass cls;

  @override
  State<ImportLearnersScreen> createState() => _ImportLearnersScreenState();
}

class _ImportLearnersScreenState extends State<ImportLearnersScreen> {
  final _text = TextEditingController();
  ClassListResult _result = const ClassListResult([], []);
  Set<String> _existing = {};
  String? _fallbackSex;

  String _key(String last, String first) => '${last.trim().toLowerCase()}|${first.trim().toLowerCase()}';

  @override
  void initState() {
    super.initState();
    store.repo.learners(widget.cls.id).then((list) {
      if (mounted) setState(() => _existing = {for (final l in list) _key(l.last, l.first)});
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _parse() => setState(() => _result = parseClassList(_text.text));

  /// New names only, each one once.
  List<ClassListRow> get _fresh {
    final seen = <String>{..._existing};
    return [for (final r in _result.rows) if (seen.add(_key(r.last, r.first))) r];
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx', 'csv', 'txt'], withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;
    try {
      _text.text = (f.extension ?? '').toLowerCase() == 'xlsx' ? xlsxToText(bytes) : utf8.decode(bytes, allowMalformed: true);
      _parse();
      if (mounted && _result.rows.isEmpty) toast(context, 'No names were found in this file. Names should look like: Dela Cruz, Juan.');
    } catch (_) {
      if (mounted) toast(context, 'This file could not be read. Save it as .xlsx, or copy the names and paste them here.');
    }
  }

  Future<void> _import(List<ClassListRow> rows) async {
    if (rows.any((r) => r.sex == null) && _fallbackSex == null) {
      toast(context, 'Choose male or female for the names that do not say.');
      return;
    }
    final learners = [
      for (final r in rows)
        Learner(id: newId(), classId: widget.cls.id, num: 0, last: r.last, first: r.first, middle: r.middle, sex: r.sex ?? _fallbackSex!, lrn: r.lrn),
    ];
    await store.repo.addLearners(widget.cls.id, learners);
    store.changed();
    if (mounted) {
      toast(context, learners.length == 1 ? 'Added 1 learner.' : 'Added ${learners.length} learners.', success: true);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fresh = _fresh;
    final noSex = fresh.where((r) => r.sex == null).length;
    final repeated = _result.rows.length - fresh.length;
    return Scaffold(
      appBar: AppBar(title: ClassTitle('Add class list', widget.cls)),
      bottomNavigationBar: fresh.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: FilledButton(onPressed: () => _import(fresh), child: Text(fresh.length == 1 ? 'Add 1 learner' : 'Add ${fresh.length} learners')),
              ),
            ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        OutlinedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Choose a file (Excel, CSV or text)'),
        ),
        const SizedBox(height: 14),
        Text('Or paste the names, one learner per line:', style: TextStyle(color: mutedText(context))),
        const SizedBox(height: 8),
        TextField(
          controller: _text,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(hintText: 'Dela Cruz, Juan, Santos, M, 109345120031\nReyes, Liza, , F', alignLabelWithHint: true),
          onChanged: (_) => _parse(),
        ),
        const SizedBox(height: 6),
        Text('Numbers, ages and dates are ignored. "MALE" and "FEMALE" heading lines work too.', style: TextStyle(fontSize: 12, color: mutedText(context))),
        if (noSex > 0) ...[
          const SizedBox(height: 12),
          AppCard(
            color: lateAmber.withAlpha(isDark(context) ? 46 : 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(noSex == 1 ? '1 name does not say male or female. It is:' : '$noSex names do not say male or female. They are:', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                emptySelectionAllowed: true,
                segments: const [ButtonSegment(value: 'M', label: Text('Male')), ButtonSegment(value: 'F', label: Text('Female'))],
                selected: {if (_fallbackSex != null) _fallbackSex!},
                onSelectionChanged: (s) => setState(() => _fallbackSex = s.isEmpty ? null : s.first),
              ),
            ]),
          ),
        ],
        if (_result.skipped.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${_result.skipped.length} ${_result.skipped.length == 1 ? 'line was' : 'lines were'} skipped because they have no "Last, First" name: '
            '${_result.skipped.take(3).map((s) => '"$s"').join(', ')}${_result.skipped.length > 3 ? '...' : ''}',
            style: TextStyle(fontSize: 13, color: penRed),
          ),
        ],
        if (repeated > 0) ...[
          const SizedBox(height: 8),
          Text(repeated == 1 ? '1 name is already on the list and will be left out.' : '$repeated names are already on the list and will be left out.',
              style: TextStyle(fontSize: 13, color: mutedText(context))),
        ],
        if (fresh.isNotEmpty) ...[
          SectionTitle(fresh.length == 1 ? '1 learner ready' : '${fresh.length} learners ready'),
          for (final r in fresh)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 14, child: Text(r.sex ?? _fallbackSex ?? '?', style: const TextStyle(fontSize: 12))),
              title: Text([r.last, r.first, r.middle].where((s) => s.isNotEmpty).join(', ')),
              subtitle: r.lrn.isEmpty ? null : Text('LRN ${r.lrn}'),
            ),
        ],
      ]),
    );
  }
}
