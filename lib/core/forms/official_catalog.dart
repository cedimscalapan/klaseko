import 'dart:convert';
import 'package:flutter/services.dart';
import 'curriculum.dart';

class OfficialForm {
  final Map<String, dynamic> data;
  OfficialForm(this.data);
  String get id => data['id'] as String;
  String get title => data['title'] as String;
  String get source => data['source'] as String;
  String? get asset => data['asset'] as String?;
  String get curriculum => data['curriculum'] as String;
  bool get historical => data['archive'] == true;
  bool matches(int grade, int year, {bool shsPilot = false}) {
    if (data['kind'] == 'ecr' && curriculum != 'sshs_pilot' && year >= 2026)
      return false;
    if (grade < (data['minGrade'] as int) || grade > (data['maxGrade'] as int))
      return false;
    if (data['schoolYear'] != null && year != data['schoolYear']) return false;
    if (historical)
      return year < 2026 &&
          curriculumFor(grade, year, shsPilot: shsPilot)
              .code
              .startsWith('legacy');
    if (curriculum == 'sshs_pilot')
      return shsPilot &&
          (year == 2025 && grade == 11 || year == 2026 && grade == 12);
    if (curriculum == 'legacy_shs')
      return curriculumFor(grade, year, shsPilot: shsPilot).code ==
          'legacy_shs';
    return curriculum != 'als';
  }

  static Future<List<OfficialForm>> load() async {
    final catalog = jsonDecode(
            await rootBundle.loadString('assets/deped_forms/catalog.json'))
        as Map<String, dynamic>;
    return (catalog['files'] as List)
        .map((e) => OfficialForm(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
