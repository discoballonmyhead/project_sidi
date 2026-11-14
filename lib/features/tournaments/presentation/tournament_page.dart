import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/network/rpc.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../auth/presentation/session_cubit.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../domain/tournament.dart';
import 'event_form_page.dart';
import 'poster_studio_page.dart';
import 'tournament_cubits.dart';
import 'tournament_forms.dart';

class TournamentPage extends StatelessWidget {
  const TournamentPage({super.key, required this.tournamentId});
  final String tournamentId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TournamentDetailCubit(sl(), tournamentId)..load(),
      child: Scaffold(
        appBar: AppBar(),
        body: AsyncView<TournamentDetailCubit, TournamentDetail>(builder: (context, detail, state) => _TournamentView(detail, busy: state.busy)),
      ),
    );
  }
}

class _TournamentView extends StatelessWidget {
  const _TournamentView(this.detail, {required this.busy});
  final TournamentDetail detail;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = detail.tournament;
    return ContentWidth(
      child: ListView(
        padding: pagePadding,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SportAvatar(t.sportCode, size: 56),
              Gap.md,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    InkWell(
                      onTap: () => context.push('/org/${t.orgId}'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: Text(t.orgName, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary))),
                          if (t.orgIsVerified) ...[Gap.xs, const VerifiedBadge()],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              StatusChip(t.status, label: t.status == 'open' ? 'Entries open' : t.status == 'closed' ? 'Entries closed' : null),
            ],
          ),
          Gap.md,
          _Fact(Icons.calendar_today_outlined, Fmt.range(t.startsOn, t.endsOn)),
          _Fact(Icons.place_outlined, t.place),
          if (t.registrationClosesAt != null && t.status == 'open') _Fact(Icons.timer_outlined, 'Enter by ${Fmt.dayTime(t.registrationClosesAt)}'),
          if (t.description != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(t.description!)),
          if (t.rules != null)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Rules and notes'),
              childrenPadding: const EdgeInsets.only(bottom: 12),
              expandedAlignment: Alignment.centerLeft,
              children: [Text(t.rules!)],
            ),
          if (detail.canManage) ...[Gap.md, _HostPanel(detail, busy: busy)],
          SectionHeader(
            'Events',
            trailing: detail.canManage && t.status != 'completed' && t.status != 'cancelled'
                ? TextButton.icon(onPressed: () => _editEvent(context, detail, null), icon: const Icon(Icons.add, size: 18), label: const Text('Add event'))
                : null,
          ),
          if (detail.events.isEmpty)
            Text(
              detail.canManage ? 'Add an event: pick how it is scored and which format the draw follows.' : 'Events will be announced soon.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          for (final event in detail.events) Padding(padding: const EdgeInsets.only(bottom: 10), child: _EventCard(detail, event, busy: busy)),
          if (detail.posters.isNotEmpty || detail.canManage) ...[
            SectionHeader(
              'Posters',
              trailing: detail.canManage
                  ? PopupMenuButton<String>(
                      onSelected: (kind) => _openStudio(context, kind, null),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'promotion', child: Text('Promotion poster')),
                        PopupMenuItem(value: 'winner', child: Text('Winners poster')),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add, size: 18), SizedBox(width: 4), Text('Design')]),
                      ),
                    )
                  : null,
            ),
            if (detail.posters.isEmpty)
              Text(
                'Design a poster to promote the tournament, and a winners poster once it is over.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else
              SizedBox(
                height: 300,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: detail.posters.length,
                  separatorBuilder: (_, _) => Gap.md,
                  itemBuilder: (context, index) => _PosterTile(detail.posters[index], canManage: detail.canManage),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

Future<void> _openStudio(BuildContext context, String kind, Poster? poster) {
  final cubit = context.read<TournamentDetailCubit>();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => PosterStudioPage(cubit: cubit, kind: kind, poster: poster)),
  );
}

Future<void> _editEvent(BuildContext context, TournamentDetail detail, EventSummary? event) async {
  final cubit = context.read<TournamentDetailCubit>();
  final catalog = context.read<CatalogCubit>().state.data;
  if (catalog == null) return;
  final org = context.read<SessionCubit>().state.me?.organizations.where((o) => o.id == detail.tournament.orgId).firstOrNull;
  final result = await Navigator.of(context).push<Json>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EventFormPage(
        catalog: catalog,
        sportCode: detail.tournament.sportCode,
        existing: event,
        canChargeFees: org?.has('paid_entries') ?? false,
      ),
    ),
  );
  if (result != null) await cubit.saveEvent(result);
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        Gap.sm,
        Expanded(child: Text(text)),
      ],
    ),
  );
}

/// What the host can do with the tournament as a whole.
class _HostPanel extends StatelessWidget {
  const _HostPanel(this.detail, {required this.busy});
  final TournamentDetail detail;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TournamentDetailCubit>();
    final t = detail.tournament;
    final pending = detail.events.fold<int>(0, (sum, e) => sum + e.pendingCount);
    final (hint, label, next) = switch (t.status) {
      'draft' => ('Only your team can see this draft.', 'Publish & open entries', 'open'),
      'open' => ('Published. People can enter.', 'Close entries', 'closed'),
      'closed' => ('Entries are closed. Make the draw in each event.', 'Reopen entries', 'open'),
      'live' => ('Being played. Score matches in each event.', null, null),
      'completed' => ('Finished. Design a winners poster to share the results.', null, null),
      _ => ('This tournament was cancelled.', null, null),
    };
    return Card(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 18, color: theme.colorScheme.onSecondaryContainer),
                Gap.sm,
                Expanded(child: Text('You host this tournament', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      final catalog = context.read<CatalogCubit>().state.data;
                      if (catalog == null) return;
                      final patch = await showTournamentForm(context, catalog, existing: t);
                      if (patch != null) await cubit.save(patch);
                    } else if (value == 'draft') {
                      await cubit.setStatus('draft');
                    } else if (await confirm(
                      context,
                      title: 'Cancel this tournament?',
                      message: 'It is taken down for everyone. Entry fees already paid must be refunded from Payments.',
                      confirmLabel: 'Cancel tournament',
                      destructive: true,
                    )) {
                      await cubit.setStatus('cancelled');
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit details')),
                    if (t.status == 'open') const PopupMenuItem(value: 'draft', child: Text('Unpublish')),
                    if (const {'draft', 'open', 'closed', 'live'}.contains(t.status)) const PopupMenuItem(value: 'cancel', child: Text('Cancel tournament')),
                  ],
                ),
              ],
            ),
            Text(
              pending > 0 ? '$hint $pending entr${pending == 1 ? 'y' : 'ies'} waiting for you.' : hint,
              style: theme.textTheme.bodyMedium,
            ),
            if (label != null) ...[
              Gap.md,
              FilledButton(onPressed: busy ? null : () => cubit.setStatus(next!), child: Text(label)),
            ],
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard(this.detail, this.event, {required this.busy});
  final TournamentDetail detail;
  final EventSummary event;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TournamentDetailCubit>();
    final t = detail.tournament;
    final entry = event.myEntry;
    final entryLive = entry != null && const {'pending', 'accepted', 'waitlisted'}.contains(entry.status);
    final canEnter = t.registrationOpen && event.status == 'setup' && !entryLive;
    final feeText = event.entryFee == 0 ? 'Free entry' : 'Entry ${Fmt.money(event.entryFee, t.currency)}';
    final full = event.maxEntrants != null && event.acceptedCount >= event.maxEntrants!;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/event/${event.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(event.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  if (event.status != 'setup') StatusChip(event.status),
                  if (detail.canManage && event.pendingCount > 0)
                    Padding(padding: const EdgeInsets.only(left: 8), child: Badge(label: Text('${event.pendingCount} to review'))),
                  if (detail.canManage && event.status == 'setup')
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'edit') {
                          await _editEvent(context, detail, event);
                        } else if (await confirm(context, title: 'Delete ${event.name}?', message: 'Its entries are removed too.', confirmLabel: 'Delete', destructive: true)) {
                          await cubit.deleteEvent(event);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit event and format')),
                        PopupMenuItem(value: 'delete', child: Text('Delete event')),
                      ],
                    )
                  else
                    const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.chevron_right_rounded)),
                ],
              ),
              Text(
                '${event.formatSummary} · ${event.rulesetName}',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                '${event.acceptedCount}${event.maxEntrants == null ? '' : ' / ${event.maxEntrants}'} entered · $feeText',
                style: theme.textTheme.bodySmall,
              ),
              if (event.podium.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      // Rank 3 can be shared when no third-place match was played.
                      for (final place in event.podium.where((p) => p.rank <= 3))
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              place.rank == 1 ? Icons.emoji_events_rounded : Icons.military_tech_outlined,
                              size: 18,
                              color: switch (place.rank) { 1 => const Color(0xFFD4A017), 2 => const Color(0xFF8A8D91), _ => const Color(0xFFB0703C) },
                            ),
                            const SizedBox(width: 4),
                            Text(place.name, style: TextStyle(fontWeight: place.rank == 1 ? FontWeight.w800 : FontWeight.w500)),
                          ],
                        ),
                    ],
                  ),
                ),
              if (entryLive || canEnter) ...[
                Gap.md,
                Row(
                  children: [
                    if (entryLive) ...[
                      StatusChip(entry.status, label: switch (entry.status) { 'accepted' => 'You are in', 'waitlisted' => 'On the waiting list', _ => 'Entry sent' }),
                      if (entry.payment?.status == 'pending')
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text('Fee due at the venue', style: theme.textTheme.labelMedium),
                        ),
                      const Spacer(),
                      if (event.status == 'setup')
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  if (await confirm(context, title: 'Withdraw your entry?', message: event.name, confirmLabel: 'Withdraw', destructive: true)) {
                                    await cubit.withdraw(entry);
                                  }
                                },
                          child: const Text('Withdraw'),
                        ),
                    ] else ...[
                      const Spacer(),
                      FilledButton.tonal(
                        onPressed: busy
                            ? null
                            : () async {
                                final result = await showEntryForm(context, event, currency: t.currency, feeText: feeText);
                                if (result == null) return;
                                await cubit.register(
                                  event,
                                  name: result['name'] as String?,
                                  members: (result['members'] as String? ?? '').split('\n').map((m) => m.trim()).where((m) => m.isNotEmpty).toList(),
                                  contact: result['contact'] as String?,
                                );
                              },
                        child: Text(full ? 'Join waiting list' : 'Enter'),
                      ),
                    ],
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

class _PosterTile extends StatelessWidget {
  const _PosterTile(this.poster, {required this.canManage});
  final Poster poster;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TournamentDetailCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => canManage
                ? _openStudio(context, poster.kind, poster)
                : showDialog<void>(
                    context: context,
                    builder: (context) => Dialog(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(onTap: () => Navigator.pop(context), child: PosterThumb(poster)),
                    ),
                  ),
            child: PosterThumb(poster),
          ),
        ),
        if (canManage)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              posterStatus(poster),
              IconButton(
                tooltip: 'Delete poster',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  if (await confirm(context, title: 'Delete this poster?', confirmLabel: 'Delete', destructive: true)) await cubit.deletePoster(poster);
                },
              ),
            ],
          ),
      ],
    );
  }
}
