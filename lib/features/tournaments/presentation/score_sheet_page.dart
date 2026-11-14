import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../app/theme.dart';
import '../../../core/bloc/async_cubit.dart';
import '../../../core/network/rpc.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/common.dart';
import '../../catalog/domain/catalog.dart';
import '../domain/tournament.dart';
import 'tournament_cubits.dart';

/// Score entry for one match. The editor shown depends on the ruleset's
/// scoring engine; whatever is typed is checked by that engine on the server
/// as you go, so the sheet itself knows no scoring rules.
class ScoreSheetPage extends StatefulWidget {
  const ScoreSheetPage({super.key, required this.cubit, required this.match, required this.ruleset});

  final EventCubit cubit;
  final MatchItem match;
  final Ruleset ruleset;

  @override
  State<ScoreSheetPage> createState() => _ScoreSheetPageState();
}

class _ScoreSheetPageState extends State<ScoreSheetPage> {
  late Json _score = _normalise(widget.match.score);
  late final _preview = ScorePreviewCubit(sl(), widget.ruleset.key)..check(_score);

  /// Fills in the skeleton an empty score needs for its editor.
  Json _normalise(Json score) => switch (widget.ruleset.scoringKind) {
    'rally_games' => {...score, 'games': score['games'] is List && (score['games'] as List).isNotEmpty ? score['games'] : [<int>[0, 0]]},
    'team_tie' => {...score, 'rubbers': score['rubbers'] is List ? score['rubbers'] : <Json>[]},
    _ => {...score, 'innings': score['innings'] is List ? score['innings'] : <Json>[]},
  };

  void _change(Json score) {
    setState(() => _score = score);
    _preview.check(score);
  }

  Future<void> _save({required bool isFinal}) async {
    final navigator = Navigator.of(context);
    if (await widget.cubit.score(widget.match, _score, isFinal: isFinal) && isFinal) navigator.pop();
  }

  Future<void> _walkover(String side) async {
    final navigator = Navigator.of(context);
    final name = side == 'a' ? widget.match.nameA : widget.match.nameB;
    if (!await confirm(context, title: 'Walkover to $name?', message: 'The opponent did not play.', confirmLabel: 'Record walkover')) return;
    if (await widget.cubit.walkover(widget.match, side)) navigator.pop();
  }

  @override
  void dispose() {
    _preview.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final match = widget.match;
    return MultiBlocProvider(
      providers: [BlocProvider.value(value: widget.cubit), BlocProvider.value(value: _preview)],
      child: BlocListener<EventCubit, AsyncState<EventView>>(
        listenWhen: (previous, current) => previous.notice != current.notice && current.notice != null,
        listener: (context, state) => showNotice(context, state.notice!),
        child: Scaffold(
          appBar: AppBar(
            title: Text(match.label),
            actions: [
              PopupMenuButton<String>(
                onSelected: _walkover,
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'a', child: Text('Walkover to ${match.nameA}')),
                  PopupMenuItem(value: 'b', child: Text('Walkover to ${match.nameB}')),
                ],
              ),
            ],
          ),
          body: ContentWidth(
            maxWidth: 640,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: pagePadding,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _SideName('A', match.nameA)),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('v', style: theme.textTheme.titleMedium)),
                          Expanded(child: _SideName('B', match.nameB, alignEnd: true)),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 16),
                        child: Text(
                          '${widget.ruleset.name} · ${widget.ruleset.description}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      switch (widget.ruleset.scoringKind) {
                        'rally_games' => _GamesEditor(score: _score, config: widget.ruleset.config, onChanged: _change, labels: (match.nameA, match.nameB)),
                        'team_tie' => _TieEditor(score: _score, config: widget.ruleset.config, onChanged: _change, labels: (match.nameA, match.nameB)),
                        'cricket_limited' => _LimitedOversEditor(score: _score, config: widget.ruleset.config, onChanged: _change, labels: (match.nameA, match.nameB)),
                        _ => _MultiInningsEditor(score: _score, onChanged: _change, labels: (match.nameA, match.nameB)),
                      },
                    ],
                  ),
                ),
                _Verdict(match: match, onSaveLive: () => _save(isFinal: false), onConfirm: () => _save(isFinal: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideName extends StatelessWidget {
  const _SideName(this.tag, this.name, {this.alignEnd = false});
  final String tag;
  final String name;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text('Side $tag', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

/// What the scoring engine makes of the score, and the buttons to save it.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.match, required this.onSaveLive, required this.onConfirm});
  final MatchItem match;
  final VoidCallback onSaveLive;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = context.select<EventCubit, bool>((c) => c.state.busy);
    return BlocBuilder<ScorePreviewCubit, ScorePreviewState>(
      builder: (context, preview) {
        final result = preview.result;
        final complete = result?.complete ?? false;
        final text = preview.error ??
            (result == null
                ? 'Checking...'
                : !complete
                ? (result.summary.isEmpty ? 'Enter the score' : '${result.summary} · in progress')
                : switch (result.outcome) {
                    'win' => '${result.winner == 'a' ? match.nameA : match.nameB} won${result.margin == null ? '' : ' ${result.margin}'} · ${result.summary}',
                    'tie' => 'Match tied · ${result.summary}',
                    'draw' => 'Match drawn · ${result.summary}',
                    _ => 'No result',
                  });
        return Material(
          elevation: 8,
          color: theme.colorScheme.surfaceContainer,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        preview.error != null
                            ? Icons.error_outline_rounded
                            : complete
                            ? Icons.check_circle_rounded
                            : Icons.timelapse_rounded,
                        size: 20,
                        color: preview.error != null
                            ? theme.colorScheme.error
                            : complete
                            ? const Color(0xFF1B8A4B)
                            : theme.colorScheme.outline,
                      ),
                      Gap.sm,
                      Expanded(
                        child: Text(
                          text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: preview.error != null ? theme.colorScheme.error : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Gap.md,
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy || preview.error != null ? null : onSaveLive,
                          child: const Text('Save live score'),
                        ),
                      ),
                      Gap.md,
                      Expanded(
                        child: FilledButton(
                          onPressed: busy || preview.checking || !complete || preview.error != null ? null : onConfirm,
                          child: const Text('Confirm result'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A compact number input. Zero is shown as a hint rather than as text, so
/// the first digit typed is the score instead of something appended to "0".
class _Num extends StatelessWidget {
  const _Num({super.key, required this.value, required this.onChanged, this.label, this.width = 76, this.decimal = false});
  final num? value;
  final ValueChanged<String> onChanged;
  final String? label;
  final double width;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    const style = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
    return SizedBox(
      width: width,
      child: TextFormField(
        initialValue: value == null || value == 0 ? '' : (value == value.roundToDouble() ? value.toInt().toString() : value.toString()),
        textAlign: TextAlign.center,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.]' : r'[0-9]')), LengthLimitingTextInputFormatter(5)],
        style: style,
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          hintText: '0',
          hintStyle: style.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

List<List<int>> _games(dynamic raw) => [
  for (final game in (raw as List? ?? const []))
    [((game as List)[0] as num).toInt(), (game[1] as num).toInt()],
];

/// Games of a rally-point match: badminton, table tennis.
class _GamesEditor extends StatelessWidget {
  const _GamesEditor({super.key, required this.score, required this.config, required this.onChanged, required this.labels, this.compact = false});
  final Json score;
  final Json config;
  final ValueChanged<Json> onChanged;
  final (String, String) labels;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final games = _games(score['games']);
    final bestOf = (config['best_of'] as num?)?.toInt() ?? 3;
    final retired = score['retired'] as String?;

    void setGames(List<List<int>> next) => onChanged({...score, 'games': next});

    return Column(
      children: [
        for (final (index, game) in games.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 64, child: Text('Game ${index + 1}', style: Theme.of(context).textTheme.labelMedium)),
                _Num(
                  key: ValueKey('a$index-${games.length}'),
                  value: game[0],
                  onChanged: (text) => setGames([...games]..[index] = [int.tryParse(text) ?? 0, game[1]]),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('-')),
                _Num(
                  key: ValueKey('b$index-${games.length}'),
                  value: game[1],
                  onChanged: (text) => setGames([...games]..[index] = [game[0], int.tryParse(text) ?? 0]),
                ),
                SizedBox(
                  width: 48,
                  child: index == games.length - 1 && games.length > 1
                      ? IconButton(tooltip: 'Remove game', icon: const Icon(Icons.close, size: 18), onPressed: () => setGames([...games]..removeLast()))
                      : null,
                ),
              ],
            ),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            if (games.length < bestOf)
              TextButton.icon(onPressed: () => setGames([...games, [0, 0]]), icon: const Icon(Icons.add, size: 18), label: const Text('Next game')),
            if (!compact)
              PopupMenuButton<String>(
                tooltip: 'Retirement',
                onSelected: (value) => onChanged({...score, 'retired': value == 'none' ? null : value}..removeWhere((k, v) => v == null)),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'a', child: Text('${labels.$1} retired')),
                  PopupMenuItem(value: 'b', child: Text('${labels.$2} retired')),
                  if (retired != null) const PopupMenuItem(value: 'none', child: Text('Nobody retired')),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    retired == null ? 'Retired hurt?' : '${retired == 'a' ? labels.$1 : labels.$2} retired',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A team tie: a fixed order of rubbers, each a rally-point match.
class _TieEditor extends StatelessWidget {
  const _TieEditor({required this.score, required this.config, required this.onChanged, required this.labels});
  final Json score;
  final Json config;
  final ValueChanged<Json> onChanged;
  final (String, String) labels;

  @override
  Widget build(BuildContext context) {
    final slots = [for (final r in (config['rubbers'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    final rubbers = [for (final r in (score['rubbers'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    final rubberConfig = Map<String, dynamic>.from(config['rubber'] as Map? ?? const {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, rubber) in rubbers.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${index + 1}. ${slots.elementAtOrNull(index)?['label'] ?? 'Rubber'}',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (index == rubbers.length - 1)
                          IconButton(
                            tooltip: 'Remove rubber',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => onChanged({...score, 'rubbers': [...rubbers]..removeLast()}),
                          ),
                      ],
                    ),
                    _GamesEditor(
                      key: ValueKey('rubber-$index-${rubbers.length}'),
                      score: {...rubber, 'games': (rubber['games'] is List && (rubber['games'] as List).isNotEmpty) ? rubber['games'] : [<int>[0, 0]]},
                      config: rubberConfig,
                      labels: labels,
                      compact: true,
                      onChanged: (next) => onChanged({...score, 'rubbers': [...rubbers]..[index] = next}),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (rubbers.length < slots.length)
          OutlinedButton.icon(
            onPressed: () => onChanged({
              ...score,
              'rubbers': [
                ...rubbers,
                {'games': [<int>[0, 0]]},
              ],
            }),
            icon: const Icon(Icons.add, size: 18),
            label: Text('Start ${slots[rubbers.length]['label']}'),
          ),
      ],
    );
  }
}

/// `18.3` overs to balls and back, for the given balls per over.
int _ballsOf(String overs, int bpo) {
  final parts = overs.split('.');
  final whole = int.tryParse(parts.first) ?? 0;
  final extra = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0).clamp(0, bpo - 1) : 0;
  return whole * bpo + extra;
}

double? _oversOf(int? balls, int bpo) => balls == null ? null : (balls ~/ bpo) + (balls % bpo) / 10;

class _SidePicker extends StatelessWidget {
  const _SidePicker({required this.value, required this.labels, required this.onChanged});
  final String value;
  final (String, String) labels;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    showSelectedIcon: false,
    segments: [
      ButtonSegment(value: 'a', label: Text(labels.$1, overflow: TextOverflow.ellipsis)),
      ButtonSegment(value: 'b', label: Text(labels.$2, overflow: TextOverflow.ellipsis)),
    ],
    selected: {value},
    onSelectionChanged: (selection) => onChanged(selection.first),
  );
}

/// Limited-overs cricket: two innings, with rain rules and Super Overs.
class _LimitedOversEditor extends StatelessWidget {
  const _LimitedOversEditor({required this.score, required this.config, required this.onChanged, required this.labels});
  final Json score;
  final Json config;
  final ValueChanged<Json> onChanged;
  final (String, String) labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bpo = (config['balls_per_over'] as num?)?.toInt() ?? 6;
    final innings = [for (final i in (score['innings'] as List? ?? const [])) Map<String, dynamic>.from(i as Map)];
    final first = innings.elementAtOrNull(0) ?? {'side': 'a', 'runs': 0, 'wickets': 0, 'balls': 0};
    final second = innings.elementAtOrNull(1);
    final battingFirst = first['side'] as String? ?? 'a';
    final chasing = battingFirst == 'a' ? 'b' : 'a';
    final revised = score['revised'] is Map ? Map<String, dynamic>.from(score['revised'] as Map) : null;
    final superOvers = [for (final s in (score['super_over'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
    final noResult = score['no_result'] == true;

    void put(Json patch) => onChanged({...score, ...patch}..removeWhere((key, value) => value == null));
    void setInnings(int index, Json patch) {
      final next = [first, ?second];
      next[index] = {...next[index], ...patch};
      put({'innings': next});
    }

    Widget inningsCard(int index, Json data, String title) => Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            Gap.md,
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Num(key: ValueKey('runs$index'), label: 'Runs', width: 96, value: data['runs'] as num?, onChanged: (t) => setInnings(index, {'runs': int.tryParse(t) ?? 0})),
                _Num(key: ValueKey('wkts$index'), label: 'Wickets', width: 96, value: data['wickets'] as num?, onChanged: (t) => setInnings(index, {'wickets': int.tryParse(t) ?? 0})),
                _Num(
                  key: ValueKey('overs$index'),
                  label: 'Overs',
                  width: 96,
                  decimal: true,
                  value: _oversOf((data['balls'] as num?)?.toInt(), bpo),
                  onChanged: (t) => setInnings(index, {'balls': _ballsOf(t, bpo)}),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('No result'),
          subtitle: const Text('Abandoned or washed out before a result was possible'),
          value: noResult,
          onChanged: (value) => put({'no_result': value ? true : null}),
        ),
        if (!noResult) ...[
          Text('Batted first', style: theme.textTheme.labelLarge),
          Gap.sm,
          _SidePicker(
            value: battingFirst,
            labels: labels,
            onChanged: (side) => put({
              'innings': [
                {...first, 'side': side},
                if (second != null) {...second, 'side': side == 'a' ? 'b' : 'a'},
              ],
            }),
          ),
          Gap.md,
          inningsCard(0, first, 'First innings · ${battingFirst == 'a' ? labels.$1 : labels.$2}'),
          Gap.md,
          if (second == null)
            OutlinedButton.icon(
              onPressed: () => put({
                'innings': [
                  first,
                  {'side': chasing, 'runs': 0, 'wickets': 0, 'balls': 0},
                ],
              }),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Start the chase'),
            )
          else
            inningsCard(1, second, 'Second innings · ${chasing == 'a' ? labels.$1 : labels.$2}'),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Rain rules and Super Over'),
            initiallyExpanded: revised != null || superOvers.isNotEmpty || score['overs'] != null,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Num(
                      label: 'Overs a side',
                      width: 130,
                      value: score['overs'] as num?,
                      onChanged: (t) => put({'overs': int.tryParse(t)}),
                    ),
                    _Num(
                      label: 'DLS target',
                      width: 130,
                      value: revised?['target'] as num?,
                      onChanged: (t) {
                        final target = int.tryParse(t);
                        put({'revised': target == null ? null : {...?revised, 'target': target}});
                      },
                    ),
                    _Num(
                      label: 'Chase overs',
                      width: 130,
                      decimal: true,
                      value: _oversOf((revised?['balls'] as num?)?.toInt(), bpo),
                      onChanged: (t) {
                        if (revised == null && t.isEmpty) return;
                        put({'revised': {...?revised, 'balls': t.isEmpty ? null : _ballsOf(t, bpo)}..removeWhere((k, v) => v == null)});
                      },
                    ),
                  ],
                ),
              ),
              Gap.md,
              for (final (index, over) in superOvers.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(child: Text('Super Over ${index + 1}')),
                      _Num(
                        key: ValueKey('soa$index-${superOvers.length}'),
                        label: 'A',
                        value: over['a'] as num?,
                        onChanged: (t) => put({'super_over': [...superOvers]..[index] = {...over, 'a': int.tryParse(t) ?? 0}}),
                      ),
                      Gap.sm,
                      _Num(
                        key: ValueKey('sob$index-${superOvers.length}'),
                        label: 'B',
                        value: over['b'] as num?,
                        onChanged: (t) => put({'super_over': [...superOvers]..[index] = {...over, 'b': int.tryParse(t) ?? 0}}),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          final next = [...superOvers]..removeAt(index);
                          put({'super_over': next.isEmpty ? null : next});
                        },
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => put({
                    'super_over': [
                      ...superOvers,
                      {'a': 0, 'b': 0},
                    ],
                  }),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add a Super Over'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Tests and first-class matches: up to four innings, declarations, draws.
class _MultiInningsEditor extends StatelessWidget {
  const _MultiInningsEditor({required this.score, required this.onChanged, required this.labels});
  final Json score;
  final ValueChanged<Json> onChanged;
  final (String, String) labels;

  @override
  Widget build(BuildContext context) {
    final innings = [for (final i in (score['innings'] as List? ?? const [])) Map<String, dynamic>.from(i as Map)];
    void setAll(List<Json> next) => onChanged({...score, 'innings': next});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, data) in innings.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Innings ${index + 1}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                        if (index == innings.length - 1)
                          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setAll([...innings]..removeLast())),
                      ],
                    ),
                    _SidePicker(
                      value: data['side'] as String? ?? 'a',
                      labels: labels,
                      onChanged: (side) => setAll([...innings]..[index] = {...data, 'side': side}),
                    ),
                    Gap.md,
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Num(
                          key: ValueKey('tr$index-${innings.length}'),
                          label: 'Runs',
                          width: 96,
                          value: data['runs'] as num?,
                          onChanged: (t) => setAll([...innings]..[index] = {...data, 'runs': int.tryParse(t) ?? 0}),
                        ),
                        _Num(
                          key: ValueKey('tw$index-${innings.length}'),
                          label: 'Wickets',
                          width: 96,
                          value: data['wickets'] as num?,
                          onChanged: (t) => setAll([...innings]..[index] = {...data, 'wickets': int.tryParse(t) ?? 0}),
                        ),
                        FilterChip(
                          label: const Text('Declared'),
                          selected: data['declared'] == true,
                          onSelected: (on) => setAll([...innings]..[index] = {...data, 'declared': on}),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (innings.length < 4)
          OutlinedButton.icon(
            onPressed: () => setAll([
              ...innings,
              {'side': innings.isEmpty ? 'a' : (innings.last['side'] == 'a' ? 'b' : 'a'), 'runs': 0, 'wickets': 10, 'declared': false},
            ]),
            icon: const Icon(Icons.add, size: 18),
            label: Text('Add innings ${innings.length + 1}'),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Match drawn'),
          subtitle: const Text('Time ran out before a result'),
          value: score['drawn'] == true,
          onChanged: (value) => onChanged({...score, 'drawn': value}),
        ),
      ],
    );
  }
}
