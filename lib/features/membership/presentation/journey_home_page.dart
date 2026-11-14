import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../domain/membership.dart';
import 'membership_cubits.dart';

/// "Journey" tab: the user's memberships and mentorships.
class JourneyHomePage extends StatelessWidget {
  const JourneyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MyMembershipsCubit(sl())..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('My journey')),
        body: AsyncView<MyMembershipsCubit, List<Membership>>(
          builder: (context, memberships, _) => memberships.isEmpty
              ? EmptyState(
                  icon: Icons.insights_rounded,
                  title: 'Start your journey',
                  message: 'Join a club or a mentorship programme and your coach will track your sessions, '
                      'measurements and progress reports here.',
                  action: FilledButton.tonal(onPressed: () => context.go('/discover'), child: const Text('Find a club')),
                )
              : ContentWidth(
                  child: ListView.separated(
                    padding: pagePadding,
                    itemCount: memberships.length,
                    separatorBuilder: (_, _) => Gap.md,
                    itemBuilder: (context, index) => _MembershipCard(memberships[index]),
                  ),
                ),
        ),
      ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard(this.membership);
  final Membership membership;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<MyMembershipsCubit>();
    final live = membership.status == 'active' || membership.status == 'paused';
    final open = live || membership.status == 'pending';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: live && membership.tracksPerformance ? () => context.push('/journey/${membership.id}') : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SportAvatar(membership.sportCode, size: 44),
                  Gap.md,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(membership.planName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          '${membership.orgName} · ${Fmt.label(membership.tier)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  StatusChip(membership.status),
                ],
              ),
              Gap.md,
              Text(switch (membership.status) {
                'pending' => 'Waiting for the organisation to accept your request.',
                'active' when membership.tracksPerformance =>
                  '${membership.sessionCount} sessions · ${membership.reportCount} reports'
                      '${membership.coachName == null ? '' : ' · Coach ${membership.coachName}'}',
                'active' => membership.endsOn == null ? 'Active' : 'Renews ${Fmt.dayYear(membership.endsOn)}',
                _ => Fmt.label(membership.status),
              }, style: theme.textTheme.bodyMedium),
              if (open) ...[
                Gap.sm,
                Row(
                  children: [
                    if (live && membership.tracksPerformance)
                      FilledButton.tonalIcon(
                        onPressed: () => context.push('/journey/${membership.id}'),
                        icon: const Icon(Icons.insights_rounded, size: 18),
                        label: const Text('View progress'),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          title: membership.status == 'pending' ? 'Withdraw this request?' : 'Cancel this membership?',
                          message: membership.planName,
                          confirmLabel: membership.status == 'pending' ? 'Withdraw' : 'Cancel membership',
                          destructive: true,
                        );
                        if (ok) await cubit.cancel(membership);
                      },
                      child: Text(membership.status == 'pending' ? 'Withdraw' : 'Cancel'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
