import 'package:intl/intl.dart';

abstract final class Fmt {
  static final _day = DateFormat('EEE d MMM');
  static final _dayYear = DateFormat('d MMM yyyy');
  static final _time = DateFormat('HH:mm');
  static final _dayTime = DateFormat('EEE d MMM · HH:mm');
  static final _month = DateFormat('MMM yyyy');

  static String day(DateTime? value) => value == null ? '-' : _day.format(value);
  static String dayYear(DateTime? value) => value == null ? '-' : _dayYear.format(value);
  static String time(DateTime? value) => value == null ? '-' : _time.format(value);
  static String dayTime(DateTime? value) => value == null ? '-' : _dayTime.format(value);
  static String month(DateTime? value) => value == null ? '-' : _month.format(value);

  static String range(DateTime? from, DateTime? to) {
    if (from == null) return '-';
    if (to == null || Days.same(from, to)) return dayYear(from);
    return '${_day.format(from)} - ${dayYear(to)}';
  }

  static String timeRange(DateTime from, DateTime to) => '${_time.format(from)} - ${_time.format(to)}';

  static String money(num amount, [String currency = 'INR']) {
    final whole = amount == amount.roundToDouble();
    try {
      return NumberFormat.simpleCurrency(name: currency, decimalDigits: whole ? 0 : 2).format(amount);
    } catch (_) {
      return '$currency ${amount.toStringAsFixed(whole ? 0 : 2)}';
    }
  }

  static String compact(num amount) => NumberFormat.compact().format(amount);

  /// `1` or `1.5`, never `1.0`.
  static String number(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(value.abs() < 10 ? 2 : 1);

  /// `snake_case` to `Sentence case`.
  static String label(String value) {
    if (value.isEmpty) return value;
    final text = value.replaceAll('_', ' ');
    return text[0].toUpperCase() + text.substring(1);
  }
}

abstract final class Days {
  static bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  static DateTime of(DateTime value) => DateTime(value.year, value.month, value.day);
}
