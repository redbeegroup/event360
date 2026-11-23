import 'package:dio/dio.dart';
import 'package:event360_core/event360_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// An API that records the last request and answers [body].
({Event360Api api, List<RequestOptions> seen}) stubApi(Object? body) {
  final seen = <RequestOptions>[];
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example/v1'))
    ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      seen.add(o);
      h.resolve(Response(requestOptions: o, statusCode: 200, data: body));
    }));
  return (api: Event360Api(const AppConfig(app: Event360App.user, apiBaseUrl: 'https://api.example'), MemoryTokenStore(), dio: dio), seen: seen);
}

Map<String, dynamic> orderRow({String status = 'PAID', Map<String, dynamic>? buyer}) => {
      'id': 'abcdef12-0000',
      'number': 'ABCDEF12',
      'status': status,
      'needsReview': false,
      'createdAt': '2026-11-20T10:00:00.000Z',
      'paidAt': '2026-11-20T10:01:00.000Z',
      'holdExpiresAt': null,
      'totalMmk': 30000,
      'discountMmk': 0,
      'quantity': 2,
      'buyer': buyer ?? {'name': 'Aye', 'phone': '0977•••123'},
    };

void main() {
  test('canSeePayouts', () {
    OrgMembership m(String r) => OrgMembership(id: 'o', name: 'n', slug: 's', role: r, kycStatus: 'APPROVED');
    expect(m('ORG_OWNER').canSeePayouts, isTrue);
    expect(m('ORG_FINANCE').canSeePayouts, isTrue);
    expect(m('ORG_MANAGER').canSeePayouts, isFalse);
    expect(m('CREW').canSeePayouts, isFalse);
  });

  test('EventSales.fromJson with next price and free type', () {
    final s = EventSales.fromJson({
      'ticketTypes': [
        {'id': 'a', 'name': 'GA', 'priceMmk': 15000, 'basePriceMmk': 10000, 'nextPrice': {'priceMmk': 20000, 'startsAt': '2026-12-01T00:00:00.000Z'}, 'quota': 100, 'sold': 4, 'held': 1, 'offered': 0, 'revenueMmk': 60000},
        {'id': 'b', 'name': 'Free', 'priceMmk': 0, 'basePriceMmk': 0, 'nextPrice': null, 'quota': 10, 'sold': 0, 'held': 0, 'offered': 0, 'revenueMmk': 0},
      ],
      'paidOrders': 3, 'grossMmk': 60000, 'commissionMmk': 3000, 'netMmk': 57000, 'refundedOrders': 1, 'refundedMmk': 5000, 'recent': [],
    });
    expect(s.types[0].nextPriceMmk, 20000);
    expect(s.types[0].nextPriceAt, DateTime.utc(2026, 12));
    expect(s.types[1].nextPriceMmk, isNull);
    expect(s.types[1].nextPriceAt, isNull);
    expect(s.netMmk, 57000);
    expect(s.hasPaidTypes, isTrue);
    final free = EventSales.fromJson({'ticketTypes': [], 'paidOrders': 0, 'grossMmk': 0, 'commissionMmk': 0, 'netMmk': 0, 'refundedOrders': 0, 'refundedMmk': 0, 'recent': []});
    expect(free.hasPaidTypes, isFalse);
  });

  test('OrgOrderRow and page', () {
    final p = OrgOrderPage.fromJson({'orders': [orderRow(), orderRow(buyer: {'name': null, 'phone': null})], 'nextCursor': null});
    expect(p.orders[0].buyerName, 'Aye');
    expect(p.orders[0].buyerPhone, '0977•••123');
    expect(p.orders[0].paidAt, DateTime.utc(2026, 11, 20, 10, 1));
    expect(p.orders[1].buyerName, isNull);
    expect(p.nextCursor, isNull);
    expect(OrgOrderPage.fromJson({'orders': [], 'nextCursor': 'abc'}).nextCursor, 'abc');
  });

  test('OrgOrderDetail.fromJson', () {
    final d = OrgOrderDetail.fromJson({
      ...orderRow(status: 'REFUNDED'),
      'subtotalMmk': 30000,
      'commissionMmk': 1500,
      'promoCode': null,
      'groupDiscountBp': 500,
      'items': [
        {'ticketTypeId': 't', 'name': 'VIP', 'nameMy': null, 'quantity': 2, 'unitPriceMmk': 15000, 'seats': [{'label': 'A1', 'labelMy': null}, {'label': 'A2', 'labelMy': 'က၂'}]},
      ],
      'payments': [{'provider': 'KBZPAY', 'status': 'SUCCEEDED', 'createdAt': '2026-11-20T10:00:30.000Z'}],
      'refunds': [{'status': 'MANUAL', 'amountMmk': 30000, 'createdAt': '2026-11-21T10:00:00.000Z', 'completedAt': null}],
      'tickets': {'total': 2, 'valid': 0, 'checkedIn': 1, 'void': 1},
    });
    expect(d.row.status, 'REFUNDED');
    expect(d.groupDiscountBp, 500);
    expect(d.promoCode, isNull);
    expect(d.items.single.seats.map((s) => s.label), ['A1', 'A2']);
    expect(d.items.single.seats[1].labelMy, 'က၂');
    expect(d.payments.single.provider, 'KBZPAY');
    expect(d.refunds.single.completedAt, isNull);
    expect(d.ticketsCheckedIn, 1);
    expect(d.ticketsVoid, 1);
  });

  test('PayoutSummary.fromJson with voided payout and negative owed', () {
    final s = PayoutSummary.fromJson({
      'earnedMmk': 1000, 'eventsNetMmk': 1000, 'reconciled': true, 'paidOutMmk': 1500, 'owedMmk': -500,
      'events': [{'eventId': 'e', 'title': 'Night', 'grossMmk': 2000, 'discountMmk': 100, 'commissionMmk': 100, 'refundsMmk': 900, 'netMmk': 1000}],
      'payouts': [
        {'id': 'p1', 'organizationId': 'o', 'amountMmk': 1500, 'paidAt': '2026-11-22T00:00:00.000Z', 'method': 'BANK', 'reference': 'R1', 'note': null, 'createdAt': '2026-11-22T01:00:00.000Z', 'voidedAt': null, 'voidReason': null},
        {'id': 'p2', 'organizationId': 'o', 'amountMmk': 700, 'paidAt': '2026-11-21T00:00:00.000Z', 'method': 'CASH', 'reference': null, 'note': 'n', 'createdAt': '2026-11-21T01:00:00.000Z', 'voidedAt': '2026-11-22T02:00:00.000Z', 'voidReason': 'typo'},
      ],
    });
    expect(s.owedMmk, -500);
    expect(s.events.single.refundsMmk, 900);
    expect(s.payouts[0].isVoided, isFalse);
    expect(s.payouts[1].isVoided, isTrue);
    expect(s.payouts[1].voidReason, 'typo');
    final e = PayoutSummary.fromJson({'earnedMmk': 0, 'paidOutMmk': 0, 'owedMmk': 0, 'reconciled': true, 'events': [], 'payouts': []});
    expect(e.events, isEmpty);
    expect(e.payouts, isEmpty);
  });

  test('eventOrders sends only non-null params; other methods hit their paths', () async {
    var t = stubApi({'orders': [], 'nextCursor': null});
    await t.api.eventOrders('o1', 'e1');
    expect(t.seen.single.path, '/organizations/o1/events/e1/orders');
    expect(t.seen.single.queryParameters, {'limit': 30});
    t = stubApi({'orders': [], 'nextCursor': null});
    await t.api.eventOrders('o1', 'e1', status: 'paid', q: 'aye', cursor: 'c', limit: 10);
    expect(t.seen.single.queryParameters, {'status': 'paid', 'q': 'aye', 'cursor': 'c', 'limit': 10});

    t = stubApi({...orderRow(), 'subtotalMmk': 0, 'commissionMmk': 0, 'items': [], 'payments': [], 'refunds': [], 'tickets': {'total': 0, 'valid': 0, 'checkedIn': 0, 'void': 0}});
    await t.api.eventOrder('o1', 'e1', 'x');
    expect(t.seen.single.path, '/organizations/o1/events/e1/orders/x');

    t = stubApi({'earnedMmk': 0, 'paidOutMmk': 0, 'owedMmk': 0, 'reconciled': true, 'events': [], 'payouts': []});
    await t.api.payoutSummary('o1');
    expect(t.seen.single.path, '/organizations/o1/payouts/summary');

    t = stubApi({'ticketTypes': [], 'recent': []});
    await t.api.eventSales('o1', 'e1');
    expect(t.seen.single.path, '/organizations/o1/events/e1/sales');
  });
}
