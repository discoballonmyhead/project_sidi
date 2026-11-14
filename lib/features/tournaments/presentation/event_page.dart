import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/form_sheet.dart';
import '../domain/tournament.dart';
import 'score_sheet_page.dart';
import 'tournament_cubits.dart';
import 'widgets/match_widgets.dart';

/// One event of a tournament. Everyone sees the draw, tables and results;
/// hosts also manage the field, run the engine, score and schedule from here.
class EventPage extends StatelessWidget {
  const EventPage({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => EventCubit(sl(), sl(), eventId)..load(),
      // The Material gives the loading and error states a surface to sit on;
      // once loaded, the event brings its own Scaffold.
      child: Material(
        child: AsyncView<EventCubit, EventView>(
          refreshable: false,
          builder: (context, view, state) => _EventScaffold(view, busy: state.busy),
        ),
      ),
    );
  }
}

class _EventScaffold extends StatelessWidget {
  const _EventScaffold(this.view, {required this.busy});
  final EventView view;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final event = view.detail;
    final cubit = context.read<EventCubit>();
    final started = !event.isSetup;
    final tabs = [
      if (started) const Tab(text: 'Draw & results'),
      Tab(text: event.canManage ? 'Field (${view.field.where((e) => e.status == 'accepted').length})' : 'Entrants'),
    ];
    return DefaultTabController(
      key: ValueKey(started),
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.name),
              Text(event.tournamentName, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          actions: [
            if (event.canManage && started)
              PopupMenuButton<String>(
                onSelected: (_) async {
                  final ok = await confirm(
                    context,
                    title: 'Reset this event?',
                    message: 'Every match, result and schedule of this event is deleted and the field returns to setup. This cannot be undone.',
                    confirmLabel: 'Reset event',
                    destructive: true,
                  );
                  if (ok) await cubit.reset();
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Reset event to setup'))],
              ),
          ],
          bottom: tabs.length > 1 ? TabBar(tabs: tabs) : null,
        ),
        body: TabBarView(
          children: [
            if (started) _StagesView(view),
            _FieldView(view, busy: busy),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The field: entries, seeds, and making the draw
// ---------------------------------------------------------------------------

class _FieldView extends StatelessWidget {
  const _FieldView(this.view, {required this.busy});
  final EventView view;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<EventCubit>();
    final event = view.detail;
    final accepted = view.field.where((e) => e.status == 'accepted').length;
    final manage = event.canManage;

    return RefreshIndicator(
      onRefresh: cubit.load,
      child: ContentWidth(
        child: ListView(
          padding: pagePadding,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.stages.map((s) => s.stage.formatName).join(' → '),
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        StatusChip(event.status, label: event.isSetup ? 'Setup' : null),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        event.ruleset.name,
                        '$accepted in the field${event.maxEntrants == null ? '' : ' of ${event.maxEntrants}'}',
                        event.entryFee == 0 ? 'Free entry' : 'Entry ${Fmt.money(event.entryFee, event.currency)}',
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (manage && event.isSetup) ...[
                      Gap.md,
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: busy || accepted < 2
                                ? null
                                : () async {
                                    final ok = await confirm(
                                      context,
                                      title: 'Make the draw?',
                                      message:
                                          '$accepted entrants go into ${event.stages.first.stage.name}. Entries still waiting are declined, '
                                          'and seeds are locked. You can reset the event afterwards if you need to start over.',
                                      confirmLabel: 'Make the draw',
                                    );
                                    if (ok) await cubit.start();
                                  },
                            icon: const Icon(Icons.account_tree_outlined, size: 18),
                            label: const Text('Make the draw'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _addEntrants(context),
                            icon: const Icon(Icons.group_add_outlined, size: 18),
                            label: const Text('Add entrants'),
                          ),
                        ],
                      ),
                      if (accepted < 2)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Accept at least two entrants to make the draw.', style: theme.textTheme.bodySmall),
                        ),
                    ],
                    if (!manage && event.isSetup)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('The draw has not been made yet.', style: theme.textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
            ),
            Gap.md,
            if (view.field.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: EmptyState(icon: Icons.groups_outlined, title: 'No entrants yet'),
              ),
            for (final entrant in view.field)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _EntrantTile(entrant, currency: event.currency, editable: manage && event.isSetup, manage: manage),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addEntrants(BuildContext context) async {
    final cubit = context.read<EventCubit>();
    final result = await showFormSheet(
      context,
      title: 'Add entrants',
      description: 'For walk-ups, invited teams or a list you already have. They go straight into the field.',
      submitLabel: 'Add',
      fields: const [FieldSpec.multiline('names', 'Names', required: true, helper: 'One per line. The order sets nothing; seed them afterwards.')],
    );
    if (result == null) return;
    final names = (result['names'] as String).split('\n').map((n) => n.trim()).where((n) => n.isNotEmpty).toList();
    if (names.isNotEmpty) await cubit.addEntrants(names);
  }
}

class _EntrantTile extends StatelessWidget {
  const _EntrantTile(this.entrant, {required this.currency, required this.editable, required this.manage});
  final Entrant entrant;
  final String currency;
  final bool editable;
  final bool manage;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<EventCubit>();
    final payment = entrant.payment;
    final others = entrant.members.where((m) => m.name != entrant.name).map((m) => m.name).join(', ');
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(entrant.finalRank != null ? '#${entrant.finalRank}' : (entrant.seed?.toString() ?? '-'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
        title: Text(entrant.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            if (entrant.seed != null) 'Seed ${entrant.seed}' else if (manage) 'Unseeded',
            if (others.isNotEmpty) others,
            if (manage && payment != null) 'fee ${payment.status == 'pending' ? 'due' : payment.status}',
            if (manage && entrant.contact != null) entrant.contact,
          ].whereType<String>().join(' · '),
        ),
        trailing: !manage
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entrant.status != 'accepted') StatusChip(entrant.status),
                  if (editable)
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        switch (value) {
                          case 'seed':
                            final result = await showFormSheet(
                              context,
                              title: 'Seed ${entrant.name}',
                              description: 'Seeds are kept apart in the draw. Leave empty for unseeded.',
                              fields: [FieldSpec.integer('seed', 'Seed', initial: entrant.seed)],
                            );
                            if (result != null) await cubit.seed(entrant, result['seed'] as int?);
                          case 'rename':
                            final result = await showFormSheet(
                              context,
                              title: 'Rename',
                              fields: [FieldSpec.text('name', 'Name', initial: entrant.name, required: true)],
                            );
                            if (result != null) await cubit.rename(entrant, result['name'] as String);
                          case 'remove':
                            if (await confirm(context, title: 'Remove ${entrant.name}?', confirmLabel: 'Remove', destructive: true)) {
                              await cubit.remove(entrant);
                            }
                          default:
                            await cubit.decide(entrant, value);
                        }
                      },
                      itemBuilder: (_) => [
                        if (entrant.status != 'accepted') const PopupMenuItem(value: 'accepted', child: Text('Accept')),
                        if (entrant.status == 'pending') const PopupMenuItem(value: 'waitlisted', child: Text('Wait-list')),
                        if (entrant.status != 'rejected') const PopupMenuItem(value: 'rejected', child: Text('Decline')),
                        const PopupMenuDivider(),
                        const PopupMenuItem(value: 'seed', child: Text('Set seed')),
                        const PopupMenuItem(value: 'rename', child: Text('Rename')),
                        const PopupMenuItem(value: 'remove', child: Text('Remove')),
                      ],
                    ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stages: tables, draws, fixtures
// ---------------------------------------------------------------------------

class _StagesView extends StatefulWidget {
  const _StagesView(this.view);
  final EventView view;

  @override
  State<_StagesView> createState() => _StagesViewState();
}

class _StagesViewState extends State<_StagesView> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<EventCubit>();
    final event = widget.view.detail;
    final stages = event.stages;
    // Default to the stage being played, or the last one that has finished.
    final live = stages.indexWhere((s) => s.stage.status == 'live');
    final index = _selected ?? (live >= 0 ? live : stages.lastIndexWhere((s) => s.stage.status == 'completed')).clamp(0, stages.length - 1);
    final stage = stages[index];
    final next = stages.elementAtOrNull(index + 1);
    final qualify = next?.stage.config['qualify'];
    final qualifiers = qualify is Map ? ((qualify['per_group'] ?? qualify['top']) as num?)?.toInt() ?? 0 : 0;
    final visible = stage.matches.where((m) => !m.isHidden).toList();
    final unscheduled = visible.where((m) => !m.isFinal && m.scheduledAt == null).length;

    final groups = <String, List<StandingRow>>{};
    for (final row in stage.standings) {
      groups.putIfAbsent(row.groupName ?? '', () => []).add(row);
    }
    final rounds = <int, List<MatchItem>>{};
    for (final match in visible) {
      rounds.putIfAbsent(match.roundNo, () => []).add(match);
    }

    void open(MatchItem match) => _openMatch(context, widget.view, match);

    return RefreshIndicator(
      onRefresh: cubit.load,
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          if (stages.length > 1)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final (i, s) in stages.indexed)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('${i + 1}. ${s.stage.name}'),
                        selected: i == index,
                        onSelected: s.stage.status == 'pending' ? null : (_) => setState(() => _selected = i),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${stage.stage.formatName} · ${Fmt.label(stage.stage.status)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                if (event.canManage && unscheduled > 0)
                  TextButton.icon(
                    onPressed: () => _autoSchedule(context, stage),
                    icon: const Icon(Icons.auto_awesome_motion_outlined, size: 18),
                    label: Text('Schedule $unscheduled'),
                  ),
              ],
            ),
          ),
          if (stage.isBracket)
            BracketView(matches: stage.matches, onTap: open)
          else
            for (final group in groups.entries)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (groups.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6, top: 4),
                          child: Text(group.key, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                      StandingsTable(rows: group.value, scoringKind: event.ruleset.scoringKind, qualifiers: qualifiers),
                    ],
                  ),
                ),
              ),
          for (final round in rounds.keys.toList()..sort())
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionHeader(stage.isBracket ? 'Round $round' : rounds[round]!.first.label.replaceAll(' bye', '')),
                    for (final match in rounds[round]!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: MatchTile(match, showLabel: stage.isBracket, onTap: event.canManage ? () => open(match) : null),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _autoSchedule(BuildContext context, StageDetail stage) async {
    final cubit = context.read<EventCubit>();
    final courts = widget.view.courts;
    if (courts.isEmpty) {
      cubit.say('Add courts under Facilities to schedule matches on them.', isError: true);
      return;
    }
    final result = await showFormSheet(
      context,
      title: 'Schedule ${stage.stage.name}',
      description: 'Lays the unscheduled matches across the courts round by round and holds the courts so customers cannot book them.',
      submitLabel: 'Schedule',
      fields: [
        FieldSpec.multiChoice('courts', 'Courts', {for (final c in courts) c.id: c.name}, initial: [courts.first.id], required: true),
        const FieldSpec.dateTime('starts_at', 'First match starts', required: true),
        const FieldSpec.integer('minutes', 'Minutes per match', initial: 45, required: true),
      ],
    );
    if (result == null) return;
    await cubit.autoSchedule(
      stage.stage.id,
      resourceIds: (result['courts'] as List).cast<String>(),
      startsAt: DateTime.parse(result['starts_at'] as String),
      matchMinutes: (result['minutes'] as int?) ?? 45,
    );
  }
}

/// What a host can do with a match, depending on where it stands.
Future<void> _openMatch(BuildContext context, EventView view, MatchItem match) async {
  final cubit = context.read<EventCubit>();
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('${match.nameA} v ${match.nameB}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(match.label),
          ),
          if (match.isPlayable)
            ListTile(leading: const Icon(Icons.scoreboard_outlined), title: const Text('Enter score'), onTap: () => Navigator.pop(context, 'score')),
          if (!match.isFinal)
            ListTile(leading: const Icon(Icons.schedule_outlined), title: const Text('Set court and time'), onTap: () => Navigator.pop(context, 'schedule')),
          if (!match.isFinal && match.scheduledAt != null)
            ListTile(leading: const Icon(Icons.event_busy_outlined), title: const Text('Clear schedule'), onTap: () => Navigator.pop(context, 'unschedule')),
          if (match.isFinal)
            ListTile(
              leading: const Icon(Icons.undo_rounded),
              title: const Text('Reopen to correct the result'),
              subtitle: const Text('Possible until the next match that depends on it is played'),
              onTap: () => Navigator.pop(context, 'reopen'),
            ),
          if (match.status == 'pending')
            const ListTile(leading: Icon(Icons.hourglass_empty_rounded), title: Text('Waiting for earlier results'), enabled: false),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'score':
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ScoreSheetPage(cubit: cubit, match: match, ruleset: view.detail.ruleset),
        ),
      );
    case 'schedule':
      final courts = view.courts;
      final result = await showFormSheet(
        context,
        title: 'Schedule ${match.label}',
        fields: [
          FieldSpec.choice(
            'resource_id',
            'Court',
            {for (final c in courts) c.id: c.name},
            initial: match.resourceId,
            required: false,
            helper: 'Holding a court blocks it for customer bookings.',
          ),
          FieldSpec.dateTime('starts_at', 'Start', initial: match.scheduledAt, required: true),
          const FieldSpec.integer('minutes', 'Minutes', initial: 45, required: true),
        ],
      );
      if (result != null) {
        await cubit.schedule(
          match,
          resourceId: result['resource_id'] as String?,
          startsAt: DateTime.parse(result['starts_at'] as String),
          minutes: (result['minutes'] as int?) ?? 45,
        );
      }
    case 'unschedule':
      await cubit.schedule(match);
    case 'reopen':
      await cubit.reopen(match);
  }
}
