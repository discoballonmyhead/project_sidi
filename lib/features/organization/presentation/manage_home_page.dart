import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../domain/organization.dart';
import 'org_forms.dart';
import 'organization_cubits.dart';

/// The manage section's home: today's numbers and the way into every tool
/// the caller's role and the organisation's features allow.
class ManageHomePage extends StatelessWidget {
  const ManageHomePage({super.key, required this.orgId});
  final String orgId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OrgOverviewCubit(sl(), orgId)..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Manage'),
            actions: [
              IconButton(
                tooltip: 'Public page',
                icon: const Icon(Icons.storefront_outlined),
                onPressed: () => context.push('/org/$orgId'),
              ),
            ],
          ),
          body: AsyncView<OrgOverviewCubit, OrgOverview>(builder: (context, overview, _) => _Dashboard(overview)),
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard(this.overview);
  final OrgOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = overview.org;
    final base = '/manage/${org.id}';
    final net = overview.amount('month_income') - overview.amount('month_expense');

    return ContentWidth(
      child: ListView(
        padding: pagePadding,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(org.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
                        if (org.isVerified) ...[Gap.sm, const VerifiedBadge(size: 20)],
                      ],
                    ),
                    Text(
                      '${Fmt.label(overview.myRole)}${org.city == null ? '' : ' · ${org.city}'}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (overview.canManage)
                IconButton(
                  tooltip: 'Edit details',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final cubit = context.read<OrgOverviewCubit>();
                    final catalog = context.read<CatalogCubit>().state.data;
                    if (catalog == null) return;
                    final patch = await showOrgEditForm(context, catalog, org);
                    if (patch != null) await cubit.update(patch);
                  },
                ),
            ],
          ),
          if (!overview.isApproved) ...[Gap.md, _StatusBanner(org.status)],
          Gap.lg,
          TileGrid(
            children: [
              if (overview.canDesk)
                StatTile(
                  label: 'Bookings today',
                  value: '${overview.stat('bookings_today')}',
                  icon: Icons.event_available_outlined,
                  onTap: () => context.push('$base/desk'),
                ),
              if (overview.canDesk)
                StatTile(
                  label: 'To collect',
                  value: Fmt.money(overview.amount('payments_due'), org.currency),
                  icon: Icons.payments_outlined,
                  onTap: () => context.push('$base/payments'),
                ),
              StatTile(
                label: 'Members',
                value: '${overview.stat('members_active')}',
                icon: Icons.groups_2_outlined,
                onTap: () => context.push('$base/members'),
              ),
              StatTile(
                label: 'Mentees',
                value: '${overview.stat('mentees')}',
                icon: Icons.insights_rounded,
                onTap: () => context.push('$base/members'),
              ),
              if (overview.canManage)
                StatTile(
                  label: 'Net this month',
                  value: Fmt.money(net, org.currency),
                  icon: Icons.account_balance_wallet_outlined,
                  color: net < 0 ? theme.colorScheme.error : const Color(0xFF1B8A4B),
                  onTap: () => context.push('$base/budget'),
                ),
              if (overview.canManage)
                StatTile(
                  label: 'Staff',
                  value: '${overview.stat('employees')}',
                  icon: Icons.badge_outlined,
                  onTap: () => context.push('$base/staff'),
                ),
            ],
          ),
          const SectionHeader('Day to day'),
          _Menu([
            if (overview.canDesk)
              _MenuItem(
                Icons.calendar_month_outlined,
                'Front desk',
                'Today\'s bookings, walk-ins and check-ins',
                '$base/desk',
                badge: overview.stat('bookings_pending'),
              ),
            if (overview.canDesk) _MenuItem(Icons.payments_outlined, 'Payments', 'Record what customers have paid', '$base/payments'),
            _MenuItem(
              Icons.groups_2_outlined,
              'Members & mentees',
              'Requests, coaches, sessions and progress reports',
              '$base/members',
              badge: overview.stat('members_pending'),
            ),
          ]),
          if (overview.canManage) ...[
            const SectionHeader('Set-up'),
            _Menu([
              _MenuItem(
                Icons.stadium_outlined,
                'Facilities & courts',
                '${overview.stat('facilities')} facilities · ${overview.stat('resources')} bookable',
                '$base/facilities',
              ),
              _MenuItem(Icons.card_membership_outlined, 'Plans', 'Passes, memberships and mentorship programmes', '$base/plans'),
              _MenuItem(Icons.manage_accounts_outlined, 'Team access', 'Who can run this organisation in the app', '$base/team'),
            ]),
            const SectionHeader('Competition'),
            _Menu([
              _MenuItem(
                Icons.emoji_events_outlined,
                'Tournaments',
                overview.has('tournaments')
                    ? '${overview.stat('tournaments_active')} running · draws, scoring, posters'
                    : 'Request access to host tournaments',
                overview.has('tournaments') ? '$base/tournaments' : '$base/access',
                badge: overview.stat('entrants_pending'),
                locked: !overview.has('tournaments'),
              ),
            ]),
            const SectionHeader('Money & people'),
            _Menu([
              _MenuItem(Icons.badge_outlined, 'Staff', 'Employees, roles and pay', '$base/staff'),
              _MenuItem(Icons.receipt_long_outlined, 'Payroll', 'Pay runs for each period', '$base/payroll'),
              _MenuItem(Icons.pie_chart_outline_rounded, 'Budget', 'Rent, running costs, income and limits', '$base/budget'),
            ]),
            const SectionHeader('Platform'),
            _Menu([
              _MenuItem(
                Icons.verified_outlined,
                'Access & verification',
                org.isVerified ? 'Verified · feature access' : 'Get verified and unlock features',
                '$base/access',
                badge: overview.stat('requests_pending'),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = status == 'pending';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pending ? scheme.secondaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(pending ? Icons.hourglass_top_rounded : Icons.block_rounded, color: pending ? scheme.onSecondaryContainer : scheme.onErrorContainer),
          Gap.md,
          Expanded(
            child: Text(switch (status) {
              'pending' => 'Waiting for approval. You will be notified as soon as the review is done; bookings and members open then.',
              'suspended' => 'This organisation is suspended. It is hidden from customers and cannot take bookings.',
              _ => 'This application was not approved. Check your notifications for the reason.',
            }, style: TextStyle(color: pending ? scheme.onSecondaryContainer : scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.icon, this.title, this.subtitle, this.route, {this.badge = 0, this.locked = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final int badge;
  final bool locked;
}

class _Menu extends StatelessWidget {
  const _Menu(this.items);
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (index, item) in items.indexed) ...[
            if (index > 0) const Divider(indent: 56),
            ListTile(
              leading: Icon(item.icon, color: scheme.primary),
              title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(item.subtitle),
              trailing: item.locked
                  ? Icon(Icons.lock_outline_rounded, size: 18, color: scheme.outline)
                  : item.badge > 0
                  ? Badge(label: Text('${item.badge}'))
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(item.route),
            ),
          ],
        ],
      ),
    );
  }
}
