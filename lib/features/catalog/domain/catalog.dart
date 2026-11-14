import '../../../core/network/rpc.dart';

class Sport {
  const Sport({required this.code, required this.name});
  final String code;
  final String name;
}

class FeatureDef {
  const FeatureDef({required this.key, required this.name, required this.description, required this.autoGrant, required this.requiresVerified});
  final String key;
  final String name;
  final String description;
  final bool autoGrant;
  final bool requiresVerified;
}

/// How a sport is scored: selects the scoring engine and its parameters.
class Ruleset {
  const Ruleset({
    required this.key,
    required this.sportCode,
    required this.name,
    this.governingBody,
    required this.description,
    required this.scoringKind,
    required this.config,
    required this.isTeam,
  });

  final String key;
  final String sportCode;
  final String name;
  final String? governingBody;
  final String description;

  /// `rally_games`, `team_tie`, `cricket_limited` or `cricket_multi`.
  final String scoringKind;
  final Json config;
  final bool isTeam;
}

class FormatOption {
  const FormatOption({required this.key, required this.type, required this.label, this.defaultValue, this.min, this.max});
  final String key;

  /// `int` or `bool`.
  final String type;
  final String label;
  final Object? defaultValue;
  final int? min;
  final int? max;
}

/// A stage format: selects the pairing and ranking engines.
class StageFormat {
  const StageFormat({required this.key, required this.name, required this.description, required this.needsWinner, required this.options});
  final String key;
  final String name;
  final String description;
  final bool needsWinner;
  final List<FormatOption> options;
}

/// One stage of an event pipeline, as edited in the event form.
class StageSpec {
  const StageSpec({required this.name, required this.format, this.config = const {}});
  final String name;
  final String format;
  final Json config;

  StageSpec copyWith({String? name, String? format, Json? config}) =>
      StageSpec(name: name ?? this.name, format: format ?? this.format, config: config ?? this.config);

  Json toJson() => {'name': name, 'format': format, 'config': config};
}

/// A named preset of stages, e.g. "ICC T20 World Cup".
class FormatTemplate {
  const FormatTemplate({
    required this.key,
    this.sportCode,
    required this.name,
    this.governingBody,
    required this.description,
    this.rulesetKey,
    required this.stages,
  });

  final String key;
  final String? sportCode;
  final String name;
  final String? governingBody;
  final String description;
  final String? rulesetKey;
  final List<StageSpec> stages;
}

class MetricDef {
  const MetricDef({required this.id, required this.sportCode, required this.name, required this.unit, required this.higherIsBetter});
  final String id;
  final String sportCode;
  final String name;
  final String unit;
  final bool higherIsBetter;
}

/// Reference data that drives the UI. Loaded once per session.
class Catalog {
  const Catalog({
    required this.sports,
    required this.features,
    required this.rulesets,
    required this.stageFormats,
    required this.templates,
    required this.metrics,
  });

  final List<Sport> sports;
  final List<FeatureDef> features;
  final List<Ruleset> rulesets;
  final List<StageFormat> stageFormats;
  final List<FormatTemplate> templates;
  final List<MetricDef> metrics;

  String sportName(String? code) => sports.where((s) => s.code == code).firstOrNull?.name ?? (code ?? '');
  Ruleset? ruleset(String? key) => rulesets.where((r) => r.key == key).firstOrNull;
  StageFormat? format(String? key) => stageFormats.where((f) => f.key == key).firstOrNull;
  List<Ruleset> rulesetsFor(String sport) => rulesets.where((r) => r.sportCode == sport).toList();
  List<FormatTemplate> templatesFor(String sport) => templates.where((t) => t.sportCode == null || t.sportCode == sport).toList();

  /// Sports that have competition rulesets (gym does not).
  List<Sport> get competitiveSports => sports.where((s) => rulesets.any((r) => r.sportCode == s.code)).toList();
}
