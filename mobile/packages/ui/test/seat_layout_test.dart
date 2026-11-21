import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:event360_ui/event360_ui.dart';
import 'package:flutter_test/flutter_test.dart';

SeatLayout theatre() => SeatLayout.fromJson(jsonDecode(File('test/fixtures/theatre.json').readAsStringSync()) as Map<String, dynamic>);

void main() {
  // Expected values computed with expandSeats from apps/api/src/modules/seating/layout.ts on the same fixture.
  group('expandSeats parity with the API', () {
    final l = theatre();
    test('1,200 seats in API order', () {
      expect(l.seats.length, 1200);
      expect(l.seats.first.seatKey, 'S:1:1');
      expect(l.seats.last.seatKey, 'BR:10:20');
    });
    test('positions match the TypeScript output', () {
      void at(int i, String key, double x, double y) {
        expect(l.seats[i].seatKey, key);
        expect(l.seats[i].pos.dx, closeTo(x, 1e-9), reason: key);
        expect(l.seats[i].pos.dy, closeTo(y, 1e-9), reason: key);
      }

      at(0, 'S:1:1', 220, 232);
      at(1, 'S:1:2', 244, 224.98);
      at(7, 'S:1:8', 388, 190.42000000000002);
      at(100, 'S:3:21', 724, 208.18);
      at(600, 'S:16:1', 220, 592);
      at(1000, 'BR:1:1', 1000, 334.2);
      at(1199, 'BR:10:20', 1456, 550.2);
    });
    test('labels in English and Myanmar', () {
      expect(l.seats[0].label, 'Stalls · Row 1 · Seat 1');
      expect(l.seats[0].labelMy, 'ရှေ့ခန်း · အတန်း 1 · ခုံ 1');
      expect(l.seats[1000].labelFor('my'), 'ဘောလ်ကနီ ညာ · အတန်း 1 · ခုံ 1');
      expect(l.seats[1000].labelFor('en'), 'Balcony Right · Row 1 · Seat 1');
    });
    test('an empty Myanmar section name falls back to the English name', () {
      final l = SeatLayout.fromJson({
        'width': 400,
        'height': 300,
        'sections': [
          {'key': 'A', 'name': 'Stalls', 'nameMy': '', 'kind': 'SEATED', 'x': 0, 'y': 0, 'rows': [{'label': '1', 'seats': [{'n': 1}]}]},
        ],
      });
      expect(l.seats.single.labelMy, 'Stalls · အတန်း 1 · ခုံ 1');
    });
    test('seat keys are unique', () {
      expect(l.seats.map((s) => s.seatKey).toSet().length, 1200);
    });
  });

  group('hit testing', () {
    final l = theatre();
    test('seatAt finds the seat under a point and null in empty space', () {
      expect(l.seatAt(const Offset(220, 232))?.seatKey, 'S:1:1');
      expect(l.seatAt(const Offset(223, 234))?.seatKey, 'S:1:1');
      expect(l.seatAt(const Offset(244, 224.98))?.seatKey, 'S:1:2');
      expect(l.seatAt(const Offset(1456, 550.2))?.seatKey, 'BR:10:20');
      expect(l.seatAt(const Offset(10, 990)), isNull);
      // Between two seats 24 apart, further than the radius from either
      expect(l.seatAt(const Offset(232, 229), slop: 0), isNull);
    });
    test('sectionAt returns the section a point is in', () {
      expect(l.sectionAt(const Offset(220, 232))?.key, 'S');
      expect(l.sectionAt(const Offset(1100, 400))?.key, 'BR');
      expect(l.sectionAt(const Offset(5, 5)), isNull);
    });
    test('standing sections hit inside their rectangle', () {
      final s = SeatLayout.fromJson({
        'width': 500,
        'height': 400,
        'sections': [
          {'key': 'F', 'name': 'Floor', 'kind': 'STANDING', 'x': 100, 'y': 100, 'w': 200, 'h': 80, 'capacity': 300},
        ],
      });
      expect(s.seats, isEmpty);
      expect(s.sectionAt(const Offset(150, 140))?.key, 'F');
      expect(s.sectionAt(const Offset(150, 200)), isNull);
    });
  });

  test('seat type chars and colours', () {
    expect(seatTypeIndex('0'), 0);
    expect(seatTypeIndex('a'), 10);
    expect(seatTypeIndex('Z'), 61);
    expect(seatTypeIndex('-'), isNull);
    expect(parseHexColor('#f2b632'), const Color(0xFFF2B632));
    expect(parseHexColor('nope'), isNull);
    expect(SeatState.fromChar('A'), SeatState.available);
    expect(SeatState.fromChar('G'), SeatState.held);
    expect(SeatState.fromChar('U'), SeatState.unavailable);
  });
}
