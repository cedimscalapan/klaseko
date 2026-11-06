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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          final pages = IndexedStack(
            index: _tab,
            children: [
              HomeScreen(onGo: go, active: _tab == 0),
              const ClassesScreen(),
              const CheckHubScreen(),
              const MoreScreen(),
            ],
          );
          const destinations = [
            NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded),
              label: 'Today',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_stories_outlined),
              selectedIcon: Icon(Icons.auto_stories_rounded),
              label: 'Classes',
            ),
            NavigationDestination(
              icon: Icon(Icons.document_scanner_outlined),
              selectedIcon: Icon(Icons.document_scanner_rounded),
              label: 'Check papers',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune_rounded),
              label: 'More',
            ),
          ];
          return Scaffold(
            body: Row(
              children: [
                if (wide)
                  SafeArea(
                    child: NavigationRail(
                      selectedIndex: _tab,
                      onDestinationSelected: go,
                      labelType: NavigationRailLabelType.all,
                      minWidth: 100,
                      leading: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Icon(Icons.school_rounded, size: 32),
                      ),
                      destinations: [
                        for (final d in destinations)
                          NavigationRailDestination(
                            icon: d.icon,
                            selectedIcon: d.selectedIcon,
                            label: Text(d.label),
                          ),
                      ],
                    ),
                  ),
                if (wide)
                  VerticalDivider(
                    width: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                Expanded(child: pages),
              ],
            ),
            bottomNavigationBar: wide
                ? null
                : DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: NavigationBar(
                      selectedIndex: _tab,
                      onDestinationSelected: go,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                      destinations: destinations,
                    ),
                  ),
          );
        },
      ),
    );
  }
}
