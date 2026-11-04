import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/grading.dart';
import '../../core/models.dart';
import '../../core/sample.dart';
import '../theme.dart';
import '../widgets.dart';
import '../brand.dart';
import 'about_screen.dart';
import 'backup.dart';
import 'profile_form.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  Future<void> _restore(BuildContext context) async {
    final ok = await confirm(context,
        title: 'Restore from a backup?',
        message: 'Everything on this phone will be replaced by the backup file. Make a backup of the current data first if you need it.',
        action: 'Choose file');
    if (!ok) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) return;
    if (!context.mounted) return;
    final restored = await withProgress<bool>(context, 'Restoring...', () async {
      try {
        await store.repo.importJson(utf8.decode(bytes));
      } on TypeError {
        throw const FormatException('This file is not a KlaseKo backup.');
      } on FormatException {
        throw const FormatException('This file is not a KlaseKo backup.');
      }
      await store.reloadProfile();
      return true;
    });
    if (restored == true && context.mounted) toast(context, 'Backup restored.', success: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = store.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        AppCard(
          onTap: () => push(context, const ProfileScreen()),
          child: Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: brandBlue,
              child: Text(p.teacher.isEmpty ? '?' : p.teacher.trim()[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.teacher.isEmpty ? 'Your profile' : p.teacher, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('${p.schoolName} · SY ${p.sy} · ${p.terms == 4 ? '4 quarters' : '3 terms'}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            const Icon(Icons.edit_outlined),
          ]),
        ),
        const SectionTitle('Appearance'),
        _tile(context, Icons.contrast_rounded, 'Theme', _themeLabel(p.themeMode), () => _chooseTheme(context)),
        const SectionTitle('Your data'),
        Loader<Map<String, String>>(
          load: store.repo.settings,
          builder: (context, settings) => _tile(context, Icons.backup_outlined, 'Back up', backupStatus(settings), () => backUpNow(context)),
        ),
        _tile(context, Icons.restore_outlined, 'Restore', 'Bring back data from a KlaseKo backup file, for example on a new phone.', () => _restore(context)),
        _tile(context, Icons.science_outlined, 'Add a sample class', 'A fictional Grade 8 class to practice with.', () async {
          await withProgress(context, 'Adding sample class...', () => createSampleClass(store.repo, store.profile));
          store.changed();
          if (context.mounted) toast(context, 'Sample class added. Open it from Classes.');
        }),
        const SectionTitle('Help'),
        _tile(context, Icons.rule_outlined, 'Grading rules', 'How KlaseKo computes grades (DO 015, s. 2026)', () => push(context, const RulesScreen())),
        _tile(context, Icons.print_outlined, 'Printing answer sheets', 'Tips for sheets the camera reads well', () => push(context, const PrintTipsScreen())),
        _tile(context, Icons.lock_outline, 'Privacy', 'Where your learners\' data is kept', () => push(context, const PrivacyScreen())),
        _tile(context, Icons.info_outline_rounded, 'About KlaseKo', 'Version, licenses and what the name means', () => push(context, const AboutScreen())),
        const SectionTitle('Danger zone'),
        _tile(context, Icons.delete_forever_outlined, 'Erase everything', 'Delete all data on this phone and start over', () async {
          final ok = await confirm(context, title: 'Erase all KlaseKo data?', message: 'Classes, learners, attendance, scores and exams on this phone are deleted. This cannot be undone.', action: 'Erase');
          if (!ok) return;
          await store.repo.wipe();
          await store.reloadProfile();
        }, danger: true),
        const SizedBox(height: 16),
        const Center(child: BrandLogo(size: 30)),
        const SizedBox(height: 6),
        Center(child: Text('Version ${Brand.version} · Works offline', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
      ]),
    );
  }

  String _themeLabel(String v) => switch (v) {
        'light' => 'Light',
        'dark' => 'Dark, easy on the eyes at night',
        _ => 'Follows your phone setting',
      };

  Future<void> _chooseTheme(BuildContext context) async {
    final current = store.profile.themeMode;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Theme', style: Theme.of(ctx).textTheme.titleLarge)),
          for (final (value, title, subtitle, icon) in const [
            ('system', 'Follow my phone', 'Light by day, dark when your phone is in dark mode', Icons.phone_android_rounded),
            ('light', 'Light', 'Navy on soft white paper', Icons.light_mode_rounded),
            ('dark', 'Dark', 'Soft blue-gray, gentle on the eyes at night', Icons.dark_mode_rounded),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(subtitle),
              trailing: value == current ? Icon(Icons.check_circle_rounded, color: Theme.of(ctx).colorScheme.primary) : null,
              onTap: () => Navigator.pop(ctx, value),
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (picked == null || picked == current) return;
    final p = SchoolProfile.fromSettings(store.profile.toSettings())..themeMode = picked;
    await store.saveProfile(p);
  }

  Widget _tile(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap, {bool danger = false}) =>
      NavRow(icon: icon, title: title, subtitle: subtitle, onTap: onTap, color: danger ? penRed : brandBlue);
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final SchoolProfile _p = SchoolProfile.fromSettings(store.profile.toSettings());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('School profile'),
        actions: [
          TextButton(
            onPressed: () async {
              if (!_formKey.currentState!.validate()) return;
              _formKey.currentState!.save();
              await store.saveProfile(_p);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(16), children: [ProfileFields(profile: _p)])),
    );
  }
}

class _InfoScreen extends StatelessWidget {
  const _InfoScreen({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: children),
      );
}

Widget _p(String text) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(text, style: const TextStyle(height: 1.45)));

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) => _InfoScreen(title: 'Grading rules', children: [
        _p('KlaseKo follows DepEd Order No. 015, s. 2026 (classroom assessment) for SY 2026-2027. Check with your school head if your division issues different instructions.'),
        const SectionTitle('Steps for each term'),
        _p('1. Add up the raw scores of each component.\n2. Percentage score (PS) = raw score / highest possible score x 100.\n3. Weighted score (WS) = PS x the component weight.\n4. Initial grade = WW WS + PT WS + EX WS.\n5. Transmute the initial grade to the term grade with the SY 2026-2027 table, then round to a whole number.'),
        _p('Examinations combine Summative Test 1 (30%), Summative Test 2 (30%) and the Term Examination (40%) before the EX weight is applied.'),
        const SectionTitle('Weights (WW / PT / EX)'),
        for (final w in weightPresets.where((w) => w.id != 'custom'))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Expanded(child: Text(w.label, style: const TextStyle(fontSize: 13))),
              Text('${w.ww.toInt()} / ${w.pt.toInt()} / ${w.ex.toInt()}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        const SectionTitle('Final grade and descriptors'),
        _p('Final grade = average of the term grades, rounded. General average = average of the final grades. Passing is 75.'),
        _p('90-100 Advancing · 80-89 Benchmarking · 75-79 Connecting · 65-74 Developing · below 65 Emerging.'),
        _p('Promotion: pass all learning areas to be promoted; fail one or two to attend Summer Remedial Class; fail more than two to be retained.'),
        _p('Grade 1 uses letter grades A to E in SY 2026-2027. Choose "Letter grades" when you create a Grade 1 class.'),
        _p('Older rules: classes set to a DO 8, s. 2015 preset (for Grade 12 learners still on the old curriculum) use those weights and descriptors.'),
      ]);
}

class PrintTipsScreen extends StatelessWidget {
  const PrintTipsScreen({super.key});

  @override
  Widget build(BuildContext context) => _InfoScreen(title: 'Printing answer sheets', children: [
        _p('Print at 100% size ("Actual size"), not "Fit to page", so the bubbles print at the right size.'),
        _p('Use the paper size set in your school profile (short, long or A4). Black ink only; grayscale is fine.'),
        _p('Photocopies work if the circles and item numbers stay clear. Avoid copies that are too light.'),
        _p('Ask learners to shade one circle fully with a dark pen or a soft pencil, and not to write on the black markers.'),
        _p('When scanning, lay the sheet flat in good light and avoid shadows from your phone. You do not need to line anything up: fit all the bubbles and their item numbers in the photo. Include the learner number too, and the app will know whose paper it is.'),
        _p('If a paper cannot be read, use "Check by tapping" for that learner.'),
      ]);
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => _InfoScreen(title: 'Privacy', children: [
        _p('KlaseKo works without internet. Learner names, LRNs, attendance, scores and photos of answer sheets stay on this phone.'),
        _p('The database is encrypted. Its key is kept in your phone\'s secure storage (Android Keystore), so the file cannot be read if it is copied off the phone.'),
        _p('Photos of answer sheets are read and then discarded. They are not saved in your gallery.'),
        _p('Backup files are not encrypted. Keep them in a private place, such as your own Google Drive, and do not post them in group chats.'),
        _p('Use learner data only for school purposes, following the Data Privacy Act of 2012 (RA 10173) and your school\'s data privacy policy.'),
      ]);
}
