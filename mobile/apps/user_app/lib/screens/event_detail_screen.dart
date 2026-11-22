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
import '../app/promo_text.dart';
import '../app/providers.dart';
import '../app/waitlist_text.dart';
import '../l10n/app_localizations.dart';
import '../widgets/discount_lines.dart';
import '../widgets/event_card.dart';
import '../widgets/total_amounts.dart';
import '../widgets/waitlist_offer.dart';

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
    // Seated ticket types are bought on the seat map, the rest (unseated, standing) by quantity
    final canRegister = !ended && !cancelled && e.ticketTypes.any((tt) => !tt.seated && sellable(tt));
    final canChooseSeats = !ended && !cancelled && e.ticketTypes.any((tt) => tt.seated && sellable(tt));
    final sellsPaid = e.ticketTypes.any((tt) => !tt.seated && !tt.isFree && sellable(tt));
    // Nothing to buy but a sold-out type the buyer is not in line for yet: the bar offers the waitlist
    final entries = ref.watch(waitlistProvider).value ?? const <WaitlistEntry>[];
    final waitlistType = canRegister || canChooseSeats || ended || cancelled
        ? null
        : e.ticketTypes.where((tt) => tt.soldOut && activeEntryFor(entries, tt.id) == null).firstOrNull;
    final bold = theme.textTheme.titleLarge;
    final dark = theme.brightness == Brightness.dark;
    void open(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

    Widget priceText(TicketType tt) => Text(tt.isFree ? t.free : t.mmk(formatAmount(tt.priceMmk, lang)),
        style: theme.textTheme.titleMedium?.copyWith(fontSize: 15, color: tt.isFree ? (dark ? E360DarkColors.success : E360Colors.success) : null));
    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: bold), const SizedBox(height: 12), ...children]),
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

    // "Good to know": only what the event already tells us (price rises, group tiers, refund policy)
    final goodToKnow = <(String, String, bool)>[
      for (final tt in e.ticketTypes)
        if (tt.nextPrice != null && tt.priceMmk > 0)
          (t.priceRiseSoon, t.priceRiseCard(pickLang(lang, tt.name, tt.nameMy), t.mmk(formatAmount(tt.nextPrice!.priceMmk, lang)), formatDay(tt.nextPrice!.startsAt, lang)), false),
      if (e.groupDiscounts.isNotEmpty)
        (
          t.groupDiscountTitle,
          ([...e.groupDiscounts]..sort((a, b) => a.minQuantity.compareTo(b.minQuantity))).map((g) => t.groupTierLine(g.minQuantity, percentText(g.percentBp))).join('\n'),
          false,
        ),
      if (!e.refundPolicy.isEmpty) (t.refundPolicy, e.refundPolicy.of(lang), true),
    ];

    // Only what the buyer can actually buy; if nothing is on sale, the whole list.
    final sellableTypes = e.ticketTypes.where(sellable).toList();
    final priceRange = _priceRange(t, lang, sellableTypes.isEmpty ? e.ticketTypes : sellableTypes);
    final day = dateBadge(e.startsAt, lang);
    final dateLine = '${day.day} ${day.month} · ${formatTime(e.startsAt, lang)}';

    return Scaffold(
      body: _ScrollWithBar(
        title: pickLang(lang, e.title, e.titleMy),
        onBack: () => context.canPop() ? context.pop() : context.go('/'),
        onShare: () => SharePlus.instance.share(ShareParams(text: shareText(e, lang))),
        slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 260,
            child: Stack(fit: StackFit.expand, children: [
              EventCover(url: e.coverImageUrl, aspectRatio: 16 / 10),
              Positioned(
                left: 16,
                right: 16,
                top: MediaQuery.paddingOf(context).top + 8,
                child: Row(children: [
                  _RoundIcon(
                    icon: Icons.arrow_back,
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                  ),
                  const Spacer(),
                  _RoundIcon(icon: Icons.event_available, tooltip: t.addToCalendar, onPressed: () => open(ref.read(apiProvider).calendarUri(e.id))),
                  const SizedBox(width: 10),
                  _RoundIcon(
                    icon: Icons.ios_share,
                    tooltip: t.share,
                    onPressed: () => SharePlus.instance.share(ShareParams(text: shareText(e, lang))),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverList.list(children: [
            if (cancelled) _Banner(text: t.eventCancelled, color: theme.colorScheme.error),
            if (!cancelled && ended) _Banner(text: t.eventEnded, color: theme.colorScheme.outline),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (e.seating != null) E360Badge(t.reservedSeating, kind: E360BadgeKind.gold),
              E360Badge(pickLang(lang, e.categoryName, e.categoryNameMy)),
              E360Badge(formatLabel(t, e.format)),
              if (e.ageMin != null) E360Badge(t.ageLimit(e.ageMin!)),
            ]),
            const SizedBox(height: 10),
            Text(pickLang(lang, e.title, e.titleMy), style: theme.textTheme.headlineMedium),
            const SizedBox(height: 6),
            InkWell(
              key: const Key('organizerLink'),
              borderRadius: BorderRadius.circular(8),
              onTap: e.organizerSlug == null ? null : () => context.push('/organizer/${e.organizerSlug}'),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      children: [
                        ..._byOrganizer(t.byOrganizer('\u0000'), e.organizerName, theme, linked: e.organizerSlug != null),
                        if (e.organizerVerified)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(start: 4),
                              child: Semantics(label: t.verified, child: Icon(Icons.verified, size: 16, color: theme.colorScheme.primary)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (summary.isNotEmpty) Text(summary, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 16),
            InfoRow(
              icon: Icons.event,
              title: formatEventDate(e.startsAt, lang),
              subtitle: formatTimeRange(e.startsAt, e.endsAt, lang),
              onTap: () => open(ref.read(apiProvider).calendarUri(e.id)),
            ),
            const SizedBox(height: 10),
            if (e.venue != null) ...[
              InfoRow(
                icon: Icons.place_outlined,
                title: pickLang(lang, e.venue!.name, e.venue!.nameMy),
                subtitle: [e.venue!.address, e.venue!.city].whereType<String>().join(', '),
                onTap: () => open(e.venue!.mapsUri),
              ),
              const SizedBox(height: 10),
            ],
            if (e.format == 'ONLINE') InfoRow(icon: Icons.live_tv_outlined, title: t.formatOnline),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(color: theme.colorScheme.outlineVariant),
              section(t.overview, [_Overview(text: description)]),
            ],
          ]),
        ),
        if (goodToKnow.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text(t.goodToKnow, style: bold)),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  key: const Key('goodToKnow'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final (i, (title, body, policy)) in goodToKnow.indexed) ...[
                        if (i > 0) const SizedBox(width: 12),
                        // Tiers and price rises list in full; the refund policy is cut at 3 lines with "Read more" for all of it
                        _GoodCard(
                          title: title,
                          body: body,
                          maxLines: policy ? 3 : null,
                          onMore: policy && body.length > 80 ? () => _showPolicy(context, title, body) : null,
                        ),
                      ],
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverList.list(children: [
            section(t.tickets, [
              _CardBox(
                child: Column(children: [
                  for (final (i, tt) in e.ticketTypes.indexed) ...[
                    if (i > 0) Divider(indent: 16, endIndent: 16, color: theme.colorScheme.outlineVariant),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(width: 12, height: 12, decoration: BoxDecoration(color: parseHexColor(tt.color) ?? theme.colorScheme.primary, shape: BoxShape.circle)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(pickLang(lang, tt.name, tt.nameMy), style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                            Text(tt.soldOut ? t.soldOut : t.remaining(tt.remaining),
                                style: theme.textTheme.bodySmall?.copyWith(color: !tt.soldOut && _scarce(tt) ? (dark ? E360DarkColors.amberInk : E360Colors.amberInk) : null, fontWeight: !tt.soldOut && _scarce(tt) ? FontWeight.w600 : null)),
                            if (priceRiseText(t, lang, tt.priceMmk, tt.nextPrice) != null)
                              Text(priceRiseText(t, lang, tt.priceMmk, tt.nextPrice)!, key: Key('priceRise-${tt.id}'), style: theme.textTheme.bodySmall),
                            if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) priceText(tt),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        // Large text: the price moves under the name instead of squeezing it out of the row
                        if (MediaQuery.textScalerOf(context).scale(1) < 1.5) priceText(tt),
                      ]),
                    ),
                    if (tt.soldOut && !ended && !cancelled) _WaitlistRow(event: e, type: tt),
                  ],
                ]),
              ),
              if (!payable && e.ticketTypes.any((tt) => !tt.isFree))
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(t.paidSoon, style: theme.textTheme.bodySmall)),
            ]),
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
                      borderRadius: BorderRadius.circular(14),
                      child: GestureDetector(
                        onTap: () => _openGallery(context, e.gallery, i, lang),
                        child: AspectRatio(aspectRatio: 4 / 3, child: CachedNetworkImage(imageUrl: e.gallery[i].url, fit: BoxFit.cover)),
                      ),
                    ),
                  ),
                ),
              ]),
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
                        Container(width: 2, color: theme.colorScheme.outlineVariant),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(pickLang(lang, s.title, s.titleMy), style: theme.textTheme.titleSmall?.copyWith(fontSize: 15)),
                              Text([formatTimeRange(s.startsAt, s.endsAt, lang), if (s.location != null) s.location!].join(' · '),
                                  style: theme.textTheme.bodySmall),
                              if (pickLang(lang, s.description, s.descriptionMy).isNotEmpty) Text(pickLang(lang, s.description, s.descriptionMy), style: theme.textTheme.bodyMedium),
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
                  height: 132 + MediaQuery.textScalerOf(context).scale(36) - 36, // the name and role lines grow with the text size
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
                            Text(pickLang(lang, p.name, p.nameMy), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                            if (pickLang(lang, p.role, p.roleMy).isNotEmpty)
                              Text(pickLang(lang, p.role, p.roleMy), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            if (practical.isNotEmpty)
              section(t.practicalInfo, [
                for (final (icon, title, value) in practical)
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: InfoRow(icon: icon, title: title, subtitle: value.isEmpty ? null : value)),
              ]),
            if (e.venue != null)
              section(t.directions, [
                _CardBox(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(pickLang(lang, e.venue!.name, e.venue!.nameMy), style: theme.textTheme.titleMedium),
                      Text([e.venue!.address, e.venue!.city].whereType<String>().join(', '), style: theme.textTheme.bodyMedium),
                      if (pickLang(lang, e.venue!.directions, e.venue!.directionsMy).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(pickLang(lang, e.venue!.directions, e.venue!.directionsMy), style: theme.textTheme.bodyMedium),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: E360Buttons.outline,
                        onPressed: () => open(e.venue!.mapsUri),
                        icon: const Icon(Icons.map_outlined),
                        label: Text(t.openInMaps),
                      ),
                    ]),
                  ),
                ),
              ]),
            if (e.faqs.isNotEmpty)
              section(t.faq, [
                for (final f in e.faqs)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(pickLang(lang, f.question, f.questionMy), style: theme.textTheme.titleSmall?.copyWith(fontSize: 15)),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    childrenPadding: const EdgeInsets.only(bottom: 12),
                    children: [Text(pickLang(lang, f.answer, f.answerMy), style: theme.textTheme.bodyMedium)],
                  ),
              ]),
            if (!e.terms.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(children: [
                  if (!e.terms.isEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      leading: const Icon(Icons.gavel_outlined),
                      title: Text(t.terms),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      children: [Text(e.terms.of(lang), style: theme.textTheme.bodyMedium)],
                    ),
                ]),
              ),
          ]),
        ),
      ]),
      bottomNavigationBar: canRegister || canChooseSeats || waitlistType != null
          ? PrimaryActionBar(
              summary: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(priceRange, key: const Key('barPrice'), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                Text(dateLine, key: const Key('barDate'), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ]),
              action: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.55),
                child: canChooseSeats && canRegister
                    // Seats AND standing tickets on sale: the button asks which kind first
                    ? FilledButton(
                        key: const Key('getTickets'),
                        style: E360Buttons.gold,
                        onPressed: () => _chooseKind(
                          context,
                          ref,
                          payable,
                          seatsFrom: _fromLabel(t, lang, e.ticketTypes.where((tt) => tt.seated && sellable(tt))),
                          standingFrom: _fromLabel(t, lang, e.ticketTypes.where((tt) => !tt.seated && sellable(tt))),
                        ),
                        child: Text(t.getTickets, textAlign: TextAlign.center),
                      )
                    : canChooseSeats
                    ? FilledButton(
                        key: const Key('chooseSeats'),
                        style: E360Buttons.gold,
                        onPressed: () => context.push('/event/${e.id}/seats'),
                        child: Text(t.chooseSeats, textAlign: TextAlign.center),
                      )
                    : canRegister
                        ? FilledButton(
                            key: const Key('getTickets'),
                            style: E360Buttons.gold,
                            onPressed: () => _startRegister(context, ref, payable),
                            child: Text(sellsPaid ? t.getTickets : t.registerFree, textAlign: TextAlign.center),
                          )
                        : FilledButton(
                            key: const Key('joinWaitlistBar'),
                            style: E360Buttons.gold,
                            onPressed: () => _joinWaitlist(context, ref, e, waitlistType!),
                            child: Text(t.joinWaitlist, textAlign: TextAlign.center),
                          ),
              ),
            )
          : null,
    );
  }

  /// "From 5,000 MMK", or "Free" when the cheapest of [types] is free.
  static String _fromLabel(L10n t, String lang, Iterable<TicketType> types) {
    final lo = types.map((x) => x.priceMmk).fold<int?>(null, (m, p) => m == null || p < m ? p : m);
    if (lo == null || lo == 0) return t.free;
    return t.fromPrice(t.mmk(formatAmount(lo, lang)));
  }

  /// Small sheet for events with seats and standing tickets: "Choose seats" → seat map, "Standing tickets" → quantity picker.
  void _chooseKind(BuildContext context, WidgetRef ref, bool payable, {required String seatsFrom, required String standingFrom}) {
    final theme = Theme.of(context);
    final t = L10n.of(context);
    Widget row(Key key, String title, String price, VoidCallback onTap) => Material(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.colorScheme.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: key,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(price, style: theme.textTheme.bodySmall?.copyWith(fontSize: 14)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                ]),
              ),
            ),
          ),
        );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(t.chooseTicketKind, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            row(const Key('kindSeats'), t.chooseSeats, seatsFrom, () {
              Navigator.of(sheet).pop();
              context.push('/event/${event.id}/seats');
            }),
            const SizedBox(height: 12),
            row(const Key('kindStanding'), t.standingTickets, standingFrom, () {
              Navigator.of(sheet).pop();
              _startRegister(context, ref, payable);
            }),
          ]),
        ),
      ),
    );
  }

  /// "15,000 – 45,000 MMK", one price, or "Free".
  static String _priceRange(L10n t, String lang, List<TicketType> types) {
    if (types.isEmpty) return '';
    final prices = types.map((x) => x.priceMmk).toList()..sort();
    final lo = prices.first, hi = prices.last;
    if (hi == 0) return t.free;
    if (lo == hi) return t.mmk(formatAmount(hi, lang));
    return '${lo == 0 ? t.free : formatAmount(lo, lang)} – ${t.mmk(formatAmount(hi, lang))}';
  }

  /// "By NAME" with only the name in bold (the name is the link to the organizer page).
  static List<InlineSpan> _byOrganizer(String template, String name, ThemeData theme, {required bool linked}) {
    final i = template.indexOf('\u0000');
    final nameSpan = TextSpan(text: name, style: TextStyle(fontWeight: FontWeight.w700, color: linked ? theme.colorScheme.primary : null));
    return [if (i > 0) TextSpan(text: template.substring(0, i)), nameSpan, if (i >= 0 && i + 1 < template.length) TextSpan(text: template.substring(i + 1))];
  }

  void _showPolicy(BuildContext context, String title, String body) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(body, style: theme.textTheme.bodyLarge),
          ]),
        ),
      ),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => _RegisterSheet(event: event, payable: payable),
    );
    if (orderId != null && context.mounted) await context.push('/checkout/$orderId');
  }
}

/// Join flow for a sold-out type: sign in first, then pick a quantity. Shared by the ticket row and the bottom bar.
Future<void> _joinWaitlist(BuildContext context, WidgetRef ref, EventSummary event, TicketType type) async {
  final me = await ref.read(sessionProvider.future);
  if (!context.mounted) return;
  if (me == null) {
    await context.push('/login?from=${Uri.encodeComponent('/event/${event.id}')}');
    return;
  }
  final joined = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _JoinWaitlistSheet(type: type),
  );
  if (joined == true) ref.invalidate(waitlistProvider);
}

/// Under a sold-out ticket type: "Join waitlist", then "You're #N in line · Leave" (or "Buy now" once an offer arrives).
/// With [stacked] (the ticket picker) the join button takes the full row, so a long label never wraps in a corner.
class _WaitlistRow extends ConsumerStatefulWidget {
  const _WaitlistRow({required this.event, required this.type, this.stacked = false, this.keyPrefix = ''});
  final EventSummary event;
  final TicketType type;
  final bool stacked;

  /// Keeps the keys apart when the same row shows on the page and in the ticket picker above it.
  final String keyPrefix;
  @override
  ConsumerState<_WaitlistRow> createState() => _WaitlistRowState();
}

class _WaitlistRowState extends ConsumerState<_WaitlistRow> {
  bool _busy = false;

  Future<void> _join() => _joinWaitlist(context, ref, widget.event, widget.type);

  Future<void> _leave() async {
    final t = L10n.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).leaveWaitlist(widget.type.id);
      ref.invalidate(waitlistProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.waitlistLeft), duration: const Duration(seconds: 2)));
    } on ApiException catch (e) {
      ref.invalidate(waitlistProvider); // e.g. already gone: show what the server says now
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(waitlistErrorText(L10n.of(context), e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final entry = activeEntryFor(ref.watch(waitlistProvider).value ?? const [], widget.type.id);
    final id = widget.type.id;
    // With large text the message and its button stack instead of sharing one row
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    Widget beside(Widget message, Widget action) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [message, const SizedBox(height: 8), action]);
    if (entry != null && large) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: entry.isOffered
            ? beside(
                Text(t.waitlistOfferedInline, key: Key('${widget.keyPrefix}waitlistOffered-$id'), style: theme.textTheme.titleSmall),
                FilledButton(
                  key: Key('${widget.keyPrefix}buyOffer-$id'),
                  style: E360Buttons.navy.copyWith(minimumSize: const WidgetStatePropertyAll(Size(64, 44))),
                  onPressed: () => openOffer(context, ref, entry),
                  child: Text(t.buyNow),
                ),
              )
            : beside(
                Text(t.waitlistPosition(entry.position ?? 1), key: Key('${widget.keyPrefix}waitlistPosition-$id'), style: theme.textTheme.titleSmall),
                TextButton(key: Key('${widget.keyPrefix}leaveWaitlist-$id'), onPressed: _busy ? null : _leave, child: Text(t.leaveWaitlist)),
              ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(children: [
        if (entry == null) ...[
          // The button takes what is left (and wraps its label) so a long Myanmar label cannot overflow the row
          Expanded(
            child: Align(
              alignment: widget.stacked ? Alignment.center : AlignmentDirectional.centerEnd,
              widthFactor: null,
              child: SizedBox(
                width: widget.stacked ? double.infinity : null,
                child: OutlinedButton(
                key: Key('${widget.keyPrefix}joinWaitlist-$id'),
                style: E360Buttons.outline,
                onPressed: _join,
                  child: Text(t.joinWaitlist, textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        ] else if (entry.isOffered) ...[
          Expanded(child: Text(t.waitlistOfferedInline, key: Key('${widget.keyPrefix}waitlistOffered-$id'), style: theme.textTheme.titleSmall)),
          // The offer is the thing to act on here, but the screen's one gold button is the bar's: navy
          FilledButton(
            key: Key('${widget.keyPrefix}buyOffer-$id'),
            style: E360Buttons.navy.copyWith(minimumSize: const WidgetStatePropertyAll(Size(64, 44))),
            onPressed: () => openOffer(context, ref, entry),
            child: Text(t.buyNow),
          ),
        ] else ...[
          Expanded(
            child: Text(
              t.waitlistPosition(entry.position ?? 1),
              key: Key('${widget.keyPrefix}waitlistPosition-$id'),
              style: theme.textTheme.titleSmall,
            ),
          ),
          TextButton(key: Key('${widget.keyPrefix}leaveWaitlist-$id'), onPressed: _busy ? null : _leave, child: Text(t.leaveWaitlist)),
        ],
      ]),
    );
  }
}

/// Quantity picker (1..maxPerOrder) for joining a sold-out type's line. Pops true once joined.
class _JoinWaitlistSheet extends ConsumerStatefulWidget {
  const _JoinWaitlistSheet({required this.type});
  final TicketType type;
  @override
  ConsumerState<_JoinWaitlistSheet> createState() => _JoinWaitlistSheetState();
}

class _JoinWaitlistSheetState extends ConsumerState<_JoinWaitlistSheet> {
  int _qty = 1;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).joinWaitlist(widget.type.id, _qty);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = waitlistErrorText(L10n.of(context), e));
      if (e.status == 409) ref.invalidate(waitlistProvider); // e.g. already in line, or tickets came back
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final max_ = widget.type.maxPerOrder;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.waitlistSheetTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(pickLang(lang, widget.type.name, widget.type.nameMy), style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(t.waitlistHint),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text('${t.quantity} · ${t.perPersonLimit(max_)}')),
          StepperButton(key: const Key('waitMinus'), icon: Icons.remove, semanticLabel: t.fewerTickets(pickLang(lang, widget.type.name, widget.type.nameMy)), onPressed: _qty > 1 ? () => setState(() => _qty--) : null),
          SizedBox(width: 36, child: Text('$_qty', key: const Key('waitQty'), textAlign: TextAlign.center, style: theme.textTheme.titleLarge)),
          StepperButton(key: const Key('waitPlus'), icon: Icons.add, semanticLabel: t.moreTickets(pickLang(lang, widget.type.name, widget.type.nameMy)), onPressed: _qty < max_ ? () => setState(() => _qty++) : null),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, key: const Key('waitError'), style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('waitSubmit'),
          style: E360Buttons.navy,
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(t.waitlistJoinAction),
        ),
      ]),
    );
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
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      );
}

/// White circle over the cover photo (back, calendar, share).
class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0x2E15172E), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: SizedBox.square(
          dimension: 44,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: tooltip,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: Icon(icon, size: 22, color: E360Colors.ink),
              onPressed: onPressed,
            ),
          ),
        ),
      );
}

/// Bordered white box: radius 14, 1 px line, no elevation.
class _CardBox extends StatelessWidget {
  const _CardBox({required this.child, this.selected, this.ringed = false});
  final Widget child;

  /// With [ringed] (the ticket picker) every card has a 2 px border and only its colour changes, so nothing shifts.
  final bool? selected;
  final bool ringed;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: ringed ? Border.all(color: selected == true ? scheme.primary : scheme.outlineVariant, width: 2) : Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// One "Good to know" card (200 wide, scrolls sideways with its neighbours).
class _GoodCard extends StatelessWidget {
  const _GoodCard({required this.title, required this.body, this.maxLines, this.onMore});
  final String title, body;
  final int? maxLines;
  final VoidCallback? onMore;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 200,
      child: Container(
        constraints: const BoxConstraints(minHeight: 104),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontSize: 15)),
          const SizedBox(height: 6),
          Text(body, maxLines: maxLines, overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: 14, height: 1.45)),
          if (onMore != null)
            TextButton(
              key: const Key('policyMore'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44), alignment: AlignmentDirectional.centerStart, tapTargetSize: MaterialTapTargetSize.shrinkWrap, textStyle: theme.textTheme.labelLarge),
              onPressed: onMore,
              child: Text(L10n.of(context).readMore),
            ),
        ]),
      ),
    );
  }
}

/// The description, cut at four lines with "Read more" when it is longer.
class _Overview extends StatefulWidget {
  const _Overview({required this.text});
  final String text;
  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge!;
    return LayoutBuilder(builder: (context, c) {
      final painter = TextPainter(text: TextSpan(text: widget.text, style: style), maxLines: 4, textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))
        ..layout(maxWidth: c.maxWidth);
      final cut = painter.didExceedMaxLines;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.text, maxLines: _open ? null : 4, overflow: _open ? TextOverflow.visible : TextOverflow.ellipsis, style: style),
        if (cut && !_open)
          TextButton(
            key: const Key('readMore'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44), alignment: AlignmentDirectional.centerStart, tapTargetSize: MaterialTapTargetSize.shrinkWrap, textStyle: theme.textTheme.labelLarge),
            onPressed: () => setState(() => _open = true),
            child: Text(t.readMore),
          ),
      ]);
    });
  }
}

/// Few enough left to say so in amber.
bool _scarce(TicketType tt) => tt.remaining <= 20 || (tt.quota > 0 && tt.remaining * 4 <= tt.quota);

class _RegisterSheet extends ConsumerStatefulWidget {
  const _RegisterSheet({required this.event, required this.payable});
  final EventSummary event;
  final bool payable;
  @override
  ConsumerState<_RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends ConsumerState<_RegisterSheet> {
  late final List<TicketType> _options = widget.event.ticketTypes.where((t) => !t.seated && !t.soldOut && (t.isFree || widget.payable)).toList();
  late TicketType _type = _options.first;
  // Same key for retries of this sheet: the API returns the same order instead of holding seats twice
  final String _idempotencyKey = List.generate(16, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  int _qty = 1;
  bool _busy = false;
  bool _promoOpen = false;
  final _promo = TextEditingController();
  PromoCheck? _promoResult; // applied code (for the current type and quantity)
  bool _checking = false;

  @override
  void dispose() {
    _promo.dispose();
    super.dispose();
  }

  void _resetPromo() => _promoResult = null;

  Future<void> _applyPromo() async {
    final code = _promo.text.trim();
    if (code.isEmpty) return;
    setState(() => _checking = true);
    try {
      final r = await ref.read(apiProvider).checkPromo(widget.event.id, code, {_type.id: _qty});
      if (mounted) setState(() => _promoResult = r);
    } on ApiException {
      if (mounted) setState(() => _promoResult = PromoCheck(valid: false, discountMmk: 0, totalMmk: _type.priceMmk * _qty));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }
  String? _error;
  bool _done = false;

  int get _max => [_type.maxPerOrder, _type.remaining].reduce((a, b) => a < b ? a : b);

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = _promoResult?.valid == true ? _promo.text.trim() : null;
      final o = await ref.read(apiProvider).createOrder(widget.event.id, {_type.id: _qty}, idempotencyKey: '$_idempotencyKey-${_type.id}-$_qty-${code ?? ''}', promoCode: code);
      ref.invalidate(eventProvider(widget.event.id));
      if (o.isPaid) {
        ref.invalidate(myTicketsProvider);
        setState(() => _done = true);
      } else {
        ref.invalidate(pendingOrdersProvider);
        if (mounted) Navigator.of(context).pop(o.id); // → checkout
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.reasonCode != null) {
          // The promo code was rejected at order time (e.g. used up meanwhile): it is no longer applied, and its
          // reason shows under the code in our own (Myanmar) text. Submitting again orders at full price.
          _promoResult = PromoCheck(valid: false, reasonCode: e.reasonCode, discountMmk: 0, totalMmk: _type.priceMmk * _qty);
        } else {
          _error = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _select(TicketType tt) => setState(() {
        _type = tt;
        _qty = 1;
        _resetPromo();
      });

  Widget _typeCard(TicketType tt, String lang, L10n t, ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final selected = tt.id == _type.id;
    final name = pickLang(lang, tt.name, tt.nameMy);
    final limit = t.perPersonLimit(tt.maxPerOrder);
    final scarce = _scarce(tt);
    final amber = dark ? E360DarkColors.amberInk : E360Colors.amberInk;
    final rise = priceRiseText(t, lang, tt.priceMmk, tt.nextPrice);
    final max = [tt.maxPerOrder, tt.remaining].reduce((a, b) => a < b ? a : b);
    return _CardBox(
      ringed: true,
      selected: selected,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: Text(name, style: theme.textTheme.titleMedium)),
            const SizedBox(width: 12),
            StepperButton(
              icon: Icons.remove,
              semanticLabel: t.fewerTickets(name),
              onPressed: selected && _qty > 1
                  ? () => setState(() {
                        _qty--;
                        _resetPromo();
                      })
                  : null,
            ),
            SizedBox(width: 32, child: Text(selected ? '$_qty' : '0', key: Key('qty-${tt.id}'), textAlign: TextAlign.center, style: theme.textTheme.titleLarge)),
            StepperButton(
              icon: Icons.add,
              semanticLabel: t.moreTickets(name),
              onPressed: !selected
                  ? (max > 0 ? () => _select(tt) : null)
                  : _qty < _max
                      ? () => setState(() {
                            _qty++;
                            _resetPromo();
                          })
                      : null,
            ),
          ]),
        ),
        Divider(color: theme.colorScheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tt.isFree ? t.free : t.mmk(formatAmount(tt.priceMmk, lang)), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              scarce ? '${t.remaining(tt.remaining)} · $limit' : limit,
              key: Key('scarcity-${tt.id}'),
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 14, color: scarce ? amber : null, fontWeight: scarce ? FontWeight.w600 : null),
            ),
            if (rise != null) Text(rise, key: Key('sheetRise-${tt.id}'), style: theme.textTheme.bodySmall?.copyWith(fontSize: 14)),
          ]),
        ),
      ]),
    );
  }

  /// Name and price beside the badge; with large text the badge drops to its own line instead of overflowing.
  Widget _soldOutHeader(Widget info, Widget badge) {
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(height: 8), badge]);
    }
    return Row(children: [Expanded(child: info), const SizedBox(width: 12), badge]);
  }

  Widget _soldOutCard(TicketType tt, String lang, L10n t, ThemeData theme) {
    final price = tt.isFree ? t.free : t.mmk(formatAmount(tt.priceMmk, lang));
    return _CardBox(
      ringed: true,
      selected: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: _soldOutHeader(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pickLang(lang, tt.name, tt.nameMy), style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(price, style: theme.textTheme.bodySmall?.copyWith(fontSize: 14)),
            ]),
            E360Badge(t.soldOut, kind: E360BadgeKind.dark),
          ),
        ),
        Divider(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 14),
        _WaitlistRow(event: widget.event, type: tt, stacked: true, keyPrefix: 'sheet-'),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final view = resolveDiscount(
      tiers: widget.event.groupDiscounts,
      paidQty: _type.isFree ? 0 : _qty,
      paidSubtotalMmk: _type.isFree ? 0 : _type.priceMmk * _qty,
      totalMmk: _type.priceMmk * _qty,
      promo: _promoResult,
    );
    final e = widget.event;
    final listed = e.ticketTypes.where((x) => !x.seated && (x.soldOut || x.isFree || widget.payable)).toList();
    final showPromo = _promoOpen || _promoResult != null || _promo.text.isNotEmpty;
    // With large text the pinned header and footer would leave the cards almost no room: the footer then scrolls
    // with the cards instead. At normal sizes it stays pinned.
    final scrollFooter = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final footer = Container(
      decoration: BoxDecoration(color: scheme.surface, border: Border(top: BorderSide(color: scheme.outlineVariant))),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_type.isFree) DiscountLines(view: view, lang: lang),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TotalRow(
              label: Text(t.ticketsTotal(_qty), style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
              original: !_type.isFree && view.discountMmk > 0 ? t.mmk(formatAmount(_type.priceMmk * _qty, lang)) : null,
              total: _type.isFree ? t.free : t.mmk(formatAmount(view.totalMmk, lang)),
              totalKey: const Key('sheetTotal'),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: scheme.error))),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('sheetSubmit'),
            style: E360Buttons.gold.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(54)), textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: E360Colors.goldInk))
                : Text(_type.isFree ? t.register : t.continueToPayment),
          ),
        ]),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _done
          ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle, size: 56, color: scheme.primary),
                const SizedBox(height: 12),
                Text(t.registered, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  style: E360Buttons.navy,
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.go('/tickets');
                  },
                  child: Text(t.viewTickets),
                ),
              ]),
            )
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(children: [
                        Text(pickLang(lang, e.title, e.titleMy), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                        Text('${formatDay(e.startsAt, lang)} · ${formatTime(e.startsAt, lang)}', textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(fontSize: 14)),
                      ]),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final tt in listed) ...[
                      tt.soldOut ? _soldOutCard(tt, lang, t, theme) : _typeCard(tt, lang, t, theme),
                      const SizedBox(height: 12),
                    ],
                    if (!_type.isFree) ...[
                      if (!showPromo)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            key: const Key('sheetAddPromo'),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            onPressed: () => setState(() => _promoOpen = true),
                            child: Text(t.addPromoCode, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary, decoration: TextDecoration.underline, decorationColor: scheme.primary)),
                          ),
                        )
                      else ...[
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: TextField(
                              key: const Key('promoField'),
                              controller: _promo,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(labelText: t.promoCode, isDense: true),
                              onChanged: (_) => setState(_resetPromo),
                              onSubmitted: (_) => _applyPromo(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(key: const Key('promoApply'), style: E360Buttons.outline, onPressed: _checking ? null : _applyPromo, child: Text(t.apply)),
                        ]),
                        if (_promoResult != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _promoResult!.valid
                                ? (_promoResult!.promoApplied
                                    ? Text(t.promoApplied(t.mmk(formatAmount(_promoResult!.discountMmk, lang))), style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600))
                                    : const SizedBox.shrink()) // lost to the group discount: DiscountLines says so
                                : Text(promoReasonText(t, _promoResult!.reasonCode), style: TextStyle(color: scheme.error)),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ],
                      ]),
                    ),
                    if (scrollFooter) footer,
                  ]),
                ),
              ),
              if (!scrollFooter) footer,
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
    final danger = theme.brightness == Brightness.dark ? E360DarkColors.danger : E360Colors.danger;
    final onDanger = theme.brightness == Brightness.dark ? E360DarkColors.paper : Colors.white;
    String dur(int? sec) => sec == null ? '' : '${sec ~/ 3600 > 0 ? '${sec ~/ 3600}:' : ''}${((sec % 3600) ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';
    void open(String kind, String id, String title) => context.push('/watch/$kind/$id?title=${Uri.encodeQueryComponent(title)}');
    Widget iconTile(IconData icon, Color color) => Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: theme.colorScheme.outlineVariant)),
          child: Icon(icon, size: 20, color: color),
        );
    // A Material (not a DecoratedBox) so the tile's ink shows
    Widget tileCard(Widget tile) => Material(
          color: theme.colorScheme.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: theme.colorScheme.outlineVariant)),
          child: tile,
        );
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.watch, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final l in s.live)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: tileCard(
              ListTile(
                key: Key('live-${l.channelId}'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: iconTile(Icons.live_tv, l.isLive ? danger : theme.colorScheme.primary),
                title: Text(pickLang(lang, l.title, l.titleMy), style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                subtitle: Text(l.isLive ? t.watchLive : t.startsAtTime(formatEventDate(l.startsAt, lang)), style: theme.textTheme.bodySmall),
                trailing: l.isLive
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: danger, borderRadius: BorderRadius.circular(6)),
                        child: Text(t.liveNow, style: TextStyle(color: onDanger, fontWeight: FontWeight.w700, fontSize: 12)),
                      )
                    : null,
                onTap: l.isLive ? () => open('live', l.channelId, pickLang(lang, l.title, l.titleMy)) : null,
              ),
            ),
          ),
        for (final r in s.recordings)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: tileCard(
              ListTile(
                key: Key('vod-${r.id}'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: iconTile(Icons.play_circle_outline, theme.colorScheme.primary),
                title: Text(pickLang(lang, r.title, r.titleMy), style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
                subtitle: Text([
                  t.recordingsTitle,
                  if (r.durationSec != null) dur(r.durationSec),
                  if (r.availableUntil != null) t.availableUntil(formatEventDate(r.availableUntil!, lang)),
                ].join(' · '), style: theme.textTheme.bodySmall),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open('vod', r.id, pickLang(lang, r.title, r.titleMy)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The page's scroll view with a slim pinned bar (back, title, share) that fades in once the cover has scrolled away.
class _ScrollWithBar extends StatefulWidget {
  const _ScrollWithBar({required this.slivers, required this.title, required this.onBack, required this.onShare});
  final List<Widget> slivers;
  final String title;
  final VoidCallback onBack, onShare;
  @override
  State<_ScrollWithBar> createState() => _ScrollWithBarState();
}

class _ScrollWithBarState extends State<_ScrollWithBar> {
  final _controller = ScrollController();
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final show = _controller.hasClients && _controller.offset > 200;
      if (show != _show) setState(() => _show = show);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final theme = Theme.of(context);
    return Stack(children: [
      CustomScrollView(controller: _controller, slivers: widget.slivers),
      if (_show)
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Material(
            key: const Key('pinnedBar'),
            color: theme.colorScheme.surface,
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant))),
              child: Padding(
                padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, left: 8, right: 8),
                child: SizedBox(
                  height: 56,
                  child: Row(children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                      icon: const Icon(Icons.arrow_back),
                      onPressed: widget.onBack,
                    ),
                    Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium)),
                    IconButton(
                      tooltip: t.share,
                      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                      icon: const Icon(Icons.ios_share),
                      onPressed: widget.onShare,
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
