import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/network/rpc.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_sheet.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../domain/booking.dart';
import 'booking_cubits.dart';

const _tenures = {'owned': 'Owned', 'rented': 'Rented', 'leased': 'Leased'};
const _kinds = {
  'court': 'Court',
  'table': 'Table',
  'pitch': 'Pitch / ground',
  'net': 'Practice net',
  'gym_floor': 'Gym floor',
  'studio': 'Studio',
  'other': 'Other',
};
const _weekdays = {'1': 'Mon', '2': 'Tue', '3': 'Wed', '4': 'Thu', '5': 'Fri', '6': 'Sat', '0': 'Sun'};

/// Facilities (owned or rented halls) and the resources customers book.
class FacilitiesPage extends StatelessWidget {
  const FacilitiesPage({super.key, required this.orgId});
  final String orgId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => FacilitiesCubit(sl(), orgId)..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Facilities & courts')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _editFacility(context, null),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Add facility'),
          ),
          body: AsyncView<FacilitiesCubit, List<ManagedFacility>>(
            builder: (context, facilities, _) => facilities.isEmpty
                ? const EmptyState(
                    icon: Icons.stadium_outlined,
                    title: 'Add your first facility',
                    message: 'A facility is a hall, ground or gym. Add it, then list its courts, tables, nets or floors for booking.',
                  )
                : ContentWidth(
                    child: ListView(
                      padding: pagePadding.copyWith(bottom: 96),
                      children: [for (final facility in facilities) _FacilityCard(facility)],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

Future<void> _editFacility(BuildContext context, ManagedFacility? facility) async {
  final cubit = context.read<FacilitiesCubit>();
  final result = await showFormSheet(
    context,
    title: facility == null ? 'New facility' : 'Edit facility',
    fields: [
      FieldSpec.text('name', 'Name', initial: facility?.name, required: true, hint: 'Main hall'),
      FieldSpec.text('address', 'Address', initial: facility?.address),
      FieldSpec.text('city', 'City', initial: facility?.city),
      FieldSpec.choice('tenure', 'Tenure', _tenures, initial: facility?.tenure ?? 'owned'),
      if (facility == null)
        const FieldSpec.number(
          'monthly_cost',
          'Monthly rent or loan repayment',
          helper: 'Optional. Added to your budget as a recurring cost for this facility.',
        ),
      FieldSpec.integer(
        'cancel_hours',
        'Free cancellation window (hours)',
        initial: facility?.cancelHours ?? 6,
        helper: 'Customers can cancel up to this many hours before their slot.',
      ),
      if (facility != null) FieldSpec.toggle('is_active', 'Open for bookings', initial: facility.isActive),
    ],
  );
  if (result != null) await cubit.saveFacility({...result, 'id': ?facility?.id});
}

/// Builds the opening-hours rows the backend stores from the simple form:
/// one band per open day, split in two when a peak price is set.
List<Json> _hoursFromForm(Json form) {
  final days = (form['days'] as List).cast<String>();
  final opens = form['opens'] as String? ?? '06:00';
  final closes = form['closes'] as String? ?? '22:00';
  final peakFrom = form['peak_from'] as String?;
  final peakPrice = form['peak_price'] as num?;
  final hasPeak = peakFrom != null && peakPrice != null && peakFrom.compareTo(opens) > 0 && peakFrom.compareTo(closes) < 0;
  return [
    for (final day in days) ...[
      {'weekday': int.parse(day), 'opens': opens, 'closes': hasPeak ? peakFrom : closes},
      if (hasPeak) {'weekday': int.parse(day), 'opens': peakFrom, 'closes': closes, 'price': peakPrice},
    ],
  ];
}

Future<void> _editResource(BuildContext context, ManagedFacility facility, ManagedResource? managed) async {
  final cubit = context.read<FacilitiesCubit>();
  final catalog = context.read<CatalogCubit>().state.data;
  final resource = managed?.resource;
  final hours = managed?.hours ?? const <OpeningHours>[];
  final peak = hours.where((h) => h.price != null).firstOrNull;
  final sortedOpens = hours.map((h) => h.opens).toList()..sort();
  final sortedCloses = hours.map((h) => h.closes).toList()..sort();

  final result = await showFormSheet(
    context,
    title: resource == null ? 'New bookable resource' : 'Edit ${resource.name}',
    description: resource == null ? facility.name : null,
    fields: [
      FieldSpec.text('name', 'Name', initial: resource?.name, required: true, hint: 'Court 1'),
      FieldSpec.choice('sport_code', 'Sport', {for (final sport in catalog?.sports ?? const []) sport.code: sport.name}, initial: resource?.sportCode),
      FieldSpec.choice('kind', 'Type', _kinds, initial: resource?.kind ?? 'court'),
      FieldSpec.integer('slot_minutes', 'Slot length (minutes)', initial: resource?.slotMinutes ?? 60, required: true),
      FieldSpec.number('price', 'Price per slot', initial: resource?.price ?? 0, required: true),
      FieldSpec.integer(
        'capacity',
        'People per slot',
        initial: resource?.capacity ?? 1,
        required: true,
        helper: '1 for an exclusive court or table. More for a gym floor or group class.',
      ),
      FieldSpec.multiChoice('days', 'Open on', _weekdays, initial: hours.isEmpty ? _weekdays.keys : {for (final h in hours) '${h.weekday}'}, required: true),
      FieldSpec.text('opens', 'Opens', initial: sortedOpens.firstOrNull ?? '06:00', required: true, hint: '06:00'),
      FieldSpec.text('closes', 'Closes', initial: sortedCloses.lastOrNull ?? '22:00', required: true, hint: '22:00'),
      FieldSpec.text('peak_from', 'Peak hours start', initial: peak?.opens, hint: '18:00', helper: 'Optional. From this time until closing the peak price applies.'),
      FieldSpec.number('peak_price', 'Peak price per slot', initial: peak?.price),
      FieldSpec.toggle('auto_confirm', 'Confirm bookings automatically', initial: resource?.autoConfirm ?? true, helper: 'Off: each request waits for the front desk.'),
      if (resource != null) FieldSpec.toggle('is_active', 'Listed for booking', initial: resource.isActive),
    ],
  );
  if (result == null) return;
  final timePattern = RegExp(r'^([01]\d|2[0-4]):[0-5]\d$');
  for (final key in ['opens', 'closes', 'peak_from']) {
    final value = result[key] as String?;
    if (value != null && !timePattern.hasMatch(value)) {
      cubit.say('Times are written as HH:MM, for example 06:00 or 22:30.', isError: true);
      return;
    }
  }
  await cubit.saveResource({
    'id': ?resource?.id,
    'facility_id': facility.id,
    for (final key in ['name', 'sport_code', 'kind', 'slot_minutes', 'price', 'capacity', 'auto_confirm', 'is_active'])
      if (result.containsKey(key)) key: result[key],
    'hours': _hoursFromForm(result),
  });
}

Future<void> _blockResource(BuildContext context, ManagedResource managed) async {
  final cubit = context.read<FacilitiesCubit>();
  final result = await showFormSheet(
    context,
    title: 'Close ${managed.resource.name}',
    description: 'Customers cannot book during this time. Existing bookings are not changed.',
    submitLabel: 'Close',
    fields: const [
      FieldSpec.dateTime('from', 'From', required: true),
      FieldSpec.dateTime('to', 'Until', required: true),
      FieldSpec.text('reason', 'Reason', hint: 'Maintenance, private event'),
    ],
  );
  if (result == null) return;
  await cubit.block(
    managed.resource.id,
    DateTime.parse(result['from'] as String),
    DateTime.parse(result['to'] as String),
    result['reason'] as String?,
  );
}

class _FacilityCard extends StatelessWidget {
  const _FacilityCard(this.facility);
  final ManagedFacility facility;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(facility.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          [
                            _tenures[facility.tenure],
                            if (facility.monthlyCost > 0) '${Fmt.compact(facility.monthlyCost)} a month',
                            facility.city,
                            if (!facility.isActive) 'Closed',
                          ].whereType<String>().join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Edit facility', icon: const Icon(Icons.edit_outlined), onPressed: () => _editFacility(context, facility)),
                ],
              ),
              for (final managed in facility.resources) _ResourceRow(facility: facility, managed: managed),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _editResource(context, facility, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add court, table or floor'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({required this.facility, required this.managed});
  final ManagedFacility facility;
  final ManagedResource managed;

  @override
  Widget build(BuildContext context) {
    final resource = managed.resource;
    final cubit = context.read<FacilitiesCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: SportAvatar(resource.sportCode, size: 38),
          title: Text(resource.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              '${resource.slotMinutes} min',
              resource.price == 0 ? 'Free' : Fmt.money(resource.price, resource.currency),
              if (resource.isShared) '${resource.capacity} people',
              if (!resource.isActive) 'Hidden',
            ].join(' · '),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) => value == 'edit' ? _editResource(context, facility, managed) : _blockResource(context, managed),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit details and hours')),
              PopupMenuItem(value: 'block', child: Text('Close for a period')),
            ],
          ),
        ),
        for (final block in managed.blocks)
          Padding(
            padding: const EdgeInsets.only(left: 54, bottom: 4),
            child: InputChip(
              avatar: const Icon(Icons.block, size: 16),
              label: Text('Closed ${Fmt.dayTime(block.startsAt)} - ${Fmt.dayTime(block.endsAt)}${block.reason == null ? '' : ' · ${block.reason}'}'),
              onDeleted: () => cubit.unblock(block.id),
            ),
          ),
      ],
    );
  }
}
