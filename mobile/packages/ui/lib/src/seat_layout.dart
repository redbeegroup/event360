/// Seat map geometry: a Dart mirror of `expandSeats` in apps/api/src/modules/seating/layout.ts.
/// Keep both in step; the test fixture asserts they agree seat for seat.
library;

import 'dart:math' as math;
import 'dart:ui';

/// Layout units between seats and rows (same as the API).
const double kSeatSpacing = 24;

/// Drawn seat radius in layout units.
const double kSeatRadius = 9;

enum SeatAttr { restrictedView, wheelchair }

class MapSeat {
  const MapSeat({
    required this.index,
    required this.seatKey,
    required this.sectionKey,
    required this.rowLabel,
    required this.seatLabel,
    required this.label,
    required this.labelMy,
    required this.pos,
    required this.attrs,
  });

  /// Position in expandSeats order, which is also the index into the API's `seatTypes` / `status` strings.
  final int index;
  final String seatKey;
  final String sectionKey;
  final String rowLabel;
  final String seatLabel;
  final String label;
  final String labelMy;
  final Offset pos;
  final Set<SeatAttr> attrs;

  String labelFor(String lang) => lang == 'my' ? labelMy : label;
}

class MapSection {
  const MapSection({
    required this.key,
    required this.name,
    this.nameMy,
    required this.standing,
    required this.x,
    required this.y,
    required this.rotation,
    required this.capacity,
    required this.width,
    required this.height,
    required this.bounds,
  });

  final String key;
  final String name;
  final String? nameMy;
  final bool standing;
  final double x;
  final double y;

  /// Degrees. Only used by standing rectangles (seated sections are already rotated into the seat positions).
  final double rotation;
  final int? capacity;

  /// Standing rectangle size.
  final double width;
  final double height;

  /// Axis-aligned box around the whole section (seats inflated by the seat radius), in layout units.
  final Rect bounds;

  String nameFor(String lang) => (lang == 'my' && nameMy != null && nameMy!.isNotEmpty) ? nameMy! : name;
}

class MapStage {
  const MapStage({required this.rect, this.label});
  final Rect rect;
  final String? label;
}

class SeatLayout {
  SeatLayout._(this.width, this.height, this.stage, this.sections, this.seats) {
    for (final s in seats) {
      _grid.putIfAbsent(_cell(s.pos), () => []).add(s.index);
    }
    for (final s in seats) {
      _byKey[s.seatKey] = s;
    }
  }

  final double width;
  final double height;
  final MapStage? stage;
  final List<MapSection> sections;

  /// Seated sections only, in layout order (same order as the API's strings).
  final List<MapSeat> seats;

  final Map<(int, int), List<int>> _grid = {};
  final Map<String, MapSeat> _byKey = {};

  static (int, int) _cell(Offset p) => ((p.dx / kSeatSpacing).floor(), (p.dy / kSeatSpacing).floor());

  MapSeat? seatByKey(String key) => _byKey[key];

  /// Seat under [p] (layout units), or null. [slop] widens the target beyond the drawn radius for fingers.
  /// When two seats overlap the nearer one wins.
  MapSeat? seatAt(Offset p, {double slop = 3}) {
    final reach = kSeatRadius + slop;
    final (cx, cy) = _cell(p);
    MapSeat? best;
    var bestD = double.infinity;
    for (var gx = cx - 1; gx <= cx + 1; gx++) {
      for (var gy = cy - 1; gy <= cy + 1; gy++) {
        for (final i in _grid[(gx, gy)] ?? const <int>[]) {
          final d = (seats[i].pos - p).distance;
          if (d <= reach && d < bestD) {
            best = seats[i];
            bestD = d;
          }
        }
      }
    }
    return best;
  }

  /// Section under [p] (layout units), or null. Standing sections are hit inside their (rotated) rectangle,
  /// seated ones inside their padded bounds. Later sections win where two overlap.
  MapSection? sectionAt(Offset p) {
    for (final s in sections.reversed) {
      if (s.standing) {
        final rad = -s.rotation * math.pi / 180;
        final d = p - Offset(s.x, s.y);
        final lx = d.dx * math.cos(rad) - d.dy * math.sin(rad);
        final ly = d.dx * math.sin(rad) + d.dy * math.cos(rad);
        if (lx >= 0 && lx <= s.width && ly >= 0 && ly <= s.height) return s;
      } else if (s.bounds.inflate(kSeatSpacing / 2 - kSeatRadius).contains(p)) {
        return s;
      }
    }
    return null;
  }

  MapSection? sectionByKey(String key) {
    for (final s in sections) {
      if (s.key == key) return s;
    }
    return null;
  }

  factory SeatLayout.fromJson(Map<String, dynamic> j) {
    double n(Object? v, [double d = 0]) => v is num ? v.toDouble() : d;
    final seats = <MapSeat>[];
    final sections = <MapSection>[];
    for (final raw in (j['sections'] as List? ?? const [])) {
      final sec = raw as Map<String, dynamic>;
      final key = sec['key'] as String;
      final name = sec['name'] as String;
      final standing = sec['kind'] == 'STANDING';
      final sx = n(sec['x']);
      final sy = n(sec['y']);
      final rotation = n(sec['rotation']);
      if (standing) {
        final w = n(sec['w'], 200);
        final h = n(sec['h'], 100);
        final rad = rotation * math.pi / 180;
        final corners = [
          for (final c in [Offset.zero, Offset(w, 0), Offset(w, h), Offset(0, h)])
            Offset(sx + c.dx * math.cos(rad) - c.dy * math.sin(rad), sy + c.dx * math.sin(rad) + c.dy * math.cos(rad)),
        ];
        sections.add(MapSection(
          key: key,
          name: name,
          nameMy: sec['nameMy'] as String?,
          standing: true,
          x: sx,
          y: sy,
          rotation: rotation,
          capacity: (sec['capacity'] as num?)?.toInt(),
          width: w,
          height: h,
          bounds: _boundsOf(corners),
        ));
        continue;
      }
      final first = seats.length;
      final rad = rotation * math.pi / 180;
      final cosR = math.cos(rad);
      final sinR = math.sin(rad);
      final curve = n(sec['curve']);
      final rows = (sec['rows'] as List? ?? const []);
      for (var ri = 0; ri < rows.length; ri++) {
        final row = rows[ri] as Map<String, dynamic>;
        final rowLabel = row['label'] as String;
        final rs = (row['seats'] as List).cast<Map<String, dynamic>>();
        var col = 0.0;
        final xs = <double>[];
        for (var i = 0; i < rs.length; i++) {
          final gap = n(rs[i]['gapBefore']);
          col += i == 0 ? gap : 1 + gap;
          xs.add(col * kSeatSpacing);
        }
        final minX = xs.reduce(math.min);
        final maxX = xs.reduce(math.max);
        final centre = (minX + maxX) / 2;
        var half = (maxX - minX) / 2;
        if (half == 0) half = 1; // TS: `|| 1`
        for (var i = 0; i < rs.length; i++) {
          final s = rs[i];
          final lx = xs[i] + n(s['dx']);
          final t = (xs[i] - centre) / half;
          final ly = ri * kSeatSpacing + curve * half * t * t + n(s['dy']);
          final seatLabel = (s['label'] as String?) ?? '${(s['n'] as num).toString().replaceAll(RegExp(r'\.0$'), '')}';
          final nameMy = (sec['nameMy'] as String?) ?? name;
          seats.add(MapSeat(
            index: seats.length,
            seatKey: '$key:$rowLabel:$seatLabel',
            sectionKey: key,
            rowLabel: rowLabel,
            seatLabel: seatLabel,
            label: '$name · Row $rowLabel · Seat $seatLabel',
            labelMy: '$nameMy · အတန်း $rowLabel · ခုံ $seatLabel',
            pos: Offset(sx + lx * cosR - ly * sinR, sy + lx * sinR + ly * cosR),
            attrs: {
              for (final a in (s['attrs'] as List? ?? const []))
                if (a == 'RESTRICTED_VIEW') SeatAttr.restrictedView else if (a == 'WHEELCHAIR') SeatAttr.wheelchair,
            },
          ));
        }
      }
      sections.add(MapSection(
        key: key,
        name: name,
        nameMy: sec['nameMy'] as String?,
        standing: false,
        x: sx,
        y: sy,
        rotation: rotation,
        capacity: null,
        width: 0,
        height: 0,
        bounds: seats.length > first ? _boundsOf([for (final s in seats.skip(first)) s.pos]).inflate(kSeatRadius) : Rect.fromLTWH(sx, sy, 0, 0),
      ));
    }
    final st = j['stage'] as Map<String, dynamic>?;
    return SeatLayout._(
      n(j['width'], 1),
      n(j['height'], 1),
      st == null ? null : MapStage(rect: Rect.fromLTWH(n(st['x']), n(st['y']), n(st['w']), n(st['h'])), label: st['label'] as String?),
      sections,
      seats,
    );
  }

  static Rect _boundsOf(List<Offset> pts) {
    var l = pts.first.dx, r = l, t = pts.first.dy, b = t;
    for (final p in pts) {
      l = math.min(l, p.dx);
      r = math.max(r, p.dx);
      t = math.min(t, p.dy);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }
}

/// What the API's availability letter means.
enum SeatState {
  available,

  /// Sold or in someone's checkout (API 'T').
  taken,

  /// Held for guests (API 'G').
  held,

  /// No ticket type assigned (API 'U').
  unavailable;

  static SeatState fromChar(String c) => switch (c) {
        'A' => available,
        'T' => taken,
        'G' => held,
        _ => unavailable,
      };
}

const _typeChars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// Index into the API's ticket type list for a `seatTypes` character, or null for '-' (no type).
int? seatTypeIndex(String c) {
  final i = _typeChars.indexOf(c);
  return i < 0 ? null : i;
}

/// Parses `#rrggbb` (as the API sends ticket type colours); null when it is not a colour.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  return m == null ? null : Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}
