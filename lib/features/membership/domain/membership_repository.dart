import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import 'membership.dart';

abstract interface class MembershipRepository {
  // Member
  Future<Result<void>> join(String planId, {String? note});
  Future<Result<void>> cancel(String membershipId);
  Future<Result<List<Membership>>> myMemberships();
  Future<Result<Journey>> myJourney(String membershipId);

  // Organisation
  Future<Result<List<Plan>>> plans(String orgId);
  Future<Result<void>> savePlan(String orgId, Json plan);
  Future<Result<List<Membership>>> orgMemberships(String orgId);
  Future<Result<void>> decide(String membershipId, {required bool approve, String? coachId});
  Future<Result<void>> update(String membershipId, Json patch);
  Future<Result<Journey>> memberJourney(String membershipId);
  Future<Result<void>> logSession(String membershipId, Json session);
  Future<Result<void>> recordMetrics(String membershipId, List<Json> entries, {DateTime? on});
  Future<Result<void>> publishReport(String membershipId, Json report);
  Future<Result<void>> defineMetric(String orgId, Json metric);
}
