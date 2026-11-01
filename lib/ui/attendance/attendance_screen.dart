import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/export/form_data.dart';
import '../../core/models.dart';
import '../reports/sf2_screen.dart';
import '../theme.dart';
import '../widgets.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.cls});
  final SchoolClass cls;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _day = DateTime.now();
  List<Learner> _learners = [];
  Map<String, String> _marks = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (_day.weekday > DateTime.friday) _day = _day.subtract(Duration(days: _day.weekday - DateTime.friday));
    _load();
  }

  Future<void> _load() async {
    final k = dayKey(_day);
    final learners = (await store.repo.learners(widget.cls.id)).where((l) => l.isActive).toList();
    final att = await store.repo.attendance(widget.cls.id, from: k, to: k);
    if (!mounted) return;
    setState(() {
      _learners = learners;
      _marks = Map.of(att[k] ?? {});
      _loading = false;
    });
  }

  Future<void> _set(String learnerId, String? status) async {
    setState(() {
      if (status == null) {
        _marks.remove(learnerId);
      } else {
        _marks[learnerId] = status;
      }
    });
    await store.repo.setAttendance(widget.cls.id, dayKey(_day), {learnerId: status});
    store.changed();
  }

  Future<void> _allPresent() async {
    final values = {for (final l in _learners) l.id: _marks[l.id] ?? 'P'};
    setState(() => _marks = Map.of(values));
    await store.repo.setAttendance(widget.cls.id, dayKey(_day), values);
    store.changed();
    if (mounted) toast(context, 'Unmarked learners set to present.');
  }

  Future<void> _clearDay() async {
    final ok = await confirm(context, title: 'Clear this day?', message: 'Removes all marks for ${DateFormat('MMM d').format(_day)}. Use this for a holiday or a day with no classes.', action: 'Clear');
    if (!ok) return;
    await store.repo.setAttendance(widget.cls.id, dayKey(_day), {for (final l in _learners) l.id: null});
    store.changed();
    _load();
  }

  void _move(int days) {
    var d = _day.add(Duration(days: days));
    while (d.weekday > DateTime.friday) {
      d = d.add(Duration(days: days.sign == 0 ? 1 : days.sign));
    }
    setState(() {
      _day = d;
      _loading = true;
    });
    _load();
  }

  Future<void> _pick() async {
    final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2020), lastDate: DateTime(2035));
    if (d == null) return;
    setState(() {
      _day = d;
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _marks.values.where((s) => s == 'P').length;
    final l = _marks.values.where((s) => s == 'L').length;
    final a = _marks.values.where((s) => s == 'A').length;
    final unmarked = _learners.length - _marks.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            tooltip: 'Monthly SF2',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => push(context, Sf2Screen(cls: widget.cls, initialMonth: _day)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'clear' ? _clearDay() : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'clear', child: Text('Clear this day (no classes)'))],
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(children: [
            IconButton(onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: InkWell(
                onTap: _pick,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: [
                    Text(DateFormat('EEEE').format(_day), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    Text(DateFormat('MMMM d, y').format(_day), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
            IconButton(onPressed: () => _move(1), icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Pill('$p present', color: goodGreen),
            const SizedBox(width: 6),
            Pill('$l late', color: lateAmber),
            const SizedBox(width: 6),
            Pill('$a absent', color: penRed),
            const Spacer(),
            if (unmarked > 0) TextButton.icon(onPressed: _allPresent, icon: const Icon(Icons.done_all), label: Text('$unmarked left: all present')),
          ]),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _learners.isEmpty
                  ? const EmptyState(icon: Icons.people_outline, title: 'No learners', message: 'Add learners to this class first.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: _learners.length,
                      itemBuilder: (context, i) {
                        final ln = _learners[i];
                        final s = _marks[ln.id];
                        final header = i == 0 || _learners[i - 1].sex != ln.sex;
                        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (header) SectionTitle(ln.sex == 'M' ? 'Male' : 'Female'),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: AppCard(
                              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                              child: Row(children: [
                                Expanded(child: Text(ln.fullName, style: const TextStyle(fontWeight: FontWeight.w600))),
                                _MarkButton(label: 'P', color: goodGreen, selected: s == 'P', onTap: () => _set(ln.id, s == 'P' ? null : 'P')),
                                _MarkButton(label: 'L', color: lateAmber, selected: s == 'L', onTap: () => _set(ln.id, s == 'L' ? null : 'L')),
                                _MarkButton(label: 'A', color: penRed, selected: s == 'A', onTap: () => _set(ln.id, s == 'A' ? null : 'A')),
                              ]),
                            ),
                          ),
                        ]);
                      },
                    ),
        ),
      ]),
    );
  }
}

class _MarkButton extends StatelessWidget {
  const _MarkButton({required this.label, required this.color, required this.selected, required this.onTap});
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Semantics(
          button: true,
          selected: selected,
          label: {'P': 'Present', 'L': 'Late', 'A': 'Absent'}[label],
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? color : Colors.transparent,
                border: Border.all(color: selected ? color : Theme.of(context).colorScheme.outlineVariant, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
        ),
      );
}
