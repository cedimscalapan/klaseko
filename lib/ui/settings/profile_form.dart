import 'package:flutter/material.dart';

import '../../core/models.dart';

/// Fields for the school profile. Writes into [profile] when the parent Form is saved.
class ProfileFields extends StatefulWidget {
  const ProfileFields({super.key, required this.profile});
  final SchoolProfile profile;

  @override
  State<ProfileFields> createState() => _ProfileFieldsState();
}

class _ProfileFieldsState extends State<ProfileFields> {
  SchoolProfile get p => widget.profile;

  Widget _field(String label, String initial, void Function(String) save, {bool required = false, String? hint, TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          initialValue: initial,
          keyboardType: type,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: required ? '$label *' : label, hintText: hint),
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Please enter $label' : null : null,
          onSaved: (v) => save((v ?? '').trim()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _field('Your name (as it appears on forms)', p.teacher, (v) => p.teacher = v, required: true, hint: 'e.g. Maria L. Santos'),
      _field('School name', p.schoolName, (v) => p.schoolName = v, required: true),
      _field('School ID', p.schoolId, (v) => p.schoolId = v, type: TextInputType.number),
      Row(children: [
        Expanded(child: _field('Region', p.region, (v) => p.region = v, hint: 'e.g. MIMAROPA')),
        const SizedBox(width: 10),
        Expanded(child: _field('Division', p.division, (v) => p.division = v, hint: 'e.g. Calapan City')),
      ]),
      _field('District', p.district, (v) => p.district = v),
      _field('School head', p.schoolHead, (v) => p.schoolHead = v),
      _field('School year', p.sy, (v) => p.sy = v.isEmpty ? '2026-2027' : v, required: true, hint: '2026-2027'),
      const SizedBox(height: 4),
      const Text('Grading periods', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 3, label: Text('3 terms'), icon: Icon(Icons.looks_3_outlined)),
          ButtonSegment(value: 4, label: Text('4 quarters'), icon: Icon(Icons.looks_4_outlined)),
        ],
        selected: {p.terms},
        onSelectionChanged: (s) => setState(() => p.terms = s.first),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 14),
        child: Text('SY 2026-2027 uses three terms (DO 015, s. 2026). Choose 4 quarters only for an older school year.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
      const Text('Paper size for printing', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'letter', label: Text('Short')),
          ButtonSegment(value: 'long', label: Text('Long')),
          ButtonSegment(value: 'a4', label: Text('A4')),
        ],
        selected: {p.paper},
        onSelectionChanged: (s) => setState(() => p.paper = s.first),
      ),
    ]);
  }
}
