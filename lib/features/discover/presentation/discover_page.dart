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
import '../domain/discover.dart';
import 'discover_cubits.dart';

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(create: (_) => OrgSearchCubit(sl())..load(), child: const _DiscoverView());
  }
}

class _DiscoverView extends StatefulWidget {
  const _DiscoverView();

  @override
  State<_DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<_DiscoverView> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => context.read<OrgSearchCubit>().search(query: text));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OrgSearchCubit>();
    final sports = context.select<CatalogCubit, List<Sport>>((c) => c.state.data?.sports ?? const []);
    return Scaffold(
      appBar: AppBar(title: const Text('Find a place to play')),
      body: ContentWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                onChanged: _onQueryChanged,
                decoration: const InputDecoration(hintText: 'Search clubs, academies, cities', prefixIcon: Icon(Icons.search)),
              ),
            ),
            SizedBox(
              height: 44,
              child: BlocBuilder<OrgSearchCubit, AsyncState<List<OrgCard>>>(
                builder: (context, _) => ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
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
              child: AsyncView<OrgSearchCubit, List<OrgCard>>(
                builder: (context, orgs, _) => orgs.isEmpty
                    ? const EmptyState(
                        icon: Icons.travel_explore_rounded,
                        title: 'Nothing here yet',
                        message: 'No approved organisation matches. Try another sport or search term.',
                      )
                    : ListView.separated(
                        padding: pagePadding,
                        itemCount: orgs.length,
                        separatorBuilder: (_, _) => Gap.md,
                        itemBuilder: (context, index) => _OrgTile(orgs[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrgTile extends StatelessWidget {
  const _OrgTile(this.org);
  final OrgCard org;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/org/${org.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: Text(org.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  if (org.isVerified) ...[Gap.xs, const VerifiedBadge()],
                ],
              ),
              if (org.city != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(org.city!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              if (org.description != null) ...[
                Gap.sm,
                Text(org.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              ],
              Gap.md,
              Row(
                children: [
                  for (final sport in org.sports.take(4))
                    Padding(padding: const EdgeInsets.only(right: 6), child: SportAvatar(sport, size: 28)),
                  const Spacer(),
                  if (org.resourceCount > 0)
                    Text(
                      org.minPrice == null || org.minPrice == 0
                          ? '${org.resourceCount} to book'
                          : '${org.resourceCount} to book · from ${Fmt.money(org.minPrice!, org.currency)}',
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
