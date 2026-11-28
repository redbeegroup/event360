/// Pure helpers behind the event guide: status, the "today" window, now-and-next and in-event search.
/// Every function takes `now` explicitly (UTC) so it can be tested without a clock.
library;

import 'models.dart';

/// Yangon is a fixed UTC+6:30 (no daylight saving); same offset as the app's `toYangon`.
const yangonOffset = Duration(hours: 6, minutes: 30);

enum GuidePhase { before, onNow, ended, cancelled }

GuidePhase guidePhase({required DateTime startsAt, required DateTime endsAt, String? status, required DateTime now}) {
  if (status == 'CANCELLED') return GuidePhase.cancelled;
  if (now.isBefore(startsAt)) return GuidePhase.before;
  if (now.isBefore(endsAt)) return GuidePhase.onNow;
  return GuidePhase.ended;
}

/// Time until the start, rounded down to whole days, hours or minutes (at least 1 minute).
({int value, String unit}) startsIn(DateTime startsAt, DateTime now) {
  final d = startsAt.difference(now);
  if (d.inDays >= 1) return (value: d.inDays, unit: 'days');
  if (d.inHours >= 1) return (value: d.inHours, unit: 'hours');
  final m = d.inMinutes;
  return (value: m < 1 ? 1 : m, unit: 'minutes');
}

/// True from the earlier of 00:00 Yangon on the start date and six hours before the start, until the end.
bool isEventToday({required DateTime startsAt, required DateTime endsAt, required DateTime now}) {
  final local = startsAt.toUtc().add(yangonOffset);
  final midnight = DateTime.utc(local.year, local.month, local.day).subtract(yangonOffset);
  final sixBefore = startsAt.toUtc().subtract(const Duration(hours: 6));
  final opens = midnight.isBefore(sixBefore) ? midnight : sixBefore;
  return !now.isBefore(opens) && now.isBefore(endsAt);
}

/// The guide link stays on the ticket until a week after the event ends.
bool guideLinkVisible({required DateTime endsAt, required DateTime now}) => now.isBefore(endsAt.add(const Duration(days: 7)));

/// Sessions running at [now] (start order) and the next [nextCount] sessions that have not started.
({List<ScheduleItem> now, List<ScheduleItem> next}) nowAndNext(List<ScheduleItem> sessions, DateTime now, {int nextCount = 3}) {
  int byTime(ScheduleItem a, ScheduleItem b) {
    final c = a.startsAt.compareTo(b.startsAt);
    if (c != 0) return c;
    final e = a.endsAt.compareTo(b.endsAt);
    return e != 0 ? e : a.title.compareTo(b.title);
  }

  final sorted = [...sessions]..sort(byTime);
  final running = sorted.where((s) => !s.startsAt.isAfter(now) && now.isBefore(s.endsAt)).toList();
  final upcoming = sorted.where((s) => s.startsAt.isAfter(now)).take(nextCount).toList();
  return (now: running, next: upcoming);
}

class GuideHit {
  const GuideHit({required this.group, required this.index, required this.title, this.snippet, this.id});

  /// 'schedule' | 'lineup' | 'faq' | 'info'
  final String group;

  /// Position in the event's own list for that group (`event.schedule`, `event.performers`, `event.faqs`, or [infoFields] for 'info'),
  /// never in a re-sorted or day-grouped list.
  final int index;

  /// The session's id for 'schedule' hits (null for other groups, or sessions without an id).
  final String? id;
  final String title;
  final String? snippet;
}

/// Order of the 'info' group's [GuideHit.index].
const infoFields = ['Dress code', 'Languages', 'Parking', 'Accessibility', 'What to bring', 'Terms', 'Refund policy', 'Getting there'];

/// Case-insensitive search of one event's guide content in both languages. One hit per item (never per field).
/// [lang] only picks which language the hit's title and snippet are shown in.
List<GuideHit> searchEvent(EventSummary event, String query, {String lang = 'en'}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  // First matching field of the item, as a snippet; null when nothing matches.
  String? match(Iterable<String?> fields) {
    final texts = fields.whereType<String>().where((t) => t.isNotEmpty).toList();
    for (final t in texts) {
      if (t.toLowerCase().contains(q)) return _snippet(t, q);
    }
    return null;
  }

  final hits = <GuideHit>[];
  for (var i = 0; i < event.schedule.length; i++) {
    final s = event.schedule[i];
    final m = match([s.title, s.titleMy, s.description, s.descriptionMy, s.location]);
    if (m != null) hits.add(GuideHit(group: 'schedule', index: i, title: pickLang(lang, s.title, s.titleMy), snippet: m, id: s.id));
  }
  for (var i = 0; i < event.performers.length; i++) {
    final p = event.performers[i];
    final m = match([p.name, p.nameMy, p.role, p.roleMy, p.bio, p.bioMy]);
    if (m != null) hits.add(GuideHit(group: 'lineup', index: i, title: pickLang(lang, p.name, p.nameMy), snippet: m));
  }
  for (var i = 0; i < event.faqs.length; i++) {
    final f = event.faqs[i];
    final m = match([f.question, f.questionMy, f.answer, f.answerMy]);
    if (m != null) hits.add(GuideHit(group: 'faq', index: i, title: pickLang(lang, f.question, f.questionMy), snippet: m));
  }
  final info = <LocalizedText>[
    event.dressCode,
    event.languages,
    event.parking,
    event.accessibility,
    event.whatToBring,
    event.terms,
    event.refundPolicy,
    LocalizedText(event.venue?.directions, event.venue?.directionsMy),
  ];
  for (var i = 0; i < info.length; i++) {
    final m = match([info[i].en, info[i].my]);
    if (m != null) hits.add(GuideHit(group: 'info', index: i, title: infoFields[i], snippet: m));
  }
  return hits;
}

String _snippet(String text, String q) {
  const radius = 40;
  final at = text.toLowerCase().indexOf(q);
  final from = (at - radius).clamp(0, text.length);
  final to = (at + q.length + radius).clamp(0, text.length);
  return '${from > 0 ? '…' : ''}${text.substring(from, to).trim()}${to < text.length ? '…' : ''}';
}
