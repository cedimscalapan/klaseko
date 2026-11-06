import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/sample.dart';
import 'settings/profile_form.dart';
import 'brand.dart';
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
  bool _sample = false;
  bool _busy = false;

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      if (_sample) await createSampleClass(store.repo, _profile);
      await store.saveProfile(_profile, markOnboarded: true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Could not finish setup. Please try again.');
      }
    }
  }

  void _back() {
    if (_busy || _step == 0) return;
    if (_step == 1) _formKey.currentState?.save();
    FocusScope.of(context).unfocus();
    setState(() => _step--);
  }

  void _next() {
    if (_step == 1) {
      if (!(_formKey.currentState?.validate() ?? false)) return;
      _formKey.currentState!.save();
    }
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    const names = ['Welcome', 'Your school', 'Ready'];
    return PopScope(
      canPop: _step == 0 && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                    child: Row(
                      children: [
                        const Expanded(
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: BrandLogo(size: 32)))),
                        const SizedBox(width: 12),
                        Text(
                          'Step ${_step + 1} of 3',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        for (var i = 0; i < 3; i++)
                          Expanded(
                            child: Semantics(
                              label: '${names[i]}, step ${i + 1} of 3',
                              selected: i == _step,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: i <= _step
                                            ? brandBlue
                                            : Theme.of(context)
                                                .colorScheme
                                                .outlineVariant,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      names[i],
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: i == _step
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        color: i == _step
                                            ? brandBlue
                                            : mutedText(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: [_welcome(), _profileStep(), _ready()][_step],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                    child: Row(
                      children: [
                        if (_step > 0) ...[
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _back,
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              size: 18,
                            ),
                            label: const Text('Back'),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _next,
                            icon: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _step == 2
                                        ? Icons.check_rounded
                                        : Icons.arrow_forward_rounded,
                                    size: 20,
                                  ),
                            label: Text(
                              _busy
                                  ? 'Setting up…'
                                  : _step == 0
                                      ? 'Get started'
                                      : _step == 1
                                          ? 'Continue'
                                          : 'Open KlaseKo',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome() => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),
          HeroHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BrandMark(size: 64),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(24),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_off_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Offline ready',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const Text(
                  'More time for\nyour students.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your classes, assessments and progress.\nTogether in one calm workspace.',
                  style: TextStyle(
                    color: Color(0xFFDCEAF0),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Made for your teaching day',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          for (final f in const [
            (
              Icons.fact_check_outlined,
              'Stay on top of every class',
              'Attendance, scores and reports in one place.',
            ),
            (
              Icons.document_scanner_outlined,
              'Make checking lighter',
              'Create exams and scan answer sheets.',
            ),
            (
              Icons.school_outlined,
              'A fit for your school',
              'DepEd, private K–12 and higher education.',
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(f.$1, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.$2,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          f.$3,
                          style: TextStyle(
                              color: mutedText(context), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _profileStep() => Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Your school',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'These go on the header of your forms and reports. You can change them later in More.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            ProfileFields(profile: _profile, compact: true),
            const SizedBox(height: 20),
          ],
        ),
      );

  Widget _ready() => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: IconBadge(Icons.check_circle_outline_rounded, size: 72),
          ),
          const Text(
            "Your workspace is ready",
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Next, add your first class. Want to look around with practice data first?',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _sample,
              onChanged: (v) => setState(() => _sample = v),
              title: const Text(
                'Add a sample class',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Grade 8 Mathematics with 12 fictional learners, October attendance, scores and a checked exam. Delete it anytime.',
              ),
            ),
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 12),
          Text(
            'You can add your first class after setup. School settings stay editable in More.',
            style: TextStyle(color: mutedText(context)),
          ),
        ],
      );
}
