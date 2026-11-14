import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../../../core/utils/json.dart';
import '../../booking/data/booking_repository_impl.dart';
import '../../catalog/data/catalog_repository_impl.dart';
import '../domain/tournament.dart';
import '../domain/tournament_repository.dart';

TournamentCard tournamentFromJson(Json t) => TournamentCard(
  id: t.str('id'),
  orgId: t.str('org_id'),
  sportCode: t.str('sport_code'),
  name: t.str('name'),
  description: t.strOrNull('description'),
  venue: t.strOrNull('venue'),
  facilityId: t.strOrNull('facility_id'),
  facilityName: t.strOrNull('facility_name'),
  startsOn: t.dayOrNull('starts_on') ?? DateTime.now(),
  endsOn: t.dayOrNull('ends_on') ?? DateTime.now(),
  registrationClosesAt: t.dateOrNull('registration_closes_local'),
  registrationOpen: t.flag('registration_open'),
  status: t.str('status'),
  rules: t.strOrNull('rules'),
  orgName: t.str('org_name'),
  orgIsVerified: t.flag('org_is_verified'),
  currency: t.str('currency', 'INR'),
  eventCount: t.integer('event_count'),
  entrantCount: t.integer('entrant_count'),
  minEntryFee: t.numberOrNull('min_entry_fee'),
);

Stage _stageFromJson(Json s) => Stage(
  id: s.str('id'),
  seq: s.integer('seq'),
  name: s.str('name'),
  formatKey: s.str('format_key'),
  formatName: s.str('format_name'),
  config: s.obj('config'),
  status: s.str('status'),
);

Poster posterFromJson(Json p) => Poster(
  id: p.str('id'),
  kind: p.str('kind', 'promotion'),
  template: p.str('template', 'spotlight'),
  title: p.str('title'),
  payload: p.obj('payload'),
  imageUrl: p.strOrNull('image_url'),
  isPublished: p.flag('is_published'),
);

Entrant entrantFromJson(Json e) => Entrant(
  id: e.str('id'),
  name: e.str('name'),
  seed: e.intOrNull('seed'),
  status: e.str('status'),
  finalRank: e.intOrNull('final_rank'),
  members: e.list('members', (m) => EntrantMember(name: m.str('name'), isCaptain: m.flag('is_captain'))),
  contact: e.strOrNull('contact'),
  registeredByName: e.strOrNull('registered_by_name'),
  payment: paymentRefFromJson(e.objOrNull('payment')),
);

MatchResult? matchResultFromJson(Json? r) => r == null
    ? null
    : MatchResult(
        complete: r.flag('complete'),
        outcome: r.strOrNull('outcome'),
        winner: r.strOrNull('winner'),
        summary: r.str('summary'),
        margin: r.strOrNull('margin'),
      );

MatchItem matchFromJson(Json m) => MatchItem(
  id: m.str('id'),
  stageId: m.str('stage_id'),
  seq: m.integer('seq'),
  bracket: m.str('bracket', 'main'),
  roundNo: m.integer('round_no'),
  matchNo: m.integer('match_no'),
  label: m.str('label'),
  status: m.str('status'),
  score: m.obj('score'),
  result: matchResultFromJson(m.objOrNull('result')),
  winnerId: m.strOrNull('winner_id'),
  sideA: m.strOrNull('side_a'),
  sideB: m.strOrNull('side_b'),
  sideAName: m.strOrNull('side_a_name'),
  sideBName: m.strOrNull('side_b_name'),
  sideASeed: m.intOrNull('side_a_seed'),
  sideBSeed: m.intOrNull('side_b_seed'),
  sideAPlaceholder: m.strOrNull('side_a_placeholder'),
  sideBPlaceholder: m.strOrNull('side_b_placeholder'),
  scheduledAt: m.dateOrNull('scheduled_local'),
  resourceId: m.strOrNull('resource_id'),
  resourceName: m.strOrNull('resource_name'),
  groupName: m.strOrNull('group_name'),
);

TournamentDetail tournamentDetailFromJson(dynamic json) {
  final map = asJson(json);
  return TournamentDetail(
    tournament: tournamentFromJson(map.obj('tournament')),
    canManage: map.flag('can_manage'),
    events: map.list('events', (e) {
      final entry = e.objOrNull('my_entry');
      return EventSummary(
        id: e.str('id'),
        name: e.str('name'),
        entrantKind: e.str('entrant_kind', 'player'),
        category: e.str('category', 'open'),
        rulesetKey: e.str('ruleset_key'),
        rulesetName: e.str('ruleset_name'),
        templateKey: e.strOrNull('template_key'),
        entryFee: e.number('entry_fee'),
        maxEntrants: e.intOrNull('max_entrants'),
        status: e.str('status'),
        acceptedCount: e.integer('accepted_count'),
        pendingCount: e.integer('pending_count'),
        stages: e.list('stages', _stageFromJson),
        podium: e.list('podium', (p) => PodiumPlace(rank: p.integer('rank'), name: p.str('name'))),
        myEntry: entry == null
            ? null
            : MyEntry(
                id: entry.str('id'),
                name: entry.str('name'),
                status: entry.str('status'),
                payment: paymentRefFromJson(entry.objOrNull('payment')),
              ),
      );
    }),
    posters: map.list('posters', posterFromJson),
  );
}

EventDetail eventDetailFromJson(dynamic json) {
  final map = asJson(json);
  final event = map.obj('event');
  return EventDetail(
    id: event.str('id'),
    tournamentId: event.str('tournament_id'),
    tournamentName: event.str('tournament_name'),
    orgId: event.str('org_id'),
    sportCode: event.str('sport_code'),
    name: event.str('name'),
    entrantKind: event.str('entrant_kind', 'player'),
    entryFee: event.number('entry_fee'),
    maxEntrants: event.intOrNull('max_entrants'),
    status: event.str('status'),
    currency: event.str('currency', 'INR'),
    ruleset: rulesetFromJson(map.obj('ruleset')),
    canManage: map.flag('can_manage'),
    entrants: map.list('entrants', entrantFromJson),
    stages: map.list(
      'stages',
      (s) => StageDetail(
        stage: _stageFromJson(s),
        hasTable: s.flag('has_table'),
        standings: s.list(
          'standings',
          (r) => StandingRow(
            entrantId: r.str('entrant_id'),
            name: r.str('name'),
            groupName: r.strOrNull('group_name'),
            position: r.integer('position'),
            played: r.integer('played'),
            won: r.integer('won'),
            lost: r.integer('lost'),
            tied: r.integer('tied'),
            drawn: r.integer('drawn'),
            noResult: r.integer('no_result'),
            points: r.number('points'),
            setsFor: r.integer('sets_for'),
            setsAgainst: r.integer('sets_against'),
            scoreFor: r.integer('score_for'),
            scoreAgainst: r.integer('score_against'),
            nrr: r.number('nrr'),
          ),
        ),
        matches: s.list('matches', matchFromJson),
      ),
    ),
  );
}

String _idOf(dynamic json) => asJson(json).str('id');

class TournamentRepositoryImpl implements TournamentRepository {
  TournamentRepositoryImpl(this._rpc, this._client);

  final Rpc _rpc;
  final SupabaseClient _client;

  @override
  Future<Result<List<TournamentCard>>> search({String? query, String? sport, bool past = false}) => _rpc.call(
    'tournaments_search',
    params: {'p_query': query, 'p_sport': sport, 'p_scope': past ? 'past' : 'upcoming'},
    parse: (json) => parseList(json, tournamentFromJson),
  );

  @override
  Future<Result<TournamentDetail>> detail(String tournamentId) =>
      _rpc.call('tournament_detail', params: {'p_tournament_id': tournamentId}, parse: tournamentDetailFromJson);

  @override
  Future<Result<EventDetail>> event(String eventId) =>
      _rpc.call('event_detail', params: {'p_event_id': eventId}, parse: eventDetailFromJson);

  @override
  Future<Result<String>> register(String eventId, {String? name, List<String> members = const [], String? contact}) =>
      _rpc.call(
        'event_register',
        params: {
          'p_event_id': eventId,
          'p_name': name,
          'p_members': [
            for (final member in members) {'name': member},
          ],
          'p_contact': contact,
        },
        parse: (json) => asJson(json).str('status'),
      );

  @override
  Future<Result<void>> withdraw(String entrantId) => _rpc.run('entry_withdraw', params: {'p_entrant_id': entrantId});

  @override
  Future<Result<List<EntryListing>>> myEntries() => _rpc.call(
    'my_entries',
    parse: (json) => parseList(
      json,
      (e) => EntryListing(
        id: e.str('id'),
        name: e.str('name'),
        status: e.str('status'),
        finalRank: e.intOrNull('final_rank'),
        eventId: e.str('event_id'),
        eventName: e.str('event_name'),
        tournamentId: e.str('tournament_id'),
        tournamentName: e.str('tournament_name'),
        tournamentStatus: e.str('tournament_status'),
        sportCode: e.str('sport_code'),
        startsOn: e.dayOrNull('starts_on') ?? DateTime.now(),
        orgName: e.str('org_name'),
        payment: paymentRefFromJson(e.objOrNull('payment')),
      ),
    ),
  );

  @override
  Future<Result<List<TournamentCard>>> orgTournaments(String orgId) =>
      _rpc.call('org_tournaments', params: {'p_org_id': orgId}, parse: (json) => parseList(json, tournamentFromJson));

  @override
  Future<Result<String>> saveTournament(String orgId, Json tournament) =>
      _rpc.call('org_tournament_save', params: {'p_org_id': orgId, 'p_tournament': tournament}, parse: _idOf);

  @override
  Future<Result<void>> setStatus(String tournamentId, String status) =>
      _rpc.run('org_tournament_set_status', params: {'p_tournament_id': tournamentId, 'p_status': status});

  @override
  Future<Result<String>> saveEvent(String tournamentId, Json event) =>
      _rpc.call('org_event_save', params: {'p_tournament_id': tournamentId, 'p_event': event}, parse: _idOf);

  @override
  Future<Result<void>> deleteEvent(String eventId) => _rpc.run('org_event_delete', params: {'p_event_id': eventId});

  @override
  Future<Result<List<Entrant>>> entrants(String eventId) =>
      _rpc.call('org_event_entrants', params: {'p_event_id': eventId}, parse: (json) => parseList(json, entrantFromJson));

  @override
  Future<Result<void>> addEntrants(String eventId, List<String> names) =>
      _rpc.run('org_entrants_add', params: {'p_event_id': eventId, 'p_entrants': names});

  @override
  Future<Result<void>> decideEntrant(String entrantId, String status) =>
      _rpc.run('org_entrant_decide', params: {'p_entrant_id': entrantId, 'p_status': status});

  @override
  Future<Result<void>> updateEntrant(String entrantId, Json patch) =>
      _rpc.run('org_entrant_update', params: {'p_entrant_id': entrantId, 'p_patch': patch});

  @override
  Future<Result<void>> removeEntrant(String entrantId) =>
      _rpc.run('org_entrant_remove', params: {'p_entrant_id': entrantId});

  @override
  Future<Result<void>> startEvent(String eventId) => _rpc.run('org_event_start', params: {'p_event_id': eventId});

  @override
  Future<Result<void>> resetEvent(String eventId) => _rpc.run('org_event_reset', params: {'p_event_id': eventId});

  @override
  Future<Result<MatchResult>> previewScore(String rulesetKey, Json score) => _rpc.call(
    'score_preview',
    params: {'p_ruleset_key': rulesetKey, 'p_score': score},
    parse: (json) => matchResultFromJson(asJson(json))!,
  );

  @override
  Future<Result<void>> scoreMatch(String matchId, Json score, {required bool isFinal}) =>
      _rpc.run('org_match_score', params: {'p_match_id': matchId, 'p_score': score, 'p_final': isFinal});

  @override
  Future<Result<void>> walkover(String matchId, String winnerSide) =>
      _rpc.run('org_match_walkover', params: {'p_match_id': matchId, 'p_winner_side': winnerSide});

  @override
  Future<Result<void>> reopenMatch(String matchId) => _rpc.run('org_match_reopen', params: {'p_match_id': matchId});

  @override
  Future<Result<void>> scheduleMatch(String matchId, {String? resourceId, DateTime? startsAt, int minutes = 60}) =>
      _rpc.run(
        'org_match_schedule',
        params: {
          'p_match_id': matchId,
          'p_resource_id': resourceId,
          'p_starts_at': startsAt == null ? null : isoLocal(startsAt),
          'p_minutes': minutes,
        },
      );

  @override
  Future<Result<int>> autoSchedule(
    String stageId, {
    required List<String> resourceIds,
    required DateTime startsAt,
    required int matchMinutes,
    int gapMinutes = 5,
  }) => _rpc.call(
    'org_stage_auto_schedule',
    params: {
      'p_stage_id': stageId,
      'p_resource_ids': resourceIds,
      'p_starts_at': isoLocal(startsAt),
      'p_match_minutes': matchMinutes,
      'p_gap_minutes': gapMinutes,
    },
    parse: (json) => json is num ? json.toInt() : 0,
  );

  @override
  Future<Result<String>> savePoster(String tournamentId, Json poster) =>
      _rpc.call('org_poster_save', params: {'p_tournament_id': tournamentId, 'p_poster': poster}, parse: _idOf);

  @override
  Future<Result<void>> deletePoster(String posterId) => _rpc.run('org_poster_delete', params: {'p_poster_id': posterId});

  @override
  Future<Result<String>> uploadPosterImage({required String orgId, required String posterId, required Uint8List png}) async {
    try {
      // Storage policies only allow writes under the organisation's own folder.
      final path = '$orgId/posters/$posterId.png';
      final bucket = _client.storage.from('media');
      await bucket.uploadBinary(path, png, fileOptions: const FileOptions(contentType: 'image/png', upsert: true));
      // The cache-buster makes a re-export show up straight away.
      return Ok('${bucket.getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}');
    } catch (error) {
      return Err(SupabaseRpc.mapError(error));
    }
  }
}
