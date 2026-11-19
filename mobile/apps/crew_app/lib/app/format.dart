import 'package:intl/intl.dart';

const _mmt = Duration(hours: 6, minutes: 30);

/// Myanmar Standard Time (UTC+06:30), whatever the device's zone.
DateTime toYangon(DateTime t) => t.toUtc().add(_mmt);

String _loc(String lang) => lang == 'my' ? 'my' : 'en';

/// e.g. "5:42 PM"
String formatTime(DateTime t, String lang) => DateFormat.jm(_loc(lang)).format(toYangon(t));

/// e.g. "Sat, 19 Dec · 5:00 PM"
String formatDayTime(DateTime t, String lang) => '${DateFormat('EEE, d MMM', _loc(lang)).format(toYangon(t))} · ${formatTime(t, lang)}';

/// "K7QM-4XRT" from a typed code or from a redeem link (…?code=K7QM-4XRT).
String? extractEventCode(String raw) {
  final s = raw.trim();
  final uri = Uri.tryParse(s);
  final fromLink = uri?.queryParameters['code'] ?? Uri.tryParse(uri?.fragment ?? '')?.queryParameters['code'];
  final code = (fromLink ?? s).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : null;
}
