import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/lang_button.dart' show compactFilled;
import 'common.dart';

// ───────────── Door (crew codes) ─────────────

class DoorTab extends ConsumerStatefulWidget {
  const DoorTab({super.key, required this.k, required this.canEdit});
  final EventKey k;
  final bool canEdit;
  @override
  ConsumerState<DoorTab> createState() => _DoorState();
}

class _DoorState extends ConsumerState<DoorTab> {
  final _label = TextEditingController();
  final _gate = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _gate.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_label.text.trim().length < 2) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await ref.read(apiProvider).createCrewCode(widget.k.orgId, widget.k.eventId, _label.text.trim(), gate: _gate.text.trim());
      ref.invalidate(crewCodesProvider(widget.k));
      _label.clear();
      _gate.clear();
      if (mounted) await showDialog<void>(context: context, builder: (_) => _CodeDialog(code: c));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(CrewCode c) async {
    final t = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t.revokeConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
          FilledButton(style: compactFilled, onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.revoke)),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(apiProvider).revokeCrewCode(widget.k.orgId, widget.k.eventId, c.id).catchError((_) {});
    ref.invalidate(crewCodesProvider(widget.k));
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final codes = ref.watch(crewCodesProvider(widget.k));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t.doorHint),
      const SizedBox(height: 12),
      if (widget.canEdit) ...[
        TextField(key: const Key('codeLabel'), controller: _label, decoration: InputDecoration(labelText: t.codeLabel)),
        const SizedBox(height: 8),
        TextField(key: const Key('codeGate'), controller: _gate, decoration: InputDecoration(labelText: t.gate)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 12),
        FilledButton.icon(key: const Key('createCode'), style: E360Buttons.gold, onPressed: _busy ? null : _create, icon: const Icon(Icons.qr_code_2), label: Text(t.createCode)),
      ] else
        readOnly(context, t),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        style: E360Buttons.outline,
        onPressed: () => launchUrl(Uri.parse(crewWebUrl), mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.open_in_new),
        label: Text(t.openCrewApp),
      ),
      const SizedBox(height: 12),
      codes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => loadError(t, () => ref.invalidate(crewCodesProvider(widget.k))),
        data: (list) => Column(children: [
          for (final c in list)
            ListTile(
              key: Key('code-${c.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(c.active ? Icons.badge_outlined : Icons.block, color: c.active ? theme.colorScheme.primary : theme.disabledColor),
              title: Text([c.label, if (c.gate != null) c.gate!].join(' · ')),
              subtitle: Text(
                c.revokedAt != null
                    ? t.revoked
                    : !c.active
                        ? t.expired
                        : '${t.devices(c.devices)} · ${formatDayTime(c.expiresAt, lang)}',
              ),
              trailing: c.active && widget.canEdit ? TextButton(onPressed: () => _revoke(c), child: Text(t.revoke)) : null,
            ),
        ]),
      ),
    ]);
  }
}

class _CodeDialog extends StatelessWidget {
  const _CodeDialog({required this.code});
  final CrewCode code;
  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    // The Crew app reads the code from any link with ?code=…; the web link also works on phones without the app.
    final link = '$crewWebUrl#/redeem?code=${code.code}';
    return AlertDialog(
      title: Text(t.codeCreated),
      content: SizedBox(
        width: 260,
        // Large text: the dialog content scrolls instead of overflowing
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(color: Colors.white, padding: const EdgeInsets.all(10), child: SizedBox.square(dimension: 200, child: QrImageView(data: link, size: 200))),
            const SizedBox(height: 12),
            SelectableText(code.code ?? '', key: const Key('newCode'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text(t.codeOnce, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
      actions: [
        IconButton(onPressed: () => Clipboard.setData(ClipboardData(text: code.code ?? '')), icon: const Icon(Icons.copy)),
        FilledButton(style: compactFilled, onPressed: () => Navigator.of(context).pop(), child: Text(t.done)),
      ],
    );
  }
}
