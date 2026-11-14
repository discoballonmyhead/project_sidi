import '../../../core/bloc/async_cubit.dart';
import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../../../core/utils/format.dart';
import '../domain/booking.dart';
import '../domain/booking_repository.dart';

/// Slots of one resource for the selected day, and booking them.
class AvailabilityCubit extends AsyncCubit<Availability> {
  AvailabilityCubit(this._repository, this.resourceId);

  final BookingRepository _repository;
  final String resourceId;
  DateTime day = Days.of(DateTime.now());

  @override
  Future<Result<Availability>> fetch() => _repository.availability(resourceId, day);

  Future<void> selectDay(DateTime value) {
    day = Days.of(value);
    return load();
  }

  Future<bool> book(Slot slot, {required int slots, String? notes}) => act(
    () => _repository.book(resourceId, slot.startsAt, slots: slots, notes: notes),
    success: 'Booked for ${Fmt.dayTime(slot.startsLocal)}.',
  );
}

typedef MyBookings = ({List<Booking> upcoming, List<Booking> past});

class MyBookingsCubit extends AsyncCubit<MyBookings> {
  MyBookingsCubit(this._repository);
  final BookingRepository _repository;

  @override
  Future<Result<MyBookings>> fetch() async {
    final upcoming = await _repository.myBookings(upcoming: true);
    if (upcoming case Err(:final failure)) return Err(failure);
    final past = await _repository.myBookings(upcoming: false);
    if (past case Err(:final failure)) return Err(failure);
    return Ok((upcoming: upcoming.valueOrNull!, past: past.valueOrNull!));
  }

  Future<bool> cancel(Booking booking) => act(() => _repository.cancel(booking.id), success: 'Booking cancelled.');
}

/// Facilities and their bookable resources, for the manage section.
class FacilitiesCubit extends AsyncCubit<List<ManagedFacility>> {
  FacilitiesCubit(this._repository, this.orgId);
  final BookingRepository _repository;
  final String orgId;

  @override
  Future<Result<List<ManagedFacility>>> fetch() => _repository.facilities(orgId);

  Future<bool> saveFacility(Json facility) => act(() => _repository.saveFacility(orgId, facility), success: 'Facility saved.');
  Future<bool> saveResource(Json resource) => act(() => _repository.saveResource(orgId, resource), success: 'Saved.');
  Future<bool> block(String resourceId, DateTime from, DateTime to, String? reason) =>
      act(() => _repository.blockResource(resourceId, from, to, reason: reason), success: 'Closed for that time.');
  Future<bool> unblock(String blockId) => act(() => _repository.unblockResource(blockId));
}

typedef DeskDay = ({List<Booking> bookings, List<ManagedFacility> facilities});

/// The front desk: every booking of one day, plus walk-ins.
class DeskCubit extends AsyncCubit<DeskDay> {
  DeskCubit(this._repository, this.orgId);
  final BookingRepository _repository;
  final String orgId;
  DateTime day = Days.of(DateTime.now());

  @override
  Future<Result<DeskDay>> fetch() async {
    final bookings = await _repository.orgBookings(orgId, day, day);
    if (bookings case Err(:final failure)) return Err(failure);
    final facilities = state.data?.facilities.isNotEmpty == true
        ? Ok<List<ManagedFacility>>(state.data!.facilities)
        : await _repository.facilities(orgId);
    if (facilities case Err(:final failure)) return Err(failure);
    return Ok((bookings: bookings.valueOrNull!, facilities: facilities.valueOrNull!));
  }

  Future<void> selectDay(DateTime value) {
    day = Days.of(value);
    return load();
  }

  Future<bool> setStatus(Booking booking, String status) =>
      act(() => _repository.setBookingStatus(booking.id, status), success: 'Booking ${Fmt.label(status).toLowerCase()}.');

  Future<bool> settle(PaymentRef payment, String status, {String? method}) =>
      act(() => _repository.settlePayment(payment.id, status, method: method), success: 'Payment ${Fmt.label(status).toLowerCase()}.');

  Future<bool> walkIn(String resourceId, DateTime startsAt, {required int slots, String? name, String? handle, num? price}) => act(
    () => _repository.deskBook(resourceId, startsAt, slots: slots, customerName: name, handle: handle, price: price),
    success: 'Booking added.',
  );
}

class PaymentsCubit extends AsyncCubit<List<Payment>> {
  PaymentsCubit(this._repository, this.orgId);
  final BookingRepository _repository;
  final String orgId;
  String? status = 'pending';

  @override
  Future<Result<List<Payment>>> fetch() => _repository.payments(orgId, status: status);

  Future<void> filter(String? value) {
    status = value;
    return load();
  }

  Future<bool> settle(Payment payment, String status, {String? method}) =>
      act(() => _repository.settlePayment(payment.id, status, method: method), success: 'Payment ${Fmt.label(status).toLowerCase()}.');
}
