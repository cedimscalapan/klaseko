import 'package:flutter/material.dart';

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

  void go(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        HomeScreen(onGo: go),
        const ClassesScreen(),
        const CheckHubScreen(),
        const MoreScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Classes'),
          NavigationDestination(icon: Icon(Icons.document_scanner_outlined), selectedIcon: Icon(Icons.document_scanner), label: 'Check papers'),
          NavigationDestination(icon: Icon(Icons.menu), selectedIcon: Icon(Icons.menu_open), label: 'More'),
        ],
      ),
    );
  }
}
