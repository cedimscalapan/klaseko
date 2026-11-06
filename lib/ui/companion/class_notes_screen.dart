import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/companion.dart';
import '../../core/db.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> quickClassNote(BuildContext context, SchoolClass cls,
    {ClassNote? existing}) async {
  final learners =
      (await store.repo.learners(cls.id)).where((l) => l.isActive).toList();
  if (!context.mounted) return;
  final result = await showModalBottomSheet<ClassNote>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) =>
        NoteEditor(cls: cls, learners: learners, existing: existing),
  );
  if (result == null) return;
  try {
    await store.repo.saveClassNote(result);
    // Choosing “Remind me on Today” is the opt-in. No device notification.
    if (result.remindOn.isNotEmpty && result.remindOn != existing?.remindOn) {
      await store.repo.putSettings({'today_reminders': '1'});
    }
    store.changed();
    if (context.mounted)
      toast(context, 'Note saved on this device.', success: true);
  } catch (_) {
    if (context.mounted) {
      toast(context, 'Could not save the note. Please try again.');
      await quickClassNote(context, cls, existing: result);
    }
  }
}

/// A short note is the only required input. Details stay out of the way.
class NoteEditor extends StatefulWidget {
  const NoteEditor(
      {super.key, required this.cls, required this.learners, this.existing});
  final SchoolClass cls;
  final List<Learner> learners;
  final ClassNote? existing;
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final text = TextEditingController(text: widget.existing?.text ?? '');
  late String learner = widget.existing?.learnerId ?? '';
  late String reminder = widget.existing?.remindOn ?? '';
  late bool pinned = widget.existing?.pinned ?? false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void save() {
    if (text.text.trim().isEmpty) return;
    final existing = widget.existing;
    Navigator.pop(
        context,
        ClassNote(
            id: existing?.id ?? newId(),
            classId: widget.cls.id,
            text: text.text.trim(),
            created: existing?.created ?? now(),
            updated: now(),
            learnerId: learner,
            remindOn: reminder,
            pinned: pinned,
            done: existing?.done ?? false));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(
                      widget.existing == null
                          ? 'Quick class note'
                          : 'Edit note',
                      style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                  tooltip: 'Close note',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close))
            ]),
            Text('${widget.cls.title} · ${widget.cls.subject}',
                style: TextStyle(color: mutedText(context))),
            const SizedBox(height: 16),
            TextField(
                controller: text,
                autofocus: true,
                minLines: 3,
                maxLines: 7,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Note',
                    hintText:
                        'Where did the class stop? What should you prepare next?')),
            ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Optional details'),
                initiallyExpanded:
                    reminder.isNotEmpty || learner.isNotEmpty || pinned,
                children: [
                  DropdownButtonFormField<String>(
                      initialValue: widget.learners.any((l) => l.id == learner)
                          ? learner
                          : '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Link to a learner (optional)'),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('Whole class')),
                        for (final l in widget.learners)
                          DropdownMenuItem(
                              value: l.id,
                              child: Text(l.fullName,
                                  overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: (value) =>
                          setState(() => learner = value ?? '')),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Pin this note'),
                      value: pinned,
                      onChanged: (v) => setState(() => pinned = v)),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Remind me on Today'),
                      subtitle: Text(reminder.isEmpty
                          ? 'Optional · appears when you open the app'
                          : reminder),
                      trailing: reminder.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Remove reminder',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() => reminder = '')),
                      onTap: () async {
                        final date = await showDatePicker(
                            context: context,
                            initialDate:
                                DateTime.tryParse(reminder) ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100));
                        if (date != null && mounted)
                          setState(() => reminder = localDay(date));
                      }),
                ]),
            const SizedBox(height: 12),
            SizedBox(
                width: double.infinity,
                child: ValueListenableBuilder(
                    valueListenable: text,
                    builder: (_, value, __) => FilledButton.icon(
                        onPressed: value.text.trim().isEmpty ? null : save,
                        icon: const Icon(Icons.check),
                        label: const Text('Save note')))),
          ],
        )),
      );
}

class ClassNotesScreen extends StatefulWidget {
  const ClassNotesScreen({super.key, required this.cls});
  final SchoolClass cls;
  @override
  State<ClassNotesScreen> createState() => _ClassNotesScreenState();
}

class _ClassNotesScreenState extends State<ClassNotesScreen> {
  String query = '', filter = 'Notes';
  Future<(List<ClassNote>, List<Learner>)> load() async => (
        await store.repo.classNotes(widget.cls.id),
        await store.repo.learners(widget.cls.id)
      );

  Future<void> action(String action, ClassNote note) async {
    if (action == 'edit') {
      await quickClassNote(context, widget.cls, existing: note);
      return;
    }
    try {
      if (action == 'delete') {
        await store.repo.deleteClassNote(note.id);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('Note deleted'),
              action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () async {
                    await store.repo.saveClassNote(note);
                    store.changed();
                  })));
      } else {
        await store.repo.saveClassNote(note.copyWith(
            updated: now(),
            pinned: action == 'pin' ? !note.pinned : null,
            done: action == 'done' ? !note.done : null));
      }
      store.changed();
    } catch (_) {
      if (mounted) toast(context, 'Could not update the note. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: ClassTitle('Class notes', widget.cls)),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => quickClassNote(context, widget.cls),
            icon: const Icon(Icons.add),
            label: const Text('Quick note')),
        body: Loader<(List<ClassNote>, List<Learner>)>(
            load: load,
            builder: (context, data) {
              final names = {for (final l in data.$2) l.id: l.fullName};
              final notes = data.$1
                  .where((n) =>
                      (filter == 'Done' ? n.done : !n.done) &&
                      (filter != 'Pinned' || n.pinned) &&
                      (filter != 'Reminders' || n.remindOn.isNotEmpty) &&
                      '${n.text} ${names[n.learnerId] ?? ''}'
                          .toLowerCase()
                          .contains(query.toLowerCase()))
                  .toList();
              return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  children: [
                    TextField(
                        onChanged: (value) => setState(() => query = value),
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Find a note or learner')),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, children: [
                      for (final value in [
                        'Notes',
                        'Pinned',
                        'Reminders',
                        'Done'
                      ])
                        ChoiceChip(
                            label: Text(value),
                            selected: filter == value,
                            onSelected: (_) => setState(() => filter = value))
                    ]),
                    const SizedBox(height: 12),
                    if (notes.isEmpty)
                      EmptyState(
                          icon: Icons.sticky_note_2_outlined,
                          title: query.isNotEmpty
                              ? 'No matching notes'
                              : 'A place for the small things',
                          message:
                              'Save lesson reminders, materials to bring, or where your class stopped. Everything stays on this device.'),
                    for (final note in notes)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                              onTap: () => quickClassNote(context, widget.cls,
                                  existing: note),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      if (note.pinned)
                                        const Padding(
                                            padding: EdgeInsets.only(right: 6),
                                            child:
                                                Icon(Icons.push_pin, size: 18)),
                                      Expanded(
                                          child: Text(
                                              DateFormat('MMM d · h:mm a')
                                                  .format(DateTime
                                                      .fromMillisecondsSinceEpoch(
                                                          note.updated)),
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: mutedText(context)))),
                                      PopupMenuButton<String>(
                                          tooltip: 'Note options',
                                          onSelected: (value) =>
                                              action(value, note),
                                          itemBuilder: (_) => [
                                                const PopupMenuItem(
                                                    value: 'edit',
                                                    child: Text('Edit')),
                                                PopupMenuItem(
                                                    value: 'pin',
                                                    child: Text(note.pinned
                                                        ? 'Unpin'
                                                        : 'Pin')),
                                                PopupMenuItem(
                                                    value: 'done',
                                                    child: Text(note.done
                                                        ? 'Reopen'
                                                        : 'Mark done')),
                                                const PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text('Delete'))
                                              ])
                                    ]),
                                    Text(note.text,
                                        style: const TextStyle(height: 1.5)),
                                    if (note.learnerId.isNotEmpty)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Text(
                                              names[note.learnerId] ??
                                                  'Former class member',
                                              style: TextStyle(
                                                  color: mutedText(context)))),
                                    if (note.remindOn.isNotEmpty)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Text(
                                              'Today reminder · ${note.remindOn}${note.done ? ' · done' : ''}',
                                              style:
                                                  TextStyle(color: brandBlue))),
                                  ]))),
                  ]);
            }),
      );
}
