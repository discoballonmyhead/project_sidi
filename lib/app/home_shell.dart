import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/session_cubit.dart';

/// The signed-in frame: five tabs, as a bottom bar on phones and a rail on
/// wide screens. Each tab keeps its own navigation stack.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static const _tabs = [
    (icon: Icons.travel_explore_outlined, selected: Icons.travel_explore, label: 'Discover'),
    (icon: Icons.event_available_outlined, selected: Icons.event_available, label: 'Bookings'),
    (icon: Icons.emoji_events_outlined, selected: Icons.emoji_events, label: 'Tournaments'),
    (icon: Icons.insights_outlined, selected: Icons.insights, label: 'Journey'),
    (icon: Icons.person_outline_rounded, selected: Icons.person_rounded, label: 'Account'),
  ];

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final unread = context.select<SessionCubit, int>((c) => c.state.me?.unreadNotifications ?? 0);
    Widget icon(int index, IconData data) => index == 4 && unread > 0 ? Badge(label: Text('$unread'), child: Icon(data)) : Icon(data);

    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Icon(Icons.sports_score_rounded, size: 32, color: Theme.of(context).colorScheme.primary),
              ),
              destinations: [
                for (final (index, tab) in _tabs.indexed)
                  NavigationRailDestination(icon: icon(index, tab.icon), selectedIcon: icon(index, tab.selected), label: Text(tab.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _go,
        destinations: [
          for (final (index, tab) in _tabs.indexed)
            NavigationDestination(icon: icon(index, tab.icon), selectedIcon: icon(index, tab.selected), label: tab.label),
        ],
      ),
    );
  }
}
