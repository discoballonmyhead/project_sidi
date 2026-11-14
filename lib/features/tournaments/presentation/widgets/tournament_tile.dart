import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/common.dart';
import '../../domain/tournament.dart';

class TournamentTile extends StatelessWidget {
  const TournamentTile(this.tournament, {super.key, this.showStatus = true});

  final TournamentCard tournament;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fee = tournament.minEntryFee;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/tournament/${tournament.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SportAvatar(tournament.sportCode, size: 46),
              Gap.md,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tournament.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Fmt.range(tournament.startsOn, tournament.endsOn)} · ${tournament.place}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (showStatus) ...[
                          StatusChip(tournament.status, label: tournament.status == 'open' ? 'Entries open' : null),
                          Gap.sm,
                        ],
                        Flexible(
                          child: Text(
                            '${tournament.eventCount} event${tournament.eventCount == 1 ? '' : 's'}'
                            ' · ${tournament.entrantCount} entered'
                            '${fee == null ? '' : fee == 0 ? ' · Free entry' : ' · from ${Fmt.money(fee, tournament.currency)}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
