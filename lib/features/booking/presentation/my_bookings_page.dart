import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../domain/booking.dart';
import 'booking_cubits.dart';

class MyBookingsPage extends StatelessWidget {
  const MyBookingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MyBookingsCubit(sl())..load(),
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('My bookings'),
            bottom: const TabBar(tabs: [Tab(text: 'Upcoming'), Tab(text: 'History')]),
          ),
          body: AsyncView<MyBookingsCubit, MyBookings>(
            refreshable: false,
            builder: (context, bookings, _) => TabBarView(
              children: [
                _BookingList(bookings.upcoming, emptyTitle: 'No upcoming bookings', showFind: true),
                _BookingList(bookings.past, emptyTitle: 'No past bookings yet'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingList extends StatelessWidget {
  const _BookingList(this.bookings, {required this.emptyTitle, this.showFind = false});
  final List<Booking> bookings;
  final String emptyTitle;
  final bool showFind;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MyBookingsCubit>();
    return RefreshIndicator(
      onRefresh: cubit.load,
      child: bookings.isEmpty
          ? EmptyState(
              icon: Icons.event_available_outlined,
              title: emptyTitle,
              message: showFind ? 'Find a court, table or gym slot near you.' : null,
              action: showFind ? FilledButton.tonal(onPressed: () => context.go('/discover'), child: const Text('Find a place')) : null,
            )
          : ContentWidth(
              child: ListView.separated(
                padding: pagePadding,
                itemCount: bookings.length,
                separatorBuilder: (_, _) => Gap.md,
                itemBuilder: (context, index) => BookingCard(
                  booking: bookings[index],
                  onCancel: bookings[index].canCancel
                      ? () async {
                          final ok = await confirm(
                            context,
                            title: 'Cancel this booking?',
                            message: '${bookings[index].resourceName} · ${Fmt.dayTime(bookings[index].startsAt)}',
                            confirmLabel: 'Cancel booking',
                            destructive: true,
                          );
                          if (ok) await cubit.cancel(bookings[index]);
                        }
                      : null,
                ),
              ),
            ),
    );
  }
}

/// A booking as the customer sees it. Reused by the front desk with [trailing].
class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking, this.onCancel, this.showCustomer = false, this.trailing});

  final Booking booking;
  final VoidCallback? onCancel;
  final bool showCustomer;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payment = booking.payment;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SportAvatar(booking.sportCode, size: 44),
            Gap.md,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showCustomer ? booking.customerName : booking.resourceName,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    showCustomer ? booking.resourceName : '${booking.orgName} · ${booking.facilityName}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${Fmt.day(booking.startsAt)} · ${Fmt.timeRange(booking.startsAt, booking.endsAt)}',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusChip(booking.status),
                      if (booking.kind != 'customer') StatusChip('info', label: Fmt.label(booking.kind)),
                      if (booking.price > 0)
                        Text(
                          '${Fmt.money(booking.price, booking.currency)}'
                          '${payment == null ? '' : ' · ${payment.status == 'pending' ? 'to pay' : payment.status}'}',
                          style: theme.textTheme.labelMedium,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onCancel != null)
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}
