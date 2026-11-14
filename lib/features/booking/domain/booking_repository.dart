import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import 'booking.dart';

abstract interface class BookingRepository {
  // Customer
  Future<Result<Availability>> availability(String resourceId, DateTime day);
  Future<Result<Booking>> book(String resourceId, DateTime startsAt, {int slots = 1, String? notes});
  Future<Result<void>> cancel(String bookingId, {String? reason});
  Future<Result<List<Booking>>> myBookings({required bool upcoming});

  // Organisation: facilities
  Future<Result<List<ManagedFacility>>> facilities(String orgId);
  Future<Result<void>> saveFacility(String orgId, Json facility);
  Future<Result<void>> saveResource(String orgId, Json resource);
  Future<Result<void>> blockResource(String resourceId, DateTime from, DateTime to, {String? reason});
  Future<Result<void>> unblockResource(String blockId);

  // Organisation: front desk
  Future<Result<List<Booking>>> orgBookings(String orgId, DateTime from, DateTime to);
  Future<Result<void>> deskBook(
    String resourceId,
    DateTime startsAt, {
    required int slots,
    String? customerName,
    String? handle,
    num? price,
    String? notes,
  });
  Future<Result<void>> setBookingStatus(String bookingId, String status, {String? reason});
  Future<Result<List<Payment>>> payments(String orgId, {String? status});
  Future<Result<void>> settlePayment(String paymentId, String status, {String? method});
}
