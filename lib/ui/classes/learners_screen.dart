import 'package:flutter/material.dart';

import '../../core/db.dart';
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
        title: const Text('Learners'),
        actions: [
          IconButton(
            tooltip: 'Paste class list',
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
              message: 'Paste the class list from SF1 or LIS, or add learners one by one.',
              action: FilledButton.icon(
                onPressed: () => push(context, ImportLearnersScreen(cls: cls)),
                icon: const Icon(Icons.content_paste_go_outlined),
                label: const Text('Paste class list'),
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

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _l = e == null
        ? Learner(id: newId(), classId: widget.cls.id, num: 0, last: '', first: '', sex: 'M')
        : Learner.fromMap(e.toMap());
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    if (widget.existing == null) {
      await store.repo.addLearners(widget.cls.id, [_l]);
    } else {
      await store.repo.saveLearner(_l);
    }
    store.changed();
    if (mounted) Navigator.pop(context);
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

  Widget _text(String label, String value, void Function(String) save, {bool required = false, TextInputType? type, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          initialValue: value,
          keyboardType: type,
          textCapitalization: type == null ? TextCapitalization.words : TextCapitalization.none,
          decoration: InputDecoration(labelText: required ? '$label *' : label, hintText: hint),
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
          onSaved: (v) => save((v ?? '').trim()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit learner' : 'Add learner'),
        actions: [if (editing) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline, color: penRed), tooltip: 'Delete')],
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
          _text('LRN (12 digits)', _l.lrn, (v) => _l.lrn = v, type: TextInputType.number),
          _text('Birth date', _l.birth, (v) => _l.birth = v, type: TextInputType.datetime, hint: 'yyyy-mm-dd'),
          _text('Address', _l.address, (v) => _l.address = v),
          _text('Parent / guardian', _l.guardian, (v) => _l.guardian = v),
          _text('Contact number', _l.contact, (v) => _l.contact = v, type: TextInputType.phone),
          DropdownButtonFormField<String>(
            value: _l.status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [for (final e in statusLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _l.status = v!),
          ),
          const SizedBox(height: 12),
          _text('Remarks', _l.remarks, (v) => _l.remarks = v),
          if (editing)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Learner number ${two(_l.num)} is printed on answer sheets so the scanner knows whose paper it is.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          FilledButton(onPressed: _save, child: Text(editing ? 'Save' : 'Add learner')),
        ]),
      ),
    );
  }
}

/// Paste a class list, one learner per line: "Last, First, Middle, M/F, LRN" (middle and LRN optional).
/// Tab-separated rows copied from Excel or LIS also work.
class ImportLearnersScreen extends StatefulWidget {
  const ImportLearnersScreen({super.key, required this.cls});
  final SchoolClass cls;

  @override
  State<ImportLearnersScreen> createState() => _ImportLearnersScreenState();
}

class _ImportLearnersScreenState extends State<ImportLearnersScreen> {
  final _text = TextEditingController();
  List<Learner> _parsed = [];
  List<String> _errors = [];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _parse() {
    final out = <Learner>[];
    final errors = <String>[];
    final lines = _text.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    for (var i = 0; i < lines.length; i++) {
      final parts = lines[i].split(RegExp(r'\t|,')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      String? lrn;
      String? sex;
      final names = <String>[];
      for (final p in parts) {
        final up = p.toUpperCase();
        if (RegExp(r'^\d{6,}$').hasMatch(p)) {
          lrn = p;
        } else if (up == 'M' || up == 'F' || up == 'MALE' || up == 'FEMALE') {
          sex = up.substring(0, 1);
        } else {
          names.add(p);
        }
      }
      if (names.length < 2 || sex == null) {
        errors.add('Line ${i + 1}: "${lines[i]}" needs at least Last name, First name and M or F.');
        continue;
      }
      out.add(Learner(
        id: newId(),
        classId: widget.cls.id,
        num: 0,
        last: names[0],
        first: names[1],
        middle: names.length > 2 ? names[2] : '',
        sex: sex,
        lrn: lrn ?? '',
      ));
    }
    setState(() {
      _parsed = out;
      _errors = errors;
    });
  }

  Future<void> _import() async {
    await store.repo.addLearners(widget.cls.id, _parsed);
    store.changed();
    if (mounted) {
      toast(context, 'Added ${_parsed.length} learners.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paste class list')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('One learner per line. Example:', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: const SelectableText('Dela Cruz, Juan, Santos, M, 109345120031\nReyes, Liza, , F\nTorres, Ben, Lopez, Male',
              style: TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          minLines: 8,
          maxLines: 16,
          decoration: const InputDecoration(hintText: 'Paste names here', alignLabelWithHint: true),
          onChanged: (_) => _parse(),
        ),
        const SizedBox(height: 12),
        if (_errors.isNotEmpty)
          AppCard(
            color: penRed.withAlpha(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final e in _errors) Text(e, style: const TextStyle(color: penRed))]),
          ),
        if (_parsed.isNotEmpty) ...[
          SectionTitle('${_parsed.length} learners ready'),
          for (final l in sortForForms(_parsed))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 14, child: Text(l.sex, style: const TextStyle(fontSize: 12))),
              title: Text(l.fullName),
              subtitle: l.lrn.isEmpty ? null : Text('LRN ${l.lrn}'),
            ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _import, child: Text('Add ${_parsed.length} learners')),
        ],
      ]),
    );
  }
}
