import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../widgets.dart';
import '../theme.dart';
import 'class_detail_screen.dart';
import 'class_form.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  String _query = '';
  bool _advisory = false;
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<(SchoolClass, int)>> _load() async {
    final out = <(SchoolClass, int)>[];
    for (final c in await store.repo.classes()) {
      out.add((c, (await store.repo.learners(c.id)).length));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your classes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => push(context, const ClassFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Add class'),
      ),
      body: Loader<List<(SchoolClass, int)>>(
        load: _load,
        builder: (context, all) {
          final list = all
              .where(
                (r) =>
                    (!_advisory || r.$1.advisory) &&
                    '${r.$1.title} ${r.$1.subject}'.toLowerCase().contains(
                      _query.toLowerCase(),
                    ),
              )
              .toList();
          if (all.isEmpty) {
            return const EmptyState(
              icon: Icons.groups_outlined,
              title: 'No classes yet',
              message: 'Add one class for each section and subject you teach. Mark your advisory class to make SF1, SF2 and SF9.',
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${all.length} classes · your teaching, organized',
                      style: TextStyle(color: mutedText(context)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search section or subject',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All classes'),
                          selected: !_advisory,
                          onSelected: (_) => setState(() => _advisory = false),
                        ),
                        ChoiceChip(
                          label: const Text('Advisory'),
                          selected: _advisory,
                          onSelected: (_) => setState(() => _advisory = true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (list.isEmpty)
                const Expanded(
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matching classes',
                    message: 'Try another search or choose All classes.',
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final (c, n) = list[i];
                      return AppCard(
                        onTap: () =>
                            push(context, ClassDetailScreen(classId: c.id)),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: const Icon(Icons.auto_stories_outlined),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${c.subject} · $n learners · SY ${c.sy}',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                  if (c.advisory)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Advisory class',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
