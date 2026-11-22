import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/format.dart';
import '../../app/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/lang_button.dart' show compactFilled;
import 'common.dart';

/// The gate label every check-in made from this app carries.
const organizerGate = 'Organizer app';

/// Check-in and undo are offered only while the crew app would list the event: PUBLISHED or ONGOING,
/// from one day before the start to twelve hours after the end.
bool checkInOpen(OrgEvent e, DateTime now) =>
    (e.status == 'PUBLISHED' || e.status == 'ONGOING') &&
    !now.isBefore(e.startsAt.subtract(const Duration(hours: 24))) &&
    !now.isAfter(e.endsAt.add(const Duration(hours: 12)));

/// The number as dialled: no spaces, dashes or brackets (a leading + stays).
String telNumber(String phone) => phone.replaceAll(RegExp(r'[^0-9+]'), '');

String attendeeStatusLabel(L10n t, Attendee a) => a.isIn
    ? t.statusIn
    : a.isValid
        ? t.statusNotIn
        : t.statusCancelled;

/// An attendee with its search text worked out once, so typing in the search box stays quick with thousands of rows.
class _Row {
  _Row(this.a)
      : text = [a.displayName, a.guestName, a.seatLabel, a.seatLabelMy].whereType<String>().join('\n').toLowerCase(),
        digits = (a.phone ?? '').replaceAll(RegExp(r'\D'), ''),
        nameKey = a.displayName.toLowerCase(),
        group = a.isValid ? 0 : (a.isIn ? 1 : 2);
  final Attendee a;
  final String text, digits, nameKey;
  final int group;

  bool matches(String q, String qDigits) => text.contains(q) || (qDigits.isNotEmpty && digits.contains(qDigits));
}

/// Not in first, then checked in, then cancelled; by name within each group.
List<_Row> _sorted(List<Attendee> list) => [for (final a in list) _Row(a)]
  ..sort((x, y) {
    final g = x.group.compareTo(y.group);
    if (g != 0) return g;
    final n = x.nameKey.compareTo(y.nameKey);
    if (n != 0) return n;
    final c = x.a.createdAt.compareTo(y.a.createdAt);
    return c != 0 ? c : x.a.id.compareTo(y.a.id);
  });

class GuestsTab extends ConsumerStatefulWidget {
  const GuestsTab({super.key, required this.k, required this.canEdit, required this.event});
  final EventKey k;
  final bool canEdit;
  /// Null while the event is still loading (or failed to load): the list shows, with no actions.
  final OrgEvent? event;
  @override
  ConsumerState<GuestsTab> createState() => _GuestsTabState();
}

class _GuestsTabState extends ConsumerState<GuestsTab> {
  final _search = TextEditingController();
  bool _onlyNotIn = false;
  String _q = '';
  List<Attendee>? _source;
  List<_Row> _rows = const [];
  DateTime _updated = DateTime.now();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(attendeesProvider(widget.k));
    ref.invalidate(attendanceProvider(widget.k));
    try {
      await ref.read(attendeesProvider(widget.k).future);
    } catch (_) {}
  }

  void _open(Attendee a) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AttendeeSheet(k: widget.k, attendee: a, canEdit: widget.canEdit, event: widget.event, parentContext: context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final async = ref.watch(attendeesProvider(widget.k));
    final data = async.value;
    if (data == null) {
      return async.hasError ? loadError(t, _refresh) : const Center(child: CircularProgressIndicator());
    }
    if (!identical(data, _source)) {
      _source = data;
      _rows = _sorted(data);
      _updated = DateTime.now();
    }
    final total = data.where((a) => !a.isDead).length;
    final inCount = data.where((a) => a.isIn).length;
    final q = _q.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    final shown = [
      for (final r in _rows)
        if ((!_onlyNotIn || r.a.isValid) && (q.isEmpty || r.matches(q, qDigits))) r.a,
    ];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.guestsCount(inCount, total), key: const Key('guestsCount'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            key: const Key('guestSearch'),
            controller: _search,
            decoration: InputDecoration(
              hintText: t.guestsSearch,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _q.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() {
                    _search.clear();
                    _q = '';
                  })),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          FilterChip(key: const Key('guestFilterNotIn'), label: Text(t.guestsNotIn), selected: _onlyNotIn, onSelected: (v) => setState(() => _onlyNotIn = v)),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: shown.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: [Text(data.isEmpty ? t.guestsEmpty : t.guestsNoMatch, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium)])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: shown.length + 1,
                  itemBuilder: (_, i) {
                    if (i == shown.length) {
                      return Padding(padding: const EdgeInsets.all(12), child: Text(t.updatedAt(formatTime(_updated, lang)), textAlign: TextAlign.center, style: theme.textTheme.bodySmall));
                    }
                    final a = shown[i];
                    return _GuestTile(a: a, lang: lang, onTap: () => _open(a));
                  },
                ),
        ),
      ),
    ]);
  }
}

String _seat(String lang, Attendee a) => a.seatLabel == null ? '' : pickLang(lang, a.seatLabel!, a.seatLabelMy);

String _name(L10n t, Attendee a) => a.displayName.isEmpty ? t.guestBadge : a.displayName;

E360BadgeKind _statusKind(Attendee a) => a.isIn ? E360BadgeKind.success : E360BadgeKind.neutral;

class _GuestTile extends StatelessWidget {
  const _GuestTile({required this.a, required this.lang, required this.onTap});
  final Attendee a;
  final String lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final seat = _seat(lang, a);
    final tile = ListTile(
      key: Key('guestRow-${a.id}'),
      onTap: onTap,
      title: Text(_name(t, a), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text([a.ticketTypeName, if (seat.isNotEmpty) seat].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          E360Badge(attendeeStatusLabel(t, a), kind: _statusKind(a)),
          if (a.isComplimentary) E360Badge(t.guestBadge, kind: E360BadgeKind.gold),
        ]),
      ]),
    );
    return a.isDead ? Opacity(opacity: 0.55, child: tile) : tile;
  }
}

/// Bottom sheet with one ticket: details and, inside the check-in window, Check in or Undo.
class AttendeeSheet extends ConsumerStatefulWidget {
  const AttendeeSheet({super.key, required this.k, required this.attendee, required this.canEdit, required this.event, required this.parentContext});
  final EventKey k;
  final Attendee attendee;
  final bool canEdit;
  final OrgEvent? event;

  /// The tab's context: snack bars go there so they outlive the sheet.
  final BuildContext parentContext;
  @override
  ConsumerState<AttendeeSheet> createState() => _AttendeeSheetState();
}

class _AttendeeSheetState extends ConsumerState<AttendeeSheet> {
  bool _busy = false;
  String? _error;

  void _refreshLists() {
    ref.invalidate(attendeesProvider(widget.k));
    ref.invalidate(attendanceProvider(widget.k));
  }

  void _finish(String message) {
    final messenger = ScaffoldMessenger.maybeOf(widget.parentContext);
    Navigator.of(context).pop();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _checkIn() async {
    final t = L10n.of(context);
    final lang = ref.read(langProvider);
    final a = widget.attendee;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await ref.read(apiProvider).crewManualCheckin(widget.k.eventId, a.id, gate: organizerGate);
      _refreshLists();
      if (!mounted) return;
      if (out.accepted) {
        _finish(t.checkedInOk(_name(t, a)));
      } else if (out.result == 'ALREADY_CHECKED_IN') {
        final ci = out.ticket?.checkedIn;
        final time = ci == null ? '' : formatTime(ci.at, lang);
        final gate = ci?.gate;
        _finish(ci == null ? t.statusIn : (gate == null || gate.isEmpty) ? t.alreadyCheckedIn(time) : t.alreadyCheckedInGate(time, gate));
      } else {
        final dead = const {'VOID', 'REFUNDED', 'TRANSFERRED'}.contains(out.result);
        _finish(dead ? t.checkInRefused(t.statusCancelled) : t.checkInRefusedGeneric);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? t.checkInNoConnection : e.message);
    } catch (_) {
      if (mounted) setState(() => _error = t.checkInRefusedGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    final t = L10n.of(context);
    final a = widget.attendee;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t.undoCheckInConfirm(_name(t, a))),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
          FilledButton(key: const Key('guestUndoConfirm'), style: compactFilled, onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.undoCheckIn)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).crewUndo(widget.k.eventId, a.id);
      _refreshLists();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (e.status == 409) {
        // Not checked in any more: the list was out of date.
        _refreshLists();
        if (mounted) Navigator.of(context).pop();
      } else if (mounted) {
        setState(() => _error = e.isNetwork ? t.loadError : e.message);
      }
    } catch (_) {
      if (mounted) setState(() => _error = t.loadError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _call(String phone) async {
    await launchUrl(Uri(scheme: 'tel', path: telNumber(phone))).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final lang = ref.watch(langProvider);
    final theme = Theme.of(context);
    final a = widget.attendee;
    final seat = _seat(lang, a);
    final phone = a.phone ?? '';
    final ev = widget.event;
    final open = ev != null && checkInOpen(ev, DateTime.now());
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(_name(t, a), style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            E360Badge(attendeeStatusLabel(t, a), kind: _statusKind(a)),
            if (a.isComplimentary) E360Badge(t.guestBadge, kind: E360BadgeKind.gold),
          ]),
          const SizedBox(height: 12),
          if (phone.isNotEmpty) ...[
            SelectableText(phone, key: const Key('guestPhone'), style: theme.textTheme.titleMedium),
            if (!kIsWeb)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(key: const Key('guestCall'), onPressed: () => _call(phone), icon: const Icon(Icons.call_outlined), label: Text(t.call)),
              ),
            const SizedBox(height: 4),
          ],
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text([a.ticketTypeName, if (seat.isNotEmpty) seat].join(' · '), style: theme.textTheme.bodyLarge)),
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t.registeredOn(formatDayTime(a.createdAt, lang)), style: theme.textTheme.bodySmall)),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, key: const Key('guestError'), style: TextStyle(color: theme.colorScheme.error))),
          if (widget.canEdit && a.isValid)
            if (open)
              FilledButton.icon(key: const Key('guestCheckIn'), style: E360Buttons.gold, onPressed: _busy ? null : _checkIn, icon: const Icon(Icons.how_to_reg_outlined), label: Text(t.checkIn))
            else
              Text(t.checkInClosed, key: const Key('guestClosed'), style: theme.textTheme.bodySmall),
          if (widget.canEdit && a.isIn && open)
            OutlinedButton.icon(key: const Key('guestUndo'), style: E360Buttons.outline, onPressed: _busy ? null : _undo, icon: const Icon(Icons.undo), label: Text(t.undoCheckIn)),
          if (!widget.canEdit) readOnly(context, t),
        ]),
      ),
    );
  }
}
