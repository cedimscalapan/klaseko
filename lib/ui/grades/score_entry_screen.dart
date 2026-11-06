import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/companion.dart';
import '../theme.dart';
import '../widgets.dart';

/// Fast score entry: one field per learner, the keyboard's Next key moves down the list.
class ScoreEntryScreen extends StatefulWidget {
  const ScoreEntryScreen(
      {super.key, required this.cls, required this.activity, this.learnerId});
  final SchoolClass cls;
  final Activity activity;
  final String? learnerId;

  @override
  State<ScoreEntryScreen> createState() => _ScoreEntryScreenState();
}

class _ScoreEntryScreenState extends State<ScoreEntryScreen> {
  List<Learner> _learners = [];
  final Map<String, TextEditingController> _ctrl = {};
  final Map<String, FocusNode> _focus = {};
  bool _loading = true;
  bool _dirty = false;

  double get hps => widget.activity.hps;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final learners = (await store.repo.learners(widget.cls.id))
        .where((l) =>
            l.isActive &&
            (widget.learnerId == null || l.id == widget.learnerId))
        .toList();
    final scores =
        (await store.repo.scores(widget.cls.id))[widget.activity.id] ?? {};
    final activities = await store.repo.activities(widget.cls.id);
    final fresh =
        activities.where((a) => a.id == widget.activity.id).firstOrNull;
    if (fresh != null) {
      widget.activity.workStates = fresh.workStates;
      widget.activity.dueDate = fresh.dueDate;
    }
    if (!mounted) return;
    for (final l in learners) {
      final s = scores[l.id];
      _ctrl[l.id] = TextEditingController(text: s == null ? '' : fmtScore(s))
        ..addListener(() => _dirty = true);
      _focus[l.id] = FocusNode();
    }
    if (!mounted) return;
    setState(() {
      _learners = learners;
      _loading = false;
    });
    // Ready to type: the keyboard opens on the first learner without a score.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_focus.containsKey(widget.learnerId)) {
        _focus[widget.learnerId]!.requestFocus();
        return;
      }
      for (final l in learners) {
        if (_ctrl[l.id]!.text.isEmpty &&
            widget.activity.workStates[l.id] != 'excused') {
          _focus[l.id]!.requestFocus();
          break;
        }
      }
    });
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  String? _problem(String text) {
    if (text.trim().isEmpty) return null;
    final v = double.tryParse(text.trim());
    if (v == null) return 'Not a number';
    if (v < 0 || v > hps) return '0 to ${fmtScore(hps)}';
    return null;
  }

  Future<bool> _save() async {
    for (final l in _learners) {
      final p = _problem(_ctrl[l.id]!.text);
      if (p != null) {
        toast(context, 'Check the score of ${l.fullName}: $p');
        _focus[l.id]!.requestFocus();
        return false;
      }
    }
    try {
      await store.repo.setScores(widget.activity.id, {
        for (final l in _learners)
          l.id: _ctrl[l.id]!.text.trim().isEmpty
              ? null
              : double.parse(_ctrl[l.id]!.text.trim()),
      });
    } catch (_) {
      if (mounted) toast(context, 'Could not save scores. Please try again.');
      return false;
    }
    store.changed();
    _dirty = false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (!_dirty || await _save()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(a.title, overflow: TextOverflow.ellipsis),
                ListenableBuilder(
                  listenable: Listenable.merge(_ctrl.values.toList()),
                  builder: (context, _) => Text(
                    '${widget.cls.title} · HPS ${fmtScore(a.hps)} · ${_ctrl.values.where((c) => c.text.trim().isNotEmpty).length}/${_learners.length} scored',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ]),
          actions: [
            if (widget.learnerId != null)
              IconButton(
                  tooltip: 'Save and score the whole class',
                  icon: const Icon(Icons.groups_outlined),
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    if (await _save() && mounted) {
                      nav.pushReplacement(MaterialPageRoute(
                          builder: (_) =>
                              ScoreEntryScreen(cls: widget.cls, activity: a)));
                    }
                  }),
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                if (await _save()) {
                  nav.pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                itemCount: _learners.length + 1,
                itemBuilder: (context, i) {
                  if (i == _learners.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                          'Blank scores stay pending. They do not become zero. Enter 0 only when intended. Scoring excused work removes its excused status.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    );
                  }
                  final l = _learners[i];
                  final header = i == 0 || _learners[i - 1].sex != l.sex;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (header)
                          SectionTitle(l.sex == 'M' ? 'Male' : 'Female'),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            SizedBox(
                                width: 30,
                                child: Text(two(l.num),
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant))),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(l.fullName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  ValueListenableBuilder<TextEditingValue>(
                                      valueListenable: _ctrl[l.id]!,
                                      builder: (_, value, __) => Text(
                                          widget.activity.workStates[l.id] ==
                                                      'excused' &&
                                                  value.text.trim().isNotEmpty
                                              ? 'Scored · excused status will be removed'
                                              : workStatus(
                                                      widget.activity,
                                                      l.id,
                                                      double.tryParse(
                                                          value.text),
                                                      DateTime.now())
                                                  .label,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: mutedText(context)))),
                                ])),
                            SizedBox(
                              width: 92,
                              child: ValueListenableBuilder<TextEditingValue>(
                                valueListenable: _ctrl[l.id]!,
                                builder: (context, v, _) {
                                  final p = _problem(v.text);
                                  return TextField(
                                    controller: _ctrl[l.id],
                                    focusNode: _focus[l.id],
                                    textAlign: TextAlign.center,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[0-9.]'))
                                    ],
                                    textInputAction: i == _learners.length - 1
                                        ? TextInputAction.done
                                        : TextInputAction.next,
                                    onSubmitted: (_) {
                                      if (i < _learners.length - 1)
                                        _focus[_learners[i + 1].id]!
                                            .requestFocus();
                                    },
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 18,
                                        color: p != null ? penRed : null),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: '-',
                                      suffixText: '/${fmtScore(hps)}',
                                      errorText: p,
                                      errorStyle: const TextStyle(fontSize: 10),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ]),
                        ),
                      ]);
                },
              ),
      ),
    );
  }
}
