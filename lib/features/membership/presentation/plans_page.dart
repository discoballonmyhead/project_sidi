import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_sheet.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../domain/membership.dart';
import 'membership_cubits.dart';

const planTiers = {
  'pass': 'Pass · casual access',
  'member': 'Member · regular access and discounts',
  'club': 'Club · squad training with progress tracking',
  'mentee': 'Mentee · one-to-one coaching with reports',
};
const billingPeriods = {'one_time': 'One-time', 'weekly': 'Weekly', 'monthly': 'Monthly', 'quarterly': 'Quarterly', 'yearly': 'Yearly'};

/// What the organisation sells beyond single slots.
class PlansPage extends StatelessWidget {
  const PlansPage({super.key, required this.orgId, required this.currency});
  final String orgId;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PlansCubit(sl(), orgId)..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Plans')),
          floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(context, null), icon: const Icon(Icons.add), label: const Text('New plan')),
          body: AsyncView<PlansCubit, List<Plan>>(
            builder: (context, plans, _) => plans.isEmpty
                ? const EmptyState(
                    icon: Icons.card_membership_outlined,
                    title: 'No plans yet',
                    message: 'Create passes, club memberships or mentorship programmes. Club and mentee plans give members a coach, '
                        'logged sessions and progress reports.',
                  )
                : ContentWidth(
                    child: ListView.separated(
                      padding: pagePadding.copyWith(bottom: 96),
                      itemCount: plans.length,
                      separatorBuilder: (_, _) => Gap.sm,
                      itemBuilder: (context, index) {
                        final plan = plans[index];
                        return Card(
                          child: ListTile(
                            leading: SportAvatar(plan.sportCode),
                            title: Text(plan.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              [
                                Fmt.label(plan.tier),
                                '${Fmt.money(plan.price, currency)} ${billingPeriods[plan.billingPeriod]?.toLowerCase() ?? ''}',
                                '${plan.memberCount} active',
                                if (plan.tracksPerformance) 'tracks progress',
                                if (!plan.isActive) 'hidden',
                              ].join(' · '),
                            ),
                            trailing: const Icon(Icons.edit_outlined, size: 20),
                            onTap: () => _edit(context, plan),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Plan? plan) async {
    final cubit = context.read<PlansCubit>();
    final catalog = context.read<CatalogCubit>().state.data;
    final result = await showFormSheet(
      context,
      title: plan == null ? 'New plan' : 'Edit plan',
      fields: [
        FieldSpec.text('name', 'Name', initial: plan?.name, required: true, hint: 'Junior squad'),
        FieldSpec.choice('tier', 'Tier', planTiers, initial: plan?.tier ?? 'member'),
        FieldSpec.choice(
          'sport_code',
          'Sport',
          {for (final sport in catalog?.sports ?? const []) sport.code: sport.name},
          initial: plan?.sportCode,
          required: false,
          helper: 'Leave empty for a plan that covers every sport.',
        ),
        FieldSpec.number('price', 'Price', initial: plan?.price ?? 0, required: true),
        FieldSpec.choice('billing_period', 'Billed', billingPeriods, initial: plan?.billingPeriod ?? 'monthly'),
        FieldSpec.number('booking_discount_pct', 'Discount on bookings (%)', initial: plan?.bookingDiscountPct ?? 0),
        FieldSpec.toggle(
          'tracks_performance',
          'Track performance',
          initial: plan?.tracksPerformance ?? false,
          helper: 'Members get a coach, logged sessions, measurements and progress reports.',
        ),
        FieldSpec.multiline('description', 'Description', initial: plan?.description),
        if (plan != null) FieldSpec.toggle('is_active', 'Open for new members', initial: plan.isActive),
      ],
    );
    if (result == null) return;
    // New club and mentee plans track performance unless switched off.
    if (plan == null && result['tracks_performance'] == false && const {'club', 'mentee'}.contains(result['tier'])) {
      result['tracks_performance'] = true;
    }
    await cubit.save({...result, 'id': ?plan?.id});
  }
}
