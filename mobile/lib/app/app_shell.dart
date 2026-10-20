import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/design_system/aira_bottom_nav.dart';

/// Tab shell: Home, Studies, Exports, Settings. Per-study screens are pushed
/// full-screen above it.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = [
    AiraNavItem(icon: LucideIcons.house, label: 'Home'),
    AiraNavItem(icon: LucideIcons.scanLine, label: 'Studies'),
    AiraNavItem(icon: LucideIcons.upload, label: 'Exports'),
    AiraNavItem(icon: LucideIcons.slidersHorizontal, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AiraBottomNav(
        items: _items,
        currentIndex: navigationShell.currentIndex,
        onTap: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
