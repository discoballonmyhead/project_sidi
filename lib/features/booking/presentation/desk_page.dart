import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_sheet.dart';
import '../domain/booking.dart';
import 'booking_cubits.dart';
import 'my_bookings_page.dart';

const paymentMethods = {'cash': 'Cash', 'upi': 'UPI', 'card': 'Card', 'bank_transfer': 'Bank transfer', 'other': 'Other'};

/// The front desk: one day of bookings across every court, with check-in,
/// payment and walk-in bookings.
class DeskPage extends StatelessWidget {
  const DeskPage({super.key, required this.orgId});
  final String orgId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DeskCubit(sl(), orgId)..load(),
      child: Builder(
        builder: (context) {
          final cubit = context.read<DeskCubit>();
          return Scaffold(
            appBar: AppBar(title: const Text('Front desk')),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => _walkIn(context),
              icon: const Icon(Icons.add),
              label: const Text('Walk-in'),
            ),
            body: AsyncView<DeskCubit, DeskDay>(
              refreshable: false,
              builder: (context, desk, _) {
                final active = desk.bookings.where((b) => b.status != 'cancelled').toList();
                return ContentWidth(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left_rounded),
                              onPressed: () => cubit.selectDay(cubit.day.subtract(const Duration(days: 1))),
                            ),
                            Expanded(
                              child: TextButton(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: cubit.day,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (picked != null) await cubit.selectDay(picked);
                                },
                                child: Text(
                                  Days.same(cubit.day, DateTime.now()) ? 'Today · ${Fmt.day(cubit.day)}' : Fmt.dayYear(cubit.day),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right_rounded),
                              onPressed: () => cubit.selectDay(cubit.day.add(const Duration(days: 1))),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: cubit.load,
                          child: active.isEmpty
                              ? const EmptyState(icon: Icons.event_note_outlined, title: 'No bookings on this day')
                              : ListView.separated(
                                  padding: pagePadding.copyWith(bottom: 96),
                                  itemCount: active.length,
                                  separatorBuilder: (_, _) => Gap.md,
                                  itemBuilder: (context, index) => BookingCard(
                                    booking: active[index],
                                    showCustomer: true,
                                    trailing: _BookingMenu(active[index]),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _walkIn(BuildContext context) async {
    final cubit = context.read<DeskCubit>();
    final resources = [
      for (final facility in cubit.state.data?.facilities ?? const <ManagedFacility>[])
        for (final managed in facility.resources)
          if (managed.resource.isActive) managed.resource,
    ];
    if (resources.isEmpty) {
      cubit.say('Add a court or table under Facilities first.', isError: true);
      return;
    }
    final now = DateTime.now();
    final result = await showFormSheet(
      context,
      title: 'Walk-in booking',
      description: 'For customers at the counter or on the phone. Must start on a slot inside opening hours.',
      submitLabel: 'Book',
      fields: [
        FieldSpec.choice('resource_id', 'Court / table', {for (final r in resources) r.id: '${r.name} · ${r.facilityName}'}, initial: resources.first.id),
        FieldSpec.dateTime('starts_at', 'Start', initial: DateTime(cubit.day.year, cubit.day.month, cubit.day.day, now.hour + 1), required: true),
        const FieldSpec.integer('slots', 'Number of slots', initial: 1, required: true),
        const FieldSpec.text('customer_name', 'Customer name'),
        const FieldSpec.text('handle', 'Or their username / e-mail', helper: 'Links the booking to their account so they see it in the app.'),
        const FieldSpec.number('price', 'Price', helper: 'Leave empty to charge the listed price.'),
      ],
    );
    if (result == null) return;
    await cubit.walkIn(
      result['resource_id'] as String,
      DateTime.parse(result['starts_at'] as String),
      slots: (result['slots'] as int?) ?? 1,
      name: result['customer_name'] as String?,
      handle: result['handle'] as String?,
      price: result['price'] as num?,
    );
  }
}

class _BookingMenu extends StatelessWidget {
  const _BookingMenu(this.booking);
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DeskCubit>();
    final payment = booking.payment;
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value.startsWith('pay:')) {
          await cubit.settle(payment!, 'paid', method: value.substring(4));
        } else if (value == 'refund' || value == 'waive') {
          await cubit.settle(payment!, value == 'refund' ? 'refunded' : 'waived');
        } else if (value == 'cancelled') {
          if (await confirm(context, title: 'Cancel this booking?', message: booking.customerName, confirmLabel: 'Cancel booking', destructive: true)) {
            await cubit.setStatus(booking, value);
          }
        } else {
          await cubit.setStatus(booking, value);
        }
      },
      itemBuilder: (_) => [
        if (booking.status == 'pending') const PopupMenuItem(value: 'confirmed', child: Text('Confirm booking')),
        if (booking.status == 'confirmed') const PopupMenuItem(value: 'completed', child: Text('Checked in · completed')),
        if (booking.status == 'confirmed') const PopupMenuItem(value: 'no_show', child: Text('No-show')),
        if (payment?.status == 'pending') ...[
          const PopupMenuDivider(),
          for (final method in paymentMethods.entries) PopupMenuItem(value: 'pay:${method.key}', child: Text('Paid by ${method.value.toLowerCase()}')),
          const PopupMenuItem(value: 'waive', child: Text('Waive payment')),
        ],
        if (payment?.status == 'paid') const PopupMenuItem(value: 'refund', child: Text('Refund payment')),
        if (booking.isOpen) ...[const PopupMenuDivider(), const PopupMenuItem(value: 'cancelled', child: Text('Cancel booking'))],
      ],
    );
  }
}
