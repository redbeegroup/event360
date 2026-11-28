import 'package:intl/intl.dart';

/// Myanmar Standard Time is UTC+06:30 all year (no DST) — events are shown in Yangon time
/// regardless of the phone's time zone.
const _mmt = Duration(hours: 6, minutes: 30);

DateTime toYangon(DateTime utc) => utc.toUtc().add(_mmt);

String _loc(String lang) => lang == 'my' ? 'my' : 'en';

/// e.g. "Fri, 15 Jan 2027 · 5:00 PM"
String formatEventDate(DateTime start, String lang) {
  final d = toYangon(start);
  return '${DateFormat('EEE, d MMM y', _loc(lang)).format(d)} · ${DateFormat.jm(_loc(lang)).format(d)}';
}

/// e.g. "5:00 PM – 10:00 PM" (same day) or full end date otherwise.
String formatTimeRange(DateTime start, DateTime end, String lang) {
  final s = toYangon(start), e = toYangon(end);
  final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
  final t = DateFormat.jm(_loc(lang));
  return sameDay ? '${t.format(s)} – ${t.format(e)}' : '${t.format(s)} – ${DateFormat('d MMM y', _loc(lang)).add_jm().format(e)}';
}

/// Short date for cards: day number + month.
({String day, String month}) dateBadge(DateTime start, String lang) {
  final d = toYangon(start);
  return (day: DateFormat('d', _loc(lang)).format(d), month: DateFormat('MMM', _loc(lang)).format(d));
}

String formatAmount(int mmk, String lang) => NumberFormat.decimalPattern(_loc(lang)).format(mmk);

/// A whole count in the language's own numerals (Myanmar digits in Burmese); plural selection should still use the int.
String formatCount(int n, String lang) => NumberFormat.decimalPattern(_loc(lang)).format(n);

/// Accepts 09…, 959…, +959… with spaces/dashes; mirrors the API's normalizeMyanmarPhone.
bool isValidMyanmarPhone(String input) {
  final digits = input.replaceAll(RegExp(r'[\s\-()]'), '');
  final m = RegExp(r'^(?:\+?959|09)(\d{7,10})$').firstMatch(digits);
  return m != null;
}

/// e.g. "Sat, 5 Dec" — a day header for schedules.
String formatDay(DateTime start, String lang) => DateFormat('EEE, d MMM', _loc(lang)).format(toYangon(start));

/// e.g. "5:00 PM"
String formatTime(DateTime t, String lang) => DateFormat.jm(_loc(lang)).format(toYangon(t));
