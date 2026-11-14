import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/common.dart';
import '../../domain/tournament.dart';

/// One side of a match: seed, name and whether it won.
class _SideRow extends StatelessWidget {
  const _SideRow({required this.name, this.seed, required this.won, required this.known});
  final String name;
  final int? seed;
  final bool won;
  final bool known;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (seed != null)
          SizedBox(width: 22, child: Text('$seed', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline))),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: won ? FontWeight.w800 : FontWeight.w500,
              fontStyle: known ? null : FontStyle.italic,
              color: known ? null : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (won) Icon(Icons.check_rounded, size: 16, color: theme.colorScheme.primary),
      ],
    );
  }
}

/// A match in a fixtures list.
class MatchTile extends StatelessWidget {
  const MatchTile(this.match, {super.key, this.onTap, this.showLabel = true});
  final MatchItem match;
  final VoidCallback? onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = match.result;
    final meta = [
      if (showLabel) match.label,
      if (match.groupName != null && match.groupName != 'League') match.groupName,
      if (match.scheduledAt != null) Fmt.dayTime(match.scheduledAt),
      if (match.resourceName != null) match.resourceName,
    ].whereType<String>().join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  if (match.status == 'live' || match.status == 'walkover') StatusChip(match.status),
                  if (match.status == 'ready' && onTap != null) StatusChip('ready', label: 'Enter score'),
                ],
              ),
              const SizedBox(height: 6),
              _SideRow(name: match.nameA, seed: match.sideASeed, won: match.wonBy('a'), known: match.sideA != null),
              const SizedBox(height: 3),
              _SideRow(name: match.nameB, seed: match.sideBSeed, won: match.wonBy('b'), known: match.sideB != null),
              if (result != null && result.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    result.summary,
                    if (result.outcome == 'win' && result.margin != null && result.margin != 'walkover') 'won ${result.margin}',
                    if (result.outcome == 'tie') 'tied',
                    if (result.outcome == 'draw') 'drawn',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A knockout draw: one column per round, matches spaced so each sits between
/// the two that feed it.
class BracketView extends StatelessWidget {
  const BracketView({super.key, required this.matches, this.onTap});
  final List<MatchItem> matches;
  final void Function(MatchItem match)? onTap;

  static const _cardHeight = 86.0;
  static const _cardWidth = 210.0;
  static const _gap = 14.0;

  static const _titles = {
    'main': null,
    'winners': 'Winners bracket',
    'losers': 'Losers bracket',
    'grand_final': 'Grand final',
    'playoff': null,
    'third_place': 'Third place',
  };

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];
    for (final bracket in _titles.keys) {
      final inBracket = matches.where((m) => m.bracket == bracket && m.status != 'cancelled').toList();
      if (inBracket.isEmpty) continue;
      final rounds = <int, List<MatchItem>>{};
      for (final match in inBracket) {
        rounds.putIfAbsent(match.roundNo, () => []).add(match);
      }
      final roundNos = rounds.keys.toList()..sort();
      final tallest = rounds.values.map((r) => r.length).reduce((a, b) => a > b ? a : b);
      final height = tallest * (_cardHeight + _gap);
      sections.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_titles[bracket] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                child: Text(_titles[bracket]!, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final round in roundNos)
                    Padding(
                      padding: const EdgeInsets.only(right: 22),
                      child: SizedBox(
                        width: _cardWidth,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            for (final match in rounds[round]!..sort((a, b) => a.matchNo.compareTo(b.matchNo)))
                              _BracketCard(match, onTap: onTap == null ? null : () => onTap!(match)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Gap.lg,
          ],
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: sections),
    );
  }
}

class _BracketCard extends StatelessWidget {
  const _BracketCard(this.match, {this.onTap});
  final MatchItem match;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bye = match.status == 'bye';
    return SizedBox(
      height: BracketView._cardHeight,
      child: Opacity(
        opacity: bye ? 0.55 : 1,
        child: Material(
          color: match.status == 'live' ? theme.colorScheme.errorContainer.withValues(alpha: 0.5) : theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: match.status == 'ready' && onTap != null ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: bye ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bye ? '${match.label} · bye' : match.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 10),
                  ),
                  const SizedBox(height: 2),
                  _SideRow(name: match.nameA, seed: match.sideASeed, won: match.wonBy('a'), known: match.sideA != null),
                  _SideRow(name: match.nameB, seed: match.sideBSeed, won: match.wonBy('b'), known: match.sideB != null),
                  if (match.result != null && match.result!.summary.isNotEmpty)
                    Text(
                      match.result!.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, color: theme.colorScheme.primary),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A league table. Columns adapt to what the sport counts.
class StandingsTable extends StatelessWidget {
  const StandingsTable({super.key, required this.rows, required this.scoringKind, this.qualifiers = 0});
  final List<StandingRow> rows;
  final String scoringKind;

  /// How many places advance, to draw the qualification line.
  final int qualifiers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cricket = scoringKind.startsWith('cricket');
    final limited = scoringKind == 'cricket_limited';
    final showTies = rows.any((r) => r.tied > 0 || r.drawn > 0 || r.noResult > 0);
    final header = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700);
    final cell = theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    Widget num(String text, {TextStyle? style, double width = 38}) =>
        SizedBox(width: width, child: Text(text, textAlign: TextAlign.center, style: style ?? cell));

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(width: 26, child: Text('#', style: header)),
                Expanded(child: Text('', style: header)),
                num('P', style: header),
                num('W', style: header),
                num('L', style: header),
                if (showTies) num(cricket ? 'T/D/NR' : 'T', style: header, width: 56),
                if (!cricket) num('Games', style: header, width: 56),
                if (limited) num('NRR', style: header, width: 62),
                num('Pts', style: header, width: 42),
              ],
            ),
            const Divider(height: 12),
            for (final row in rows) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 26, child: Text('${row.position}', style: cell?.copyWith(fontWeight: FontWeight.w700))),
                    Expanded(child: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: cell?.copyWith(fontWeight: FontWeight.w600))),
                    num('${row.played}'),
                    num('${row.won}'),
                    num('${row.lost}'),
                    if (showTies) num(cricket ? '${row.tied}/${row.drawn}/${row.noResult}' : '${row.tied}', width: 56),
                    if (!cricket) num('${row.setsFor}-${row.setsAgainst}', width: 56),
                    if (limited) num('${row.nrr >= 0 ? '+' : ''}${row.nrr.toStringAsFixed(3)}', width: 62),
                    num(Fmt.number(row.points), style: cell?.copyWith(fontWeight: FontWeight.w800), width: 42),
                  ],
                ),
              ),
              if (qualifiers > 0 && row.position == qualifiers && row != rows.last)
                Divider(height: 4, thickness: 2, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
            ],
          ],
        ),
      ),
    );
  }
}
