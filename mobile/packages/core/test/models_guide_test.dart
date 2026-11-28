import 'package:event360_core/event360_core.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> ticketJson({bool extras = true}) => {
      'id': 't1',
      'status': 'CHECKED_IN',
      'ticketType': {'id': 'tt', 'name': 'GA'},
      'event': {
        'id': 'e1',
        if (extras) 'slug': 'big-night',
        if (extras) 'status': 'PUBLISHED',
        'title': 'Big Night',
        'startsAt': '2027-01-15T10:30:00.000Z',
        'endsAt': '2027-01-15T15:30:00.000Z',
        'organization': 'Org',
      },
      if (extras) 'checkedInAt': '2027-01-15T11:00:00.000Z',
    };

void main() {
  test('ScheduleItem parses id, absent id is null', () {
    final base = {'title': 'Opening', 'startsAt': '2027-01-15T10:30:00Z', 'endsAt': '2027-01-15T11:30:00Z'};
    expect(ScheduleItem.fromJson({...base, 'id': 's1'}).id, 's1');
    expect(ScheduleItem.fromJson(base).id, isNull);
  });

  test('MyTicket reads the new keys from the API', () {
    final t = MyTicket.fromApi(ticketJson());
    expect(t.checkedInAt, DateTime.utc(2027, 1, 15, 11));
    expect(t.eventStatus, 'PUBLISHED');
    expect(t.eventSlug, 'big-night');
    expect(t.isCheckedIn, isTrue);
  });

  test('MyTicket without the new keys has nulls', () {
    final t = MyTicket.fromApi(ticketJson(extras: false)..['status'] = 'VALID');
    expect(t.checkedInAt, isNull);
    expect(t.eventStatus, isNull);
    expect(t.eventSlug, isNull);
    expect(t.isCheckedIn, isFalse);
  });

  test('toJson to fromJson round trip keeps the new fields', () {
    final t = MyTicket.fromJson(MyTicket.fromApi(ticketJson()).toJson());
    expect(t.checkedInAt, DateTime.utc(2027, 1, 15, 11));
    expect(t.eventStatus, 'PUBLISHED');
    expect(t.eventSlug, 'big-night');
  });

  test('an older cached entry without the new keys still loads', () {
    final old = MyTicket.fromApi(ticketJson(extras: false)).toJson()
      ..remove('checkedInAt')
      ..remove('eventStatus')
      ..remove('eventSlug');
    final t = MyTicket.fromJson(old);
    expect(t.id, 't1');
    expect(t.checkedInAt, isNull);
    expect(t.eventSlug, isNull);
  });

  test('EventAnnouncement round trip', () {
    final a = EventAnnouncement.fromJson({'id': 'a1', 'title': 'Gates', 'titleMy': 'ဂိတ်', 'body': 'Open', 'bodyMy': null, 'createdAt': '2027-01-15T09:00:00.000Z'});
    expect(a.titleMy, 'ဂိတ်');
    final b = EventAnnouncement.fromJson(a.toJson());
    expect(b.createdAt, a.createdAt);
    expect(b.bodyMy, isNull);
  });
}
