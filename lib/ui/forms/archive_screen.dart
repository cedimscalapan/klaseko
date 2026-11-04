import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/export/share.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'archive_info.dart';

enum _Sort { subject, term, week, form }

const _sortLabels = {_Sort.subject: 'Subject', _Sort.term: 'Term', _Sort.week: 'Week', _Sort.form: 'Form'};

DateTime _mondayOf(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  return DateTime(d.year, d.month, d.day - (d.weekday - 1));
}

/// Every form the teacher has made, in folders. [cls] limits it to one class.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, this.cls});
  final SchoolClass? cls;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  _Sort _sort = _Sort.term;
  String? _sy;
  String _query = '';

  String _folderOf(ArchiveEntry e) => switch (_sort) {
        _Sort.subject => '${e.subject} · ${e.classTitle}',
        _Sort.term => e.term == null ? 'Whole year and other forms' : store.profile.termName(e.term!),
        _Sort.week => 'Week of ${DateFormat('MMM d, y').format(_mondayOf(e.created))}',
        _Sort.form => archiveForms[e.form] ?? 'Other forms',
      };

  @override
  void initState() {
    super.initState();
    if (widget.cls != null) _sort = _Sort.term;
  }

  @override
  Widget build(BuildContext context) {
    final cls = widget.cls;
    return Scaffold(
      appBar: AppBar(title: cls == null ? const Text('Forms archive') : ClassTitle('Forms archive', cls)),
      body: Loader<List<ArchiveEntry>>(
        load: () => store.repo.archiveEntries(classId: cls?.id),
        builder: (context, all) {
          if (all.isEmpty) {
            return const EmptyState(
              icon: Icons.folder_open_rounded,
              title: 'No forms yet',
              message: 'Every form you make is filed here by itself, sorted by subject, term, week and form.',
            );
          }
          final years = all.map((e) => e.sy).toSet().toList()..sort((a, b) => b.compareTo(a));
          final year = years.contains(_sy) ? _sy! : years.first;
          final q = _query.trim().toLowerCase();
          final shown = all
              .where((e) => e.sy == year && (q.isEmpty || '${e.title} ${e.subject} ${e.classTitle} ${e.period}'.toLowerCase().contains(q)))
              .toList();
          final folders = <String, List<ArchiveEntry>>{};
          for (final e in shown) {
            (folders[_folderOf(e)] ??= []).add(e);
          }
          // Newest week first; other sorts by name.
          final names = folders.keys.toList()
            ..sort((a, b) => _sort == _Sort.week ? folders[b]!.first.created.compareTo(folders[a]!.first.created) : a.compareTo(b));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search forms'),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final s in _Sort.values)
                ChoiceChip(label: Text(_sortLabels[s]!), selected: _sort == s, onSelected: (_) => setState(() => _sort = s)),
              if (years.length > 1)
                DropdownButton<String>(
                  value: year,
                  items: [for (final y in years) DropdownMenuItem(value: y, child: Text('SY $y'))],
                  onChanged: (v) => setState(() => _sy = v),
                ),
            ]),
            const SizedBox(height: 10),
            if (names.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No matching forms.'))),
            for (final name in names)
              NavRow(
                icon: Icons.folder_rounded,
                color: gold,
                title: name,
                subtitle: folders[name]!.length == 1 ? '1 form' : '${folders[name]!.length} forms',
                onTap: () => push(context, _FolderScreen(title: name, ids: [for (final e in folders[name]!) e.id], classId: cls?.id)),
              ),
          ]);
        },
      ),
    );
  }
}

class _FolderScreen extends StatelessWidget {
  const _FolderScreen({required this.title, required this.ids, this.classId});
  final String title;
  final List<String> ids;
  final String? classId;

  Future<void> _share(BuildContext context, ArchiveEntry e) async {
    final bytes = await store.repo.archiveBytes(e);
    if (bytes == null) {
      if (context.mounted) toast(context, 'This file is no longer on the phone.');
      return;
    }
    await saveAndShare(bytes, '${e.title}${e.mime == pdfMime ? '.pdf' : '.xlsx'}', e.mime);
  }

  Future<void> _open(BuildContext context, ArchiveEntry e) async {
    if (e.mime != pdfMime) return _share(context, e);
    final bytes = await store.repo.archiveBytes(e);
    if (bytes == null || !context.mounted) return;
    push(
      context,
      Scaffold(
        appBar: AppBar(title: Text(e.title)),
        body: PdfPreview(build: (_) => bytes, canChangePageFormat: false, canChangeOrientation: false, canDebug: false, allowSharing: true, allowPrinting: true),
      ),
    );
  }

  void _setTerm(BuildContext context, ArchiveEntry e) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var t = 1; t <= store.profile.terms; t++)
            ListTile(
              title: Text(store.profile.termName(t)),
              trailing: e.term == t ? const Icon(Icons.check_rounded) : null,
              onTap: () async {
                Navigator.pop(ctx);
                await store.repo.setArchiveTerm(e.id, t);
                store.changed();
              },
            ),
          ListTile(
            title: const Text('Whole year and other forms'),
            trailing: e.term == null ? const Icon(Icons.check_rounded) : null,
            onTap: () async {
              Navigator.pop(ctx);
              await store.repo.setArchiveTerm(e.id, null);
              store.changed();
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Loader<List<ArchiveEntry>>(
        load: () => store.repo.archiveEntries(classId: classId),
        builder: (context, all) {
          final list = all.where((e) => ids.contains(e.id)).toList();
          if (list.isEmpty) return const EmptyState(icon: Icons.folder_open_rounded, title: 'This folder is empty', message: 'Its forms were deleted or moved.');
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            for (final e in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  onTap: () => _open(context, e),
                  child: Row(children: [
                    Icon(e.mime == pdfMime ? Icons.picture_as_pdf_outlined : Icons.table_view_outlined, color: brandBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          [
                            '${e.subject} · ${e.classTitle}',
                            if (e.term != null) store.profile.termName(e.term!),
                            DateFormat('MMM d, y').format(DateTime.fromMillisecondsSinceEpoch(e.created)),
                          ].join(' · '),
                          style: TextStyle(fontSize: 12, color: mutedText(context)),
                        ),
                      ]),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'share') {
                          await _share(context, e);
                        } else if (v == 'term') {
                          _setTerm(context, e);
                        } else if (v == 'delete') {
                          final ok = await confirm(context, title: 'Delete this file?', message: 'Your records stay. You can make this form again anytime.');
                          if (!ok) return;
                          await store.repo.deleteArchive(e);
                          store.changed();
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'share', child: Text('Share or save')),
                        const PopupMenuItem(value: 'term', child: Text('Move to a term')),
                        PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: penRed))),
                      ],
                    ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
