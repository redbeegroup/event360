import 'package:event360_ui/event360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> section(String key, double x) => {
      'key': key,
      'name': key,
      'kind': 'SEATED',
      'x': x,
      'y': 40,
      'rows': [
        {
          'label': '1',
          'seats': [for (var n = 1; n <= 5; n++) {'n': n}],
        },
        {
          'label': '2',
          'seats': [for (var n = 1; n <= 5; n++) {'n': n}],
        },
      ],
    };

SeatLayout twoSections() => SeatLayout.fromJson({
      'width': 1000,
      'height': 400,
      'sections': [section('A', 100), section('B', 700)],
    });

void main() {
  late SeatLayout layout;
  late SeatMapViewController ctl;
  late List<int> taps;
  late List<double> scales;

  setUp(() {
    layout = twoSections();
    ctl = SeatMapViewController();
    taps = [];
    scales = [];
  });

  Future<void> pump(WidgetTester tester, {Set<int> selected = const {}}) => tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 390,
            height: 500,
            child: SeatMapView(
              layout: layout,
              states: List.filled(layout.seats.length, SeatState.available),
              colors: List.filled(layout.seats.length, Colors.blue),
              selected: selected,
              controller: ctl,
              onSeatTap: taps.add,
              onScaleChanged: scales.add,
            ),
          ),
        ),
      ));

  /// Screen position of a layout point, via the map's own transform.
  Offset screenOf(WidgetTester tester, Offset p) {
    final box = tester.renderObject<RenderBox>(find.byKey(const Key('seatMap')));
    return box.localToGlobal(p);
  }

  testWidgets('first frame fits the whole map inside the viewport', (tester) async {
    await pump(tester);
    final rect = tester.getRect(find.byKey(const Key('seatMap')));
    final view = tester.getRect(find.byType(SeatMapView));
    expect(rect.width, closeTo(390, 0.01));
    expect(rect.height, closeTo(156, 0.01));
    expect(rect.left, greaterThanOrEqualTo(view.left - 0.01));
    expect(rect.right, lessThanOrEqualTo(view.right + 0.01));
    expect(rect.top, greaterThanOrEqualTo(view.top));
    expect(rect.bottom, lessThanOrEqualTo(view.bottom));
    expect(ctl.scale, closeTo(390 / 1000, 1e-6));
    expect(ctl.scale, lessThan(kSeatTapScale));
  });

  testWidgets('tap while zoomed out zooms to the section and does not call onSeatTap', (tester) async {
    await pump(tester);
    await tester.tapAt(screenOf(tester, layout.seats.first.pos));
    await tester.pumpAndSettle();
    expect(taps, isEmpty);
    expect(ctl.scale, greaterThanOrEqualTo(kSeatTapScale));
    expect(scales, isNotEmpty);
    expect(scales.last, ctl.scale);
  });

  testWidgets('after zoomTo a tap on a seat centre calls onSeatTap with its index', (tester) async {
    await pump(tester);
    ctl.zoomTo(layout.sections.first.bounds);
    await tester.pumpAndSettle();
    expect(ctl.scale, greaterThanOrEqualTo(kSeatTapScale));
    final seat = layout.seats[6];
    await tester.tapAt(screenOf(tester, seat.pos));
    await tester.pump();
    expect(taps, [6]);
  });

  testWidgets('fit() returns to the whole map', (tester) async {
    await pump(tester);
    ctl.zoomTo(layout.sections.first.bounds);
    await tester.pumpAndSettle();
    ctl.fit();
    await tester.pump();
    expect(ctl.scale, closeTo(390 / 1000, 1e-6));
  });

  testWidgets('selected seats repaint', (tester) async {
    await pump(tester);
    CustomPaint paint() => tester.widget<CustomPaint>(find.descendant(of: find.byKey(const Key('seatMap')), matching: find.byType(CustomPaint)));
    final before = paint().painter! as SeatMapPainter;
    await pump(tester, selected: {3});
    final after = paint().painter! as SeatMapPainter;
    expect(after.shouldRepaint(before), isTrue);
    expect(after.selected, {3});
  });

  testWidgets('viewport size change leaves the camera where it is', (tester) async {
    Widget app(double w) => MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: w,
              height: 500,
              child: SeatMapView(
                layout: layout,
                states: List.filled(layout.seats.length, SeatState.available),
                colors: List.filled(layout.seats.length, Colors.blue),
                controller: ctl,
              ),
            ),
          ),
        );
    await tester.pumpWidget(app(390));
    ctl.zoomTo(layout.sections.first.bounds);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byKey(const Key('seatMap')));
    final scale = ctl.scale;
    await tester.pumpWidget(app(300));
    await tester.pumpAndSettle();
    expect(ctl.scale, scale);
    expect(tester.getTopLeft(find.byKey(const Key('seatMap'))), before);
  });

  testWidgets('onScaleChanged reports after a zoom', (tester) async {
    await pump(tester);
    expect(scales, isEmpty);
    ctl.zoomTo(layout.sections.first.bounds);
    await tester.pumpAndSettle();
    expect(scales, isNotEmpty);
    expect(scales.last, closeTo(ctl.scale, 1e-9));
    expect(scales.last, greaterThanOrEqualTo(kSeatTapScale));
  });

  testWidgets('overlay sees the fit scale on the first frame', (tester) async {
    final tiny = SeatLayout.fromJson({
      'width': 100,
      'height': 100,
      'sections': [section('A', 10)],
    });
    final seen = <double>[];
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 390,
        height: 500,
        child: SeatMapView(
          layout: tiny,
          states: List.filled(tiny.seats.length, SeatState.available),
          colors: List.filled(tiny.seats.length, Colors.blue),
          overlayBuilder: (context, scale) {
            seen.add(scale);
            return const SizedBox.shrink();
          },
        ),
      ),
    ));
    expect(seen, isNotEmpty);
    expect(seen.every((s) => s >= kSeatTapScale), isTrue, reason: '$seen');
  });

  testWidgets('extraBoundary at the bottom lets the content be panned further up', (tester) async {
    Future<double> lowestEdge(EdgeInsets extra) async {
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 390,
            height: 500,
            child: SeatMapView(
              layout: layout,
              states: List.filled(layout.seats.length, SeatState.available),
              colors: List.filled(layout.seats.length, Colors.blue),
              controller: ctl,
              extraBoundary: extra,
            ),
          ),
        ),
      ));
      ctl.zoomTo(layout.sections.first.bounds);
      await tester.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        await tester.dragFrom(const Offset(195, 400), const Offset(0, -150));
        await tester.pumpAndSettle();
      }
      return tester.getBottomLeft(find.byKey(const Key('seatMap'))).dy;
    }

    final plain = await lowestEdge(EdgeInsets.zero);
    final padded = await lowestEdge(const EdgeInsets.only(bottom: 100));
    expect(padded, closeTo(plain - 100 * ctl.scale, 1.0), reason: "plain $plain padded $padded scale ${ctl.scale}");
  });
}
