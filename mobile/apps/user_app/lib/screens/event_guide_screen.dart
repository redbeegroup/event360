import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/format.dart';
import '../app/guide_providers.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/event_search.dart';
import '../widgets/event_sections.dart';

/// How often the open guide refetches the event.
const guideRefreshInterval = Duration(minutes: 5);

/// Everything a guide section needs to decide whether (and how) to draw itself.
class GuideContext {
  GuideContext({
    required this.eventId,
    required this.event,
    required this.announcements,
    required this.tickets,
    required this.streams,
    required this.savedAt,
    required this.neverSaved,
    required this.now,
    required this.lang,
  });

  final String eventId;

  /// Null only while nothing was ever saved and there is no network ([neverSaved]).
  final EventSummary? event;
  final List<EventAnnouncement> announcements;

  /// The viewer's usable tickets for this event.
  final List<MyTicket> tickets;
  final EventStreams? streams;
  final DateTime? savedAt;
  final bool neverSaved;
  final DateTime now;
  final String lang;

  bool get offline => savedAt != null || neverSaved;

  DateTime get startsAt => event?.startsAt ?? tickets.first.startsAt;
  DateTime get endsAt => event?.endsAt ?? tickets.first.endsAt;
  String get title => event == null ? pickLang(lang, tickets.first.eventTitle, tickets.first.eventTitleMy) : pickLang(lang, event!.title, event!.titleMy);

  GuidePhase get phase => guidePhase(startsAt: startsAt, endsAt: endsAt, status: event?.status ?? tickets.first.eventStatus, now: now);
}

typedef GuideSectionBuilder = Widget? Function(BuildContext context, GuideContext g);

/// One block of the guide. The builder returns null when it has nothing to show, so empty sections never appear.
class GuideSection {
  const GuideSection(this.id, this.build);
  final String id;
  final GuideSectionBuilder build;
}

/// Top to bottom. Later rounds insert their sections here.
final List<GuideSection> guideSections = [
  GuideSection('savedCopy', _savedCopySection),
  GuideSection('neverSaved', _neverSavedSection),
  GuideSection('header', _headerSection),
  GuideSection('tickets', _ticketsSection),
  GuideSection('nowNext', _nowNextSection),
  GuideSection('venue', _venueSection),
  GuideSection('watch', _watchSection),
  GuideSection('announcements', _announcementsSection),
  GuideSection('info', _infoSection),
  GuideSection('thanks', _thanksSection),
];

class EventGuideScreen extends ConsumerStatefulWidget {
  const EventGuideScreen({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<EventGuideScreen> createState() => _EventGuideScreenState();
}

class _EventGuideScreenState extends ConsumerState<EventGuideScreen> with WidgetsBindingObserver {
  Timer? _refetch;
  Timer? _clock;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimers();
  }

  void _startTimers() {
    _refetch?.cancel();
    _clock?.cancel();
    _refetch = Timer.periodic(guideRefreshInterval, (_) => _refresh());
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {}); // the status line follows the clock
    });
  }

  void _stopTimers() {
    _refetch?.cancel();
    _clock?.cancel();
    _refetch = null;
    _clock = null;
  }

  /// In the background nothing ticks; coming back refreshes once and restarts the clock.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_refetch == null) {
        _startTimers();
        _refresh();
        setState(() {});
      }
    } else if (state != AppLifecycleState.inactive) {
      _stopTimers();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTimers();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(guideProvider(widget.eventId));
    ref.invalidate(guideStreamsProvider(widget.eventId));
  }

  void _leave(String to) {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(to);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final id = widget.eventId;
    final access = guideAccessOf(
      session: ref.watch(sessionProvider),
      tickets: ref.watch(myTicketsProvider),
      idOrSlug: id,
      ticketsOwner: ref.read(myTicketsProvider.notifier).owner,
    );

    Widget scaffold(Widget body, {List<Widget> actions = const []}) => Scaffold(appBar: AppBar(title: Text(t.eventGuide), actions: actions), body: body);
    Widget loading() => scaffold(const Center(child: CircularProgressIndicator()));

    switch (access.access) {
      case GuideAccess.loading:
        return loading();
      case GuideAccess.error:
        return scaffold(MessageView(icon: Icons.wifi_off, message: t.loadError, actionLabel: t.retry, onAction: () => ref.invalidate(myTicketsProvider)));
      case GuideAccess.signedOut:
        _leave('/login?from=${Uri.encodeQueryComponent('/event/$id/guide')}');
        return loading();
      case GuideAccess.noTicket:
        _leave('/event/$id');
        return loading();
      case GuideAccess.allowed:
        break;
    }

    final guide = ref.watch(guideProvider(id));
    final data = guide.value;
    if (data == null) {
      final error = guide.error;
      if (error is ApiException && error.isNotFound) {
        // The event was removed: nothing to retry.
        return scaffold(MessageView(
          icon: Icons.event_busy,
          message: t.guideGone,
          actionLabel: MaterialLocalizations.of(context).backButtonTooltip,
          onAction: () => context.canPop() ? context.pop() : context.go('/tickets'),
        ));
      }
      if (guide.hasError) {
        return scaffold(MessageView(icon: Icons.wifi_off, message: t.loadError, actionLabel: t.retry, onAction: _refresh));
      }
      return loading();
    }
    final g = GuideContext(
      eventId: id,
      event: data.event,
      announcements: data.announcements,
      tickets: access.tickets,
      streams: data.offline ? null : ref.watch(guideStreamsProvider(id)).value,
      savedAt: data.savedAt,
      neverSaved: data.neverSaved,
      now: ref.watch(nowProvider)(),
      lang: ref.watch(langProvider),
    );
    return scaffold(
      RefreshIndicator(
        onRefresh: () async {
          _refresh();
          await ref.read(guideProvider(id).future).catchError((_) => data);
        },
        child: ListView(
          key: const Key('guideList'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            for (final s in guideSections) ...[
              if (s.build(context, g) case final w?) KeyedSubtree(key: Key('guideSection-${s.id}'), child: w),
            ],
          ],
        ),
      ),
      actions: _appBarActions(context, g),
    );
  }
}

/// The app bar's action slot: search this event (from the live or the saved copy).
List<Widget> _appBarActions(BuildContext context, GuideContext g) => [if (eventSearchAction(context, g.event) case final w?) w];

// ───── Building blocks ─────

Widget _titled(BuildContext context, {Key? key, required String title, required List<Widget> children, double top = 24}) {
  final theme = Theme.of(context);
  return Padding(
    key: key,
    padding: EdgeInsets.only(top: top),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: theme.textTheme.titleLarge),
      const SizedBox(height: 12),
      ...children,
    ]),
  );
}

Widget _card(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  return Material(
    color: theme.colorScheme.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: theme.colorScheme.outlineVariant)),
    child: child,
  );
}

Widget _needsConnection(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(L10n.of(context).needsConnection, style: Theme.of(context).textTheme.bodySmall),
    );

// ───── Sections ─────

Widget? _savedCopySection(BuildContext context, GuideContext g) {
  if (g.savedAt == null) return null;
  final t = L10n.of(context);
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.cloud_off, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(t.savedCopy(formatEventDate(g.savedAt!, g.lang)), key: const Key('guideSavedCopy'), style: theme.textTheme.bodyMedium)),
    ]),
  );
}

Widget? _neverSavedSection(BuildContext context, GuideContext g) {
  if (!g.neverSaved) return null;
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.cloud_off, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(L10n.of(context).neverSaved, key: const Key('guideNeverSaved'), style: theme.textTheme.bodyMedium)),
    ]),
  );
}

Widget? _headerSection(BuildContext context, GuideContext g) {
  final t = L10n.of(context);
  final theme = Theme.of(context);
  final phase = g.phase;
  final status = switch (phase) {
    GuidePhase.cancelled => t.guideCancelled,
    GuidePhase.ended => t.guideEnded,
    GuidePhase.onNow => t.guideOnNow,
    GuidePhase.before => () {
        final s = startsIn(g.startsAt, g.now);
        return switch (s.unit) {
          'days' => t.guideStartsInDays(s.value),
          'hours' => t.guideStartsInHours(s.value),
          _ => t.guideStartsInMinutes(s.value),
        };
      }(),
  };
  final bad = phase == GuidePhase.cancelled;
  final dark = theme.brightness == Brightness.dark;
  final color = bad ? theme.colorScheme.error : (phase == GuidePhase.onNow ? (dark ? E360DarkColors.success : E360Colors.success) : theme.colorScheme.onSurfaceVariant);
  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(g.title, key: const Key('guideTitle'), style: theme.textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text(formatEventDate(g.startsAt, g.lang), style: theme.textTheme.bodyMedium),
      const SizedBox(height: 8),
      Text(status, key: const Key('guideStatus'), style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
    ]),
  );
}

Widget? _ticketsSection(BuildContext context, GuideContext g) {
  if (g.tickets.isEmpty) return null;
  final t = L10n.of(context);
  final theme = Theme.of(context);
  final single = g.tickets.length == 1;
  final dark = theme.brightness == Brightness.dark;

  Widget row(MyTicket x) {
    final seat = x.seatText(g.lang);
    final body = Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pickLang(g.lang, x.ticketTypeName, x.ticketTypeNameMy), style: theme.textTheme.titleSmall),
            if (seat != null) Text(seat, key: Key('guideSeat-${x.id}'), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
            if (x.isCheckedIn)
              Text(
                x.checkedInAt == null ? t.checkedIn : t.checkedInAt(formatTime(x.checkedInAt!, g.lang)),
                key: Key('guideChecked-${x.id}'),
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: dark ? E360DarkColors.success : E360Colors.success),
              ),
          ]),
        ),
        if (!single) const Icon(Icons.chevron_right),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _card(context, single ? body : InkWell(key: Key('guideTicket-${x.id}'), onTap: () => context.push('/ticket/${x.id}'), child: body)),
    );
  }

  return _titled(context, key: const Key('guideTickets'), title: t.yourTickets, children: [
    for (final x in g.tickets) row(x),
    if (single)
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: FilledButton(
          key: const Key('guideShowTicket'),
          style: E360Buttons.gold,
          onPressed: () => context.push('/ticket/${g.tickets.first.id}'),
          child: Text(t.showTicket),
        ),
      ),
  ]);
}

/// The session's running stream, when it is live now (matched by session id).
LiveStream? _liveFor(GuideContext g, ScheduleItem s) {
  if (s.id == null) return null;
  return g.streams?.live.where((l) => l.sessionId == s.id && l.isLive).firstOrNull;
}

Widget? _nowNextSection(BuildContext context, GuideContext g) {
  final e = g.event;
  if (e == null || e.schedule.length < 2) return null;
  final phase = g.phase;
  if (phase == GuidePhase.ended || phase == GuidePhase.cancelled) return null;
  final t = L10n.of(context);
  final theme = Theme.of(context);
  final nn = nowAndNext(e.schedule, g.now);
  if (nn.now.isEmpty && nn.next.isEmpty) return null;

  Widget session(ScheduleItem s) {
    final live = _liveFor(g, s);
    final where = [formatTimeRange(s.startsAt, s.endsAt, g.lang), if (s.location != null && s.location!.isNotEmpty) s.location!].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _card(
        context,
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pickLang(g.lang, s.title, s.titleMy), style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(where, style: theme.textTheme.bodySmall),
            if (live != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  key: Key('guideWatch-${s.id}'),
                  style: E360Buttons.outline,
                  onPressed: () => context.push('/watch/live/${live.channelId}?title=${Uri.encodeQueryComponent(pickLang(g.lang, live.title, live.titleMy))}'),
                  icon: const Icon(Icons.live_tv),
                  label: Text(t.watch),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  return _titled(context, key: const Key('guideNowNext'), title: t.nowTitle, children: [
    if (nn.now.isNotEmpty) Column(key: const Key('guideNow'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final s in nn.now) session(s)]),
    if (nn.next.isNotEmpty) ...[
      Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Text(t.nextTitle, style: theme.textTheme.titleLarge)),
      Column(key: const Key('guideNext'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final s in nn.next) session(s)]),
    ],
    // Which sessions are on a stream is only known online: offline, an event with online sessions shows Watch disabled.
    if (g.offline && e.format != 'IN_PERSON')
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          OutlinedButton.icon(key: const Key('guideWatchOfflineSessions'), style: E360Buttons.outline, onPressed: null, icon: const Icon(Icons.live_tv), label: Text(t.watch)),
          _needsConnection(context),
        ]),
      ),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton(
        key: const Key('guideFullSchedule'),
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: () => _showFullSchedule(context, e, g.lang),
        child: Text(t.fullSchedule),
      ),
    ),
  ]);
}

void _showFullSchedule(BuildContext context, EventSummary e, String lang) {
  final t = L10n.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        key: const Key('guideScheduleSheet'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(t.fullSchedule, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ScheduleDayList(items: e.schedule, lang: lang),
        ],
      ),
    ),
  );
}

Widget? _venueSection(BuildContext context, GuideContext g) {
  final e = g.event;
  if (e == null || e.venue == null || e.format == 'ONLINE' || g.phase == GuidePhase.cancelled) return null;
  final v = e.venue!;
  final t = L10n.of(context);
  final theme = Theme.of(context);
  final directions = pickLang(g.lang, v.directions, v.directionsMy);
  final address = [v.address, v.city].whereType<String>().where((x) => x.isNotEmpty).join(', ');
  return Consumer(builder: (context, ref, _) {
    return _titled(context, key: const Key('guideVenue'), title: t.venue, children: [
      _card(
        context,
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pickLang(g.lang, v.name, v.nameMy), style: theme.textTheme.titleMedium),
            if (address.isNotEmpty) Text(address, style: theme.textTheme.bodyMedium),
            if (directions.isNotEmpty) ...[const SizedBox(height: 8), Text(directions, style: theme.textTheme.bodyMedium)],
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                key: const Key('guideDirections'),
                style: E360Buttons.outline,
                onPressed: g.offline
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final failed = t.openFailed;
                        var ok = false;
                        try {
                          ok = await ref.read(urlOpenerProvider)(guideDirectionsUri(v));
                        } catch (_) {}
                        if (!ok) messenger.showSnackBar(SnackBar(content: Text(failed)));
                      },
                icon: const Icon(Icons.map_outlined),
                label: Text(t.getDirections),
              ),
            ),
            if (g.offline) _needsConnection(context),
          ]),
        ),
      ),
    ]);
  });
}

/// Online-only events: the Watch entry takes the venue's place.
Widget? _watchSection(BuildContext context, GuideContext g) {
  final e = g.event;
  if (e == null || e.format != 'ONLINE' || g.phase == GuidePhase.cancelled || g.phase == GuidePhase.ended) return null;
  final t = L10n.of(context);
  final theme = Theme.of(context);
  final live = g.streams?.live ?? const <LiveStream>[];
  if (!g.offline && g.streams == null) return null; // not loaded yet, or not loadable
  Widget tile(LiveStream l) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _card(
          context,
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pickLang(g.lang, l.title, l.titleMy), style: theme.textTheme.titleSmall),
              Text(l.isLive ? t.watchLive : t.startsAtTime(formatEventDate(l.startsAt, g.lang)), style: theme.textTheme.bodySmall),
              if (l.isLive)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    key: Key('guideWatch-${l.sessionId}'),
                    style: E360Buttons.outline,
                    onPressed: () => context.push('/watch/live/${l.channelId}?title=${Uri.encodeQueryComponent(pickLang(g.lang, l.title, l.titleMy))}'),
                    icon: const Icon(Icons.live_tv),
                    label: Text(t.watch),
                  ),
                ),
            ]),
          ),
        ),
      );
  return _titled(context, key: const Key('guideWatchEntry'), title: t.watch, children: [
    if (g.offline)
      _card(
        context,
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.formatOnline, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            OutlinedButton.icon(key: const Key('guideWatchOffline'), style: E360Buttons.outline, onPressed: null, icon: const Icon(Icons.live_tv), label: Text(t.watch)),
            _needsConnection(context),
          ]),
        ),
      )
    else if (live.isEmpty)
      _card(
        context,
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.formatOnline, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            OutlinedButton.icon(key: const Key('guideWatchNotStarted'), style: E360Buttons.outline, onPressed: null, icon: const Icon(Icons.live_tv), label: Text(t.watch)),
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(t.guideStreamNotStarted, style: theme.textTheme.bodySmall)),
          ]),
        ),
      )
    else
      for (final l in live) tile(l),
  ]);
}

Widget? _announcementsSection(BuildContext context, GuideContext g) {
  if (g.announcements.isEmpty) return null;
  final t = L10n.of(context);
  final all = [...g.announcements]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  const shown = 3;
  return _titled(context, key: const Key('guideAnnouncements'), title: t.announcements, children: [
    for (final a in all.take(shown)) Padding(padding: const EdgeInsets.only(bottom: 8), child: _AnnouncementCard(a: a, lang: g.lang, clamp: true)),
    if (all.length > shown)
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextButton(
            key: const Key('guideSeeAllAnnouncements'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: g.offline ? null : () => _showAllAnnouncements(context, all, g.lang),
            child: Text(t.seeAll),
          ),
          if (g.offline) Padding(padding: const EdgeInsets.only(left: 4), child: _needsConnection(context)),
        ]),
      ),
  ]);
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.a, required this.lang, required this.clamp});
  final EventAnnouncement a;
  final String lang;
  final bool clamp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _card(
      context,
      Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pickLang(lang, a.title, a.titleMy), style: theme.textTheme.titleSmall),
          Text(formatEventDate(a.createdAt, lang), style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            pickLang(lang, a.body, a.bodyMy),
            key: Key('announcementBody-${a.id}'),
            maxLines: clamp ? 3 : null,
            overflow: clamp ? TextOverflow.ellipsis : TextOverflow.clip,
            style: theme.textTheme.bodyMedium,
          ),
        ]),
      ),
    );
  }
}

void _showAllAnnouncements(BuildContext context, List<EventAnnouncement> all, String lang) {
  final t = L10n.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        key: const Key('guideAnnouncementsSheet'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(t.announcements, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final a in all) Padding(padding: const EdgeInsets.only(bottom: 8), child: _AnnouncementCard(a: a, lang: lang, clamp: false)),
        ],
      ),
    ),
  );
}

Widget? _infoSection(BuildContext context, GuideContext g) {
  final e = g.event;
  if (e == null || g.phase == GuidePhase.cancelled) return null;
  final t = L10n.of(context);
  final items = practicalInfoItems(t, e, g.lang);
  if (items.isEmpty && e.faqs.isEmpty) return null;
  return _titled(context, key: const Key('guideInfo'), title: t.goodToKnow, children: [
    if (items.isNotEmpty) PracticalInfoRows(items: items),
    if (e.faqs.isNotEmpty) FaqTiles(faqs: e.faqs, lang: g.lang),
  ]);
}

Widget? _thanksSection(BuildContext context, GuideContext g) {
  if (g.phase != GuidePhase.ended) return null;
  final t = L10n.of(context);
  final theme = Theme.of(context);
  final recordings = g.streams?.recordings ?? const <Recording>[];
  return _titled(context, key: const Key('guideThanks'), title: t.guideThanks, children: [
    for (final r in recordings)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _card(
          context,
          ListTile(
            key: Key('guideRecording-${r.id}'),
            leading: const Icon(Icons.play_circle_outline),
            title: Text(pickLang(g.lang, r.title, r.titleMy), style: theme.textTheme.titleSmall),
            subtitle: Text([t.recordingsTitle, if (r.availableUntil != null) t.availableUntil(formatEventDate(r.availableUntil!, g.lang))].join(' · ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/watch/vod/${r.id}?title=${Uri.encodeQueryComponent(pickLang(g.lang, r.title, r.titleMy))}'),
          ),
        ),
      ),
  ]);
}
