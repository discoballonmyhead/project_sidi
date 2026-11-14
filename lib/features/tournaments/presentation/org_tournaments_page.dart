import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../domain/tournament.dart';
import 'tournament_cubits.dart';
import 'tournament_forms.dart';
import 'widgets/tournament_tile.dart';

/// Every tournament an organisation hosts, drafts included.
class OrgTournamentsPage extends StatelessWidget {
  const OrgTournamentsPage({super.key, required this.orgId});
  final String orgId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => OrgTournamentsCubit(sl(), orgId)..load(),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Tournaments')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _create(context),
            icon: const Icon(Icons.add),
            label: const Text('New tournament'),
          ),
          body: AsyncView<OrgTournamentsCubit, List<TournamentCard>>(
            builder: (context, tournaments, _) => tournaments.isEmpty
                ? const EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: 'Host your first tournament',
                    message: 'Create a draft, add events with the format you want, publish to take entries, '
                        'then let the engine make the draws and keep the tables.',
                  )
                : ContentWidth(
                    child: ListView.separated(
                      padding: pagePadding.copyWith(bottom: 96),
                      itemCount: tournaments.length,
                      separatorBuilder: (_, _) => Gap.md,
                      itemBuilder: (context, index) => TournamentTile(tournaments[index]),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final cubit = context.read<OrgTournamentsCubit>();
    final router = GoRouter.of(context);
    final catalog = context.read<CatalogCubit>().state.data;
    if (catalog == null) return;
    final result = await showTournamentForm(context, catalog);
    if (result == null) return;
    final id = await cubit.create(result);
    if (id != null) {
      await router.push('/tournament/$id');
      await cubit.load();
    }
  }
}
