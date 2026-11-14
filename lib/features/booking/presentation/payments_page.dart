import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../domain/booking.dart';
import 'booking_cubits.dart';
import 'desk_page.dart';

/// What customers owe and have paid: bookings, memberships, entry fees.
class PaymentsPage extends StatelessWidget {
  const PaymentsPage({super.key, required this.orgId});
  final String orgId;

  static const _filters = {'pending': 'To collect', 'paid': 'Paid', null: 'All'};

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PaymentsCubit(sl(), orgId)..load(),
      child: Builder(
        builder: (context) {
          final cubit = context.read<PaymentsCubit>();
          return Scaffold(
            appBar: AppBar(title: const Text('Payments')),
            body: AsyncView<PaymentsCubit, List<Payment>>(
              refreshable: false,
              builder: (context, payments, _) => ContentWidth(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                        children: [
                          for (final filter in _filters.entries)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(label: Text(filter.value), selected: cubit.status == filter.key, onSelected: (_) => cubit.filter(filter.key)),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: cubit.load,
                        child: payments.isEmpty
                            ? const EmptyState(icon: Icons.payments_outlined, title: 'Nothing here')
                            : ListView.separated(
                                padding: pagePadding,
                                itemCount: payments.length,
                                separatorBuilder: (_, _) => Gap.sm,
                                itemBuilder: (context, index) => _PaymentTile(payments[index]),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile(this.payment);
  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PaymentsCubit>();
    return Card(
      child: ListTile(
        leading: Icon(switch (payment.purpose) {
          'booking' => Icons.event_available_outlined,
          'membership' => Icons.card_membership_outlined,
          'tournament_entry' => Icons.emoji_events_outlined,
          _ => Icons.receipt_outlined,
        }),
        title: Text(payment.payerName ?? payment.description ?? Fmt.label(payment.purpose), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            if (payment.payerName != null && payment.description != null) payment.description,
            Fmt.dayYear(payment.paidAt ?? payment.createdAt),
            if (payment.method != null) paymentMethods[payment.method] ?? payment.method,
          ].whereType<String>().join(' · '),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.money(payment.amount, payment.currency), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                StatusChip(payment.status),
              ],
            ),
            if (payment.status == 'pending' || payment.status == 'paid')
              PopupMenuButton<String>(
                onSelected: (value) => value.startsWith('pay:')
                    ? cubit.settle(payment, 'paid', method: value.substring(4))
                    : cubit.settle(payment, value),
                itemBuilder: (_) => [
                  if (payment.status == 'pending') ...[
                    for (final method in paymentMethods.entries)
                      PopupMenuItem(value: 'pay:${method.key}', child: Text('Paid by ${method.value.toLowerCase()}')),
                    const PopupMenuItem(value: 'waived', child: Text('Waive')),
                  ] else
                    const PopupMenuItem(value: 'refunded', child: Text('Refund')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
