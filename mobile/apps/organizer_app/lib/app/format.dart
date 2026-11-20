import 'package:intl/intl.dart';

const _mmt = Duration(hours: 6, minutes: 30);

/// Myanmar Standard Time (UTC+06:30), whatever the device's zone.
DateTime toYangon(DateTime t) => t.toUtc().add(_mmt);

String _loc(String lang) => lang == 'my' ? 'my' : 'en';

/// e.g. "5:42 PM"
String formatTime(DateTime t, String lang) => DateFormat.jm(_loc(lang)).format(toYangon(t));

/// e.g. "Sat, 19 Dec · 5:00 PM"
String formatDayTime(DateTime t, String lang) => '${DateFormat('EEE, d MMM', _loc(lang)).format(toYangon(t))} · ${formatTime(t, lang)}';

/// e.g. "15,000"
String formatAmount(int mmk, String lang) => NumberFormat.decimalPattern(_loc(lang)).format(mmk);

/// "15,000 MMK" / "15,000 ကျပ်"
String formatMmk(int mmk, String lang) => '${formatAmount(mmk, lang)} ${lang == 'my' ? 'ကျပ်' : 'MMK'}';
