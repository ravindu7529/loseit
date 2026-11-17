import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'ai_assistant_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'recipes_screen.dart';

/// The four-tab shell: Dashboard / Recipes / AI Assistant / Profile.
/// Tabs are kept alive with an IndexedStack so scroll position and chat
/// state survive switching.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialIndex;

  static const _tabs = [
    _TabSpec('Dashboard', Icons.dashboard_outlined, Icons.dashboard_rounded),
    _TabSpec('Recipes', Icons.restaurant_outlined, Icons.restaurant_rounded),
    _TabSpec('AI Chat', Icons.smart_toy_outlined, Icons.smart_toy_rounded),
    _TabSpec('Profile', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  void _goToTab(int i) {
    if (_index == i) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardScreen(onSeeAllRecipes: () => _goToTab(1)),
          const RecipesScreen(),
          const AiAssistantScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: _PillNavBar(
        tabs: _tabs,
        selectedIndex: _index,
        onTap: _goToTab,
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Animated pill-style bottom navigation bar.
///
/// The active tab has a rounded-rectangle pill highlight that
/// [AnimatedContainer] smoothly resizes and recolours. Inactive tabs
/// show only the icon; the active tab shows icon + label inside the pill.
class _PillNavBar extends StatelessWidget {
  const _PillNavBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<_TabSpec> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _PillNavItem(
                    spec: tabs[i],
                    selected: selectedIndex == i,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillNavItem extends StatelessWidget {
  const _PillNavItem({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _TabSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: spec.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: 52,
            height: 38,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                selected ? spec.activeIcon : spec.icon,
                key: ValueKey(selected),
                size: 24,
                color: selected ? Colors.white : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
