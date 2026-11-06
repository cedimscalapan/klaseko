import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klaseko/core/forms/curriculum.dart';
import 'package:klaseko/core/forms/official_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('MATATAG rollout follows each grade rather than one school-wide switch',
      () {
    expect(curriculumFor(3, 2025).code, 'legacy_k10');
    expect(curriculumFor(3, 2026).code, 'matatag');
    expect(curriculumFor(10, 2026).code, 'legacy_k10');
    expect(curriculumFor(10, 2027).code, 'matatag');
    expect(gradeNumber('College year 1'), isNull);
  });
  test('Grade 12 in 2026 distinguishes pilot continuing learners', () {
    expect(curriculumFor(11, 2026).code, 'sshs');
    expect(curriculumFor(12, 2026).code, 'legacy_shs');
    expect(curriculumFor(12, 2026, shsPilot: true).code, 'sshs');
  });
  test('Bundled originals are intact and have provenance', () async {
    final forms = await OfficialForm.load();
    expect(forms.length, greaterThan(20));
    for (final f in forms) {
      final uri = Uri.parse(f.source);
      expect(uri.host.endsWith('.deped.gov.ph') || uri.host == 'deped.gov.ph',
          isTrue);
      if (f.asset != null) {
        final data = await rootBundle.load(f.asset!);
        final bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        expect(sha256.convert(bytes).toString(), f.data['sha256'],
            reason: f.title);
        expect(bytes.length, f.data['bytes']);
      }
    }
  });
  test('Historical ECRs cannot be selected for current-year classes', () async {
    final forms = await OfficialForm.load();
    for (final f in forms.where((f) => f.historical)) {
      for (var grade = 0; grade <= 12; grade++) {
        expect(f.matches(grade, 2026), isFalse, reason: f.title);
      }
    }
    final pilot = forms.firstWhere((f) => f.curriculum == 'sshs_pilot');
    expect(pilot.matches(11, 2026), isFalse);
    expect(pilot.matches(12, 2026, shsPilot: true), isTrue);
    final cohort = forms.firstWhere((f) => f.data['schoolYear'] == 2024);
    expect(cohort.matches(4, 2026), isFalse);
    expect(cohort.matches(4, 2024), isTrue);
  });
}
