import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import 'event_sections.dart';

/// The texts behind the 'info' hits, in the order of [infoFields].
List<LocalizedText> infoTexts(EventSummary e) => [
      e.dressCode,
      e.languages,
      e.parking,
      e.accessibility,
      e.whatToBring,
      e.terms,
      e.refundPolicy,
      LocalizedText(e.venue?.directions, e.venue?.directionsMy),
    ];

/// Localized labels for [infoFields] (same order). The practical-info rows use the same strings.
List<String> infoLabels(L10n t) => [t.dressCode, t.languages, t.parking, t.accessibility, t.whatToBring, t.terms, t.refundPolicy, t.directions];

/// Whether the event has anything to search; without it the search action is not shown.
bool eventIsSearchable(EventSummary? e) =>
    e != null && (e.schedule.isNotEmpty || e.performers.isNotEmpty || e.faqs.isNotEmpty || infoTexts(e).any((x) => !x.isEmpty));

/// The search icon for an app bar. Null when there is nothing to search.
Widget? eventSearchAction(BuildContext context, EventSummary? e, {Key key = const Key('eventSearchAction')}) {
  if (!eventIsSearchable(e)) return null;
  return IconButton(
    key: key,
    tooltip: L10n.of(context).searchThisEvent,
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    icon: const Icon(Icons.search),
    onPressed: () => showEventSearch(context, e!),
  );
}

/// A full-height sheet with a search field and grouped results; tapping a hit closes it and opens the item.
/// Works on the event object it is given and never touches the network.
Future<void> showEventSearch(BuildContext context, EventSummary event) async {
  final hit = await showModalBottomSheet<GuideHit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SearchSheet(event: event),
  );
  if (hit == null || !context.mounted) return;
  _openHit(context, event, hit, ProviderScope.containerOf(context).read(langProvider));
}

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet({required this.event});
  final EventSummary event;
  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final lang = ref.watch(langProvider);
    final query = _controller.text.trim();
    final hits = searchEvent(widget.event, query, lang: lang);
    final labels = infoLabels(t);
    String groupTitle(String g) => switch (g) {
          'schedule' => t.schedule,
          'lineup' => t.lineup,
          'faq' => t.faq,
          _ => t.goodToKnow,
        };

    // Keyboard: the sheet is padded by the keyboard's height, so the results list stays visible above it.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: double.infinity,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              key: const Key('eventSearchField'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: t.searchEventHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        key: const Key('eventSearchClear'),
                        tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_controller.clear),
                      ),
              ),
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? const SizedBox.shrink()
                : hits.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(t.searchNoResults(query), key: const Key('eventSearchNoResults'), textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                      )
                    : ListView.builder(
                        key: const Key('eventSearchResults'),
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: hits.length,
                        itemBuilder: (context, i) {
                          final h = hits[i];
                          final title = h.group == 'info' ? labels[h.index] : h.title;
                          // The snippet only earns a line when it says something the title does not.
                          final snippet = h.snippet?.trim();
                          final showSnippet = snippet != null && snippet.isNotEmpty && _norm(snippet) != _norm(title);
                          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            if (i == 0 || hits[i - 1].group != h.group)
                              Padding(
                                key: Key('searchGroup-${h.group}'),
                                padding: const EdgeInsets.only(top: 16, bottom: 4),
                                child: Text(groupTitle(h.group), style: theme.textTheme.titleMedium),
                              ),
                            ListTile(
                              key: Key('searchHit-${h.group}-${h.index}'),
                              contentPadding: EdgeInsets.zero,
                              minVerticalPadding: 8,
                              title: Text(title),
                              subtitle: showSnippet ? Text(snippet, maxLines: 3, overflow: TextOverflow.ellipsis) : null,
                              onTap: () => Navigator.of(context).pop(h),
                            ),
                          ]);
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

String _norm(String x) => x.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

void _openHit(BuildContext context, EventSummary e, GuideHit hit, String lang) {
  final t = L10n.of(context);
  switch (hit.group) {
    case 'schedule':
      // The hit's index is where the item was when it was found; look it up by id only if the schedule has moved since.
      final atIndex = hit.index < e.schedule.length ? e.schedule[hit.index] : null;
      final s = hit.id == null || atIndex?.id == hit.id ? atIndex : e.schedule.where((s) => s.id == hit.id).firstOrNull;
      if (s == null) return;
      final description = pickLang(lang, s.description, s.descriptionMy);
      _showTextSheet(context, const Key('searchSessionSheet'), pickLang(lang, s.title, s.titleMy), [
        Text('${formatDay(s.startsAt, lang)} · ${formatTimeRange(s.startsAt, s.endsAt, lang)}', style: Theme.of(context).textTheme.titleSmall),
        if (s.location != null && s.location!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.place_outlined, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(s.location!, style: Theme.of(context).textTheme.bodyMedium)),
          ]),
        ],
        if (description.isNotEmpty) ...[const SizedBox(height: 12), Text(description, style: Theme.of(context).textTheme.bodyLarge)],
      ]);
    case 'lineup':
      if (hit.index < e.performers.length) showPerformerSheet(context, e.performers[hit.index], lang);
    case 'faq':
      if (hit.index >= e.faqs.length) return;
      final f = e.faqs[hit.index];
      _showTextSheet(context, const Key('searchFaqSheet'), pickLang(lang, f.question, f.questionMy), [
        Text(pickLang(lang, f.answer, f.answerMy), style: Theme.of(context).textTheme.bodyLarge),
      ]);
    case 'info':
      final texts = infoTexts(e);
      if (hit.index >= texts.length) return;
      _showTextSheet(context, const Key('searchInfoSheet'), infoLabels(t)[hit.index], [
        Text(texts[hit.index].of(lang), style: Theme.of(context).textTheme.bodyLarge),
      ]);
  }
}

void _showTextSheet(BuildContext context, Key key, String title, List<Widget> body) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ...body,
      ]),
    ),
  );
}
