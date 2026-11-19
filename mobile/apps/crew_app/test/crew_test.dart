import 'dart:convert';

import 'package:crew_app/app/checkin_controller.dart';
import 'package:crew_app/app/providers.dart';
import 'package:crew_app/main.dart';
import 'package:cryptography/cryptography.dart';
import 'package:event360_core/event360_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const eventId = '11111111-1111-1111-1111-111111111111';
const ttId = '22222222-2222-2222-2222-222222222222';

Map<String, dynamic> eventJson() => {
      'id': eventId,
      'title': 'Inya Lake Live',
      'titleMy': null,
      'startsAt': '2027-01-15T10:30:00.000Z',
      'endsAt': '2027-01-15T16:30:00.000Z',
      'venue': {'name': 'Inya Lake Lawn', 'city': 'Yangon'},
    };

Map<String, dynamic> ticketJson(String id, {String status = 'CHECKED_IN', Map<String, dynamic>? checkedIn}) => {
      'id': id,
      'code': id.substring(0, 8).toUpperCase(),
      'status': status,
      'holderName': 'Aung Aung',
      'phoneLast4': '1234',
      'ticketType': {'id': ttId, 'name': 'General', 'nameMy': null},
      'checkedIn': checkedIn,
    };

/// Canned crew API. Set [offline] to make every call fail like a dropped connection.
class FakeCrewApi extends Event360Api {
  FakeCrewApi(this.store) : super(const AppConfig(app: Event360App.crew, apiBaseUrl: 'http://fake'), store);
  final MemoryTokenStore store;
  bool offline = false;
  String publicKey = '';
  final scans = <String>[];
  final synced = <Map<String, dynamic>>[];
  final undone = <String>[];
  final manual = <String>[];

  void _net() {
    if (offline) throw ApiException(null, 'Network error');
  }

  @override
  Future<CrewRedeem> crewRedeem(String code, String deviceName) async {
    if (code != 'K7QM-4XRT') throw ApiException(401, 'Invalid or expired event code');
    await store.save('crew-token', '');
    return CrewRedeem.fromJson({'accessToken': 'crew-token', 'gate': 'Side door', 'label': 'Volunteers', 'event': eventJson()});
  }

  @override
  Future<void> passwordLogin(String email, String password) async => store.save('a', 'r');

  @override
  Future<List<CrewEvent>> crewEvents() async => [CrewEvent.fromJson(eventJson())];

  @override
  Future<CrewManifest> crewManifest(String eventId) async {
    _net();
    return CrewManifest.fromJson({
      'eventId': eventId,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'publicKey': publicKey,
      'ticketTypes': [
        {'id': ttId, 'name': 'General', 'nameMy': null},
      ],
      'tickets': [
        {'id': 'aaaaaaaa-0000-0000-0000-000000000001', 'code': 'AAAAAAAA', 'tt': ttId, 'v': 1, 'status': 'VALID', 'holderName': 'Su Su', 'phoneLast4': '5678', 'checkedInAt': null},
      ],
    });
  }

  @override
  Future<ScanOutcome> crewScan(String eventId, String qr, {String? gate, String? deviceId, DateTime? scannedAt}) async {
    _net();
    scans.add(qr);
    if (qr == 'dup.qr') {
      return ScanOutcome.fromJson({
        'result': 'ALREADY_CHECKED_IN',
        'ticket': ticketJson('bbbbbbbb-0000-0000-0000-000000000002', checkedIn: {'at': '2027-01-15T11:00:00.000Z', 'gate': 'Main gate', 'by': 'Door Aung'}),
      });
    }
    if (qr == 'bad.qr') return ScanOutcome.fromJson({'result': 'INVALID', 'reason': 'signature', 'ticket': null});
    return ScanOutcome.fromJson({'result': 'ACCEPTED', 'ticket': ticketJson('cccccccc-0000-0000-0000-000000000003')});
  }

  @override
  Future<List<ScanOutcome>> crewSync(String eventId, List<Map<String, dynamic>> s) async {
    _net();
    synced.addAll(s);
    return [for (final x in s) ScanOutcome.fromJson({'result': 'ACCEPTED', 'clientId': x['clientId'], 'ticket': null})];
  }

  @override
  Future<List<CrewTicket>> crewSearch(String eventId, String q) async {
    _net();
    return [CrewTicket.fromJson(ticketJson('dddddddd-0000-0000-0000-000000000004', status: 'VALID'))];
  }

  @override
  Future<ScanOutcome> crewManualCheckin(String eventId, String ticketId, {String? gate, String? deviceId}) async {
    _net();
    manual.add(ticketId);
    return ScanOutcome.fromJson({'result': 'ACCEPTED', 'ticket': ticketJson(ticketId)});
  }

  @override
  Future<CrewTicket> crewUndo(String eventId, String ticketId) async {
    _net();
    undone.add(ticketId);
    return CrewTicket.fromJson(ticketJson(ticketId, status: 'VALID'));
  }

  @override
  Future<CrewStats> crewStats(String eventId) async {
    _net();
    return CrewStats.fromJson({
      'registered': 40,
      'checkedIn': 12,
      'byTicketType': [
        {'name': 'General', 'nameMy': null, 'registered': 40, 'checkedIn': 12},
      ],
      'byGate': [
        {'gate': 'Main gate', 'checkedIn': 12},
      ],
      'recent': [
        {
          'id': 'r1',
          'at': '2027-01-15T11:00:00.000Z',
          'gate': 'Main gate',
          'method': 'QR',
          'offline': false,
          'duplicate': false,
          'undone': false,
          'by': 'Door Aung',
          'ticket': {'id': 'eeeeeeee-0000-0000-0000-000000000005', 'code': 'EEEEEEEE', 'status': 'CHECKED_IN', 'holderName': 'Mya Mya', 'ticketType': {'name': 'General', 'nameMy': null}},
        },
      ],
    });
  }
}

void phoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1236, 2745);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<FakeCrewApi> pumpCrew(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  phoneScreen(tester);
  SharedPreferences.setMockInitialValues({'crew_lang': 'en', ...prefs});
  final sp = await SharedPreferences.getInstance();
  final api = FakeCrewApi(MemoryTokenStore());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(sp),
      apiProvider.overrideWithValue(api),
      cameraEnabledProvider.overrideWithValue(false),
      autoSyncProvider.overrideWithValue(false),
      scanDebounceProvider.overrideWithValue(Duration.zero),
    ],
    child: const CrewApp(),
  ));
  await tester.pumpAndSettle();
  return api;
}

/// A session that is already set up at a gate (skips sign-in).
Map<String, Object> readySession() => {
      'crew_session_v1': jsonEncode({'mode': 'code', 'event': eventJson(), 'gate': 'Side door', 'deviceName': 'Gate phone'}),
    };

Future<void> typeScan(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('manualInput')), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

/// A ticket QR signed with a fresh Ed25519 key, in the API's format, plus that key (base64).
Future<(String qr, String publicKey)> signedQr(String ticketId) async {
  final algo = Ed25519();
  final kp = await algo.newKeyPair();
  final pub = await kp.extractPublicKey();
  final payload = utf8.encode(jsonEncode({'tid': ticketId, 'eid': eventId, 'tt': ttId, 'v': 1}));
  final sig = await algo.sign(payload, keyPair: kp);
  String b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
  return ('${b64(payload)}.${b64(sig.bytes)}', base64Encode(pub.bytes));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('my');
  });

  testWidgets('volunteer signs in with an event code and sets up the gate', (tester) async {
    await pumpCrew(tester);
    expect(find.text('Door check-in'), findsOneWidget);
    await tester.tap(find.text('Event code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'zzzz-zzzz');
    await tester.tap(find.text('Start with this code'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid or expired event code'), findsOneWidget);
    // A pasted redeem link works too
    await tester.enterText(find.byType(TextField).first, 'https://app.dev.event360.app/crew/#/redeem?code=K7QM-4XRT');
    await tester.enterText(find.byType(TextField).at(1), 'Gate phone');
    await tester.tap(find.text('Start with this code'));
    await tester.pumpAndSettle();
    // Device named and the gate comes with the code → straight to scanning
    expect(find.text('Inya Lake Live'), findsOneWidget);
    expect(find.text('Side door · Gate phone'), findsOneWidget);
    // The gate can still be changed from the menu
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change event or gate'));
    await tester.pumpAndSettle();
    expect(find.text('Gate setup'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'VIP entrance');
    await tester.enterText(find.byType(TextField).at(1), 'VIP phone');
    await tester.tap(find.text('Start scanning'));
    await tester.pumpAndSettle();
    expect(find.text('VIP entrance · VIP phone'), findsOneWidget);
  });

  testWidgets('crew account picks an event', (tester) async {
    await pumpCrew(tester);
    await tester.enterText(find.byType(TextField).at(0), 'crew@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret-123');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Choose event'), findsOneWidget);
    await tester.tap(find.text('Inya Lake Live'));
    await tester.pumpAndSettle();
    expect(find.text('Gate setup'), findsOneWidget);
  });

  testWidgets('scan results: accepted, already checked in (with where/when), invalid', (tester) async {
    await pumpCrew(tester, prefs: readySession());
    await typeScan(tester, 'good.qr');
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('Aung Aung'), findsOneWidget);
    await typeScan(tester, 'dup.qr');
    expect(find.text('Already checked in'), findsOneWidget);
    expect(find.textContaining('Main gate'), findsOneWidget);
    expect(find.textContaining('by Door Aung'), findsOneWidget);
    await typeScan(tester, 'bad.qr');
    expect(find.text('Not a valid ticket'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // let the auto-hide timer of the first result finish
  });

  testWidgets('offline: verifies the signature on the device, queues the scan and syncs later', (tester) async {
    final (qr, key) = await tester.runAsync(() => signedQr('aaaaaaaa-0000-0000-0000-000000000001')) as (String, String);
    final api = await pumpCrew(tester, prefs: readySession());
    api.publicKey = key;
    final container = ProviderScope.containerOf(tester.element(find.byType(CrewApp)));
    await tester.runAsync(() => container.read(checkinProvider.notifier).refreshManifest());
    await tester.pumpAndSettle();

    api.offline = true;
    await tester.runAsync(() => container.read(checkinProvider.notifier).scan(qr));
    await tester.pumpAndSettle();
    expect(find.text('Checked in'), findsOneWidget);
    expect(find.text('Su Su'), findsOneWidget);
    expect(find.text('Checked offline'), findsOneWidget);
    expect(find.textContaining('1 scan(s) waiting to sync'), findsOneWidget);

    // Same ticket again while offline → caught on the device
    await tester.runAsync(() => container.read(checkinProvider.notifier).scan(qr));
    await tester.pumpAndSettle();
    expect(find.text('Already checked in'), findsOneWidget);

    // A forged QR is rejected offline
    final forged = '${qr.split('.').first}.${base64Url.encode(List.filled(64, 7)).replaceAll('=', '')}';
    await tester.runAsync(() => container.read(checkinProvider.notifier).scan(forged));
    await tester.pumpAndSettle();
    expect(find.text('Not a valid ticket'), findsOneWidget);

    // Back online: the queue is uploaded and cleared
    api.offline = false;
    await tester.runAsync(() => container.read(checkinProvider.notifier).refresh());
    await tester.pumpAndSettle();
    expect(api.synced, hasLength(1));
    expect(api.synced.single['qr'], qr);
    expect(container.read(checkinProvider).pending, isEmpty);
    expect(find.byKey(const Key('attendance')), findsOneWidget);
    expect(find.text('12 / 40 checked in'), findsOneWidget);
  });

  testWidgets('manual lookup checks a guest in; activity shows recent scans with undo', (tester) async {
    final api = await pumpCrew(tester, prefs: readySession());
    await tester.tap(find.byTooltip('Find guest'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lookupInput')), 'Aung');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Check in'));
    await tester.pumpAndSettle();
    expect(find.text('Check in Aung Aung?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Check in').last);
    await tester.pumpAndSettle();
    expect(api.manual, ['dddddddd-0000-0000-0000-000000000004']);
    expect(find.text('Checked in'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // close the result dialog
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Activity'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(CrewApp)));
    await tester.runAsync(() => container.read(checkinProvider.notifier).refresh());
    await tester.pumpAndSettle();
    expect(find.text('Mya Mya'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Undo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Undo'));
    await tester.pumpAndSettle();
    expect(api.undone, ['eeeeeeee-0000-0000-0000-000000000005']);
  });
}
