import 'dart:convert';
import 'dart:math';

import 'package:event360_core/event360_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in main() / tests.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('prefsProvider not overridden'));
final configProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment(Event360App.crew));
// Own key prefix: on the web the crew preview shares an origin with the user app.
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore(null, 'e360crew'));
final apiProvider = Provider<Event360Api>((ref) => Event360Api(ref.watch(configProvider), ref.watch(tokenStoreProvider)));

/// Whether to show the live camera (off in widget tests, where there is no camera plugin).
final cameraEnabledProvider = Provider<bool>((ref) => true);

// ───── Language ─────

class LangNotifier extends Notifier<String> {
  static const _key = 'crew_lang';
  @override
  String build() => ref.watch(prefsProvider).getString(_key) ?? 'my';

  Future<void> toggle() async {
    state = state == 'my' ? 'en' : 'my';
    await ref.read(prefsProvider).setString(_key, state);
  }
}

final langProvider = NotifierProvider<LangNotifier, String>(LangNotifier.new);
final localeProvider = Provider<Locale>((ref) => Locale(ref.watch(langProvider)));

// ───── Crew session ─────

/// How this device is signed in and where it is scanning. Persisted so the gate survives restarts.
@immutable
class CrewSession {
  const CrewSession({required this.mode, this.event, this.gate = '', this.deviceName = ''});

  /// 'account' (invited crew / organizer) or 'code' (volunteer event code, fixed to one event).
  final String mode;
  final CrewEvent? event;
  final String gate;
  final String deviceName;

  bool get isCode => mode == 'code';
  bool get ready => event != null && deviceName.isNotEmpty;

  CrewSession copyWith({CrewEvent? event, bool clearEvent = false, String? gate, String? deviceName}) => CrewSession(
        mode: mode,
        event: clearEvent ? null : (event ?? this.event),
        gate: gate ?? this.gate,
        deviceName: deviceName ?? this.deviceName,
      );

  Map<String, dynamic> toJson() => {'mode': mode, 'event': event?.toJson(), 'gate': gate, 'deviceName': deviceName};

  factory CrewSession.fromJson(Map<String, dynamic> j) => CrewSession(
        mode: j['mode'] as String,
        event: j['event'] == null ? null : CrewEvent.fromJson(j['event'] as Map<String, dynamic>),
        gate: j['gate'] as String? ?? '',
        deviceName: j['deviceName'] as String? ?? '',
      );
}

class SessionNotifier extends Notifier<CrewSession?> {
  static const _key = 'crew_session_v1';

  @override
  CrewSession? build() {
    final raw = ref.watch(prefsProvider).getString(_key);
    return raw == null ? null : CrewSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _set(CrewSession? s) async {
    state = s;
    final p = ref.read(prefsProvider);
    if (s == null) {
      await p.remove(_key);
    } else {
      await p.setString(_key, jsonEncode(s.toJson()));
    }
  }

  Future<void> signInWithAccount(String email, String password) async {
    await ref.read(apiProvider).passwordLogin(email.trim(), password);
    await _set(CrewSession(mode: 'account', deviceName: state?.deviceName ?? ''));
  }

  Future<void> redeemCode(String code, String deviceName) async {
    final r = await ref.read(apiProvider).crewRedeem(code.trim(), deviceName.trim());
    await _set(CrewSession(mode: 'code', event: r.event, gate: r.gate ?? '', deviceName: deviceName.trim()));
  }

  Future<void> chooseEvent(CrewEvent e) async => _set(state!.copyWith(event: e));

  Future<void> setGate(String gate, String deviceName) async => _set(state!.copyWith(gate: gate.trim(), deviceName: deviceName.trim()));

  /// Back to event/gate selection (account) or gate setup (code).
  Future<void> changeEventOrGate() async => _set(state!.isCode ? state!.copyWith(deviceName: '') : state!.copyWith(clearEvent: true));

  Future<void> signOut() async {
    await ref.read(apiProvider).logout();
    await _set(null);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, CrewSession?>(SessionNotifier.new);

/// Stable per-install id sent with every scan (shown in reports as the device).
final deviceIdProvider = Provider<String>((ref) {
  final p = ref.watch(prefsProvider);
  var id = p.getString('crew_device_id');
  if (id == null) {
    final r = Random.secure();
    id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    p.setString('crew_device_id', id);
  }
  return id;
});

final crewEventsProvider = FutureProvider<List<CrewEvent>>((ref) => ref.watch(apiProvider).crewEvents());
