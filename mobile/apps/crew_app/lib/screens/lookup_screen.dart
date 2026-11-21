import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/checkin_controller.dart';
import '../app/format.dart';
import '../app/providers.dart';
import '../l10n/app_localizations.dart';
import '../widgets/result_card.dart';
import '../widgets/undo.dart';
import '../widgets/lang_button.dart';

/// Find a guest by name, phone digits or ticket code when their QR can't be scanned.
class LookupScreen extends ConsumerStatefulWidget {
  const LookupScreen({super.key});
  @override
  ConsumerState<LookupScreen> createState() => _LookupScreenState();
}

class _LookupScreenState extends ConsumerState<LookupScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<CrewTicket>? _results;
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String v) async {
    if (v.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await ref.read(checkinProvider.notifier).search(v);
      if (mounted) setState(() => _results = r);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkIn(CrewTicket tk) async {
    final t = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.confirmCheckIn(tk.holderName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          FilledButton(style: compactFilled, onPressed: () => Navigator.pop(c, true), child: Text(t.checkIn)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final out = await ref.read(checkinProvider.notifier).checkIn(tk);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: Colors.transparent,
        child: ResultCard(outcome: out, lang: ref.read(langProvider), onClose: () => Navigator.pop(c)),
      ),
    );
    await _search(_q.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final local = ref.watch(checkinProvider.select((s) => s.localChecked));
    return Scaffold(
      appBar: AppBar(title: Text(t.lookup)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            key: const Key('lookupInput'),
            controller: _q,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: _search,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t.searchHint),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _results == null
              ? const SizedBox.shrink()
              : _results!.isEmpty
                  ? Center(child: Text(t.noResults))
                  : ListView.separated(
                      itemCount: _results!.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final tk = _results![i];
                        final inside = tk.isCheckedIn || local.containsKey(tk.id);
                        final ci = tk.checkedIn;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: inside ? const Color(0xFFE8F5E9) : null,
                            child: Icon(inside ? Icons.check : Icons.confirmation_number_outlined, color: inside ? const Color(0xFF1B873F) : null),
                          ),
                          title: Text(tk.holderName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text([
                            if (tk.seat != null && tk.seat!.isNotEmpty) pickLang(lang, tk.seat, tk.seatMy),
                            pickLang(lang, tk.ticketTypeName, tk.ticketTypeNameMy),
                            '#${tk.code}',
                            if (tk.phoneLast4 != null && !tk.holderName.contains(tk.phoneLast4!)) '••${tk.phoneLast4}',
                            if (inside && ci != null) t.checkedInAt(formatTime(ci.at, lang)),
                          ].join(' · ')),
                          trailing: switch (tk.status) {
                            'VALID' when !inside => FilledButton(style: compactFilled, onPressed: () => _checkIn(tk), child: Text(t.checkIn)),
                            'CHECKED_IN' => TextButton(onPressed: () => confirmUndo(context, ref, tk.id, tk.holderName).then((_) => _search(_q.text)), child: Text(t.undo)),
                            'VALID' => Text(t.offlineChecked, style: const TextStyle(fontSize: 12)),
                            _ => Text(resultStyle(t, ScanOutcome(result: tk.status)).title, style: const TextStyle(fontSize: 12)),
                          },
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
