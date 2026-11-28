import 'package:event360_core/event360_core.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime u(int d, int h, [int m = 0, int s = 0]) => DateTime.utc(2027, 1, d, h, m, s);

ScheduleItem sess(String title, DateTime a, DateTime b, {String? id, String? my, String? desc}) =>
    ScheduleItem(id: id ?? title, title: title, titleMy: my, description: desc, startsAt: a, endsAt: b);

void main() {
  group('guidePhase', () {
    final s = u(15, 12), e = u(15, 16);
    GuidePhase at(DateTime n, {String? status}) => guidePhase(startsAt: s, endsAt: e, status: status, now: n);
    test('boundaries', () {
      expect(at(s.subtract(const Duration(seconds: 1))), GuidePhase.before);
      expect(at(s), GuidePhase.onNow);
      expect(at(e.subtract(const Duration(seconds: 1))), GuidePhase.onNow);
      expect(at(e), GuidePhase.ended);
    });
    test('other statuses follow the times', () {
      expect(at(s.add(const Duration(hours: 1)), status: 'ONGOING'), GuidePhase.onNow);
      expect(at(e.add(const Duration(hours: 1)), status: 'COMPLETED'), GuidePhase.ended);
      expect(at(s.subtract(const Duration(hours: 1)), status: 'ONGOING'), GuidePhase.before);
    });
    test('cancelled wins', () {
      expect(at(s.add(const Duration(hours: 1)), status: 'CANCELLED'), GuidePhase.cancelled);
      expect(at(s, status: 'PUBLISHED'), GuidePhase.onNow);
    });
  });

  group('startsIn', () {
    final now = u(10, 0);
    test('units, rounded down', () {
      expect(startsIn(now.add(const Duration(days: 3, hours: 5)), now), (value: 3, unit: 'days'));
      expect(startsIn(now.add(const Duration(hours: 3, minutes: 40)), now), (value: 3, unit: 'hours'));
      expect(startsIn(now.add(const Duration(minutes: 20, seconds: 50)), now), (value: 20, unit: 'minutes'));
    });
    test('exactly 24 hours is 1 day, exactly 60 minutes is 1 hour', () {
      expect(startsIn(now.add(const Duration(hours: 24)), now), (value: 1, unit: 'days'));
      expect(startsIn(now.add(const Duration(minutes: 60)), now), (value: 1, unit: 'hours'));
      expect(startsIn(now.add(const Duration(minutes: 59, seconds: 59)), now), (value: 59, unit: 'minutes'));
    });
    test('30 seconds is 1 minute', () {
      expect(startsIn(now.add(const Duration(seconds: 30)), now), (value: 1, unit: 'minutes'));
    });
  });

  group('isEventToday (Yangon is UTC+6:30)', () {
    // 19:00 Yangon on 15 Jan = 12:30Z; midnight Yangon = 14 Jan 17:30Z.
    final s = u(15, 12, 30), e = u(15, 16);
    bool at(DateTime n) => isEventToday(startsAt: s, endsAt: e, now: n);
    test('evening event opens at 00:00 Yangon', () {
      expect(at(u(14, 17, 29)), isFalse); // 23:59 the day before
      expect(at(u(14, 17, 30)), isTrue); // 00:00
      expect(at(u(15, 12, 30)), isTrue);
    });
    test('00:15 start: the six-hour branch opens earlier than midnight', () {
      final s0 = u(14, 17, 45); // 00:15 Yangon on 15 Jan
      bool at0(DateTime n) => isEventToday(startsAt: s0, endsAt: u(15, 2), now: n);
      expect(at0(u(14, 11, 44)), isFalse);
      expect(at0(u(14, 11, 45)), isTrue); // 18:15 Yangon on the 14th
    });
    test('closes at the end', () {
      expect(at(u(15, 15, 59)), isTrue);
      expect(at(e), isFalse);
      expect(at(u(16, 1)), isFalse);
    });
    test('early event opens six hours before the start', () {
      final s3 = u(14, 20, 30); // 03:00 Yangon on 15 Jan
      bool at3(DateTime n) => isEventToday(startsAt: s3, endsAt: u(15, 1), now: n);
      expect(at3(u(14, 14, 29)), isFalse); // 20:59 Yangon
      expect(at3(u(14, 14, 30)), isTrue); // 21:00 Yangon
    });
    test('multi-day event is true on day 2 and 3 only because the window runs to the end', () {
      final end = u(17, 16);
      bool atm(DateTime n) => isEventToday(startsAt: s, endsAt: end, now: n);
      expect(atm(u(16, 18, 30)), isTrue); // 16 Jan 01:00 Yangon, a start-date-only check says no
      expect(atm(u(17, 15, 59)), isTrue);
      expect(atm(end), isFalse);
      expect(atm(u(17, 17)), isFalse);
    });
  });

  test('guideLinkVisible until a week after the end', () {
    final e = u(15, 16);
    expect(guideLinkVisible(endsAt: e, now: e.add(const Duration(days: 7)).subtract(const Duration(seconds: 1))), isTrue);
    expect(guideLinkVisible(endsAt: e, now: e.add(const Duration(days: 7))), isFalse);
    expect(guideLinkVisible(endsAt: e, now: e.subtract(const Duration(days: 30))), isTrue);
  });

  group('nowAndNext', () {
    final a = sess('A', u(15, 10), u(15, 12));
    final b = sess('B', u(15, 11), u(15, 13)); // overlaps A
    final c = sess('C', u(15, 14), u(15, 15));
    final d = sess('D', u(15, 16), u(15, 17));
    final f = sess('F', u(15, 18), u(15, 19));
    final g = sess('G', u(16, 9), u(16, 10)); // next day
    final all = [g, f, d, c, b, a];
    List<String> names(List<ScheduleItem> l) => l.map((x) => x.title).toList();

    test('overlapping sessions both run, next is three in order', () {
      final r = nowAndNext(all, u(15, 11, 30));
      expect(names(r.now), ['A', 'B']);
      expect(names(r.next), ['C', 'D', 'F']);
    });
    test('none running', () {
      final r = nowAndNext(all, u(15, 13, 30));
      expect(r.now, isEmpty);
      expect(names(r.next), ['C', 'D', 'F']);
    });
    test('next day sessions count as next; fewer than three', () {
      final r = nowAndNext(all, u(15, 18, 30));
      expect(names(r.now), ['F']);
      expect(names(r.next), ['G']);
    });
    test('end is exclusive, start inclusive', () {
      expect(names(nowAndNext(all, u(15, 12)).now), ['B']);
      expect(names(nowAndNext(all, u(15, 14)).now), ['C']);
    });
    test('equal start times order by end then title', () {
      final x = sess('X', u(15, 20), u(15, 22));
      final y = sess('Y', u(15, 20), u(15, 21));
      final w = sess('W', u(15, 20), u(15, 21));
      expect(names(nowAndNext([x, y, w], u(15, 19)).next), ['W', 'Y', 'X']);
      expect(names(nowAndNext([w, x, y], u(15, 19)).next), ['W', 'Y', 'X']);
    });
    test('single session, and nextCount', () {
      expect(names(nowAndNext([a], u(15, 10)).now), ['A']);
      expect(nowAndNext([a], u(15, 10)).next, isEmpty);
      expect(names(nowAndNext(all, u(15, 9), nextCount: 1).next), ['A']);
    });
  });

  group('searchEvent', () {
    final event = EventSummary.fromJson({
      'id': 'e1',
      'slug': 'night',
      'status': 'PUBLISHED',
      'title': 'Night',
      'format': 'IN_PERSON',
      'isFree': false,
      'startsAt': '2027-01-15T12:30:00Z',
      'endsAt': '2027-01-15T16:00:00Z',
      'category': {'nameEn': 'Music'},
      'organization': {'name': 'Org', 'kycStatus': 'APPROVED'},
      'ticketTypes': [],
      'soldOut': false,
      'parking': 'Free parking behind the hall',
      'parkingMy': 'ကားပါကင်',
      'dressCode': 'Smart casual',
      'sessions': [
        {'id': 's1', 'title': 'Opening Ceremony', 'titleMy': 'ဖွင့်ပွဲ', 'description': 'Welcome speech', 'location': 'Main hall', 'startsAt': '2027-01-15T12:30:00Z', 'endsAt': '2027-01-15T13:30:00Z'},
        {'id': 's2', 'title': 'Hall tour', 'startsAt': '2027-01-15T13:30:00Z', 'endsAt': '2027-01-15T14:30:00Z'},
      ],
      'performers': [
        {'name': 'Aye Chan', 'nameMy': 'အေးချမ်း', 'role': 'Headline singer', 'roleMy': 'အဓိကအဆိုတော်'},
      ],
      'faqs': [
        {'question': 'Can I bring food?', 'questionMy': 'အစားအစာ ယူလာနိုင်သလား', 'answer': 'No outside food.', 'answerMy': 'အပြင်မှ အစားအစာ မရပါ'},
      ],
    });

    test('empty and blank query', () {
      expect(searchEvent(event, ''), isEmpty);
      expect(searchEvent(event, '   '), isEmpty);
    });
    test('English query is case-insensitive, trimmed, one hit per item', () {
      final h = searchEvent(event, '  HALL ');
      expect(h.map((x) => '${x.group}:${x.index}'), ['schedule:0', 'schedule:1', 'info:2']); // location "Main hall", title "Hall tour", parking text
      expect(searchEvent(event, 'opening').single.title, 'Opening Ceremony');
      expect(searchEvent(event, 'opening').single.id, 's1');
      expect(searchEvent(event, 'food').first.id, isNull);
    });
    test('hit with several matching fields is not duplicated', () {
      // "food" appears in the FAQ question and answer
      expect(searchEvent(event, 'food').where((x) => x.group == 'faq'), hasLength(1));
    });
    test('Myanmar query matches titleMy, FAQ answer, role, practical info', () {
      expect(searchEvent(event, 'ဖွင့်ပွဲ').single.group, 'schedule');
      expect(searchEvent(event, 'အပြင်မှ').single.group, 'faq');
      expect(searchEvent(event, 'အဓိက').single.group, 'lineup');
      final p = searchEvent(event, 'ကားပါကင်').single;
      expect((p.group, p.index, p.title), ('info', 2, 'Parking'));
    });
    test('English query finds practical info and performer role', () {
      expect(searchEvent(event, 'smart').single.group, 'info');
      expect(searchEvent(event, 'singer').single.group, 'lineup');
    });
    test('title follows the language', () {
      expect(searchEvent(event, 'ဖွင့်ပွဲ', lang: 'my').single.title, 'ဖွင့်ပွဲ');
      expect(searchEvent(event, 'ceremony').single.snippet, contains('Ceremony'));
    });
    test('no match', () => expect(searchEvent(event, 'zzz'), isEmpty));
  });
}
