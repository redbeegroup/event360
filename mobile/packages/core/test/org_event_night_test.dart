import 'package:dio/dio.dart';
import 'package:event360_core/event360_core.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> row({Object? holder, String? guestName, String status = 'VALID'}) => {
      'id': 't1',
      'status': status,
      'createdAt': '2026-11-20T10:00:00.000Z',
      'seatLabel': 'Row A, Seat 1',
      'seatLabelMy': null,
      'isComplimentary': false,
      'guestName': guestName,
      'ticketType': {'id': 'tt', 'name': 'VIP'},
      'holder': holder,
    };

/// An API whose every request fails with [status] and [body].
Event360Api failingApi(int status, Object? body) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example/v1'))
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) => h.reject(DioException(requestOptions: o, response: Response(requestOptions: o, statusCode: status, data: body))),
    ));
  return Event360Api(const AppConfig(app: Event360App.user, apiBaseUrl: 'https://api.example'), MemoryTokenStore(), dio: dio);
}

void main() {
  test('Attendee.fromJson with a full row', () {
    final a = Attendee.fromJson(row(holder: {'id': 'u1', 'displayName': 'Aye', 'phone': '+959111'}, guestName: 'Guest'));
    expect(a.displayName, 'Aye');
    expect(a.ticketTypeName, 'VIP');
    expect(a.seatLabel, 'Row A, Seat 1');
    expect(a.phone, '+959111');
    expect(a.createdAt, DateTime.utc(2026, 11, 20, 10));
    expect(a.isValid, isTrue);
    expect(a.isIn, isFalse);
    expect(a.isDead, isFalse);
  });

  test('Attendee displayName falls back to guest name, then phone, then empty', () {
    expect(Attendee.fromJson(row(guestName: 'Guest')).displayName, 'Guest');
    expect(Attendee.fromJson(row(holder: {'id': 'u1', 'displayName': null, 'phone': '+959222'})).displayName, '+959222');
    expect(Attendee.fromJson(row()).displayName, '');
  });

  test('Attendee status flags', () {
    final t = Attendee.fromJson(row(status: 'TRANSFERRED'));
    expect(t.isDead, isTrue);
    expect(t.isIn, isFalse);
    expect(Attendee.fromJson(row(status: 'CHECKED_IN')).isIn, isTrue);
    expect(Attendee.fromJson(row(status: 'CHECKED_IN')).isDead, isFalse);
  });

  test('OrgSeating.fromJson without a layout has no map', () {
    final s = OrgSeating.fromJson({'layout': null, 'versionId': null, 'rules': [], 'counts': {}, 'colors': {}, 'seats': []});
    expect(s.hasMap, isFalse);
    expect(s.seats, isEmpty);
  });

  test('OrgSeating.fromJson reads seats, colours and counts', () {
    final s = OrgSeating.fromJson({
      'layout': {'sections': []},
      'counts': {'tt': {'available': 5, 'held': 1, 'offered': 2, 'guest': 3, 'sold': 4, 'comp': 6}},
      'colors': {'tt': '#ff0000'},
      'seats': [
        {'seatKey': 'A:1:1', 'status': 'GUEST_HOLD', 'ticketTypeId': 'tt', 'holdLabel': 'Sponsor'},
        {'seatKey': 'A:1:2', 'status': 'UNSOLD', 'ticketTypeId': null, 'holdLabel': null},
      ],
    });
    expect(s.hasMap, isTrue);
    expect(s.colors['tt'], '#ff0000');
    expect(s.counts['tt']!.offered, 2);
    expect(s.seats.first.holdLabel, 'Sponsor');
    expect(s.seats.last.ticketTypeId, isNull);
  });

  test('SeatCounts offered defaults to 0', () {
    expect(SeatCounts.fromJson({'offered': 3}).offered, 3);
    expect(SeatCounts.fromJson({}).offered, 0);
  });

  test('GuestTicket.canRevoke is false once checked in or revoked', () {
    Map<String, dynamic> g(String status, bool checkedIn) => {
          'id': 'g1', 'guestName': 'Zaw', 'phone': '+95 9** *** 123', 'seatKey': 'A:1:1', 'seatLabel': 'A1', 'seatLabelMy': null,
          'label': 'VIP', 'status': status, 'checkedIn': checkedIn, 'orderId': 'o', 'createdAt': '2026-11-20T10:00:00.000Z',
        };
    expect(GuestTicket.fromJson(g('VALID', false)).canRevoke, isTrue);
    expect(GuestTicket.fromJson(g('CHECKED_IN', true)).canRevoke, isFalse);
    expect(GuestTicket.fromJson(g('VALID', true)).canRevoke, isFalse);
    expect(GuestTicket.fromJson(g('REVOKED', false)).canRevoke, isFalse);
  });

  test('WaitlistCounts.fromJson', () {
    final w = WaitlistCounts.fromJson({
      'ticketTypes': [
        {'id': 'a', 'name': 'General', 'nameMy': null, 'waiting': 4, 'waitingQuantity': 6, 'offered': 1, 'offeredQuantity': 2},
        {'id': 'b', 'name': 'VIP', 'nameMy': 'ဗီအိုင်ပီ', 'waiting': 0, 'waitingQuantity': 0, 'offered': 0, 'offeredQuantity': 0},
      ],
      'total': 5,
    });
    expect(w.total, 5);
    expect(w.types.length, 2);
    expect(w.types.first.waiting, 4);
    expect(w.types.first.offered, 1);
    expect(w.types.last.nameMy, 'ဗီအိုင်ပီ');
  });

  test('a 409 with takenSeats on hold/release/comps becomes SeatsChanged', () async {
    final api = failingApi(409, {'message': 'Some seats are not available', 'takenSeats': ['A:1:1']});
    final matcher = throwsA(isA<SeatsChanged>().having((e) => e.takenSeats, 'takenSeats', ['A:1:1']).having((e) => e.message, 'message', 'Some seats are not available'));
    await expectLater(api.holdSeats('o', 'e', ['A:1:1'], 'VIP'), matcher);
    await expectLater(api.releaseSeats('o', 'e', ['A:1:1']), matcher);
    await expectLater(api.issueGuestTickets('o', 'e', ['A:1:1'], guestName: 'Zaw', phone: '0911'), matcher);
  });

  test('a 409 without takenSeats, and other errors, stay ApiException', () async {
    await expectLater(failingApi(409, {'message': 'Event is already CANCELLED'}).holdSeats('o', 'e', ['A:1:1'], 'VIP'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)));
    await expectLater(failingApi(403, {'message': 'Forbidden', 'takenSeats': ['A:1:1']}).holdSeats('o', 'e', ['A:1:1'], 'VIP'), throwsA(isA<ApiException>()));
  });
}
