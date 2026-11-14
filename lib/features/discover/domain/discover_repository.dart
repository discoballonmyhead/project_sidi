import '../../../core/error/result.dart';
import 'discover.dart';

abstract interface class DiscoverRepository {
  Future<Result<List<OrgCard>>> searchOrgs({String? query, String? sport});
  Future<Result<OrgProfile>> orgProfile(String orgId);
  Future<Result<void>> report({required String targetType, required String targetId, required String reason});
}
