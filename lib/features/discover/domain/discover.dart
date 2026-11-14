import '../../booking/domain/booking.dart';
import '../../membership/domain/membership.dart';
import '../../tournaments/domain/tournament.dart';

class OrgCard {
  const OrgCard({
    required this.id,
    required this.name,
    this.description,
    this.city,
    required this.sports,
    required this.isVerified,
    required this.currency,
    required this.resourceCount,
    this.minPrice,
  });

  final String id;
  final String name;
  final String? description;
  final String? city;
  final List<String> sports;
  final bool isVerified;
  final String currency;
  final int resourceCount;
  final double? minPrice;
}

class Org {
  const Org({
    required this.id,
    required this.name,
    this.description,
    required this.status,
    required this.isVerified,
    required this.sports,
    this.city,
    this.address,
    this.contactEmail,
    this.contactPhone,
    this.logoUrl,
    required this.currency,
    required this.timezone,
  });

  final String id;
  final String name;
  final String? description;
  final String status;
  final bool isVerified;
  final List<String> sports;
  final String? city;
  final String? address;
  final String? contactEmail;
  final String? contactPhone;
  final String? logoUrl;
  final String currency;
  final String timezone;
}

class FacilityListing {
  const FacilityListing({required this.id, required this.name, this.address, this.city, required this.resources});
  final String id;
  final String name;
  final String? address;
  final String? city;
  final List<Resource> resources;
}

/// The public page of an organisation.
class OrgProfile {
  const OrgProfile({
    required this.org,
    this.myRole,
    required this.facilities,
    required this.plans,
    required this.tournaments,
    required this.myMemberships,
  });

  final Org org;
  final String? myRole;
  final List<FacilityListing> facilities;
  final List<Plan> plans;
  final List<TournamentCard> tournaments;
  final List<Membership> myMemberships;

  Membership? membershipFor(String planId) => myMemberships.where((m) => m.planId == planId).firstOrNull;
}
