import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:crypto/crypto.dart';
import '../../core/forms/curriculum.dart';
import '../../core/forms/official_catalog.dart';
import '../../core/models.dart';
import '../../core/export/share.dart';
import '../../core/db.dart';
import '../../core/forms/template_fill.dart';
import 'templates_screen.dart';
import '../widgets.dart';
import '../theme.dart';

class OfficialFormsScreen extends StatefulWidget {
  const OfficialFormsScreen({super.key, this.cls});
  final SchoolClass? cls;
  @override
  State<OfficialFormsScreen> createState() => _OfficialFormsScreenState();
}

class _OfficialFormsScreenState extends State<OfficialFormsScreen> {
  late int grade, year;
  bool pilot = false, references = false, busy = false;
  String query = '';
  List<OfficialForm>? files;
  String? failure;
  @override
  void initState() {
    super.initState();
    grade = gradeNumber(widget.cls?.grade ?? '') ?? 1;
    year =
        int.tryParse((widget.cls?.sy ?? store.profile.sy).split('-').first) ??
            2026;
    load();
  }

  Future<void> load() async {
    try {
      final result = await OfficialForm.load();
      final settings = await store.repo.settings();
      if (mounted)
        setState(() {
          files = result;
          pilot = settings['forms_pilot_${widget.cls?.id ?? 'browser'}'] == '1';
        });
    } catch (e) {
      if (mounted)
        setState(() => failure = 'Unable to load the template library.');
    }
  }

  Future<void> setPilot(bool value) async {
    setState(() => pilot = value);
    await store.repo.putSettings(
        {'forms_pilot_${widget.cls?.id ?? 'browser'}': value ? '1' : '0'});
  }

  Future<void> source(String value) async {
    final uri = Uri.parse(value.replaceFirst('http:', 'https:'));
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted)
      toast(context, 'Unable to open the official source.');
  }

  Future<void> export(OfficialForm form) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      Uint8List bytes;
      if (form.asset != null) {
        final b = await rootBundle.load(form.asset!);
        bytes = b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes);
      } else {
        final dir = await getApplicationSupportDirectory();
        final cache = File('${dir.path}/official_forms/${form.id}.bin');
        if (await cache.exists()) {
          bytes = await cache.readAsBytes();
        } else {
          final uri = Uri.parse(form.source.replaceFirst('http:', 'https:'));
          if (uri.host != 'deped.gov.ph' && !uri.host.endsWith('.deped.gov.ph'))
            throw const FormatException('Invalid source host.');
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 30);
          try {
            final request = await client.getUrl(uri);
            request.followRedirects = false;
            final response = await request.close();
            if (response.statusCode != 200)
              throw const FormatException(
                  'Official download unavailable. Open the source page instead.');
            final buffer = BytesBuilder();
            await for (final chunk in response) {
              buffer.add(chunk);
              if (buffer.length > 30 * 1024 * 1024)
                throw const FormatException('File is too large.');
            }
            bytes = buffer.takeBytes();
          } finally {
            client.close(force: true);
          }
          await cache.parent.create(recursive: true);
          await cache.writeAsBytes(bytes, flush: true);
        }
      }
      // Cached and bundled originals must match the inspected source snapshot.
      if (bytes.length != form.data['bytes'] ||
          sha256.convert(bytes).toString() != form.data['sha256'])
        throw const FormatException(
            'The official file has changed since this edition was checked. Open the official source for the latest copy.');
      await saveAndShare(
          bytes,
          form.data['filename'] as String,
          (form.data['filename'] as String).endsWith('.zip')
              ? 'application/zip'
              : xlsxMime);
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> prepare(OfficialForm sourceForm) async {
    var kind = 'sf1';
    var sheet =
        (sourceForm.data['sheets'] as List).firstOrNull?.toString() ?? '';
    final pick = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                    title: const Text('Use this original as a reusable layout'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          'Choose the output form and worksheet. Review the cell assignments before saving. This does not confirm the edition is applicable to your school.'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          initialValue: kind,
                          isExpanded: true,
                          items: [
                            for (final entry in templateForms.entries)
                              DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value,
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: (v) => update(() => kind = v!)),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          initialValue: sheet,
                          isExpanded: true,
                          items: [
                            for (final name
                                in sourceForm.data['sheets'] as List)
                              DropdownMenuItem(
                                  value: name.toString(),
                                  child: Text(name.toString(),
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: (v) => update(() => sheet = v!))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Review mapping'))
                    ])));
    if (pick != true || sourceForm.asset == null) return;
    try {
      final b = await rootBundle.load(sourceForm.asset!);
      final bytes = b.buffer.asUint8List(b.offsetInBytes, b.lengthInBytes);
      final mappings =
          autoMapXlsx(bytes, kind).where((m) => m.sheet == sheet).toList();
      if (!mounted) return;
      await push(
          context,
          TemplateMapScreen(
              template: FormTemplate(
                  id: newId(),
                  form: kind,
                  name:
                      '${templateForms[kind]} · ${sourceForm.data['filename']}',
                  mapping: CellMap.encode(mappings),
                  created: now()),
              bytes: bytes,
              found: mappings.length));
    } catch (e) {
      if (mounted)
        toast(context,
            'This workbook needs manual review in your spreadsheet app: $e');
    }
  }

  Future<void> details(OfficialForm form) async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(form.title,
                          style: Theme.of(ctx).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Text(form.data['scope'] as String),
                      const SizedBox(height: 8),
                      Text(form.data['authority'] as String),
                      const SizedBox(height: 12),
                      Text(form.data['note'] as String),
                      const SizedBox(height: 12),
                      Text(
                          'Published file: ${form.data['filename']}\nSource checked: ${form.data['retrieved']}'),
                      if ((form.data['sheets'] as List).isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                                'Included worksheets: ${(form.data['sheets'] as List).join(', ')}')),
                      const Text(
                          'Blank original, without learner data. Complete the required fields in your spreadsheet app. KlaseKo does not certify this file as the current submission format.'),
                      const SizedBox(height: 16),
                      if (form.asset != null)
                        OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              prepare(form);
                            },
                            icon: const Icon(Icons.auto_fix_high_outlined),
                            label:
                                const Text('Set up reusable autofill layout')),
                      FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            export(form);
                          },
                          icon: const Icon(Icons.download_outlined),
                          label: Text(form.asset == null
                              ? 'Download original (internet first time)'
                              : 'Save / share original (offline)')),
                      TextButton.icon(
                          onPressed: () =>
                              source(form.data['sourcePage'] as String),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('View official source')),
                    ]))));
  }

  @override
  Widget build(BuildContext context) {
    final curriculum = curriculumFor(grade, year, shsPilot: pilot);
    final filtered = files
            ?.where((f) =>
                (references || f.matches(grade, year, shsPilot: pilot)) &&
                '${f.title} ${f.data['filename']} ${f.data['sheets']}'
                    .toLowerCase()
                    .contains(query.toLowerCase()))
            .toList() ??
        [];
    return Scaffold(
        appBar: AppBar(title: const Text('Official DepEd templates')),
        body: files == null
            ? Center(
                child: failure == null
                    ? const CircularProgressIndicator()
                    : TextButton(
                        onPressed: load, child: Text('$failure Tap to retry.')))
            : ListView(padding: const EdgeInsets.all(20), children: [
                AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Free official originals',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const Text(
                          'Original public DepEd files, with grade and curriculum filters. Source edition and current-year applicability are separate. Official submissions must follow current LIS and school instructions.')
                    ])),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                    initialValue: grade,
                    decoration: const InputDecoration(labelText: 'Grade level'),
                    items: [
                      for (var g = 0; g <= 12; g++)
                        DropdownMenuItem(
                            value: g,
                            child: Text(g == 0 ? 'Kindergarten' : 'Grade $g'))
                    ],
                    onChanged: (g) => setState(() => grade = g!)),
                const SizedBox(height: 12),
                TextFormField(
                    initialValue: '$year',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'School year starts in',
                        helperText: 'Example: 2026 means SY 2026–2027'),
                    onChanged: (v) {
                      final value = int.tryParse(v);
                      if (value != null && value >= 2015 && value <= 2100)
                        setState(() => year = value);
                    }),
                if (grade >= 11)
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: pilot,
                      onChanged: setPilot,
                      title: const Text('Strengthened SHS pilot cohort'),
                      subtitle: const Text(
                          'Grade 11 pilot in 2025–2026, continuing to Grade 12 in 2026–2027.')),
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('${curriculum.label}\n${curriculum.authority}',
                        style: TextStyle(color: mutedText(context)))),
                TextField(
                    decoration: const InputDecoration(
                        labelText: 'Search form or worksheet',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => query = v)),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: references,
                    onChanged: (v) => setState(() => references = v),
                    title: const Text('Browse all reference editions'),
                    subtitle: const Text(
                        'Includes other grades, ALS and historical files. Not recommendations for this class.')),
                if (busy) const LinearProgressIndicator(),
                if (filtered.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                          'No verified source file matches these filters. Check the official source or import your school-issued template.')),
                for (final form in filtered)
                  NavRow(
                      icon: Icons.table_view_outlined,
                      title: form.title,
                      subtitle:
                          '${form.data['scope']}\n${form.asset == null ? 'Online download' : 'Available offline'} · ${form.historical ? 'Historical grading template' : 'Review edition before use'}',
                      onTap: busy ? () {} : () => details(form)),
                const SectionTitle('Formats requiring current school guidance'),
                const Text(
                    'SF9: obtain the current report-card layout from your school and official assessment guidance. Kindergarten has a separate reporting format.\n\nLearning Outcome Assessment, Class Record, Test Result and Analysis, Report on Remedial and Intervention Program, and Individualized Learning Plan are report categories under DO 006, s. 2025; that order does not establish one identical workbook for every subject.'),
                TextButton(
                    onPressed: () =>
                        source('https://support.lis.deped.gov.ph/support/'),
                    child: const Text('Open official LIS downloads')),
                TextButton(
                    onPressed: () => source(
                        'https://www.deped.gov.ph/wp-content/uploads/DO_s2026_015r.pdf'),
                    child: const Text(
                        'DO 015, s. 2026 · assessment and reporting')),
                TextButton(
                    onPressed: () => source(
                        'https://www.deped.gov.ph/wp-content/uploads/DO_s2025_006.pdf'),
                    child: const Text(
                        'DO 006, s. 2025 · teacher report categories')),
                TextButton(
                    onPressed: () => source(
                        'https://www.deped.gov.ph/wp-content/uploads/2016/06/DO_s2016_042.pdf'),
                    child: const Text(
                        'DO 042, s. 2016 · lesson preparation formats')),
              ]));
  }
}
