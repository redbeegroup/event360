import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_brightness/screen_brightness.dart';

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

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final tickets = ref.watch(myTicketsProvider);
    final MyTicket? ticket = tickets.value?.where((x) => x.id == widget.ticketId).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(t.myTickets)),
      body: ticket == null
          ? (tickets.isLoading ? const Center(child: CircularProgressIndicator()) : MessageView(icon: Icons.confirmation_number_outlined, message: t.noTickets))
          : ListView(padding: const EdgeInsets.all(20), children: [
              Text(pickLang(lang, ticket.eventTitle, ticket.eventTitleMy),
                  textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(formatEventDate(ticket.startsAt, lang), textAlign: TextAlign.center),
              if (ticket.venueName != null) Text('${ticket.venueName}, ${ticket.venueCity ?? ''}', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (ticket.qr != null && ticket.status == 'VALID') ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: QrImageView(
                      data: ticket.qr!,
                      size: 260,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      semanticsLabel: 'Ticket QR code',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(t.showAtEntrance, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.offline_pin, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(t.offlineReady, style: theme.textTheme.bodySmall),
                ]),
              ] else
                MessageView(icon: Icons.block, message: t.ticketCancelled),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  title: Text(pickLang(lang, ticket.ticketTypeName, ticket.ticketTypeNameMy)),
                  subtitle: Text(ticket.organizer),
                  trailing: Pill('#${ticket.id.substring(0, 8).toUpperCase()}'),
                ),
              ),
            ]),
    );
  }
}
