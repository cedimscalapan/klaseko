/// Curriculum selection is separate from grading rules and template publication dates.
class CurriculumMatch {
  final String code, label, authority;
  const CurriculumMatch(this.code, this.label, this.authority);
}

int? gradeNumber(String grade) {
  if (grade == 'Kindergarten') return 0;
  final match = RegExp(r'^Grade\s+(\d+)$').firstMatch(grade);
  return match == null ? null : int.tryParse(match.group(1)!);
}

CurriculumMatch curriculumFor(int grade, int year, {bool shsPilot = false}) {
  if (grade >= 11) {
    final strengthened = (year >= 2027) ||
        (year == 2026 && (grade == 11 || shsPilot)) ||
        (year == 2025 && grade == 11 && shsPilot);
    return CurriculumMatch(
        strengthened ? 'sshs' : 'legacy_shs',
        strengthened ? 'Strengthened SHS' : 'Existing SHS curriculum',
        'DM 012, s. 2026; DM 048, s. 2025');
  }
  final rollout = {
    0: 2024,
    1: 2024,
    4: 2024,
    7: 2024,
    2: 2025,
    5: 2025,
    8: 2025,
    3: 2026,
    6: 2026,
    9: 2026,
    10: 2027
  };
  final revised = year >= (rollout[grade] ?? 9999);
  return CurriculumMatch(
      revised ? 'matatag' : 'legacy_k10',
      revised ? 'Revised K–10 / MATATAG' : 'Existing K–12 curriculum',
      'DO 010, s. 2024 (phased rollout)');
}
