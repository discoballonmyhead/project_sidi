import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../../../core/utils/json.dart';
import '../../booking/data/booking_repository_impl.dart';
import '../../membership/data/membership_repository_impl.dart';
import '../../tournaments/data/tournament_repository_impl.dart';
import '../domain/discover.dart';
import '../domain/discover_repository.dart';

Org orgFromJson(Json o) => Org(
  id: o.str('id'),
  name: o.str('name'),
  description: o.strOrNull('description'),
  status: o.str('status'),
  isVerified: o.flag('is_verified'),
  sports: o.strings('sports'),
  city: o.strOrNull('city'),
  address: o.strOrNull('address'),
  contactEmail: o.strOrNull('contact_email'),
  contactPhone: o.strOrNull('contact_phone'),
  logoUrl: o.strOrNull('logo_url'),
  currency: o.str('currency', 'INR'),
  timezone: o.str('timezone', 'Asia/Kolkata'),
);

class DiscoverRepositoryImpl implements DiscoverRepository {
  DiscoverRepositoryImpl(this._rpc);
  final Rpc _rpc;

  @override
  Future<Result<List<OrgCard>>> searchOrgs({String? query, String? sport}) => _rpc.call(
    'orgs_search',
    params: {'p_query': query, 'p_sport': sport},
    parse: (json) => parseList(
      json,
      (o) => OrgCard(
        id: o.str('id'),
        name: o.str('name'),
        description: o.strOrNull('description'),
        city: o.strOrNull('city'),
        sports: o.strings('sports'),
        isVerified: o.flag('is_verified'),
        currency: o.str('currency', 'INR'),
        resourceCount: o.integer('resource_count'),
        minPrice: o.numberOrNull('min_price'),
      ),
    ),
  );

  @override
  Future<Result<OrgProfile>> orgProfile(String orgId) => _rpc.call(
    'org_detail',
    params: {'p_org_id': orgId},
    parse: (json) {
      final map = asJson(json);
      return OrgProfile(
        org: orgFromJson(map.obj('organization')),
        myRole: map.strOrNull('my_role'),
        facilities: map.list(
          'facilities',
          (f) => FacilityListing(
            id: f.str('id'),
            name: f.str('name'),
            address: f.strOrNull('address'),
            city: f.strOrNull('city'),
            resources: f.list('resources', resourceFromJson),
          ),
        ),
        plans: map.list('plans', planFromJson),
        tournaments: map.list('tournaments', tournamentFromJson),
        myMemberships: map.list('my_memberships', membershipFromJson),
      );
    },
  );

  @override
  Future<Result<void>> report({required String targetType, required String targetId, required String reason}) => _rpc.run(
    'report_content',
    params: {'p_target_type': targetType, 'p_target_id': targetId, 'p_reason': reason},
  );
}
