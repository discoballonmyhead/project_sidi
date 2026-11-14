import '../network/rpc.dart';

/// Tolerant readers for the JSON documents the RPC layer returns.
extension JsonReaders on Json {
  String str(String key, [String fallback = '']) => this[key]?.toString() ?? fallback;

  String? strOrNull(String key) {
    final value = this[key]?.toString();
    return (value == null || value.isEmpty) ? null : value;
  }

  int integer(String key, [int fallback = 0]) => intOrNull(key) ?? fallback;

  int? intOrNull(String key) {
    final value = this[key];
    if (value is num) return value.toInt();
    if (value is String) return num.tryParse(value)?.toInt();
    return null;
  }

  double number(String key, [double fallback = 0]) => numberOrNull(key) ?? fallback;

  double? numberOrNull(String key) {
    final value = this[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool flag(String key, [bool fallback = false]) {
    final value = this[key];
    return value is bool ? value : fallback;
  }

  DateTime? dateOrNull(String key) {
    final value = this[key];
    return value is String ? DateTime.tryParse(value)?.toLocal() : null;
  }

  DateTime date(String key) => dateOrNull(key) ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// A calendar date (`2026-11-14`) with no time-zone shifting.
  DateTime? dayOrNull(String key) {
    final value = this[key];
    if (value is! String || value.length < 10) return null;
    final parsed = DateTime.tryParse(value.substring(0, 10));
    return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
  }

  Json? objOrNull(String key) {
    final value = this[key];
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Json obj(String key) => objOrNull(key) ?? const {};

  List<T> list<T>(String key, T Function(Json item) parse) => parseList(this[key], parse);

  List<String> strings(String key) {
    final value = this[key];
    return value is List ? [for (final item in value) item.toString()] : const [];
  }
}

List<T> parseList<T>(dynamic json, T Function(Json item) parse) {
  if (json is! List) return const [];
  return [
    for (final item in json)
      if (item is Map) parse(Map<String, dynamic>.from(item)),
  ];
}

Json asJson(dynamic json) => json is Map ? Map<String, dynamic>.from(json) : const {};

/// `2026-11-14T18:30:00`: a wall-clock time with no zone. Times an
/// organisation enters (walk-ins, match schedules, closures, deadlines) are
/// times at its venue, and the backend applies the venue's time zone.
String isoLocal(DateTime time) =>
    '${isoDay(time)}T${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';

/// `2026-11-14`, the format the backend expects for calendar dates.
String isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
