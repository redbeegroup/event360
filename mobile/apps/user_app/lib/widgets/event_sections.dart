import 'package:cached_network_image/cached_network_image.dart';
import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';

import '../app/format.dart';
import '../l10n/app_localizations.dart';

/// The practical-info lines of an event (age limit, dress code, language, parking, accessibility, what to bring): only the filled ones.
/// Shared by the event page and the guide.
List<(IconData, String, String)> practicalInfoItems(L10n t, EventSummary e, String lang) => [
      if (e.ageMin != null) (Icons.badge_outlined, t.ageLimit(e.ageMin!), ''),
      if (!e.dressCode.isEmpty) (Icons.checkroom, t.dressCode, e.dressCode.of(lang)),
      if (!e.languages.isEmpty) (Icons.translate, t.languages, e.languages.of(lang)),
      if (!e.parking.isEmpty) (Icons.local_parking, t.parking, e.parking.of(lang)),
      if (!e.accessibility.isEmpty) (Icons.accessible, t.accessibility, e.accessibility.of(lang)),
      if (!e.whatToBring.isEmpty) (Icons.backpack_outlined, t.whatToBring, e.whatToBring.of(lang)),
    ];

class PracticalInfoRows extends StatelessWidget {
  const PracticalInfoRows({super.key, required this.items});
  final List<(IconData, String, String)> items;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (icon, title, value) in items)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: InfoRow(icon: icon, title: title, subtitle: value.isEmpty ? null : value)),
      ]);
}

/// The schedule grouped by (Myanmar-time) day, in the order the organizer entered it.
class ScheduleDayList extends StatelessWidget {
  const ScheduleDayList({super.key, required this.items, required this.lang});
  final List<ScheduleItem> items;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = <String, List<ScheduleItem>>{};
    for (final s in items) {
      days.putIfAbsent(formatDay(s.startsAt, lang), () => []).add(s);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final day in days.entries) ...[
        Padding(padding: const EdgeInsets.only(top: 4, bottom: 4), child: Text(day.key, style: theme.textTheme.labelLarge)),
        for (final s in day.value)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 78,
                child: Padding(padding: const EdgeInsets.only(top: 10), child: Text(formatTime(s.startsAt, lang), style: theme.textTheme.labelLarge)),
              ),
              Container(width: 2, color: theme.colorScheme.outlineVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(pickLang(lang, s.title, s.titleMy), style: theme.textTheme.titleSmall?.copyWith(fontSize: 15)),
                    Text([formatTimeRange(s.startsAt, s.endsAt, lang), if (s.location != null) s.location!].join(' · '), style: theme.textTheme.bodySmall),
                    if (pickLang(lang, s.description, s.descriptionMy).isNotEmpty) Text(pickLang(lang, s.description, s.descriptionMy), style: theme.textTheme.bodyMedium),
                  ]),
                ),
              ),
            ]),
          ),
      ],
    ]);
  }
}

/// Question and answer tiles.
class FaqTiles extends StatelessWidget {
  const FaqTiles({super.key, required this.faqs, required this.lang});
  final List<Faq> faqs;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final f in faqs)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(pickLang(lang, f.question, f.questionMy), style: theme.textTheme.titleSmall?.copyWith(fontSize: 15)),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          children: [Text(pickLang(lang, f.answer, f.answerMy), style: theme.textTheme.bodyMedium)],
        ),
    ]);
  }
}

/// The performer bottom sheet (photo, name, role, bio). Shared by the event page and the event search.
void showPerformerSheet(BuildContext context, Performer p, String lang) {
  final theme = Theme.of(context);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(
          radius: 48,
          backgroundImage: p.photoUrl == null ? null : CachedNetworkImageProvider(p.photoUrl!),
          child: p.photoUrl == null ? Text(p.name.characters.first.toUpperCase(), style: theme.textTheme.headlineMedium) : null,
        ),
        const SizedBox(height: 12),
        Text(pickLang(lang, p.name, p.nameMy), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        if (pickLang(lang, p.role, p.roleMy).isNotEmpty) Text(pickLang(lang, p.role, p.roleMy), style: theme.textTheme.bodyMedium),
        if (pickLang(lang, p.bio, p.bioMy).isNotEmpty) ...[const SizedBox(height: 12), Text(pickLang(lang, p.bio, p.bioMy))],
      ]),
    ),
  );
}
