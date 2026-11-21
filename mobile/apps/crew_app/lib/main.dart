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
  if (!kDebugMode) ErrorReporter(AppConfig.fromEnvironment(Event360App.crew)).install();
  await Future.wait([initializeDateFormatting('en'), initializeDateFormatting('my')]);
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(overrides: [prefsProvider.overrideWithValue(prefs)], child: const CrewApp()));
}

class CrewApp extends ConsumerWidget {
  const CrewApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The theme follows the language: Myanmar gets its own font, weights and line heights
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
        title: 'Event 360 Crew',
        debugShowCheckedModeBanner: false,
        theme: Event360Theme.light(locale: locale),
        darkTheme: Event360Theme.dark(locale: locale),
        locale: locale,
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
