import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../domain/booking.dart';
import 'booking_cubits.dart';

class BookResourcePage extends StatelessWidget {
  const BookResourcePage({super.key, required this.resourceId});
  final String resourceId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AvailabilityCubit(sl(), resourceId)..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Book a slot')),
        body: AsyncView<AvailabilityCubit, Availability>(
          refreshable: false,
          builder: (context, availability, state) => _BookingView(availability: availability, busy: state.busy),
        ),
      ),
    );
  }
}

class _BookingView extends StatefulWidget {
  const _BookingView({required this.availability, required this.busy});
  final Availability availability;
  final bool busy;

  @override
  State<_BookingView> createState() => _BookingViewState();
}

class _BookingViewState extends State<_BookingView> {
  DateTime? _start;
  int _slots = 1;

  List<Slot> get _all => widget.availability.slots;

  /// The run of consecutive slots starting at the selection.
  List<Slot> get _picked {
    final index = _all.indexWhere((s) => s.startsAt == _start);
    if (index < 0) return const [];
    return _all.skip(index).take(_slots).toList();
  }

  /// How many consecutive free slots follow the selected start.
  int get _maxSlots {
    final index = _all.indexWhere((s) => s.startsAt == _start);
    if (index < 0) return 1;
    var count = 0;
    for (var i = index; i < _all.length && count < 4; i++) {
      if (!_all[i].isFree || (i > index && _all[i].startsAt != _all[i - 1].endsAt)) break;
      count++;
    }
    return count.clamp(1, 4);
  }

  @override
  void didUpdateWidget(_BookingView old) {
    super.didUpdateWidget(old);
    // A reload (new day, or after booking) can invalidate the selection.
    if (!_all.any((s) => s.startsAt == _start && s.isFree)) {
      _start = null;
      _slots = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<AvailabilityCubit>();
    final resource = widget.availability.resource;
    final discount = widget.availability.discountPct;
    final picked = _picked;
    final gross = picked.fold<double>(0, (sum, s) => sum + s.price);
    final total = gross * (1 - discount / 100);
    final today = Days.of(DateTime.now());

    return ContentWidth(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: pagePadding,
              children: [
                Row(
                  children: [
                    SportAvatar(resource.sportCode, size: 48),
                    Gap.md,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(resource.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            '${resource.orgName} · ${resource.facilityName}',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Gap.lg,
                SizedBox(
                  height: 68,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 21,
                    separatorBuilder: (_, _) => Gap.sm,
                    itemBuilder: (context, index) {
                      final day = today.add(Duration(days: index));
                      final selected = Days.same(day, cubit.day);
                      return _DayChip(day: day, selected: selected, onTap: () => cubit.selectDay(day));
                    },
                  ),
                ),
                SectionHeader(Fmt.day(cubit.day)),
                if (_all.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: EmptyState(icon: Icons.event_busy_outlined, title: 'Closed on this day'),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final slot in _all)
                        _SlotChip(
                          slot: slot,
                          currency: resource.currency,
                          shared: resource.isShared,
                          selected: picked.contains(slot),
                          onTap: slot.isFree
                              ? () => setState(() {
                                  _start = slot.startsAt;
                                  _slots = 1;
                                })
                              : null,
                        ),
                    ],
                  ),
                Gap.lg,
                Text(
                  resource.autoConfirm
                      ? 'Free cancellation up to ${resource.cancelHours} hours before the start.'
                      : 'The venue confirms each request. Free cancellation up to ${resource.cancelHours} hours before.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (picked.isNotEmpty)
            Material(
              elevation: 8,
              color: theme.colorScheme.surfaceContainer,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              Fmt.timeRange(picked.first.startsLocal, picked.last.endsLocal),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              total == 0
                                  ? 'Free'
                                  : '${Fmt.money(total, resource.currency)}'
                                        '${discount > 0 ? ' · ${Fmt.number(discount)}% member discount' : ''} · pay at the venue',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (_maxSlots > 1) ...[
                        IconButton(
                          onPressed: _slots > 1 ? () => setState(() => _slots--) : null,
                          icon: const Icon(Icons.remove_circle_outline),
                          tooltip: 'Shorter',
                        ),
                        Text('${_slots * resource.slotMinutes} min'),
                        IconButton(
                          onPressed: _slots < _maxSlots ? () => setState(() => _slots++) : null,
                          icon: const Icon(Icons.add_circle_outline),
                          tooltip: 'Longer',
                        ),
                      ],
                      Gap.sm,
                      FilledButton(
                        onPressed: widget.busy ? null : () => cubit.book(picked.first, slots: _slots),
                        child: Text(resource.autoConfirm ? 'Book' : 'Request'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.selected, required this.onTap});
  final DateTime day;
  final bool selected;
  final VoidCallback onTap;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 54,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _weekdays[day.weekday - 1],
                style: TextStyle(fontSize: 12, color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
              ),
              Text(
                '${day.day}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: selected ? scheme.onPrimary : scheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.slot, required this.currency, required this.shared, required this.selected, this.onTap});
  final Slot slot;
  final String currency;
  final bool shared;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final foreground = selected
        ? scheme.onPrimary
        : enabled
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: 0.38);
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHigh.withValues(alpha: enabled ? 1 : 0.5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 96,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(Fmt.time(slot.startsLocal), style: TextStyle(fontWeight: FontWeight.w700, color: foreground)),
              Text(
                switch (slot.status) {
                  'full' => shared ? 'Full' : 'Booked',
                  'blocked' => 'Closed',
                  'past' => 'Passed',
                  _ => shared ? '${slot.remaining} left' : (slot.price == 0 ? 'Free' : Fmt.money(slot.price, currency)),
                },
                style: TextStyle(fontSize: 12, color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
