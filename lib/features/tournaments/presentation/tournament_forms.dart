import 'package:flutter/material.dart';

import '../../../core/network/rpc.dart';
import '../../../core/widgets/form_sheet.dart';
import '../../catalog/domain/catalog.dart';
import '../domain/tournament.dart';

/// Create or edit a tournament's own details (events are edited separately).
Future<Json?> showTournamentForm(BuildContext context, Catalog catalog, {TournamentCard? existing}) => showFormSheet(
  context,
  title: existing == null ? 'New tournament' : 'Tournament details',
  description: existing == null ? 'It starts as a private draft. Add events, then publish to open entries.' : null,
  submitLabel: existing == null ? 'Create draft' : 'Save',
  fields: [
    FieldSpec.text('name', 'Name', initial: existing?.name, required: true, hint: 'Winter Open 2027'),
    if (existing == null)
      FieldSpec.choice('sport_code', 'Sport', {for (final sport in catalog.competitiveSports) sport.code: sport.name}),
    FieldSpec.date('starts_on', 'Starts', initial: existing?.startsOn, required: true),
    FieldSpec.date('ends_on', 'Ends', initial: existing?.endsOn, helper: 'Leave empty for a one-day tournament.'),
    FieldSpec.text('venue', 'Venue', initial: existing?.venue, hint: 'Hall name and area'),
    FieldSpec.dateTime('registration_closes_at', 'Entries close', initial: existing?.registrationClosesAt),
    FieldSpec.multiline('description', 'About', initial: existing?.description),
    FieldSpec.multiline('rules', 'Rules and notes for players', initial: existing?.rules),
  ],
);

/// The entry form: a player confirms, a pair or team names itself.
Future<Json?> showEntryForm(BuildContext context, EventSummary event, {required String currency, required String feeText}) {
  final solo = event.entrantKind == 'player';
  return showFormSheet(
    context,
    title: 'Enter ${event.name}',
    description: [
      event.rulesetName,
      event.formatSummary,
      feeText,
      'The organiser confirms each entry.',
    ].join(' · '),
    submitLabel: 'Send entry',
    fields: [
      if (!solo)
        FieldSpec.text(
          'name',
          event.entrantKind == 'pair' ? 'Pair name' : 'Team name',
          required: true,
          hint: event.entrantKind == 'pair' ? 'Rao / Mehta' : 'Riverside CC',
        ),
      if (!solo)
        FieldSpec.multiline(
          'members',
          event.entrantKind == 'pair' ? 'Your partner' : 'Team-mates',
          helper: 'One name per line. You are added as captain.',
        ),
      const FieldSpec.text('contact', 'Contact number', hint: 'So the organiser can reach you on the day'),
    ],
  );
}
