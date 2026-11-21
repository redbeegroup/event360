import 'package:dio/dio.dart';
import 'package:event360_core/event360_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// An API whose every request fails with [status] and [body].
Event360Api failingApi(int status, Object? body) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example/v1'))
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) => h.reject(DioException(requestOptions: o, response: Response(requestOptions: o, statusCode: status, data: body))),
    ));
  return Event360Api(const AppConfig(app: Event360App.user, apiBaseUrl: 'https://api.example'), MemoryTokenStore(), dio: dio);
}

void main() {
  test('ApiException carries reasonCode from the error body', () async {
    final api = failingApi(400, {'message': 'This code has been used up', 'reasonCode': 'USED_UP'});
    await expectLater(
      api.createOrder('e1', {'tt': 1}, idempotencyKey: 'k', promoCode: 'X'),
      throwsA(isA<ApiException>()
          .having((e) => e.status, 'status', 400)
          .having((e) => e.message, 'message', 'This code has been used up')
          .having((e) => e.reasonCode, 'reasonCode', 'USED_UP')),
    );
  });

  test('ApiException has no reasonCode when the body has none', () async {
    final api = failingApi(409, {'message': 'Some seats were just taken', 'takenSeats': ['A:1:1']});
    await expectLater(
      api.createOrder('e1', const {}, idempotencyKey: 'k', seats: ['A:1:1']),
      throwsA(isA<ApiException>().having((e) => e.reasonCode, 'reasonCode', isNull).having((e) => e.takenSeats, 'takenSeats', ['A:1:1'])),
    );
  });

  test('WaitlistEntry: an OFFERED entry is a live offer whatever its orderId; an expired one is not', () {
    Map<String, dynamic> row(String status, Duration left, {String? orderId}) => {
          'id': 'w1',
          'ticketTypeId': 'tt',
          'eventId': 'e1',
          'status': status,
          'quantity': 2,
          'position': null,
          'offeredQty': 2,
          'offerExpiresAt': DateTime.now().toUtc().add(left).toIso8601String(),
          'seatKeys': ['A:1:1', 'A:1:2'],
          'orderId': orderId,
          'event': {'id': 'e1', 'slug': 's', 'title': 'T', 'titleMy': null},
          'ticketType': {'id': 'tt', 'name': 'General', 'nameMy': null},
        };
    final reopened = WaitlistEntry.fromJson(row('OFFERED', const Duration(minutes: 5), orderId: 'old'));
    expect(reopened.isOffered, isTrue);
    expect(reopened.isSeated, isTrue);
    expect(reopened.seatKeys, ['A:1:1', 'A:1:2']);
    expect(WaitlistEntry.fromJson(row('OFFERED', const Duration(minutes: -1))).isOffered, isFalse);
    expect(WaitlistEntry.fromJson(row('PURCHASED', const Duration(minutes: 5))).isOffered, isFalse);
    expect(WaitlistEntry.fromJson(row('WAITING', Duration.zero)).isWaiting, isTrue);
  });
}
