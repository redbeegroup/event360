import 'dart:async';

import 'package:event360_core/event360_core.dart';
import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Uncaught errors go to Admin → Operations (not from debug runs on a developer machine)
  if (!kDebugMode) ErrorReporter(AppConfig.fromEnvironment(Event360App.user)).install();
  await Future.wait([initializeDateFormatting('en'), initializeDateFormatting('my')]);
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(overrides: [prefsProvider.overrideWithValue(prefs)], child: const UserApp()));
}

class UserApp extends ConsumerStatefulWidget {
  const UserApp({super.key});

  @override
  ConsumerState<UserApp> createState() => _UserAppState();
}

class _UserAppState extends ConsumerState<UserApp> {
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    final push = ref.read(pushProvider);
    if (!push.supported) return;
    void register([String? token]) {
      if (ref.read(sessionProvider).value == null) return;
      registerPush(push, ref.read(apiProvider), ref.read(prefsProvider), token: token).catchError((_) {});
    }

    // Register the device whenever someone signs in (and when Firebase rotates the token)
    ref.listenManual(sessionProvider, (prev, next) {
      final id = next.value?.id;
      if (id != null && id.isNotEmpty && prev?.value?.id != id) register();
    }, fireImmediately: true);
    _subs.add(push.onTokenRefresh.listen(register));
    _subs.add(push.onForeground.listen((_) {
      ref.invalidate(inboxProvider);
      ref.invalidate(waitlistProvider); // an offer may have just arrived
    }));
    _subs.add(push.onOpenLink.listen(_open));
    push.initialLink().then((l) {
      if (l != null) _open(l);
    });
  }

  void _open(String link) {
    ref.invalidate(inboxProvider);
    ref.invalidate(waitlistProvider);
    ref.read(routerProvider).push(link);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'Event 360',
      debugShowCheckedModeBanner: false,
      theme: Event360Theme.light(),
      darkTheme: Event360Theme.dark(),
      locale: locale ?? const Locale('my'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
