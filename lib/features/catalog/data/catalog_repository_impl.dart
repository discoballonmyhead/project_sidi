import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../../../core/utils/json.dart';
import '../domain/catalog.dart';
import '../domain/catalog_repository.dart';

Ruleset rulesetFromJson(Json r) => Ruleset(
  key: r.str('key'),
  sportCode: r.str('sport_code'),
  name: r.str('name'),
  governingBody: r.strOrNull('governing_body'),
  description: r.str('description'),
  scoringKind: r.str('scoring_kind'),
  config: r.obj('config'),
  isTeam: r.flag('is_team'),
);

MetricDef metricFromJson(Json m) => MetricDef(
  id: m.str('id'),
  sportCode: m.str('sport_code'),
  name: m.str('name'),
  unit: m.str('unit'),
  higherIsBetter: m.flag('higher_is_better', true),
);

StageSpec stageSpecFromJson(Json s) => StageSpec(name: s.str('name'), format: s.str('format'), config: s.obj('config'));

Catalog catalogFromJson(dynamic json) {
  final map = asJson(json);
  return Catalog(
    sports: map.list('sports', (s) => Sport(code: s.str('code'), name: s.str('name'))),
    features: map.list(
      'features',
      (f) => FeatureDef(
        key: f.str('key'),
        name: f.str('name'),
        description: f.str('description'),
        autoGrant: f.flag('auto_grant'),
        requiresVerified: f.flag('requires_verified'),
      ),
    ),
    rulesets: map.list('rulesets', rulesetFromJson),
    stageFormats: map.list(
      'stage_formats',
      (f) => StageFormat(
        key: f.str('key'),
        name: f.str('name'),
        description: f.str('description'),
        needsWinner: f.flag('needs_winner'),
        options: f.list(
          'options',
          (o) => FormatOption(
            key: o.str('key'),
            type: o.str('type'),
            label: o.str('label'),
            defaultValue: o['default'],
            min: o.intOrNull('min'),
            max: o.intOrNull('max'),
          ),
        ),
      ),
    ),
    templates: map.list(
      'format_templates',
      (t) => FormatTemplate(
        key: t.str('key'),
        sportCode: t.strOrNull('sport_code'),
        name: t.str('name'),
        governingBody: t.strOrNull('governing_body'),
        description: t.str('description'),
        rulesetKey: t.strOrNull('ruleset_key'),
        stages: t.list('stages', stageSpecFromJson),
      ),
    ),
    metrics: map.list('metrics', metricFromJson),
  );
}

class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl(this._rpc);
  final Rpc _rpc;

  @override
  Future<Result<Catalog>> load() => _rpc.call('catalog', parse: catalogFromJson);
}
