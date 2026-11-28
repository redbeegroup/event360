import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';

/// Full-screen QR for the entrance. Works offline from the cached ticket list; boosts brightness for scanners.
class TicketScreen extends ConsumerStatefulWidget {
  const TicketScreen({super.key, required this.ticketId});
  final String ticketId;
  @override
  ConsumerState<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends ConsumerState<TicketScreen> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) ScreenBrightness.instance.setApplicationScreenBrightness(1.0).catchError((_) {});
  }

  @override
  void dispose() {
    if (!kIsWeb) ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    super.dispose();
  }

  Future<void> _transfer(MyTicket ticket) async {
    final t = L10n.of(context);
    final sentTo = await showDialog<String>(context: context, builder: (_) => _TransferDialog(ticketId: ticket.id));
    if (sentTo == null || !mounted) return;
    await ref.read(myTicketsProvider.notifier).refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.transferDone(sentTo))));
    context.go('/tickets');
  }

  Future<void> _cancel(MyTicket ticket) async {
    final t = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.cancelTicketTitle),
        content: Text(t.cancelTicketBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(t.keepTicket)),
          FilledButton(key: const Key('cancelTicketConfirm'), onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(t.cancelTicket)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(apiProvider).cancelTicket(ticket.id);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    ref.invalidate(eventProvider(ticket.eventId));
    await ref.read(myTicketsProvider.notifier).refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.ticketCancelledDone)));
    context.go('/tickets');
  }

  /// Opens a link; says so when nothing could open it.
  Future<void> _open(Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = L10n.of(context).openFailed;
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Uri _directionsUri(MyTicket x) => ticketDirectionsUri(x.venueName, x.venueCity);

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final tickets = ref.watch(myTicketsProvider);
    final MyTicket? ticket = tickets.value
        ?.where((x) => x.id == widget.ticketId)
        .firstOrNull;
    const onNavy = Colors.white;

    // Outline pill for the navy page: white text and a 60% white border (the mockup's secondary buttons)
    final ghost = E360Buttons.outline.copyWith(
      minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
      foregroundColor: const WidgetStatePropertyAll(onNavy),
      side: WidgetStateProperty.all(
        const BorderSide(color: Color(0x99FFFFFF), width: 1.5),
      ),
    );

    Widget bar() => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            icon: const Icon(Icons.arrow_back, color: onNavy),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/tickets'),
          ),
          Expanded(
            child: Text(
              t.myTickets,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(color: onNavy),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );

    Widget content(MyTicket x) {
      final seat = x.seatText(lang);
      final valid = x.qr != null && x.status == 'VALID';
      void openCalendar() =>
          _open(ref.read(apiProvider).calendarUri(x.eventId));
      final hasVenue = x.venueName != null && x.venueName!.isNotEmpty;
      final venue = hasVenue
          ? [
              x.venueName!,
              if (x.venueCity != null && x.venueCity!.isNotEmpty) x.venueCity!,
            ].join(', ')
          : null;
      Widget cell(String label, String value, {Key? key}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
            Text(
              value,
              key: key,
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
            ),
          ],
        ),
      );
      final typeName = pickLang(lang, x.ticketTypeName, x.ticketTypeNameMy);
      final isMy = Localizations.localeOf(context).languageCode == 'my';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('ticketCard'),
            decoration: BoxDecoration(
              color: E360Colors.card,
              borderRadius: BorderRadius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        [
                          typeName,
                          if (seat != null) t.reservedSeating,
                        ].join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: E360Colors.amberInk,
                          letterSpacing: isMy ? 0 : 0.96,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        pickLang(lang, x.eventTitle, x.eventTitleMy),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: isMy ? 20 : 24,
                          color: E360Colors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        x.organizer,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: E360Colors.muted,
                        ),
                      ),
                      if (x.isComplimentary) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: E360Badge(
                            key: const Key('ticketComp'),
                            x.compLabel == null || x.compLabel!.isEmpty
                                ? t.complimentary
                                : t.complimentaryLabel(x.compLabel!),
                            kind: E360BadgeKind.success,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      // Myanmar dates are long: the date gets a full row there, so it never breaks mid-word
                      if (isMy) ...[
                        Row(
                          children: [
                            cell(t.ticketDate, formatDay(x.startsAt, lang)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            cell(t.ticketTime, formatTime(x.startsAt, lang)),
                            const SizedBox(width: 16),
                            if (seat != null)
                              cell(t.ticketKind, typeName)
                            else
                              const Expanded(child: SizedBox.shrink()),
                          ],
                        ),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            cell(t.ticketDate, formatDay(x.startsAt, lang)),
                            const SizedBox(width: 16),
                            cell(t.ticketTime, formatTime(x.startsAt, lang)),
                          ],
                        ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cell(t.venue, venue ?? '-'),
                          const SizedBox(width: 16),
                          if (seat != null)
                            cell(
                              t.ticketSeatLabel,
                              seat,
                              key: const Key('ticketSeat'),
                            )
                          else if (!isMy)
                            cell(t.ticketKind, typeName)
                          else
                            const Expanded(child: SizedBox.shrink()),
                        ],
                      ),
                    ],
                  ),
                ),
                // Tear line: two notches in the page colour and a dashed rule
                SizedBox(
                  height: 24,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Positioned(left: -12, top: 0, child: _Notch()),
                      const Positioned(right: -12, top: 0, child: _Notch()),
                      Positioned(
                        left: 22,
                        right: 22,
                        top: 11,
                        child: CustomPaint(
                          painter: _DashPainter(E360Colors.line),
                          size: const Size(double.infinity, 2),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
                  child: valid
                      ? Column(
                          children: [
                            QrImageView(
                              data: x.qr!,
                              size: 220,
                              padding: EdgeInsets.zero,
                              errorCorrectionLevel: QrErrorCorrectLevel.M,
                              semanticsLabel: 'Ticket QR code',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              t.showAtEntrance,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: E360Colors.muted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.offline_pin,
                                  size: 16,
                                  color: E360Colors.success,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    t.offlineReady,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: E360Colors.success,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            E360Badge('#${x.id.substring(0, 8).toUpperCase()}'),
                          ],
                        )
                      : x.isCheckedIn
                      ? Column(
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              size: 48,
                              color: E360Colors.success,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              x.checkedInAt == null
                                  ? t.checkedIn
                                  : t.checkedInAt(formatTime(x.checkedInAt!, lang)),
                              key: const Key('ticketCheckedIn'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: E360Colors.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              t.ticketUsed,
                              key: const Key('ticketUsed'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: E360Colors.muted,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            const Icon(
                              Icons.block,
                              size: 48,
                              color: E360Colors.muted,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              x.status == 'REFUNDED'
                                  ? t.ticketRefunded
                                  : t.ticketCancelled,
                              key: const Key('ticketVoid'),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: E360Colors.ink,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // One gold button: Directions, or the calendar when the ticket has no venue
          if (valid)
            Builder(
              builder: (context) {
                final calendar = hasVenue
                    ? OutlinedButton(
                        key: const Key('addToCalendar'),
                        style: ghost,
                        onPressed: openCalendar,
                        child: Text(
                          t.addToCalendar,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : FilledButton(
                        key: const Key('addToCalendar'),
                        style: E360Buttons.gold,
                        onPressed: openCalendar,
                        child: Text(
                          t.addToCalendar,
                          textAlign: TextAlign.center,
                        ),
                      );
                if (!hasVenue) return calendar;
                final directions = FilledButton(
                  key: const Key('ticketDirections'),
                  style: E360Buttons.gold.copyWith(
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                  onPressed: () => _open(_directionsUri(x)),
                  child: Text(t.getDirections, textAlign: TextAlign.center),
                );
                // Myanmar labels are long: below 380 dp the buttons stack full-width, so no pill wraps
                if (isMy && MediaQuery.sizeOf(context).width < 380) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      directions,
                      const SizedBox(height: 12),
                      calendar,
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: calendar),
                      const SizedBox(width: 12),
                      Expanded(child: directions),
                    ],
                  ),
                );
              },
            ),
          if ((x.status == 'VALID' || x.isCheckedIn) &&
              guideLinkVisible(endsAt: x.endsAt, now: ref.watch(nowProvider)()))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton.icon(
                key: const Key('ticketGuideLink'),
                style: TextButton.styleFrom(
                  foregroundColor: onNavy,
                  minimumSize: const Size(44, 48),
                ),
                onPressed: () => context.push('/event/${x.eventId}/guide'),
                icon: const Icon(Icons.menu_book_outlined),
                label: Text(t.eventGuide),
              ),
            ),
          if (x.canTransfer)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                key: const Key('transfer'),
                style: ghost,
                onPressed: () => _transfer(x),
                icon: const Icon(Icons.send_outlined),
                label: Text(t.transferTicket),
              ),
            ),
          if (x.canCancel)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton.icon(
                key: const Key('cancelTicket'),
                style: TextButton.styleFrom(
                  foregroundColor: E360DarkColors.danger,
                  minimumSize: const Size(44, 48),
                ),
                onPressed: () => _cancel(x),
                icon: const Icon(Icons.cancel_outlined),
                label: Text(t.cancelTicket),
              ),
            ),
        ],
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: E360Colors.night,
        body: SafeArea(
          child: Column(
            children: [
              bar(),
              Expanded(
                child: ticket == null
                    ? (tickets.isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : Theme(
                              data: theme.copyWith(
                                textTheme: theme.textTheme.apply(
                                  bodyColor: onNavy,
                                ),
                                colorScheme: theme.colorScheme.copyWith(
                                  outline: onNavy,
                                ),
                              ),
                              child: MessageView(
                                icon: Icons.confirmation_number_outlined,
                                message: t.noTickets,
                              ),
                            ))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        children: [content(ticket)],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notch extends StatelessWidget {
  const _Notch();
  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: const BoxDecoration(
      color: E360Colors.night,
      shape: BoxShape.circle,
    ),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (double x = 0; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, 1), Offset((x + 6).clamp(0, size.width), 1), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// Maps search link for the venue ("name, city").
Uri ticketDirectionsUri(String? venueName, String? venueCity) => Uri.parse(
  'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent([venueName, venueCity].whereType<String>().where((p) => p.isNotEmpty).join(', '))}',
);

/// Asks for the recipient's number and sends the ticket; pops with the masked number on success.
class _TransferDialog extends ConsumerStatefulWidget {
  const _TransferDialog({required this.ticketId});
  final String ticketId;
  @override
  ConsumerState<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<_TransferDialog> {
  final _phone = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final to = await ref.read(apiProvider).transferTicket(widget.ticketId, _phone.text.trim());
      if (mounted) Navigator.of(context).pop(to);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return AlertDialog(
      title: Text(t.transferTicket),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.transferHint),
          const SizedBox(height: 12),
          TextField(
            key: const Key('transferPhone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: t.phoneNumber, hintText: '09xxxxxxxxx', errorText: _error),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(t.cancel)),
        FilledButton(key: const Key('transferConfirm'), onPressed: _busy ? null : _send, child: Text(t.send)),
      ],
    );
  }
}
