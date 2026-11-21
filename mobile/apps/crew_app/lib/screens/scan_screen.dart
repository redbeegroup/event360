import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/checkin_controller.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/qr_scanner_view.dart';
import '../widgets/result_card.dart';
import '../widgets/undo.dart';
import '../widgets/lang_button.dart';

/// The door: camera + big result card, attendance counter, offline banner, and a text box for handheld scanners.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _handle(String raw) async {
    final ctrl = ref.read(checkinProvider.notifier);
    try {
      final out = await ctrl.scan(raw);
      if (out == null || !mounted) return;
      out.accepted ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
      _hide?.cancel();
      // Accepted results clear themselves so the next guest can step up; problems stay until tapped.
      if (out.accepted) _hide = Timer(const Duration(seconds: 4), () => mounted ? ctrl.dismissResult() : null);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L10n.of(context).sessionEnded)));
        await ref.read(sessionProvider.notifier).signOut();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final session = ref.watch(sessionProvider);
    final st = ref.watch(checkinProvider);
    final event = session?.event;
    if (event == null) return const SizedBox.shrink();
    final last = st.last;
    final total = st.registered;
    final pct = total == 0 ? 0.0 : (st.checkedIn / total).clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final success = dark ? E360DarkColors.success : E360Colors.success;
    final warnInk = dark ? E360DarkColors.amberInk : E360Colors.amberInk;
    final warnBg = dark ? E360DarkColors.amberBg : E360Colors.amberBg;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pickLang(lang, event.title, event.titleMy), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text([if (session!.gate.isNotEmpty) session.gate, session.deviceName].join(' · '), style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          IconButton(tooltip: t.lookup, icon: const Icon(Icons.person_search), onPressed: () => context.push('/lookup')),
          IconButton(tooltip: t.activity, icon: const Icon(Icons.history), onPressed: () => context.push('/activity')),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'lang') await ref.read(langProvider.notifier).toggle();
              if (v == 'switch') await ref.read(sessionProvider.notifier).changeEventOrGate();
              if (v == 'out') await ref.read(sessionProvider.notifier).signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'lang', child: Text(t.language)),
              PopupMenuItem(value: 'switch', child: Text(t.switchEvent)),
              PopupMenuItem(value: 'out', child: Text(t.signOut)),
            ],
          ),
        ],
      ),
      body: Column(children: [
        // Attendance
        DecoratedBox(
          decoration: BoxDecoration(color: scheme.surface, border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(children: [
              Row(children: [
                Icon(Icons.groups, size: 22, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(t.attendance(st.checkedIn, total), key: const Key('attendance'), style: theme.textTheme.titleMedium)),
                if (st.pending.isNotEmpty) Flexible(child: Text(t.pendingSync(st.pending.length), key: const Key('pendingCount'), textAlign: TextAlign.end, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: pct, minHeight: 8, borderRadius: BorderRadius.circular(8), color: success, backgroundColor: scheme.surfaceContainerHighest),
            ]),
          ),
        ),
        if (!st.online)
          MaterialBanner(
            backgroundColor: warnBg,
            dividerColor: Colors.transparent,
            leading: Icon(Icons.cloud_off, color: warnInk),
            content: Text(t.offlineBanner(st.pending.length), style: TextStyle(color: warnInk, fontWeight: FontWeight.w600)),
            actions: [TextButton(onPressed: () => ref.read(checkinProvider.notifier).refresh(), child: Text(t.retry))],
          ),
        if (st.conflicts.isNotEmpty)
          MaterialBanner(
            backgroundColor: warnBg,
            dividerColor: Colors.transparent,
            leading: Icon(Icons.warning_amber_rounded, color: warnInk),
            content: Text('${t.syncConflict}: ${st.conflicts.map((c) => c.ticket?.holderName ?? '?').join(', ')}', style: TextStyle(color: warnInk)),
            actions: [TextButton(onPressed: () => ref.read(checkinProvider.notifier).clearConflicts(), child: Text(t.ok))],
          ),
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            QrScannerView(onCode: _handle, paused: st.busy),
            if (st.busy) const Center(child: CircularProgressIndicator()),
            if (last == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(22)),
                    child: Text(t.pointCamera, style: const TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            if (last != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: ResultCard(
                  key: const Key('result'),
                  outcome: last,
                  lang: lang,
                  onClose: () => ref.read(checkinProvider.notifier).dismissResult(),
                  onUndo: last.accepted && !last.offline && last.ticket != null
                      ? () => confirmUndo(context, ref, last.ticket!.id, last.ticket!.holderName)
                      : null,
                ),
              ),
          ]),
        ),
        // Typed codes and handheld (keyboard-wedge) scanners
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('manualInput'),
                  controller: _input,
                  focusNode: _focus,
                  decoration: InputDecoration(isDense: true, hintText: t.typeOrScan, prefixIcon: const Icon(Icons.keyboard)),
                  onSubmitted: (v) {
                    _input.clear();
                    _handle(v);
                    _focus.requestFocus();
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: compactFilled,
                onPressed: () {
                  final v = _input.text;
                  _input.clear();
                  _handle(v);
                },
                child: Text(t.submit),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
