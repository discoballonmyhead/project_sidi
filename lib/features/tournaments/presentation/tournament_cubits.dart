import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/bloc/async_cubit.dart';
import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../../booking/domain/booking.dart';
import '../../booking/domain/booking_repository.dart';
import '../domain/tournament.dart';
import '../domain/tournament_repository.dart';

class TournamentSearchCubit extends AsyncCubit<List<TournamentCard>> {
  TournamentSearchCubit(this._repository);
  final TournamentRepository _repository;

  String query = '';
  String? sport;
  bool past = false;

  @override
  Future<Result<List<TournamentCard>>> fetch() => _repository.search(query: query, sport: sport, past: past);

  Future<void> search({String? query, String? Function()? sport, bool? past}) {
    if (query != null) this.query = query;
    if (sport != null) this.sport = sport();
    if (past != null) this.past = past;
    return load();
  }
}

class MyEntriesCubit extends AsyncCubit<List<EntryListing>> {
  MyEntriesCubit(this._repository);
  final TournamentRepository _repository;

  @override
  Future<Result<List<EntryListing>>> fetch() => _repository.myEntries();
}

class OrgTournamentsCubit extends AsyncCubit<List<TournamentCard>> {
  OrgTournamentsCubit(this._repository, this.orgId);
  final TournamentRepository _repository;
  final String orgId;

  @override
  Future<Result<List<TournamentCard>>> fetch() => _repository.orgTournaments(orgId);

  /// Creates a draft tournament and returns its id, or null when it failed.
  Future<String?> create(Json tournament) async {
    String? id;
    await act(() async {
      final result = await _repository.saveTournament(orgId, tournament);
      id = result.valueOrNull;
      return result;
    });
    return id;
  }
}

/// One tournament: its events, the caller's entries, and (for hosts) the
/// controls to publish it, shape its events and design posters.
class TournamentDetailCubit extends AsyncCubit<TournamentDetail> {
  TournamentDetailCubit(this._repository, this.tournamentId);
  final TournamentRepository _repository;
  final String tournamentId;

  @override
  Future<Result<TournamentDetail>> fetch() => _repository.detail(tournamentId);

  Future<bool> register(EventSummary event, {String? name, List<String> members = const [], String? contact}) async {
    String? status;
    final ok = await act(() async {
      final result = await _repository.register(event.id, name: name, members: members, contact: contact);
      status = result.valueOrNull;
      return result;
    });
    if (ok) {
      say(status == 'waitlisted'
          ? 'The event is full. You are on the waiting list.'
          : 'Entry sent. The organiser will confirm it${event.entryFee > 0 ? ' and collect the entry fee' : ''}.');
    }
    return ok;
  }

  Future<bool> withdraw(MyEntry entry) => act(() => _repository.withdraw(entry.id), success: 'Entry withdrawn.');

  // Hosting
  Future<bool> save(Json tournament) {
    final orgId = state.data?.tournament.orgId;
    if (orgId == null) return Future.value(false);
    return act(() => _repository.saveTournament(orgId, {...tournament, 'id': tournamentId}), success: 'Tournament saved.');
  }

  Future<bool> setStatus(String status) => act(
    () => _repository.setStatus(tournamentId, status),
    success: switch (status) {
      'open' => 'Published. Entries are open.',
      'closed' => 'Entries closed.',
      'draft' => 'Back to draft.',
      _ => 'Tournament cancelled.',
    },
  );

  Future<bool> saveEvent(Json event) => act(() => _repository.saveEvent(tournamentId, event), success: 'Event saved.');
  Future<bool> deleteEvent(EventSummary event) => act(() => _repository.deleteEvent(event.id), success: 'Event deleted.');
  Future<bool> deletePoster(Poster poster) => act(() => _repository.deletePoster(poster.id), success: 'Poster deleted.');

  /// Saves a poster design; with [png] also stores the rendered image and
  /// publishes it on the tournament page.
  Future<bool> savePoster(Json poster, {Uint8List? png}) => act(() async {
    final saved = await _repository.savePoster(tournamentId, poster);
    final id = saved.valueOrNull;
    final orgId = state.data?.tournament.orgId;
    if (id == null || png == null || orgId == null) return saved;
    final uploaded = await _repository.uploadPosterImage(orgId: orgId, posterId: id, png: png);
    if (uploaded case Err(:final failure)) return Err<String>(failure);
    return _repository.savePoster(tournamentId, {'id': id, 'image_url': uploaded.valueOrNull, 'is_published': true});
  }, success: png == null ? 'Poster saved.' : 'Poster published.');
}

typedef EventView = ({EventDetail detail, List<Entrant> field, List<Resource> courts});

/// One event: stages, tables, draws and results. For hosts it also carries
/// the full entry list and the courts, and exposes the engine controls.
class EventCubit extends AsyncCubit<EventView> {
  EventCubit(this._repository, this._bookings, this.eventId, {required this.orgIdOf});

  final TournamentRepository _repository;
  final BookingRepository _bookings;
  final String eventId;

  /// Resolves the hosting organisation from the tournament id, when known.
  final String? Function(String tournamentId) orgIdOf;

  @override
  Future<Result<EventView>> fetch() async {
    final detail = await _repository.event(eventId);
    if (detail case Err(:final failure)) return Err(failure);
    final event = detail.valueOrNull!;
    if (!event.canManage) return Ok((detail: event, field: event.entrants, courts: const <Resource>[]));

    final field = await _repository.entrants(eventId);
    if (field case Err(:final failure)) return Err(failure);
    var courts = state.data?.courts ?? const <Resource>[];
    final orgId = orgIdOf(event.tournamentId);
    if (courts.isEmpty && orgId != null) {
      final facilities = await _bookings.facilities(orgId);
      courts = [
        for (final facility in facilities.valueOrNull ?? const <ManagedFacility>[])
          for (final managed in facility.resources)
            if (managed.resource.isActive) managed.resource,
      ];
    }
    return Ok((detail: event, field: field.valueOrNull!, courts: courts));
  }

  // The field
  Future<bool> addEntrants(List<String> names) =>
      act(() => _repository.addEntrants(eventId, names), success: '${names.length} added to the field.');
  Future<bool> decide(Entrant entrant, String status) => act(() => _repository.decideEntrant(entrant.id, status));
  Future<bool> seed(Entrant entrant, int? seed) => act(() => _repository.updateEntrant(entrant.id, {'seed': seed}));
  Future<bool> rename(Entrant entrant, String name) => act(() => _repository.updateEntrant(entrant.id, {'name': name}));
  Future<bool> remove(Entrant entrant) => act(() => _repository.removeEntrant(entrant.id));

  // The engine
  Future<bool> start() => act(() => _repository.startEvent(eventId), success: 'Draw made. Matches are ready.');
  Future<bool> reset() => act(() => _repository.resetEvent(eventId), success: 'Event reset to setup.');

  Future<bool> score(MatchItem match, Json score, {required bool isFinal}) => act(
    () => _repository.scoreMatch(match.id, score, isFinal: isFinal),
    success: isFinal ? 'Result recorded.' : 'Live score saved.',
  );
  Future<bool> walkover(MatchItem match, String winnerSide) =>
      act(() => _repository.walkover(match.id, winnerSide), success: 'Walkover recorded.');
  Future<bool> reopen(MatchItem match) => act(() => _repository.reopenMatch(match.id), success: 'Match reopened.');

  Future<bool> schedule(MatchItem match, {String? resourceId, DateTime? startsAt, int minutes = 60}) => act(
    () => _repository.scheduleMatch(match.id, resourceId: resourceId, startsAt: startsAt, minutes: minutes),
    success: startsAt == null ? 'Schedule cleared.' : 'Match scheduled.',
  );

  Future<bool> autoSchedule(String stageId, {required List<String> resourceIds, required DateTime startsAt, required int matchMinutes}) async {
    int? count;
    final ok = await act(() async {
      final result = await _repository.autoSchedule(stageId, resourceIds: resourceIds, startsAt: startsAt, matchMinutes: matchMinutes);
      count = result.valueOrNull;
      return result;
    });
    if (ok) say(count == 0 ? 'Every match already has a time.' : '$count matches scheduled.');
    return ok;
  }
}

class ScorePreviewState extends Equatable {
  const ScorePreviewState({this.result, this.error, this.checking = false});

  final MatchResult? result;

  /// Why the scoring engine rejects the score as entered.
  final String? error;
  final bool checking;

  @override
  List<Object?> get props => [result, error, checking];
}

/// Live validation for the score sheet: asks the ruleset's scoring engine what
/// the score means as it is typed, so the client holds no scoring rules.
class ScorePreviewCubit extends Cubit<ScorePreviewState> {
  ScorePreviewCubit(this._repository, this.rulesetKey) : super(const ScorePreviewState());

  final TournamentRepository _repository;
  final String rulesetKey;
  Timer? _debounce;
  int _request = 0;

  void check(Json score) {
    _debounce?.cancel();
    emit(ScorePreviewState(result: state.result, error: state.error, checking: true));
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final request = ++_request;
      final result = await _repository.previewScore(rulesetKey, score);
      if (isClosed || request != _request) return;
      emit(result.fold((value) => ScorePreviewState(result: value), (failure) => ScorePreviewState(error: failure.message)));
    });
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
