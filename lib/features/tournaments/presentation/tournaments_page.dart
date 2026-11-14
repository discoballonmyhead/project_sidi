import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/bloc/async_cubit.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../catalog/domain/catalog.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../domain/tournament.dart';
import 'tournament_cubits.dart';
import 'widgets/tournament_tile.dart';

/// "Tournaments" tab: what is open for entry or being played, and results.
class TournamentsPage extends StatelessWidget {
  const TournamentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(create: (_) => TournamentSearchCubit(sl())..load(), child: const _TournamentsView());
  }
}

class _TournamentsView extends StatefulWidget {
  const _TournamentsView();

  @override
  State<_TournamentsView> createState() => _TournamentsViewState();
}

class _TournamentsViewState extends State<_TournamentsView> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TournamentSearchCubit>();
    final sports = context.select<CatalogCubit, List<Sport>>((c) => c.state.data?.competitiveSports ?? const []);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tournaments'),
        actions: [TextButton(onPressed: () => context.push('/entries'), child: const Text('My entries'))],
      ),
      body: ContentWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                onChanged: (text) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () => cubit.search(query: text));
                },
                decoration: const InputDecoration(hintText: 'Search tournaments, venues, organisers', prefixIcon: Icon(Icons.search)),
              ),
            ),
            SizedBox(
              height: 44,
              child: BlocBuilder<TournamentSearchCubit, AsyncState<List<TournamentCard>>>(
                builder: (context, _) => ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(label: const Text('Results'), selected: cubit.past, onSelected: (on) => cubit.search(past: on)),
                    ),
                    for (final sport in sports)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: Icon(sportStyle(sport.code).icon, size: 16),
                          label: Text(sport.name),
                          selected: cubit.sport == sport.code,
                          onSelected: (on) => cubit.search(sport: () => on ? sport.code : null),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: AsyncView<TournamentSearchCubit, List<TournamentCard>>(
                builder: (context, tournaments, _) => tournaments.isEmpty
                    ? EmptyState(
                        icon: Icons.emoji_events_outlined,
                        title: cubit.past ? 'No finished tournaments yet' : 'No tournaments right now',
                        message: 'Tournaments published by organisations appear here.',
                      )
                    : ListView.separated(
                        padding: pagePadding,
                        itemCount: tournaments.length,
                        separatorBuilder: (_, _) => Gap.md,
                        itemBuilder: (context, index) => TournamentTile(tournaments[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MyEntriesPage extends StatelessWidget {
  const MyEntriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MyEntriesCubit(sl())..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('My entries')),
        body: AsyncView<MyEntriesCubit, List<EntryListing>>(
          builder: (context, entries, _) => entries.isEmpty
              ? const EmptyState(icon: Icons.emoji_events_outlined, title: 'No entries yet', message: 'Enter a tournament and it shows up here.')
              : ContentWidth(
                  child: ListView.separated(
                    padding: pagePadding,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => Gap.sm,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Card(
                        child: ListTile(
                          leading: SportAvatar(entry.sportCode),
                          title: Text(entry.tournamentName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [
                              entry.eventName,
                              Fmt.dayYear(entry.startsOn),
                              if (entry.payment?.status == 'pending') 'fee ${Fmt.money(entry.payment!.amount, entry.payment!.currency ?? 'INR')} due',
                              if (entry.finalRank != null) 'finished ${_ordinal(entry.finalRank!)}',
                            ].join(' · '),
                          ),
                          trailing: StatusChip(entry.status),
                          onTap: () => context.push('/event/${entry.eventId}'),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}
