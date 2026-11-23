import 'package:event360_core/event360_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:organizer_app/app/retry.dart';

import 'widget_test.dart' hide main;
import 'package:flutter/material.dart';

Future<FakeApi> openOverview(WidgetTester tester, void Function(FakeApi) configure) async {
  final api = await pumpApp(tester, configure: configure);
  await tester.tap(find.byKey(const Key('event-e1')));
  // Frames only, no settling: the clock moves exactly as far as each test says
  await tester.pump();
  await tester.pump();
  return api;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  test('policy: final and client errors never retry, network and 5xx twice, anything else not at all', () {
    for (final s in [400, 401, 403, 404, 409, 422, 429]) {
      expect(appRetry(0, ApiException(s, 'x')), isNull, reason: '$s');
    }
    for (final e in [ApiException(null, 'offline'), ApiException(500, 'x'), ApiException(503, 'x')]) {
      expect(appRetry(0, e), const Duration(milliseconds: 400));
      expect(appRetry(1, e), const Duration(seconds: 1));
      expect(appRetry(2, e), isNull);
    }
    expect(appRetry(0, StateError('bug')), isNull);
    expect(appRetry(0, const FormatException('bad json')), isNull);
  });

  testWidgets('403 shows the no-access state without waiting', (tester) async {
    final api = await openOverview(tester, (a) => a.dashboardError = ApiException(403, 'Forbidden'));
    expect(find.text('You no longer have access to this'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(api.dashboardCalls, 1);
  });

  testWidgets('404 is not retried either', (tester) async {
    final api = await openOverview(tester, (a) => a.dashboardError = ApiException(404, 'Gone'));
    expect(find.text('This is no longer available'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(api.dashboardCalls, 1);
  });

  testWidgets('a network failure shows the connection error with Retry within two seconds, after two retries', (tester) async {
    final api = await openOverview(tester, (a) => a.dashboardError = ApiException(null, 'offline'));
    expect(find.text("Couldn't load. Check your connection."), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text("Couldn't load. Check your connection."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(api.dashboardCalls, 3);
    await tester.pump(const Duration(seconds: 10));
    expect(api.dashboardCalls, 3);
  });

  testWidgets('a failure followed by success within the retries shows data and no error flash', (tester) async {
    final api = await openOverview(tester, (a) {
      a.dashboardError = ApiException(500, 'blip');
      a.dashboardErrorTimes = 2;
    });
    expect(find.text('Retry'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Something went wrong. Try again.'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    expect(api.dashboardCalls, 3);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Something went wrong. Try again.'), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('sold'))).data, '13 / 300');
  });
}
