import 'dart:typed_data';

import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import 'tournament.dart';

abstract interface class TournamentRepository {
  // Browsing and entering
  Future<Result<List<TournamentCard>>> search({String? query, String? sport, bool past = false});
  Future<Result<TournamentDetail>> detail(String tournamentId);
  Future<Result<EventDetail>> event(String eventId);
  Future<Result<String>> register(String eventId, {String? name, List<String> members = const [], String? contact});
  Future<Result<void>> withdraw(String entrantId);
  Future<Result<List<EntryListing>>> myEntries();

  // Hosting
  Future<Result<List<TournamentCard>>> orgTournaments(String orgId);
  Future<Result<String>> saveTournament(String orgId, Json tournament);
  Future<Result<void>> setStatus(String tournamentId, String status);
  Future<Result<String>> saveEvent(String tournamentId, Json event);
  Future<Result<void>> deleteEvent(String eventId);

  Future<Result<List<Entrant>>> entrants(String eventId);
  Future<Result<void>> addEntrants(String eventId, List<String> names);
  Future<Result<void>> decideEntrant(String entrantId, String status);
  Future<Result<void>> updateEntrant(String entrantId, Json patch);
  Future<Result<void>> removeEntrant(String entrantId);

  /// Runs the engine: seeds the first stage and creates its matches.
  Future<Result<void>> startEvent(String eventId);
  Future<Result<void>> resetEvent(String eventId);

  /// Asks the ruleset's scoring engine what a score means, without saving.
  Future<Result<MatchResult>> previewScore(String rulesetKey, Json score);
  Future<Result<void>> scoreMatch(String matchId, Json score, {required bool isFinal});
  Future<Result<void>> walkover(String matchId, String winnerSide);
  Future<Result<void>> reopenMatch(String matchId);
  Future<Result<void>> scheduleMatch(String matchId, {String? resourceId, DateTime? startsAt, int minutes = 60});
  Future<Result<int>> autoSchedule(
    String stageId, {
    required List<String> resourceIds,
    required DateTime startsAt,
    required int matchMinutes,
    int gapMinutes = 5,
  });

  Future<Result<String>> savePoster(String tournamentId, Json poster);
  Future<Result<void>> deletePoster(String posterId);

  /// Stores a rendered poster image and returns its public URL.
  Future<Result<String>> uploadPosterImage({required String orgId, required String posterId, required Uint8List png});
}
