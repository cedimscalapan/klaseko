import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/forms/template_fill.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'official_forms_screen.dart';

List<CellMap> _autoMapJob((Uint8List, String) r) => autoMapXlsx(r.$1, r.$2);

/// The teacher's own form layouts, one list for each form.
class TemplatesScreen extends StatelessWidget {
  const TemplatesScreen({super.key});

  Future<void> _upload(BuildContext context, String form) async {
    final picked =
        await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    if (!context.mounted) return;
    final ext = (f.extension ?? '').toLowerCase();
    if (ext != 'xlsx') {
      toast(
          context,
          ext == 'xls'
              ? 'Open it in Excel or WPS and save it as .xlsx, then upload it again.'
              : 'Please choose an Excel file (.xlsx). Forms in Word or PDF can be saved or copied into Excel first.');
      return;
    }
    final bytes =
        f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null || !context.mounted) return;
    List<CellMap> maps;
    try {
      maps = await compute(_autoMapJob, (bytes, form));
    } catch (_) {
      if (context.mounted)
        toast(context,
            'This Excel file could not be read. Open it in Excel or WPS, save it again as .xlsx, and try once more.');
      return;
    }
    if (!context.mounted) return;
    final name = f.name.replaceFirst(RegExp(r'\.\w+$'), '');
    push(
        context,
        TemplateMapScreen(
            template: FormTemplate(
                id: newId(),
                form: form,
                name: name,
                mapping: CellMap.encode(maps),
                created: now()),
            bytes: bytes,
            found: maps.length));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your form layouts')),
      body: Loader<List<FormTemplate>>(
        load: store.repo.templates,
        builder: (context, list) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              NavRow(
                  icon: Icons.verified_outlined,
                  title: 'Official DepEd template library',
                  subtitle:
                      'Free originals · grade, curriculum and source edition',
                  onTap: () => push(context, const OfficialFormsScreen())),
              AppCard(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Text(
                    'Use your school or division\'s own forms. Upload the Excel file, show where each piece of data goes, and KlaseKo fills that same file for every class from then on.'),
              ),
              for (final e in templateForms.entries) ...[
                SectionTitle(e.value,
                    trailing: TextButton.icon(
                        onPressed: () => _upload(context, e.key),
                        icon: const Icon(Icons.upload_file_rounded, size: 18),
                        label: const Text('Upload'))),
                if (!list.any((t) => t.form == e.key))
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text('Using the built-in layout.',
                        style:
                            TextStyle(fontSize: 13, color: mutedText(context))),
                  ),
                for (final t in list.where((t) => t.form == e.key))
                  NavRow(
                    icon: Icons.table_view_rounded,
                    title: t.name,
                    subtitle:
                        '${CellMap.decode(t.mapping).length} places set. Tap to change them.',
                    onTap: () async {
                      final bytes = await store.repo.templateBytes(t);
                      if (!context.mounted) return;
                      if (bytes == null) {
                        toast(context,
                            'This layout\'s file is no longer on the phone. Please upload it again.');
                        return;
                      }
                      push(
                          context,
                          TemplateMapScreen(
                              template: t, bytes: bytes, existing: true));
                    },
                    trailing: IconButton(
                      tooltip: 'Delete layout',
                      icon: Icon(Icons.delete_outline, color: penRed),
                      onPressed: () async {
                        final ok = await confirm(context,
                            title: 'Delete "${t.name}"?',
                            message:
                                'Forms you already made stay in the archive.');
                        if (!ok) return;
                        await store.repo.deleteTemplate(t);
                        store.changed();
                      },
                    ),
                  ),
              ],
            ]),
      ),
    );
  }
}

/// Shows the uploaded form as a grid. Tapping a cell says which data goes there.
class TemplateMapScreen extends StatefulWidget {
  const TemplateMapScreen(
      {super.key,
      required this.template,
      required this.bytes,
      this.existing = false,
      this.found = 0});
  final FormTemplate template;
  final Uint8List bytes;
  final bool existing;

  /// How many places were found automatically.
  final int found;

  @override
  State<TemplateMapScreen> createState() => _TemplateMapScreenState();
}

class _TemplateMapScreenState extends State<TemplateMapScreen> {
  static const _cellW = 96.0, _cellH = 40.0, _headW = 40.0;

  Map<String, List<List<String>>>? _sheets;
  String? _sheet;
  late List<CellMap> _maps;
  late final TextEditingController _name;
  String _lastGroup = 'all';
  String? _error;

  late final Map<String, FormDataField> _fields = {
    for (final f in fieldsFor(widget.template.form)) f.id: f
  };

  @override
  void initState() {
    super.initState();
    _maps = CellMap.decode(widget.template.mapping);
    _name = TextEditingController(text: widget.template.name);
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sheets = await compute(previewXlsx, widget.bytes);
      if (!mounted) return;
      final mapped = _maps.isEmpty ? null : _maps.first.sheet;
      setState(() {
        _sheets = sheets;
        _sheet = sheets.containsKey(mapped)
            ? mapped
            : (sheets.keys.isEmpty ? null : sheets.keys.first);
      });
    } catch (_) {
      if (mounted)
        setState(() => _error =
            'This Excel file could not be read. Open it in Excel or WPS, save it again as .xlsx, and try once more.');
    }
  }

  CellMap? _mapAt(int r, int c) {
    for (final m in _maps) {
      if (m.sheet == _sheet && m.row == r && m.col == c) return m;
    }
    return null;
  }

  Future<void> _tapCell(int r, int c) async {
    final current = _mapAt(r, c);
    final picked = await showModalBottomSheet<FormDataField>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(controller: scroll, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('What goes in this cell?',
                  style: Theme.of(ctx).textTheme.titleLarge)),
          if (current != null)
            ListTile(
              leading: Icon(Icons.close_rounded, color: penRed),
              title: Text('Clear this cell', style: TextStyle(color: penRed)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _maps.remove(current));
              },
            ),
          for (final f in _fields.values)
            ListTile(
              dense: true,
              title: Text(f.label),
              trailing: _maps.any((m) => m.field == f.id)
                  ? const Icon(Icons.check_rounded, size: 18)
                  : null,
              onTap: () => Navigator.pop(ctx, f),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    var group = 'all';
    if (picked.kind == FieldKind.learner ||
        picked.kind == FieldKind.learnerAcross) {
      final chosen = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('Which learners start at this row?',
                        style: Theme.of(ctx).textTheme.titleLarge)),
                for (final (value, label) in const [
                  ('all', 'All learners, boys first'),
                  ('M', 'Male learners only'),
                  ('F', 'Female learners only')
                ])
                  ListTile(
                    title: Text(label),
                    trailing: value == _lastGroup
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.pop(ctx, value),
                  ),
                const SizedBox(height: 8),
              ]),
        ),
      );
      if (chosen == null || !mounted) return;
      group = chosen;
      _lastGroup = chosen;
    }
    final sheet = _sheet;
    if (sheet == null) return;
    setState(() {
      if (current != null) _maps.remove(current);
      // A single value has one place; moving it clears the old one. A list may start in several groups.
      if (picked.kind == FieldKind.single || picked.kind == FieldKind.across)
        _maps.removeWhere((m) => m.field == picked.id);
      _maps.add(CellMap(sheet, r, c, picked.id, group));
    });
  }

  Future<void> _save() async {
    if (_maps.isEmpty) {
      toast(context, 'Tap the cells where your data should go first.');
      return;
    }
    final name = _name.text.trim();
    final t = widget.template
      ..name = name.isEmpty ? widget.template.name : name
      ..mapping = CellMap.encode(_maps);
    await store.repo.saveTemplate(t, widget.existing ? null : widget.bytes);
    store.changed();
    if (mounted) {
      toast(context,
          'Layout saved. It appears on the Reports page of your classes.',
          success: true);
      Navigator.pop(context);
    }
  }

  static String _colName(int c) {
    var n = c + 1, s = '';
    while (n > 0) {
      final m = (n - 1) % 26;
      s = String.fromCharCode(65 + m) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  Widget _box(double w, Widget child, {Color? color, VoidCallback? onTap}) =>
      InkWell(
        onTap: onTap,
        child: Container(
          width: w,
          height: _cellH,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
              color: color,
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withAlpha(120),
                  width: 0.5)),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final sheets = _sheets;
    final rows = sheets == null || _sheet == null
        ? const <List<String>>[]
        : sheets[_sheet] ?? const <List<String>>[];
    final colCount =
        rows.fold<int>(1, (m, r) => r.length > m ? r.length : m) + 8;
    final rowCount = rows.length + 30;
    final muted = TextStyle(fontSize: 11, color: mutedText(context));
    return Scaffold(
      appBar: AppBar(
        title: Text('${_maps.length} places set'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: _error != null
          ? EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Could not open this file',
              message: _error!)
          : sheets == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                              controller: _name,
                              decoration: const InputDecoration(
                                  labelText: 'Name of this layout',
                                  isDense: true)),
                          const SizedBox(height: 6),
                          Text(
                            widget.found > 0
                                ? 'KlaseKo found ${widget.found} places from the wording of your form. Check them, and tap any cell to set or change it.'
                                : 'Tap a cell to choose what goes there. For a list, tap the first row.',
                            style: TextStyle(
                                fontSize: 12.5, color: mutedText(context)),
                          ),
                          if (sheets.length > 1)
                            DropdownButton<String>(
                              value: _sheet,
                              isExpanded: true,
                              items: [
                                for (final s in sheets.keys)
                                  DropdownMenuItem(value: s, child: Text(s))
                              ],
                              onChanged: (v) => setState(() => _sheet = v),
                            ),
                        ]),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: _headW + colCount * _cellW,
                        child: ListView.builder(
                          itemExtent: _cellH,
                          itemCount: rowCount + 1,
                          itemBuilder: (context, i) {
                            if (i == 0) {
                              return Row(children: [
                                _box(_headW, const SizedBox()),
                                for (var c = 0; c < colCount; c++)
                                  _box(
                                      _cellW,
                                      Center(
                                          child:
                                              Text(_colName(c), style: muted))),
                              ]);
                            }
                            final r = i - 1;
                            final row =
                                r < rows.length ? rows[r] : const <String>[];
                            return Row(children: [
                              _box(
                                  _headW,
                                  Center(
                                      child: Text('${r + 1}', style: muted))),
                              for (var c = 0; c < colCount; c++)
                                () {
                                  final m = _mapAt(r, c);
                                  final field =
                                      m == null ? null : _fields[m.field];
                                  final text = c < row.length ? row[c] : '';
                                  return _box(
                                    _cellW,
                                    Text(
                                      field == null
                                          ? text
                                          : (m!.group == 'all'
                                              ? field.label
                                              : '${field.label} (${m.group})'),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          height: 1.15,
                                          fontWeight: field == null
                                              ? FontWeight.w400
                                              : FontWeight.w700,
                                          color:
                                              field == null ? null : brandBlue),
                                    ),
                                    color: field == null
                                        ? null
                                        : brandBlue.withAlpha(
                                            isDark(context) ? 60 : 30),
                                    onTap: () => _tapCell(r, c),
                                  );
                                }(),
                            ]);
                          },
                        ),
                      ),
                    ),
                  ),
                ]),
    );
  }
}
