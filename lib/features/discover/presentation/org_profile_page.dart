import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_sheet.dart';
import '../../booking/domain/booking.dart';
import '../../membership/domain/membership.dart';
import '../../tournaments/presentation/widgets/tournament_tile.dart';
import '../domain/discover.dart';
import 'discover_cubits.dart';

class OrgProfilePage extends StatelessWidget {
  const OrgProfilePage({super.key, required this.orgId});
  final String orgId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OrgProfileCubit(sl(), sl(), orgId)..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            actions: [
              PopupMenuButton<String>(
                onSelected: (_) => _report(context),
                itemBuilder: (_) => const [PopupMenuItem(value: 'report', child: Text('Report this organisation'))],
              ),
            ],
          ),
          body: AsyncView<OrgProfileCubit, OrgProfile>(builder: (context, profile, _) => _Body(profile)),
        ),
      ),
    );
  }

  Future<void> _report(BuildContext context) async {
    final cubit = context.read<OrgProfileCubit>();
    final result = await showFormSheet(
      context,
      title: 'Report this organisation',
      description: 'Tell our moderators what is wrong. Reports are confidential.',
      submitLabel: 'Send report',
      fields: const [FieldSpec.multiline('reason', 'What is wrong?', required: true)],
    );
    if (result != null) await cubit.report(result['reason'] as String);
  }
}

class _Body extends StatelessWidget {
  const _Body(this.profile);
  final OrgProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final org = profile.org;
    final contact = [org.address, org.city, org.contactPhone, org.contactEmail].whereType<String>().join(' · ');
    return ContentWidth(
      child: ListView(
        padding: pagePadding,
        children: [
          Row(
            children: [
              Flexible(child: Text(org.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
              if (org.isVerified) ...[Gap.sm, const VerifiedBadge(size: 22)],
            ],
          ),
          if (org.status != 'approved') Padding(padding: const EdgeInsets.only(top: 6), child: StatusChip(org.status)),
          if (contact.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(contact, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          if (org.description != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(org.description!)),
          if (profile.myRole != null) ...[
            Gap.lg,
            FilledButton.tonalIcon(
              onPressed: () => context.push('/manage/${org.id}'),
              icon: const Icon(Icons.dashboard_customize_outlined),
              label: const Text('Manage this organisation'),
            ),
          ],
          if (profile.facilities.any((f) => f.resources.isNotEmpty)) ...[
            const SectionHeader('Book a slot'),
            for (final facility in profile.facilities.where((f) => f.resources.isNotEmpty)) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  [facility.name, facility.city].whereType<String>().join(' · '),
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              for (final resource in facility.resources)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: _ResourceTile(resource)),
            ],
          ],
          if (profile.plans.isNotEmpty) ...[
            const SectionHeader('Memberships & coaching'),
            for (final plan in profile.plans)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PlanTile(plan: plan, currency: org.currency, mine: profile.membershipFor(plan.id)),
              ),
          ],
          if (profile.tournaments.isNotEmpty) ...[
            const SectionHeader('Tournaments'),
            for (final tournament in profile.tournaments)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: TournamentTile(tournament)),
          ],
          if (profile.facilities.every((f) => f.resources.isEmpty) && profile.plans.isEmpty && profile.tournaments.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: EmptyState(
                icon: Icons.hourglass_empty_rounded,
                title: 'Nothing published yet',
                message: 'This organisation has not listed any courts, plans or tournaments.',
              ),
            ),
        ],
      ),
    );
  }
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile(this.resource);
  final Resource resource;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: SportAvatar(resource.sportCode),
        title: Text(resource.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${Fmt.label(resource.kind)} · ${resource.slotMinutes} min'
          '${resource.isShared ? ' · up to ${resource.capacity} people' : ''}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              resource.price == 0 ? 'Free' : Fmt.money(resource.price, resource.currency),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text('per slot', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        onTap: () => context.push('/book/${resource.id}'),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan, required this.currency, this.mine});
  final Plan plan;
  final String currency;
  final Membership? mine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perks = [
      if (plan.tracksPerformance) 'Coach, sessions and progress reports',
      if (plan.bookingDiscountPct > 0) '${Fmt.number(plan.bookingDiscountPct)}% off bookings',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(plan.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                StatusChip('info', label: Fmt.label(plan.tier)),
              ],
            ),
            if (plan.description != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(plan.description!)),
            for (final perk in perks)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 16, color: theme.colorScheme.primary),
                    Gap.sm,
                    Expanded(child: Text(perk, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
            Gap.md,
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.price == 0
                        ? 'Free'
                        : '${Fmt.money(plan.price, currency)}${plan.billingPeriod == 'one_time' ? '' : ' / ${plan.billingPeriod.replaceAll('ly', '')}'}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (mine != null)
                  StatusChip(mine!.status, label: mine!.status == 'active' ? 'You are a member' : null)
                else
                  FilledButton.tonal(onPressed: () => _join(context), child: const Text('Join')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _join(BuildContext context) async {
    final cubit = context.read<OrgProfileCubit>();
    final result = await showFormSheet(
      context,
      title: 'Join ${plan.name}',
      description: 'The organisation reviews every request. Payment is settled with them once you are accepted.',
      submitLabel: 'Send request',
      fields: const [FieldSpec.multiline('note', 'Anything they should know?', hint: 'Experience, goals, preferred times')],
    );
    if (result != null) await cubit.join(plan, note: result['note'] as String?);
  }
}
