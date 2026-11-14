/// A bookable court, table, pitch, net or gym floor.
class Resource {
  const Resource({
    required this.id,
    required this.orgId,
    required this.facilityId,
    required this.sportCode,
    required this.kind,
    required this.name,
    required this.capacity,
    required this.slotMinutes,
    required this.price,
    required this.autoConfirm,
    required this.isActive,
    required this.facilityName,
    this.facilityCity,
    required this.cancelHours,
    required this.orgName,
    required this.currency,
  });

  final String id;
  final String orgId;
  final String facilityId;
  final String sportCode;
  final String kind;
  final String name;
  final int capacity;
  final int slotMinutes;
  final double price;
  final bool autoConfirm;
  final bool isActive;
  final String facilityName;
  final String? facilityCity;
  final int cancelHours;
  final String orgName;
  final String currency;

  bool get isShared => capacity > 1;
}

class Slot {
  const Slot({required this.startsAt, required this.endsAt, required this.price, required this.remaining, required this.status});

  final DateTime startsAt;
  final DateTime endsAt;
  final double price;
  final int remaining;

  /// `free`, `full`, `blocked` or `past`.
  final String status;

  bool get isFree => status == 'free';
}

class Availability {
  const Availability({required this.resource, required this.slots, required this.discountPct});

  final Resource resource;
  final List<Slot> slots;
  final double discountPct;
}

class PaymentRef {
  const PaymentRef({required this.id, required this.status, required this.amount, this.method, this.currency});
  final String id;
  final String status;
  final double amount;
  final String? method;
  final String? currency;
}

class Booking {
  const Booking({
    required this.id,
    required this.orgId,
    required this.resourceId,
    required this.kind,
    required this.status,
    required this.price,
    required this.startsAt,
    required this.endsAt,
    required this.customerName,
    required this.resourceName,
    required this.sportCode,
    required this.facilityName,
    required this.orgName,
    required this.currency,
    required this.cancelHours,
    this.notes,
    this.payment,
  });

  final String id;
  final String orgId;
  final String resourceId;
  final String kind;
  final String status;
  final double price;
  final DateTime startsAt;
  final DateTime endsAt;
  final String customerName;
  final String resourceName;
  final String sportCode;
  final String facilityName;
  final String orgName;
  final String currency;
  final int cancelHours;
  final String? notes;
  final PaymentRef? payment;

  bool get isOpen => status == 'pending' || status == 'confirmed';
  bool get canCancel => isOpen && startsAt.subtract(Duration(hours: cancelHours)).isAfter(DateTime.now());
}

class OpeningHours {
  const OpeningHours({required this.weekday, required this.opens, required this.closes, this.price});

  /// 0 = Sunday.
  final int weekday;
  final String opens;
  final String closes;
  final double? price;
}

class ResourceBlock {
  const ResourceBlock({required this.id, required this.startsAt, required this.endsAt, this.reason});
  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? reason;
}

class ManagedResource {
  const ManagedResource({required this.resource, required this.hours, required this.blocks});
  final Resource resource;
  final List<OpeningHours> hours;
  final List<ResourceBlock> blocks;
}

class ManagedFacility {
  const ManagedFacility({
    required this.id,
    required this.name,
    this.address,
    this.city,
    required this.tenure,
    required this.cancelHours,
    required this.isActive,
    required this.monthlyCost,
    required this.resources,
  });

  final String id;
  final String name;
  final String? address;
  final String? city;

  /// `owned`, `rented` or `leased`.
  final String tenure;
  final int cancelHours;
  final bool isActive;
  final double monthlyCost;
  final List<ManagedResource> resources;
}

class Payment {
  const Payment({
    required this.id,
    required this.purpose,
    required this.amount,
    required this.currency,
    required this.status,
    this.description,
    this.method,
    this.payerName,
    required this.createdAt,
    this.paidAt,
  });

  final String id;
  final String purpose;
  final double amount;
  final String currency;
  final String status;
  final String? description;
  final String? method;
  final String? payerName;
  final DateTime createdAt;
  final DateTime? paidAt;
}
