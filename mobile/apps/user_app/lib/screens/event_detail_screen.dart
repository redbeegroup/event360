import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/event_card.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.idOrSlug});
  final String idOrSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final event = ref.watch(eventProvider(idOrSlug));
    return event.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: MessageView(
          icon: Icons.event_busy,
          message: e is ApiException && e.status == 404 ? t.noEvents : t.loadError,
          actionLabel: t.retry,
          onAction: () => ref.invalidate(eventProvider(idOrSlug)),
        ),
      ),
      data: (e) => _Detail(event: e),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.event});
  final EventSummary event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final e = event;
    final ended = e.endsAt.isBefore(DateTime.now());
    final cancelled = e.status == 'CANCELLED';
    final description = pickLang(lang, e.description, e.descriptionMy);
    final summary = pickLang(lang, e.summary, e.summaryMy);
    final payable = (ref.watch(paymentMethodsProvider).value ?? const <PaymentMethod>[]).isNotEmpty;
    bool sellable(TicketType tt) => !tt.soldOut && (tt.isFree || payable);
    final canRegister = !ended && !cancelled && e.ticketTypes.any(sellable);
    final sellsPaid = e.ticketTypes.any((tt) => !tt.isFree && sellable(tt));
    final bold = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    void open(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

    Widget infoRow(IconData icon, String title, [String? sub, VoidCallback? onTap]) => ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: onTap,
          leading: CircleAvatar(backgroundColor: theme.colorScheme.primaryContainer, child: Icon(icon, color: theme.colorScheme.onPrimaryContainer)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub == null || sub.isEmpty ? null : Text(sub),
          trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        );
    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: bold), const SizedBox(height: 8), ...children]),
        );

    final practical = <(IconData, String, String)>[
      if (e.ageMin != null) (Icons.badge_outlined, t.ageLimit(e.ageMin!), ''),
      if (!e.dressCode.isEmpty) (Icons.checkroom, t.dressCode, e.dressCode.of(lang)),
      if (!e.languages.isEmpty) (Icons.translate, t.languages, e.languages.of(lang)),
      if (!e.parking.isEmpty) (Icons.local_parking, t.parking, e.parking.of(lang)),
      if (!e.accessibility.isEmpty) (Icons.accessible, t.accessibility, e.accessibility.of(lang)),
      if (!e.whatToBring.isEmpty) (Icons.backpack_outlined, t.whatToBring, e.whatToBring.of(lang)),
    ];

    // Schedule grouped by (Myanmar-time) day
    final days = <String, List<ScheduleItem>>{};
    for (final s in e.schedule) {
      days.putIfAbsent(formatDay(s.startsAt, lang), () => []).add(s);
    }

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 240,
          actions: [
            IconButton(tooltip: t.addToCalendar, icon: const Icon(Icons.event_available), onPressed: () => open(ref.read(apiProvider).calendarUri(e.id))),
            IconButton(
              tooltip: t.share,
              icon: const Icon(Icons.ios_share),
              onPressed: () => SharePlus.instance.share(ShareParams(text: shareText(e, lang))),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(background: EventCover(url: e.coverImageUrl, aspectRatio: 16 / 10)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          sliver: SliverList.list(children: [
            if (cancelled) _Banner(text: t.eventCancelled, color: theme.colorScheme.error),
            if (!cancelled && ended) _Banner(text: t.eventEnded, color: theme.colorScheme.outline),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Pill(pickLang(lang, e.categoryName, e.categoryNameMy), color: theme.colorScheme.secondary),
              Pill(formatLabel(t, e.format), color: theme.colorScheme.tertiary),
              if (e.ageMin != null) Pill(t.ageLimit(e.ageMin!), color: theme.colorScheme.error),
            ]),
            const SizedBox(height: 10),
            Text(pickLang(lang, e.title, e.titleMy), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (summary.isNotEmpty) ...[const SizedBox(height: 6), Text(summary, style: theme.textTheme.bodyLarge)],
            const SizedBox(height: 12),
            infoRow(Icons.event, formatEventDate(e.startsAt, lang), formatTimeRange(e.startsAt, e.endsAt, lang),
                () => open(ref.read(apiProvider).calendarUri(e.id))),
            if (e.venue != null)
              infoRow(Icons.place_outlined, pickLang(lang, e.venue!.name, e.venue!.nameMy),
                  [e.venue!.address, e.venue!.city].whereType<String>().join(', '), () => open(e.venue!.mapsUri)),
            if (e.format == 'ONLINE') infoRow(Icons.live_tv_outlined, t.formatOnline),
            infoRow(
              e.organizerVerified ? Icons.verified : Icons.groups_outlined,
              e.organizerName,
              e.organizerVerified ? t.verified : t.organizer,
              e.organizerSlug == null ? null : () => context.push('/organizer/${e.organizerSlug}'),
            ),
            _WatchSection(eventId: e.id, lang: lang),
            if (e.gallery.isNotEmpty)
              section(t.gallery, [
                SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: e.gallery.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GestureDetector(
                        onTap: () => _openGallery(context, e.gallery, i, lang),
                        child: AspectRatio(aspectRatio: 4 / 3, child: CachedNetworkImage(imageUrl: e.gallery[i].url, fit: BoxFit.cover)),
                      ),
                    ),
                  ),
                ),
              ]),
            if (description.isNotEmpty) section(t.about, [Text(description)]),
            if (days.isNotEmpty)
              section(t.schedule, [
                for (final day in days.entries) ...[
                  Padding(padding: const EdgeInsets.only(top: 4, bottom: 4), child: Text(day.key, style: theme.textTheme.labelLarge)),
                  for (final s in day.value)
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        SizedBox(
                          width: 78,
                          child: Padding(padding: const EdgeInsets.only(top: 10), child: Text(formatTime(s.startsAt, lang), style: theme.textTheme.labelLarge)),
                        ),
                        Container(width: 2, color: theme.colorScheme.primaryContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(pickLang(lang, s.title, s.titleMy), style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text([formatTimeRange(s.startsAt, s.endsAt, lang), if (s.location != null) s.location!].join(' · '),
                                  style: theme.textTheme.bodySmall),
                              if (pickLang(lang, s.description, s.descriptionMy).isNotEmpty) Text(pickLang(lang, s.description, s.descriptionMy)),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                ],
              ]),
            if (e.performers.isNotEmpty)
              section(t.lineup, [
                SizedBox(
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: e.performers.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, i) {
                      final p = e.performers[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _showPerformer(context, p, lang),
                        child: SizedBox(
                          width: 88,
                          child: Column(children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: theme.colorScheme.secondaryContainer,
                              backgroundImage: p.photoUrl == null ? null : CachedNetworkImageProvider(p.photoUrl!),
                              child: p.photoUrl == null ? Text(p.name.characters.first.toUpperCase(), style: theme.textTheme.titleLarge) : null,
                            ),
                            const SizedBox(height: 6),
                            Text(pickLang(lang, p.name, p.nameMy),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (pickLang(lang, p.role, p.roleMy).isNotEmpty)
                              Text(pickLang(lang, p.role, p.roleMy), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            section(t.tickets, [
              for (final tt in e.ticketTypes)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(pickLang(lang, tt.name, tt.nameMy)),
                    subtitle: Text(tt.soldOut ? t.soldOut : t.remaining(tt.remaining)),
                    trailing: Text(tt.isFree ? t.free : t.mmk(formatAmount(tt.priceMmk, lang)),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
              if (!payable && e.ticketTypes.any((tt) => !tt.isFree)) Text(t.paidSoon, style: theme.textTheme.bodySmall),
            ]),
            if (practical.isNotEmpty)
              section(t.practicalInfo, [
                for (final (icon, title, value) in practical)
                  ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: Icon(icon), title: Text(title), subtitle: value.isEmpty ? null : Text(value)),
              ]),
            if (e.venue != null)
              section(t.directions, [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(pickLang(lang, e.venue!.name, e.venue!.nameMy), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text([e.venue!.address, e.venue!.city].whereType<String>().join(', ')),
                      if (pickLang(lang, e.venue!.directions, e.venue!.directionsMy).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(pickLang(lang, e.venue!.directions, e.venue!.directionsMy)),
                      ],
                      const SizedBox(height: 10),
                      OutlinedButton.icon(onPressed: () => open(e.venue!.mapsUri), icon: const Icon(Icons.map_outlined), label: Text(t.openInMaps)),
                    ]),
                  ),
                ),
              ]),
            if (e.faqs.isNotEmpty)
              section(t.faq, [
                for (final f in e.faqs)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(pickLang(lang, f.question, f.questionMy), style: const TextStyle(fontWeight: FontWeight.w600)),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    childrenPadding: const EdgeInsets.only(bottom: 12),
                    children: [Text(pickLang(lang, f.answer, f.answerMy))],
                  ),
              ]),
            if (!e.refundPolicy.isEmpty || !e.terms.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(children: [
                  if (!e.refundPolicy.isEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      leading: const Icon(Icons.undo),
                      title: Text(t.refundPolicy),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      children: [Text(e.refundPolicy.of(lang))],
                    ),
                  if (!e.terms.isEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      leading: const Icon(Icons.gavel_outlined),
                      title: Text(t.terms),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      children: [Text(e.terms.of(lang))],
                    ),
                ]),
              ),
          ]),
        ),
      ]),
      bottomNavigationBar: canRegister
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  key: const Key('getTickets'),
                  onPressed: () => _startRegister(context, ref, payable),
                  child: Text(sellsPaid ? t.getTickets : t.registerFree),
                ),
              ),
            )
          : null,
    );
  }

  void _showPerformer(BuildContext context, Performer p, String lang) {
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

  void _openGallery(BuildContext context, List<GalleryImage> images, int start, String lang) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: PageView.builder(
          controller: PageController(initialPage: start),
          itemCount: images.length,
          itemBuilder: (_, i) => Column(children: [
            Expanded(child: InteractiveViewer(child: Center(child: CachedNetworkImage(imageUrl: images[i].url, fit: BoxFit.contain)))),
            if (pickLang(lang, images[i].caption, images[i].captionMy).isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(pickLang(lang, images[i].caption, images[i].captionMy), style: const TextStyle(color: Colors.white)),
              ),
          ]),
        ),
      ),
    ));
  }

  Future<void> _startRegister(BuildContext context, WidgetRef ref, bool payable) async {
    final me = await ref.read(sessionProvider.future);
    if (!context.mounted) return;
    if (me == null) {
      await context.push('/login?from=${Uri.encodeComponent('/event/${event.id}')}');
      return;
    }
    final orderId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RegisterSheet(event: event, payable: payable),
    );
    if (orderId != null && context.mounted) await context.push('/checkout/$orderId');
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      );
}

class _RegisterSheet extends ConsumerStatefulWidget {
  const _RegisterSheet({required this.event, required this.payable});
  final EventSummary event;
  final bool payable;
  @override
  ConsumerState<_RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends ConsumerState<_RegisterSheet> {
  late final List<TicketType> _options = widget.event.ticketTypes.where((t) => !t.soldOut && (t.isFree || widget.payable)).toList();
  late TicketType _type = _options.first;
  // Same key for retries of this sheet: the API returns the same order instead of holding seats twice
  final String _idempotencyKey = List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  int _qty = 1;
  bool _busy = false;
  String? _error;
  bool _done = false;

  int get _max => [_type.maxPerOrder, _type.remaining].reduce((a, b) => a < b ? a : b);

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final o = await ref.read(apiProvider).createOrder(widget.event.id, {_type.id: _qty}, idempotencyKey: '$_idempotencyKey-${_type.id}-$_qty');
      ref.invalidate(eventProvider(widget.event.id));
      if (o.isPaid) {
        ref.invalidate(myTicketsProvider);
        setState(() => _done = true);
      } else {
        ref.invalidate(pendingOrdersProvider);
        if (mounted) Navigator.of(context).pop(o.id); // → checkout
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final free = _options;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: _done
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(t.registered, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go('/tickets');
                },
                child: Text(t.viewTickets),
              ),
            ])
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(pickLang(lang, widget.event.title, widget.event.titleMy), style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final tt in free)
                RadioListTile<String>(
                  value: tt.id,
                  groupValue: _type.id,
                  onChanged: (_) => setState(() {
                    _type = tt;
                    _qty = 1;
                  }),
                  title: Text(pickLang(lang, tt.name, tt.nameMy)),
                  subtitle: Text(t.remaining(tt.remaining)),
                  secondary: Text(tt.isFree ? t.free : t.mmk(formatAmount(tt.priceMmk, lang)), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('${t.quantity} · ${t.perPersonLimit(_type.maxPerOrder)}')),
                IconButton.outlined(onPressed: _qty > 1 ? () => setState(() => _qty--) : null, icon: const Icon(Icons.remove)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$_qty', style: theme.textTheme.titleLarge)),
                IconButton.outlined(onPressed: _qty < _max ? () => setState(() => _qty++) : null, icon: const Icon(Icons.add)),
              ]),
              if (!_type.isFree)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Expanded(child: Text(t.total, style: theme.textTheme.titleMedium)),
                    Text(t.mmk(formatAmount(_type.priceMmk * _qty, lang)), key: const Key('sheetTotal'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ]),
                ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('sheetSubmit'),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(_type.isFree ? t.register : t.checkout),
              ),
            ]),
    );
  }
}

/// Live streams and recordings for ticket holders. Hidden when the event has none.
class _WatchSection extends ConsumerWidget {
  const _WatchSection({required this.eventId, required this.lang});
  final String eventId;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = L10n.of(context);
    final s = ref.watch(eventStreamsProvider(eventId)).value;
    if (s == null || s.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    String dur(int? sec) => sec == null ? '' : '${sec ~/ 3600 > 0 ? '${sec ~/ 3600}:' : ''}${((sec % 3600) ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';
    void open(String kind, String id, String title) => context.push('/watch/$kind/$id?title=${Uri.encodeQueryComponent(title)}');
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.watch, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final l in s.live)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              key: Key('live-${l.channelId}'),
              leading: Icon(Icons.live_tv, color: l.isLive ? const Color(0xFFD32F2F) : null),
              title: Text(pickLang(lang, l.title, l.titleMy), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(l.isLive ? t.watchLive : t.startsAtTime(formatEventDate(l.startsAt, lang))),
              trailing: l.isLive
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFD32F2F), borderRadius: BorderRadius.circular(4)),
                      child: Text(t.liveNow, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                    )
                  : null,
              onTap: l.isLive ? () => open('live', l.channelId, pickLang(lang, l.title, l.titleMy)) : null,
            ),
          ),
        for (final r in s.recordings)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              key: Key('vod-${r.id}'),
              leading: const Icon(Icons.play_circle_outline),
              title: Text(pickLang(lang, r.title, r.titleMy), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([
                t.recordingsTitle,
                if (r.durationSec != null) dur(r.durationSec),
                if (r.availableUntil != null) t.availableUntil(formatEventDate(r.availableUntil!, lang)),
              ].join(' · ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open('vod', r.id, pickLang(lang, r.title, r.titleMy)),
            ),
          ),
      ]),
    );
  }
}
