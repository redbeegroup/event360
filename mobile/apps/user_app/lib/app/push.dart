import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Push delivery for the app. Real implementation: Firebase Cloud Messaging on Android (web/iOS: inbox only for now).
abstract class PushClient {
  /// Whether push can work in this build (Firebase config compiled in, supported platform).
  bool get supported;

  /// Asks permission (Android 13+), returns this device's token or null if not allowed/available.
  Future<String?> token();

  Stream<String> get onTokenRefresh;

  /// A notification arrived while the app is open (refresh the inbox).
  Stream<void> get onForeground;

  /// The user tapped a notification: its in-app link.
  Stream<String> get onOpenLink;

  /// Link of the notification that launched the app, if any.
  Future<String?> initialLink();

  Future<void> deleteToken();
}

class NoPush implements PushClient {
  const NoPush();
  @override
  bool get supported => false;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<void> get onForeground => const Stream.empty();
  @override
  Stream<String> get onOpenLink => const Stream.empty();
  @override
  Future<String?> initialLink() async => null;
  @override
  Future<void> deleteToken() async {}
}

/// Firebase client config comes from build flags (no google-services.json in the repo):
/// --dart-define=FIREBASE_API_KEY=… FIREBASE_APP_ID=… FIREBASE_SENDER_ID=… FIREBASE_PROJECT_ID=…
class FirebasePush implements PushClient {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get configured => _apiKey != '' && _appId != '' && _senderId != '' && _projectId != '';

  Future<FirebaseMessaging>? _ready;

  @override
  bool get supported => configured && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<FirebaseMessaging> _init() => _ready ??= () async {
        await Firebase.initializeApp(options: const FirebaseOptions(apiKey: _apiKey, appId: _appId, messagingSenderId: _senderId, projectId: _projectId));
        return FirebaseMessaging.instance;
      }();

  @override
  Future<String?> token() async {
    if (!supported) return null;
    final m = await _init();
    final s = await m.requestPermission();
    if (s.authorizationStatus == AuthorizationStatus.denied) return null;
    return m.getToken();
  }

  @override
  Stream<String> get onTokenRefresh => supported ? Stream.fromFuture(_init()).asyncExpand((m) => m.onTokenRefresh) : const Stream.empty();

  @override
  Stream<void> get onForeground => supported ? Stream.fromFuture(_init()).asyncExpand((_) => FirebaseMessaging.onMessage.map((_) {})) : const Stream.empty();

  @override
  Stream<String> get onOpenLink => supported
      ? Stream.fromFuture(_init()).asyncExpand((_) => FirebaseMessaging.onMessageOpenedApp.map((m) => m.data['link'] as String? ?? '').where((l) => l.startsWith('/')))
      : const Stream.empty();

  @override
  Future<String?> initialLink() async {
    if (!supported) return null;
    final m = await (await _init()).getInitialMessage();
    final l = m?.data['link'] as String?;
    return l != null && l.startsWith('/') ? l : null;
  }

  @override
  Future<void> deleteToken() async {
    if (supported) await (await _init()).deleteToken();
  }
}
