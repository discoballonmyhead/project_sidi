import 'package:flutter/material.dart';

import '../utils/format.dart';

/// Icon and colour for a sport code.
({IconData icon, Color color}) sportStyle(String? code) => switch (code) {
  'badminton' => (icon: Icons.sports_tennis_rounded, color: const Color(0xFF0B8457)),
  'table_tennis' => (icon: Icons.sports_baseball_rounded, color: const Color(0xFF1565C0)),
  'cricket' => (icon: Icons.sports_cricket_rounded, color: const Color(0xFFD9730D)),
  'gym' => (icon: Icons.fitness_center_rounded, color: const Color(0xFF6A3FB5)),
  _ => (icon: Icons.sports_rounded, color: const Color(0xFF546E7A)),
};

class SportAvatar extends StatelessWidget {
  const SportAvatar(this.code, {super.key, this.size = 40});

  final String? code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = sportStyle(code);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: style.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(style.icon, color: style.color, size: size * 0.55),
    );
  }
}

/// A small coloured pill for a status slug (`pending`, `confirmed`, ...).
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.label});

  final String status;
  final String? label;

  static Color colorOf(String status, ColorScheme scheme) => switch (status) {
    'confirmed' || 'approved' || 'active' || 'accepted' || 'paid' || 'completed' || 'open' || 'enabled' => const Color(0xFF1B8A4B),
    'pending' || 'waitlisted' || 'draft' || 'setup' || 'paused' || 'closed' || 'ready' => const Color(0xFFB7791F),
    'live' => const Color(0xFFD32F2F),
    'cancelled' || 'rejected' || 'suspended' || 'no_show' || 'refunded' || 'void' || 'withdrawn' || 'expired' => scheme.error,
    _ => scheme.outline,
  };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(status, Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
      child: Text(
        label ?? Fmt.label(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) =>
      Tooltip(message: 'Verified organisation', child: Icon(Icons.verified_rounded, size: size, color: const Color(0xFF1976D2)));
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          ?trailing,
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon, this.color, this.onTap});

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (icon != null) ...[Icon(icon, size: 18, color: color ?? theme.colorScheme.primary), const SizedBox(width: 6)],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A responsive grid of fixed-height tiles.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minTileWidth = 150, this.tileHeight = 92});

  final List<Widget> children;
  final double minTileWidth;
  final double tileHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minTileWidth).floor().clamp(2, 6);
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: ((constraints.maxWidth - (columns - 1) * 10) / columns) / tileHeight,
          children: children,
        );
      },
    );
  }
}

/// Keeps content readable on wide screens.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 880});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
