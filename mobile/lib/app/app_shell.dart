import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../shared/utils/responsive.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablet = Responsive.isTablet(context);
    final canAccessAdmin = ref.watch(
      authControllerProvider.select((auth) => auth.user?.canAccessAdmin ?? false),
    );
    final visibleBranchIndexes = canAccessAdmin
        ? const [0, 1, 2, 3]
        : const [0, 1, 3];
    final selectedIndex = visibleBranchIndexes.indexOf(
      navigationShell.currentIndex,
    );

    if (tablet) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
              onDestinationSelected: (index) => _onDestinationSelected(
                index,
                visibleBranchIndexes,
              ),
              labelType: NavigationRailLabelType.all,
              destinations: [
                NavigationRailDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: Text('书架'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.sticky_note_2_outlined),
                  selectedIcon: Icon(Icons.sticky_note_2),
                  label: Text('批注'),
                ),
                if (canAccessAdmin)
                  NavigationRailDestination(
                    icon: Icon(Icons.admin_panel_settings_outlined),
                    selectedIcon: Icon(Icons.admin_panel_settings),
                    label: Text('后台'),
                  ),
                NavigationRailDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: Text('我'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        onDestinationSelected: (index) =>
            _onDestinationSelected(index, visibleBranchIndexes),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.sticky_note_2_outlined),
            selectedIcon: Icon(Icons.sticky_note_2),
            label: '批注',
          ),
          if (canAccessAdmin)
            NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: Icon(Icons.admin_panel_settings),
              label: '后台',
            ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我',
          ),
        ],
      ),
    );
  }

  void _onDestinationSelected(int index, List<int> visibleBranchIndexes) {
    final actualBranchIndex = visibleBranchIndexes[index];
    navigationShell.goBranch(
      actualBranchIndex,
      initialLocation: actualBranchIndex == navigationShell.currentIndex,
    );
  }
}
