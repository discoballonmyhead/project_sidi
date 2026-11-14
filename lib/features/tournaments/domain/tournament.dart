import '../../../core/network/rpc.dart';
import '../../booking/domain/booking.dart';
import '../../catalog/domain/catalog.dart';

class TournamentCard {
  const TournamentCard({
    required this.id,
    required this.orgId,
    required this.sportCode,
    required this.name,
    this.description,
    this.venue,
    this.facilityId,
    this.facilityName,
    required this.startsOn,
    required this.endsOn,
    this.registrationClosesAt,
    required this.status,
    this.rules,
    required this.orgName,
    required this.orgIsVerified,
    required this.currency,
    required this.eventCount,
    required this.entrantCount,
    this.minEntryFee,
  });

  final String id;
  final String orgId;
  final String sportCode;
  final String name;
  final String? description;
  final String? venue;
  final String? facilityId;
  final String? facilityName;
  final DateTime startsOn;
  final DateTime endsOn;
  final DateTime? registrationClosesAt;

  /// `draft`, `open`, `closed`, `live`, `completed` or `cancelled`.
  final String status;
  final String? rules;
  final String orgName;
  final bool orgIsVerified;
  final String currency;
  final int eventCount;
  final int entrantCount;
  final double? minEntryFee;

  String get place => venue ?? facilityName ?? orgName;
  bool get registrationOpen =>
      status == 'open' && (registrationClosesAt == null || registrationClosesAt!.isAfter(DateTime.now()));
}

class Stage {
  const Stage({
    required this.id,
    required this.seq,
    required this.name,
    required this.formatKey,
    required this.formatName,
    required this.config,
    required this.status,
  });

  final String id;
  final int seq;
  final String name;
  final String formatKey;
  final String formatName;
  final Json config;
  final String status;

  StageSpec toSpec() => StageSpec(name: name, format: formatKey, config: config);
}

class PodiumPlace {
  const PodiumPlace({required this.rank, required this.name});
  final int rank;
  final String name;
}

class MyEntry {
  const MyEntry({required this.id, required this.name, required this.status, this.payment});
  final String id;
  final String name;
  final String status;
  final PaymentRef? payment;
}

class EventSummary {
  const EventSummary({
    required this.id,
    required this.name,
    required this.entrantKind,
    required this.category,
    required this.rulesetKey,
    required this.rulesetName,
    this.templateKey,
    required this.entryFee,
    this.maxEntrants,
    required this.status,
    required this.acceptedCount,
    required this.pendingCount,
    required this.stages,
    required this.podium,
    this.myEntry,
  });

  final String id;
  final String name;

  /// `player`, `pair` or `team`.
  final String entrantKind;
  final String category;
  final String rulesetKey;
  final String rulesetName;
  final String? templateKey;
  final double entryFee;
  final int? maxEntrants;

  /// `setup`, `live` or `completed`.
  final String status;
  final int acceptedCount;
  final int pendingCount;
  final List<Stage> stages;
  final List<PodiumPlace> podium;
  final MyEntry? myEntry;

  String get formatSummary => stages.map((s) => s.formatName).join(' → ');
}

class Poster {
  const Poster({
    required this.id,
    required this.kind,
    required this.template,
    required this.title,
    required this.payload,
    this.imageUrl,
    required this.isPublished,
  });

  final String id;

  /// `promotion` or `winner`.
  final String kind;
  final String template;
  final String title;
  final Json payload;
  final String? imageUrl;
  final bool isPublished;
}

class TournamentDetail {
  const TournamentDetail({required this.tournament, required this.canManage, required this.events, required this.posters});
  final TournamentCard tournament;
  final bool canManage;
  final List<EventSummary> events;
  final List<Poster> posters;
}

class EntrantMember {
  const EntrantMember({required this.name, required this.isCaptain});
  final String name;
  final bool isCaptain;
}

class Entrant {
  const Entrant({
    required this.id,
    required this.name,
    this.seed,
    required this.status,
    this.finalRank,
    this.members = const [],
    this.contact,
    this.registeredByName,
    this.payment,
  });

  final String id;
  final String name;
  final int? seed;
  final String status;
  final int? finalRank;
  final List<EntrantMember> members;
  final String? contact;
  final String? registeredByName;
  final PaymentRef? payment;
}

class StandingRow {
  const StandingRow({
    required this.entrantId,
    required this.name,
    this.groupName,
    required this.position,
    required this.played,
    required this.won,
    required this.lost,
    required this.tied,
    required this.drawn,
    required this.noResult,
    required this.points,
    required this.setsFor,
    required this.setsAgainst,
    required this.scoreFor,
    required this.scoreAgainst,
    required this.nrr,
  });

  final String entrantId;
  final String name;
  final String? groupName;
  final int position;
  final int played;
  final int won;
  final int lost;
  final int tied;
  final int drawn;
  final int noResult;
  final double points;
  final int setsFor;
  final int setsAgainst;
  final int scoreFor;
  final int scoreAgainst;
  final double nrr;
}

/// What a scoring engine made of a score.
class MatchResult {
  const MatchResult({required this.complete, this.outcome, this.winner, required this.summary, this.margin});

  final bool complete;

  /// `win`, `tie`, `draw` or `no_result`.
  final String? outcome;

  /// `a`, `b` or null.
  final String? winner;
  final String summary;
  final String? margin;
}

class MatchItem {
  const MatchItem({
    required this.id,
    required this.stageId,
    required this.seq,
    required this.bracket,
    required this.roundNo,
    required this.matchNo,
    required this.label,
    required this.status,
    required this.score,
    this.result,
    this.winnerId,
    this.sideA,
    this.sideB,
    this.sideAName,
    this.sideBName,
    this.sideASeed,
    this.sideBSeed,
    this.sideAPlaceholder,
    this.sideBPlaceholder,
    this.scheduledAt,
    this.resourceId,
    this.resourceName,
    this.groupName,
  });

  final String id;
  final String stageId;
  final int seq;

  /// `main`, `winners`, `losers`, `grand_final`, `third_place` or `playoff`.
  final String bracket;
  final int roundNo;
  final int matchNo;
  final String label;

  /// `pending`, `ready`, `live`, `completed`, `walkover`, `bye` or `cancelled`.
  final String status;

  /// Raw score in the shape the ruleset's scoring engine reads.
  final Json score;
  final MatchResult? result;
  final String? winnerId;
  final String? sideA;
  final String? sideB;
  final String? sideAName;
  final String? sideBName;
  final int? sideASeed;
  final int? sideBSeed;
  final String? sideAPlaceholder;
  final String? sideBPlaceholder;
  final DateTime? scheduledAt;
  final String? resourceId;
  final String? resourceName;
  final String? groupName;

  String get nameA => sideAName ?? sideAPlaceholder ?? (status == 'bye' ? 'Bye' : 'To be decided');
  String get nameB => sideBName ?? sideBPlaceholder ?? (status == 'bye' ? 'Bye' : 'To be decided');
  bool get isPlayable => status == 'ready' || status == 'live';
  bool get isFinal => status == 'completed' || status == 'walkover';
  bool get isHidden => status == 'bye' || status == 'cancelled';
  bool wonBy(String side) => winnerId != null && winnerId == (side == 'a' ? sideA : sideB);
}

class StageDetail {
  const StageDetail({required this.stage, required this.hasTable, required this.standings, required this.matches});
  final Stage stage;
  final bool hasTable;
  final List<StandingRow> standings;
  final List<MatchItem> matches;

  bool get isBracket => !hasTable;
}

class EventDetail {
  const EventDetail({
    required this.id,
    required this.tournamentId,
    required this.tournamentName,
    required this.sportCode,
    required this.name,
    required this.entrantKind,
    required this.entryFee,
    this.maxEntrants,
    required this.status,
    required this.currency,
    required this.ruleset,
    required this.canManage,
    required this.entrants,
    required this.stages,
  });

  final String id;
  final String tournamentId;
  final String tournamentName;
  final String sportCode;
  final String name;
  final String entrantKind;
  final double entryFee;
  final int? maxEntrants;
  final String status;
  final String currency;
  final Ruleset ruleset;
  final bool canManage;
  final List<Entrant> entrants;
  final List<StageDetail> stages;

  bool get isSetup => status == 'setup';
}

class EntryListing {
  const EntryListing({
    required this.id,
    required this.name,
    required this.status,
    this.finalRank,
    required this.eventId,
    required this.eventName,
    required this.tournamentId,
    required this.tournamentName,
    required this.tournamentStatus,
    required this.sportCode,
    required this.startsOn,
    required this.orgName,
    this.payment,
  });

  final String id;
  final String name;
  final String status;
  final int? finalRank;
  final String eventId;
  final String eventName;
  final String tournamentId;
  final String tournamentName;
  final String tournamentStatus;
  final String sportCode;
  final DateTime startsOn;
  final String orgName;
  final PaymentRef? payment;
}
