import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../app/errors.dart';
import '../../l10n/app_localizations.dart';
import 'common.dart';

// ───────────── Promo codes ─────────────

class PromosTab extends ConsumerStatefulWidget {
  const PromosTab({super.key, required this.k, required this.canEdit});
  final EventKey k;
  final bool canEdit;
  @override
  ConsumerState<PromosTab> createState() => _PromosState();
}

class _PromosState extends ConsumerState<PromosTab> {
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _max = TextEditingController();
  String _kind = 'PERCENT';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _value, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final value = int.tryParse(_value.text.trim());
    if (_code.text.trim().length < 3 || value == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).createPromoCode(widget.k.orgId, widget.k.eventId, code: _code.text.trim(), kind: _kind, value: value, maxUses: int.tryParse(_max.text.trim()));
      for (final c in [_code, _value, _max]) {
        c.clear();
      }
      ref.invalidate(promoCodesProvider(widget.k));
    } on ApiException catch (e) {
      // The one refusal the server gives here is a code that already exists
      if (mounted) setState(() => _error = e.status == 409 ? L10n.of(context).promoCodeExists : errorText(L10n.of(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final promos = ref.watch(promoCodesProvider(widget.k));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t.promosHint),
      const SizedBox(height: 12),
      if (widget.canEdit) ...[
        TextField(key: const Key('promoCode'), controller: _code, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: t.promoCode)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _kind,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: 'PERCENT', child: Text(t.percent, overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: 'FIXED', child: Text(t.fixed, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? 'PERCENT'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: TextField(key: const Key('promoValue'), controller: _value, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t.amount))),
        ]),
        const SizedBox(height: 8),
        TextField(controller: _max, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t.maxUses)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        const SizedBox(height: 12),
        FilledButton.icon(key: const Key('createPromo'), style: E360Buttons.gold, onPressed: _busy ? null : _create, icon: const Icon(Icons.sell_outlined), label: Text(t.createPromo)),
      ] else
        readOnly(context, t),
      const SizedBox(height: 12),
      promos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => loadError(t, () => ref.invalidate(promoCodesProvider(widget.k)), e),
        data: (list) => list.isEmpty
            ? Text(t.noPromos, style: theme.textTheme.bodySmall)
            : Column(children: [
                for (final p in list)
                  ListTile(
                    key: Key('promo-${p.code}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text('${p.code} · ${p.kind == 'PERCENT' ? '${p.value}%' : formatMmk(p.value, lang)}${p.isActive ? '' : ' · ${t.off}'}',
                        style: TextStyle(fontWeight: FontWeight.w600, color: p.isActive ? null : theme.disabledColor)),
                    subtitle: Text('${t.used(p.maxUses == null ? '${p.used}' : '${p.used} / ${p.maxUses}')} · ${t.discounts}: ${formatMmk(p.discountGivenMmk, lang)}'),
                    trailing: widget.canEdit
                        ? TextButton(
                            onPressed: () async {
                              await ref.read(apiProvider).setPromoActive(widget.k.orgId, widget.k.eventId, p.id, !p.isActive).catchError((_) {});
                              ref.invalidate(promoCodesProvider(widget.k));
                            },
                            child: Text(p.isActive ? t.turnOff : t.turnOn),
                          )
                        : null,
                  ),
              ]),
      ),
    ]);
  }
}
