import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/sample.dart';
import 'settings/profile_form.dart';
import 'theme.dart';
import 'widgets.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  final _profile = SchoolProfile();
  final _formKey = GlobalKey<FormState>();
  bool _sample = true;
  bool _busy = false;

  Future<void> _finish() async {
    setState(() => _busy = true);
    if (_sample) await createSampleClass(store.repo, _profile);
    await store.saveProfile(_profile, markOnboarded: true);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_welcome(), _profileStep(), _ready()];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Container(
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i <= _step ? brandBlue : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
            ]),
          ),
          Expanded(child: pages[_step]),
        ]),
      ),
    );
  }

  Widget _welcome() => ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 24),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: brandBlue, borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
        ),
        const SizedBox(height: 24),
        const Text('KlaseKo', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Isang entry, tapos na ang forms.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 18),
        for (final f in const [
          [Icons.fact_check_outlined, 'Attendance in a few taps', 'Your SF2 fills itself every month.'],
          [Icons.grid_on_outlined, 'Class record with DepEd rules', 'DO 015, s. 2026 weights, terms and transmutation built in.'],
          [Icons.quiz_outlined, 'Exam maker and printable answer sheets', 'Test papers and personalized answer sheets as PDF.'],
          [Icons.document_scanner_outlined, 'Check papers with the camera', 'Scores go straight to your class record.'],
          [Icons.insights_outlined, 'MPS and item analysis', 'Least-mastered competencies in one tap.'],
          [Icons.wifi_off_outlined, 'Works fully offline', 'Learner data stays encrypted on your phone.'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(f[0] as IconData, color: brandBlue),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f[1] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(f[2] as String, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => setState(() => _step = 1), child: const Text('Get started')),
      ]);

  Widget _profileStep() => Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Your school', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('These details go on the header of your SF1, SF2, SF9 and reports. You can change them later in More.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          ProfileFields(profile: _profile),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => setState(() => _step = 0), child: const Text('Back'))),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _formKey.currentState!.save();
                    setState(() => _step = 2);
                  }
                },
                child: const Text('Continue'),
              ),
            ),
          ]),
        ]),
      );

  Widget _ready() => ListView(padding: const EdgeInsets.all(24), children: [
        const Text("You're all set", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Add your first class from the Classes tab. Want to look around first?',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        AppCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _sample,
            onChanged: (v) => setState(() => _sample = v),
            title: const Text('Add a sample class', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Grade 8 Mathematics with 12 fictional learners, October attendance, scores and a checked exam. Delete it anytime.'),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _busy ? null : _finish, child: Text(_busy ? 'Setting up...' : 'Start using KlaseKo')),
        const SizedBox(height: 8),
        TextButton(onPressed: _busy ? null : () => setState(() => _step = 1), child: const Text('Back')),
      ]);
}
