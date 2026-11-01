import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'classes/classes_screen.dart';
import 'home_screen.dart';
import 'scan/check_hub_screen.dart';
import 'settings/more_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  void go(int tab) {
    if (tab == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back from another tab returns to Today instead of closing the app.
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) go(0);
      },
      child: Scaffold(
        body: IndexedStack(index: _tab, children: [
          HomeScreen(onGo: go),
          const ClassesScreen(),
          const CheckHubScreen(),
          const MoreScreen(),
        ]),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withAlpha(90))),
          ),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: go,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Today'),
              NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups_rounded), label: 'Classes'),
              NavigationDestination(icon: Icon(Icons.document_scanner_outlined), selectedIcon: Icon(Icons.document_scanner_rounded), label: 'Check'),
              NavigationDestination(icon: Icon(Icons.more_horiz_rounded), selectedIcon: Icon(Icons.more_horiz_rounded), label: 'More'),
            ],
          ),
        ),
      ),
    );
  }
}
