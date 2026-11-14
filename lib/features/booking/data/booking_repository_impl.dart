import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../../../core/utils/json.dart';
import '../domain/booking.dart';
import '../domain/booking_repository.dart';

Resource resourceFromJson(Json r) => Resource(
  id: r.str('id'),
  orgId: r.str('org_id'),
  facilityId: r.str('facility_id'),
  sportCode: r.str('sport_code'),
  kind: r.str('kind'),
  name: r.str('name'),
  capacity: r.integer('capacity', 1),
  slotMinutes: r.integer('slot_minutes', 60),
  price: r.number('price'),
  autoConfirm: r.flag('auto_confirm', true),
  isActive: r.flag('is_active', true),
  facilityName: r.str('facility_name'),
  facilityCity: r.strOrNull('facility_city'),
  cancelHours: r.integer('cancel_hours'),
  orgName: r.str('org_name'),
  currency: r.str('currency', 'INR'),
);

PaymentRef? paymentRefFromJson(Json? p) => p == null
    ? null
    : PaymentRef(
        id: p.str('id'),
        status: p.str('status'),
        amount: p.number('amount'),
        method: p.strOrNull('method'),
        currency: p.strOrNull('currency'),
      );

Booking bookingFromJson(Json b) => Booking(
  id: b.str('id'),
  orgId: b.str('org_id'),
  resourceId: b.str('resource_id'),
  kind: b.str('kind'),
  status: b.str('status'),
  price: b.number('price'),
  startsAt: b.date('starts_at'),
  endsAt: b.date('ends_at'),
  customerName: b.str('customer_name', 'Guest'),
  resourceName: b.str('resource_name'),
  sportCode: b.str('sport_code'),
  facilityName: b.str('facility_name'),
  orgName: b.str('org_name'),
  currency: b.str('currency', 'INR'),
  cancelHours: b.integer('cancel_hours'),
  notes: b.strOrNull('notes'),
  payment: paymentRefFromJson(b.objOrNull('payment')),
);

Payment paymentFromJson(Json p) => Payment(
  id: p.str('id'),
  purpose: p.str('purpose'),
  amount: p.number('amount'),
  currency: p.str('currency', 'INR'),
  status: p.str('status'),
  description: p.strOrNull('description'),
  method: p.strOrNull('method'),
  payerName: p.strOrNull('payer_name'),
  createdAt: p.date('created_at'),
  paidAt: p.dateOrNull('paid_at'),
);

ManagedFacility _facilityFromJson(Json f) => ManagedFacility(
  id: f.str('id'),
  name: f.str('name'),
  address: f.strOrNull('address'),
  city: f.strOrNull('city'),
  tenure: f.str('tenure', 'owned'),
  cancelHours: f.integer('cancel_hours'),
  isActive: f.flag('is_active', true),
  monthlyCost: f.number('monthly_cost'),
  resources: f.list(
    'resources',
    (r) => ManagedResource(
      resource: resourceFromJson(r),
      hours: r.list(
        'hours',
        (h) => OpeningHours(
          weekday: h.integer('weekday'),
          opens: h.str('opens'),
          closes: h.str('closes'),
          price: h.numberOrNull('price'),
        ),
      ),
      blocks: r.list(
        'blocks',
        (k) => ResourceBlock(
          id: k.str('id'),
          startsAt: k.date('starts_at'),
          endsAt: k.date('ends_at'),
          reason: k.strOrNull('reason'),
        ),
      ),
    ),
  ),
);

class BookingRepositoryImpl implements BookingRepository {
  BookingRepositoryImpl(this._rpc);
  final Rpc _rpc;

  @override
  Future<Result<Availability>> availability(String resourceId, DateTime day) => _rpc.call(
    'resource_availability',
    params: {'p_resource_id': resourceId, 'p_date': isoDay(day)},
    parse: (json) {
      final map = asJson(json);
      return Availability(
        resource: resourceFromJson(map.obj('resource')),
        discountPct: map.number('discount_pct'),
        slots: map.list(
          'slots',
          (s) => Slot(
            startsAt: s.date('starts_at'),
            endsAt: s.date('ends_at'),
            price: s.number('price'),
            remaining: s.integer('remaining'),
            status: s.str('status'),
          ),
        ),
      );
    },
  );

  @override
  Future<Result<Booking>> book(String resourceId, DateTime startsAt, {int slots = 1, String? notes}) => _rpc.call(
    'booking_create',
    params: {
      'p_resource_id': resourceId,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_slots': slots,
      'p_notes': notes,
    },
    parse: (json) => bookingFromJson(asJson(json)),
  );

  @override
  Future<Result<void>> cancel(String bookingId, {String? reason}) =>
      _rpc.run('booking_cancel', params: {'p_booking_id': bookingId, 'p_reason': reason});

  @override
  Future<Result<List<Booking>>> myBookings({required bool upcoming}) => _rpc.call(
    'my_bookings',
    params: {'p_scope': upcoming ? 'upcoming' : 'past'},
    parse: (json) => parseList(json, bookingFromJson),
  );

  @override
  Future<Result<List<ManagedFacility>>> facilities(String orgId) =>
      _rpc.call('org_facilities', params: {'p_org_id': orgId}, parse: (json) => parseList(json, _facilityFromJson));

  @override
  Future<Result<void>> saveFacility(String orgId, Json facility) =>
      _rpc.run('org_facility_save', params: {'p_org_id': orgId, 'p_facility': facility});

  @override
  Future<Result<void>> saveResource(String orgId, Json resource) =>
      _rpc.run('org_resource_save', params: {'p_org_id': orgId, 'p_resource': resource});

  @override
  Future<Result<void>> blockResource(String resourceId, DateTime from, DateTime to, {String? reason}) => _rpc.run(
    'org_resource_block',
    params: {
      'p_resource_id': resourceId,
      'p_from': from.toUtc().toIso8601String(),
      'p_to': to.toUtc().toIso8601String(),
      'p_reason': reason,
    },
  );

  @override
  Future<Result<void>> unblockResource(String blockId) => _rpc.run('org_resource_unblock', params: {'p_block_id': blockId});

  @override
  Future<Result<List<Booking>>> orgBookings(String orgId, DateTime from, DateTime to) => _rpc.call(
    'org_bookings',
    params: {'p_org_id': orgId, 'p_from': isoDay(from), 'p_to': isoDay(to)},
    parse: (json) => parseList(json, bookingFromJson),
  );

  @override
  Future<Result<void>> deskBook(
    String resourceId,
    DateTime startsAt, {
    required int slots,
    String? customerName,
    String? handle,
    num? price,
    String? notes,
  }) => _rpc.run(
    'org_booking_create',
    params: {
      'p_resource_id': resourceId,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_slots': slots,
      'p_customer_name': customerName,
      'p_handle': handle,
      'p_price': price,
      'p_notes': notes,
    },
  );

  @override
  Future<Result<void>> setBookingStatus(String bookingId, String status, {String? reason}) =>
      _rpc.run('org_booking_set_status', params: {'p_booking_id': bookingId, 'p_status': status, 'p_reason': reason});

  @override
  Future<Result<List<Payment>>> payments(String orgId, {String? status}) => _rpc.call(
    'org_payments',
    params: {'p_org_id': orgId, 'p_status': status},
    parse: (json) => parseList(json, paymentFromJson),
  );

  @override
  Future<Result<void>> settlePayment(String paymentId, String status, {String? method}) =>
      _rpc.run('org_payment_settle', params: {'p_payment_id': paymentId, 'p_status': status, 'p_method': method});
}
