import 'package:flutter/material.dart';

import '../brand.dart';
import '../theme.dart';
import '../widgets.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = mutedText(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        HeroHeader(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          child: Column(children: [
            const BrandMark(size: 92, plain: true),
            const SizedBox(height: 14),
            const BrandWordmark(size: 34, onDark: true),
            const SizedBox(height: 6),
            const Text(Brand.tagline, textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            Text(Brand.taglineEn, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(99)),
              child: const Text('Version ${Brand.version}', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        const SectionTitle('The name'),
        AppCard(
          child: Text(
            '${Brand.meaning} KlaseKo keeps everything about your class in one place: '
            'attendance, the class record, exams and paper checking, and the school forms that come out of them.',
            style: const TextStyle(height: 1.5),
          ),
        ),
        const SectionTitle('Made for DepEd teachers'),
        AppCard(
          child: Column(children: [
            for (final (icon, text) in const [
              (Icons.wifi_off_rounded, 'Works fully offline. Your learners\' data stays on your phone.'),
              (Icons.rule_rounded, 'Grades follow DO 015, s. 2026: three terms, WW, PT and EX.'),
              (Icons.document_scanner_rounded, 'Checks answer sheets with the camera, and asks you when it is unsure.'),
              (Icons.description_rounded, 'Prepares SF1, SF2, SF9, class records and MPS reports.'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  IconBadge(icon, size: 36),
                  const SizedBox(width: 12),
                  Expanded(child: Padding(padding: const EdgeInsets.only(top: 7), child: Text(text))),
                ]),
              ),
          ]),
        ),
        const SectionTitle('Legal'),
        NavRow(
          icon: Icons.gavel_rounded,
          title: 'Open-source licenses',
          subtitle: 'Fonts and libraries used in KlaseKo',
          onTap: () => showLicensePage(
            context: context,
            applicationName: Brand.name,
            applicationVersion: Brand.version,
            applicationIcon: const Padding(padding: EdgeInsets.all(12), child: BrandMark(size: 56)),
            applicationLegalese: Brand.description,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'KlaseKo is an independent app for teachers. It is not made by or affiliated with the Department of Education. '
          'Check that your forms match what your school and division require.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: muted, height: 1.45),
        ),
      ]),
    );
  }
}
