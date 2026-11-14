import 'package:flutter_test/flutter_test.dart';
import 'package:sidi/features/catalog/data/catalog_repository_impl.dart';
import 'package:sidi/features/tournaments/data/tournament_repository_impl.dart';

/// The shape `public.event_detail` returns, trimmed to one stage.
const _eventJson = {
  'can_manage': true,
  'event': {
    'id': 'e1', 'tournament_id': 't1', 'tournament_name': 'Winter Open', 'org_id': 'o1', 'sport_code': 'cricket',
    'name': 'T20 cup', 'entrant_kind': 'team', 'entry_fee': 500, 'max_entrants': null, 'status': 'live', 'currency': 'INR',
  },
  'ruleset': {
    'key': 'icc_t20', 'sport_code': 'cricket', 'name': 'T20', 'governing_body': 'ICC', 'description': 'Twenty overs a side.',
    'scoring_kind': 'cricket_limited', 'config': {'overs': 20, 'balls_per_over': 6}, 'is_team': true,
  },
  'entrants': [
    {'id': 'a', 'name': 'Hawks', 'seed': 1, 'status': 'accepted', 'final_rank': null, 'members': [{'name': 'Asha', 'is_captain': true}]},
  ],
  'stages': [
    {
      'id': 's1', 'seq': 1, 'name': 'League', 'format_key': 'round_robin', 'format_name': 'Round robin',
      'config': {'groups': 1}, 'status': 'live', 'has_table': true,
      'standings': [
        {'entrant_id': 'a', 'name': 'Hawks', 'group_name': 'League', 'position': 1, 'played': 2, 'won': 1, 'lost': 0, 'tied': 0,
         'drawn': 0, 'no_result': 1, 'points': 3, 'sets_for': 0, 'sets_against': 0, 'score_for': 200, 'score_against': 100, 'nrr': 5.0},
      ],
      'matches': [
        {
          'id': 'm1', 'stage_id': 's1', 'seq': 1, 'bracket': 'main', 'round_no': 1, 'match_no': 1, 'label': 'Round 1',
          'status': 'completed', 'score': {'innings': []}, 'winner_id': 'a', 'side_a': 'a', 'side_b': 'b',
          'side_a_name': 'Hawks', 'side_b_name': 'Kings', 'side_a_seed': 1, 'side_b_seed': 2,
          'result': {'complete': true, 'outcome': 'win', 'winner': 'a', 'summary': '200/4 (20) v 100/10 (15)', 'margin': 'by 100 runs'},
          'scheduled_local': '2026-11-20T10:00:00', 'resource_name': 'Pitch 1',
        },
        {
          'id': 'm2', 'stage_id': 's1', 'seq': 2, 'bracket': 'main', 'round_no': 2, 'match_no': 1, 'label': 'Final',
          'status': 'pending', 'score': {}, 'side_a': null, 'side_b': null,
          'side_a_placeholder': 'Winner of Semi-final 1', 'side_b_placeholder': 'Winner of Semi-final 2',
        },
      ],
    },
  ],
};

void main() {
  final event = eventDetailFromJson(_eventJson);

  test('an event carries its ruleset, so the right score sheet can be shown', () {
    expect(event.ruleset.scoringKind, 'cricket_limited');
    expect(event.ruleset.config['overs'], 20);
    expect(event.orgId, 'o1');
    expect(event.canManage, isTrue);
    expect(event.isSetup, isFalse);
  });

  test('league stages come with a table, knockouts do not', () {
    final stage = event.stages.single;
    expect(stage.hasTable, isTrue);
    expect(stage.isBracket, isFalse);
    expect(stage.standings.single.nrr, 5.0);
    expect(stage.standings.single.points, 3);
  });

  test('a finished match knows who won', () {
    final match = event.stages.single.matches.first;
    expect(match.isFinal, isTrue);
    expect(match.wonBy('a'), isTrue);
    expect(match.wonBy('b'), isFalse);
    expect(match.result?.margin, 'by 100 runs');
    expect(match.scheduledAt, DateTime(2026, 11, 20, 10), reason: 'venue wall-clock time, whatever the device zone');
  });

  test('a match waiting on earlier results names where its sides come from', () {
    final match = event.stages.single.matches.last;
    expect(match.isPlayable, isFalse);
    expect(match.nameA, 'Winner of Semi-final 1');
    expect(match.wonBy('a'), isFalse, reason: 'no winner yet, even though both sides are null');
  });

  test('templates and formats parse from the catalogue', () {
    final catalog = catalogFromJson({
      'sports': [
        {'code': 'cricket', 'name': 'Cricket'},
        {'code': 'gym', 'name': 'Gym & fitness'},
      ],
      'rulesets': [_eventJson['ruleset']],
      'stage_formats': [
        {
          'key': 'round_robin', 'name': 'Round robin', 'description': '...', 'needs_winner': false,
          'options': [{'key': 'groups', 'type': 'int', 'label': 'Groups', 'default': 1, 'min': 1, 'max': 16}],
        },
      ],
      'format_templates': [
        {
          'key': 'icc_t20_world_cup', 'sport_code': 'cricket', 'name': 'ICC T20 World Cup', 'governing_body': 'ICC',
          'description': '...', 'ruleset_key': 'icc_t20',
          'stages': [
            {'name': 'Group stage', 'format': 'round_robin', 'config': {'groups': 4}},
            {'name': 'Super 8', 'format': 'round_robin', 'config': {'groups': 2, 'qualify': {'per_group': 2}}},
            {'name': 'Knockout', 'format': 'single_elimination', 'config': {'qualify': {'per_group': 2}}},
          ],
        },
        {'key': 'knockout', 'sport_code': null, 'name': 'Knockout', 'description': '...', 'stages': []},
      ],
    });

    expect(catalog.competitiveSports.map((s) => s.code), ['cricket'], reason: 'gym has no rulesets, so no tournaments');
    expect(catalog.templatesFor('cricket'), hasLength(2), reason: 'sport-specific and generic templates');
    final worldCup = catalog.templates.first;
    expect(worldCup.stages, hasLength(3));
    expect(worldCup.stages[1].config['qualify'], {'per_group': 2});
    expect(worldCup.stages[1].toJson()['format'], 'round_robin');
    expect(catalog.format('round_robin')?.options.single.max, 16);
  });
}
