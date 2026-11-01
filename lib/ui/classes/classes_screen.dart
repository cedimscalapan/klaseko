import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../widgets.dart';
import 'class_detail_screen.dart';
import 'class_form.dart';

class ClassesScreen extends StatelessWidget {
  const ClassesScreen({super.key});

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
      appBar: AppBar(title: const Text('Classes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => push(context, const ClassFormScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Add class'),
      ),
      body: Loader<List<(SchoolClass, int)>>(
        load: _load,
        builder: (context, list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.groups_outlined,
              title: 'No classes yet',
              message: 'Add one class for each section and subject you teach. Mark your advisory class to make SF1, SF2 and SF9.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final (c, n) = list[i];
              return AppCard(
                onTap: () => push(context, ClassDetailScreen(classId: c.id)),
                child: Row(children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(c.grade.replaceAll(RegExp(r'[^0-9]'), ''), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('${c.subject} · $n learners · SY ${c.sy}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      if (c.advisory)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Advisory class', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                        ),
                    ]),
                  ),
                  const Icon(Icons.chevron_right),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
