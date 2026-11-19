import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ticketing/event360_ticketing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Periodic sync/refresh timers (off in widget tests).
final autoSyncProvider = Provider<bool>((ref) => true);

/// The camera reports the same QR many times a second; repeats within this window are ignored.
final scanDebounceProvider = Provider<Duration>((ref) => const Duration(seconds: 3));

/// How long to wait for the server before deciding on the device.
const scanTimeout = Duration(seconds: 4);

@immutable
class CheckinState {
  const CheckinState({
    this.online = true,
    this.pending = const [],
    this.last,
    this.stats,
    this.manifest,
    this.localChecked = const {},
    this.conflicts = const [],
    this.busy = false,
  });

  final bool online;

  /// Scans decided offline, waiting for /sync (maps as sent to the API).
  final List<Map<String, dynamic>> pending;
  final ScanOutcome? last;
  final CrewStats? stats;
  final CrewManifest? manifest;

  /// Ticket ids checked in on this device while offline (id → time).
  final Map<String, DateTime> localChecked;

  /// Offline check-ins the server reported as already checked in elsewhere.
  final List<ScanOutcome> conflicts;
  final bool busy;

  int get checkedIn => (stats?.checkedIn ?? 0) + pending.where((p) => p['_accepted'] == true).length;
  int get registered => stats?.registered ?? manifest?.tickets.where((t) => t.status == 'VALID' || t.status == 'CHECKED_IN').length ?? 0;

  CheckinState copyWith({
    bool? online,
    List<Map<String, dynamic>>? pending,
    ScanOutcome? last,
    bool clearLast = false,
    CrewStats? stats,
    CrewManifest? manifest,
    Map<String, DateTime>? localChecked,
    List<ScanOutcome>? conflicts,
    bool? busy,
  }) =>
      CheckinState(
        online: online ?? this.online,
        pending: pending ?? this.pending,
        last: clearLast ? null : (last ?? this.last),
        stats: stats ?? this.stats,
        manifest: manifest ?? this.manifest,
        localChecked: localChecked ?? this.localChecked,
        conflicts: conflicts ?? this.conflicts,
        busy: busy ?? this.busy,
      );
}

/// Online-first check-in with an offline fallback for the event the device is set up for.
class CheckinController extends Notifier<CheckinState> {
  final _timers = <Timer>[];
  String? _lastQr;
  DateTime? _lastQrAt;

  String get _eventId => ref.read(sessionProvider)!.event!.id;
  String get _pendingKey => 'crew_pending_$_eventId';
  String get _manifestKey => 'crew_manifest_$_eventId';
  String get _localKey => 'crew_local_$_eventId';

  @override
  CheckinState build() {
    final session = ref.watch(sessionProvider);
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    if (session?.event == null) return const CheckinState();
    final p = ref.read(prefsProvider);
    final rawManifest = p.getString(_manifestKey);
    final rawLocal = p.getString(_localKey);
    final initial = CheckinState(
      pending: [for (final s in (jsonDecode(p.getString(_pendingKey) ?? '[]') as List)) (s as Map).cast<String, dynamic>()],
      manifest: rawManifest == null ? null : CrewManifest.fromJson(jsonDecode(rawManifest) as Map<String, dynamic>),
      localChecked: rawLocal == null
          ? const {}
          : (jsonDecode(rawLocal) as Map<String, dynamic>).map((k, v) => MapEntry(k, DateTime.parse(v as String))),
    );
    if (ref.read(autoSyncProvider)) {
      _timers.add(Timer.periodic(const Duration(seconds: 20), (_) => refresh()));
      _timers.add(Timer.periodic(const Duration(minutes: 2), (_) => refreshManifest()));
      Future.microtask(() async {
        await refreshManifest();
        await refresh();
      });
    }
    ref.onDispose(() {
      for (final t in _timers) {
        t.cancel();
      }
    });
    return initial;
  }

  Event360Api get _api => ref.read(apiProvider);
  CrewSession get _session => ref.read(sessionProvider)!;

  Future<void> _savePending(List<Map<String, dynamic>> pending) =>
      ref.read(prefsProvider).setString(_pendingKey, jsonEncode(pending));

  Future<void> _saveLocal(Map<String, DateTime> local) =>
      ref.read(prefsProvider).setString(_localKey, jsonEncode(local.map((k, v) => MapEntry(k, v.toIso8601String()))));

  bool _isNetwork(Object e) => e is TimeoutException || (e is ApiException && e.isNetwork);

  /// Downloads the ticket list + key for offline use.
  Future<void> refreshManifest() async {
    try {
      final m = await _api.crewManifest(_eventId);
      await ref.read(prefsProvider).setString(_manifestKey, jsonEncode(m.toJson()));
      state = state.copyWith(manifest: m, online: true);
    } catch (e) {
      if (_isNetwork(e)) state = state.copyWith(online: false);
    }
  }

  /// Uploads queued offline scans, then refreshes the counters.
  Future<void> refresh() async {
    try {
      if (state.pending.isNotEmpty) await _sync();
      final s = await _api.crewStats(_eventId);
      state = state.copyWith(stats: s, online: true);
    } catch (e) {
      if (_isNetwork(e)) state = state.copyWith(online: false);
    }
  }

  Future<void> _sync() async {
    final batch = [...state.pending];
    final results = await _api.crewSync(_eventId, [for (final s in batch) Map.of(s)..remove('_accepted')]);
    final byId = {for (final r in results) r.clientId: r};
    final conflicts = [
      ...state.conflicts,
      for (final s in batch)
        if (s['_accepted'] == true && byId[s['clientId']]?.result == 'ALREADY_CHECKED_IN') byId[s['clientId']]!,
    ];
    final sent = batch.map((s) => s['clientId']).toSet();
    final remaining = state.pending.where((s) => !sent.contains(s['clientId'])).toList();
    await _savePending(remaining);
    await _saveLocal(const {});
    state = state.copyWith(pending: remaining, conflicts: conflicts, localChecked: const {}, online: true);
    unawaited(refreshManifest());
  }

  String _clientId() {
    final r = Random();
    return '${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 30)}';
  }

  /// Ticket QR text from the scanner or keyboard. Returns null when it's a repeat of the last scan (camera bounce).
  Future<ScanOutcome?> scan(String raw) async {
    final qr = raw.trim();
    if (qr.isEmpty) return null;
    final now = DateTime.now();
    if (qr == _lastQr && _lastQrAt != null && now.difference(_lastQrAt!) < ref.read(scanDebounceProvider)) return null;
    _lastQr = qr;
    _lastQrAt = now;
    if (!qr.contains('.')) return lookupByCode(qr); // short ticket code typed by hand
    state = state.copyWith(busy: true);
    ScanOutcome out;
    try {
      out = await _api.crewScan(_eventId, qr, gate: _session.gate, deviceId: ref.read(deviceIdProvider), scannedAt: now).timeout(scanTimeout);
      state = state.copyWith(online: true);
      unawaited(refresh());
    } catch (e) {
      if (!_isNetwork(e)) {
        state = state.copyWith(busy: false);
        rethrow;
      }
      state = state.copyWith(online: false);
      out = await _offlineScan(qr, now);
    }
    state = state.copyWith(last: out, busy: false);
    return out;
  }

  Future<ScanOutcome> _offlineScan(String qr, DateTime at) async {
    final m = state.manifest;
    if (m == null) return ScanOutcome(result: 'NO_OFFLINE_DATA', offline: true);
    final claims = await OfflineTicketVerifier(base64Decode(m.publicKey)).verify(qr);
    if (claims == null) return ScanOutcome(result: 'INVALID', offline: true);
    if (claims.eventId != _eventId) return ScanOutcome(result: 'WRONG_EVENT', offline: true);
    final t = m.tickets.where((x) => x.id == claims.ticketId).firstOrNull;
    if (t != null && t.version != claims.version) return ScanOutcome(result: 'INVALID', reason: 'outdated_qr', offline: true);
    if (t != null && ['VOID', 'REFUNDED', 'TRANSFERRED'].contains(t.status)) {
      return ScanOutcome(result: t.status, ticket: _ticketFromManifest(t), offline: true);
    }
    final already = state.localChecked[claims.ticketId] ?? (t?.status == 'CHECKED_IN' ? (t?.checkedInAt ?? at) : null);
    if (already != null) {
      return ScanOutcome(result: 'ALREADY_CHECKED_IN', ticket: t == null ? null : _ticketFromManifest(t, checkedAt: already), offline: true);
    }
    return _acceptOffline(at, {'qr': qr, 'method': 'QR'}, claims.ticketId, t, notInList: t == null);
  }

  Future<ScanOutcome> _acceptOffline(DateTime at, Map<String, dynamic> body, String ticketId, ManifestTicket? t, {bool notInList = false}) async {
    final item = {
      'clientId': _clientId(),
      ...body,
      if (_session.gate.isNotEmpty) 'gate': _session.gate,
      'deviceId': ref.read(deviceIdProvider),
      'scannedAt': at.toUtc().toIso8601String(),
      '_accepted': true,
    };
    final pending = [...state.pending, item];
    final local = {...state.localChecked, ticketId: at};
    await _savePending(pending);
    await _saveLocal(local);
    state = state.copyWith(pending: pending, localChecked: local);
    return ScanOutcome(
      result: 'ACCEPTED',
      ticket: t == null ? null : _ticketFromManifest(t, checkedAt: at),
      reason: notInList ? 'not_in_list' : null,
      offline: true,
    );
  }

  CrewTicket _ticketFromManifest(ManifestTicket t, {DateTime? checkedAt}) {
    final tt = state.manifest?.ticketTypes[t.ticketTypeId];
    final at = checkedAt ?? t.checkedInAt;
    return CrewTicket(
      id: t.id,
      code: t.code,
      status: at != null ? 'CHECKED_IN' : t.status,
      holderName: t.holderName,
      phoneLast4: t.phoneLast4,
      ticketTypeName: tt?.name ?? '',
      ticketTypeNameMy: tt?.nameMy,
      checkedIn: at == null ? null : CheckedInInfo(at: at, gate: checkedAt != null ? _session.gate : null),
    );
  }

  /// A ticket code typed at the scan box: check that exact ticket in when the code is unique.
  Future<ScanOutcome?> lookupByCode(String code) async {
    final hits = await search(code);
    final exact = hits.where((t) => t.code.toLowerCase() == code.toLowerCase()).toList();
    if (exact.length != 1) {
      final out = ScanOutcome(result: 'INVALID', reason: 'unknown_code');
      state = state.copyWith(last: out);
      return out;
    }
    final out = await checkIn(exact.first);
    return out;
  }

  /// Manual lookup: server search, or the downloaded list when offline.
  Future<List<CrewTicket>> search(String q) async {
    try {
      final r = await _api.crewSearch(_eventId, q).timeout(scanTimeout);
      state = state.copyWith(online: true);
      return r;
    } catch (e) {
      if (!_isNetwork(e)) rethrow;
      state = state.copyWith(online: false);
      final m = state.manifest;
      if (m == null) return [];
      final term = q.trim().toLowerCase();
      final digits = term.replaceAll(RegExp(r'\D'), '');
      return m.tickets
          .where((t) =>
              t.holderName.toLowerCase().contains(term) ||
              t.code.toLowerCase().startsWith(term) ||
              (digits.length >= 3 && (t.phoneLast4 ?? '').contains(digits.length > 4 ? digits.substring(digits.length - 4) : digits)))
          .take(20)
          .map((t) => _ticketFromManifest(t, checkedAt: state.localChecked[t.id]))
          .toList();
    }
  }

  /// Manual check-in of a looked-up ticket.
  Future<ScanOutcome> checkIn(CrewTicket t) async {
    final now = DateTime.now();
    ScanOutcome out;
    try {
      out = await _api.crewManualCheckin(_eventId, t.id, gate: _session.gate, deviceId: ref.read(deviceIdProvider)).timeout(scanTimeout);
      state = state.copyWith(online: true);
      unawaited(refresh());
    } catch (e) {
      if (!_isNetwork(e)) rethrow;
      state = state.copyWith(online: false);
      if (t.isCheckedIn || state.localChecked.containsKey(t.id)) {
        out = ScanOutcome(result: 'ALREADY_CHECKED_IN', ticket: t, offline: true);
      } else {
        final mt = state.manifest?.tickets.where((x) => x.id == t.id).firstOrNull;
        out = await _acceptOffline(now, {'ticketId': t.id, 'method': 'MANUAL'}, t.id, mt);
      }
    }
    state = state.copyWith(last: out);
    return out;
  }

  /// Undo needs the server (it's the source of truth across gates).
  Future<CrewTicket> undo(String ticketId) async {
    final t = await _api.crewUndo(_eventId, ticketId);
    state = state.copyWith(clearLast: state.last?.ticket?.id == ticketId);
    await refresh();
    return t;
  }

  void dismissResult() => state = state.copyWith(clearLast: true);
  void clearConflicts() => state = state.copyWith(conflicts: const []);
}

final checkinProvider = NotifierProvider<CheckinController, CheckinState>(CheckinController.new);
