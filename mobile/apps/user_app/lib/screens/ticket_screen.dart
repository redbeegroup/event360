import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  Future<void> _transfer(MyTicket ticket) async {
    final t = L10n.of(context);
    final sentTo = await showDialog<String>(context: context, builder: (_) => _TransferDialog(ticketId: ticket.id));
    if (sentTo == null || !mounted) return;
    await ref.read(myTicketsProvider.notifier).refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.transferDone(sentTo))));
    context.go('/tickets');
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
                MessageView(icon: Icons.block, message: ticket.status == 'REFUNDED' ? t.ticketRefunded : t.ticketCancelled),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  title: Text(pickLang(lang, ticket.ticketTypeName, ticket.ticketTypeNameMy)),
                  subtitle: Text(ticket.organizer),
                  trailing: Pill('#${ticket.id.substring(0, 8).toUpperCase()}'),
                ),
              ),
              if (ticket.canTransfer)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    key: const Key('transfer'),
                    onPressed: () => _transfer(ticket),
                    icon: const Icon(Icons.send_outlined),
                    label: Text(t.transferTicket),
                  ),
                ),
            ]),
    );
  }
}

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
