import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/lang_button.dart' show compactFilled;
import 'common.dart';

// ───────────── Announcements ─────────────

class AnnounceTab extends ConsumerStatefulWidget {
  const AnnounceTab({super.key, required this.k, required this.canEdit});
  final EventKey k;
  final bool canEdit;
  @override
  ConsumerState<AnnounceTab> createState() => _AnnounceState();
}

class _AnnounceState extends ConsumerState<AnnounceTab> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _titleMy = TextEditingController();
  final _bodyMy = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _body, _titleMy, _bodyMy]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final t = L10n.of(context);
    if (_title.text.trim().length < 3 || _body.text.trim().length < 3) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t.sendConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
          FilledButton(key: const Key('confirmSend'), style: compactFilled, onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.send)),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).sendAnnouncement(widget.k.orgId, widget.k.eventId, title: _title.text.trim(), body: _body.text.trim(), titleMy: _titleMy.text.trim(), bodyMy: _bodyMy.text.trim());
      for (final c in [_title, _body, _titleMy, _bodyMy]) {
        c.clear();
      }
      ref.invalidate(announcementsProvider(widget.k));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.sent)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final ann = ref.watch(announcementsProvider(widget.k));
    return ann.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => loadError(t, () => ref.invalidate(announcementsProvider(widget.k))),
      data: (a) => ListView(padding: const EdgeInsets.all(16), children: [
        Text(t.announceHint),
        const SizedBox(height: 6),
        Text('${t.recipients(a.ticketHolders)} · ${t.leftToday(a.remainingToday)}', key: const Key('announceCounts'), style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (!widget.canEdit)
          readOnly(context, t)
        else if (a.remainingToday > 0 && a.ticketHolders > 0) ...[
          TextField(key: const Key('annTitle'), controller: _title, maxLength: 80, decoration: InputDecoration(labelText: t.heading)),
          TextField(key: const Key('annBody'), controller: _body, maxLength: 500, maxLines: 4, minLines: 2, decoration: InputDecoration(labelText: t.message)),
          TextField(controller: _titleMy, maxLength: 80, decoration: InputDecoration(labelText: t.headingMy)),
          TextField(controller: _bodyMy, maxLength: 500, maxLines: 4, minLines: 2, decoration: InputDecoration(labelText: t.messageMy)),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          FilledButton.icon(key: const Key('sendAnnouncement'), style: E360Buttons.gold, onPressed: _busy ? null : _send, icon: const Icon(Icons.campaign_outlined), label: Text(t.send)),
        ],
        const SizedBox(height: 16),
        if (a.items.isEmpty) Text(t.noAnnouncements, style: theme.textTheme.bodySmall),
        for (final i in a.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(pickLang(lang, i.title, i.titleMy)),
            subtitle: Text('${pickLang(lang, i.body, i.bodyMy)}\n${formatDayTime(i.createdAt, lang)} · ${t.recipients(i.recipients)}'),
            isThreeLine: true,
          ),
      ]),
    );
  }
}
