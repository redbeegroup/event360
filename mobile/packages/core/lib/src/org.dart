/// Organizer-side models (organizer app).
library;

DateTime _dt(Object? v) => DateTime.parse(v as String).toUtc();
DateTime? _dtn(Object? v) => v == null ? null : _dt(v);
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

class OrgMembership {
  OrgMembership({required this.id, required this.name, required this.slug, required this.role, required this.kycStatus});
  final String id;
  final String name;
  final String slug;
  final String role; // ORG_OWNER | ORG_MANAGER | ORG_FINANCE | CREW
  final String kycStatus;

  /// Owners and managers can change things; finance can only look.
  bool get canEdit => role == 'ORG_OWNER' || role == 'ORG_MANAGER';
  bool get canView => canEdit || role == 'ORG_FINANCE';

  factory OrgMembership.fromJson(Map<String, dynamic> j) => OrgMembership(
        id: j['id'] as String,
        name: j['name'] as String,
        slug: j['slug'] as String,
        role: j['role'] as String,
        kycStatus: j['kycStatus'] as String? ?? 'NOT_SUBMITTED',
      );
}

class OrgEvent {
  OrgEvent({required this.id, required this.slug, required this.title, this.titleMy, required this.status, required this.startsAt, required this.endsAt, this.coverImageUrl, this.venue});
  final String id;
  final String slug;
  final String title;
  final String? titleMy;
  final String status; // DRAFT | SUBMITTED | PUBLISHED | ONGOING | COMPLETED | CANCELLED | REJECTED
  final DateTime startsAt;
  final DateTime endsAt;
  final String? coverImageUrl;
  final String? venue;

  bool get isPast => endsAt.isBefore(DateTime.now().toUtc());
  bool get isLiveNow => !isPast && startsAt.isBefore(DateTime.now().toUtc());

  factory OrgEvent.fromJson(Map<String, dynamic> j) => OrgEvent(
        id: j['id'] as String,
        slug: j['slug'] as String,
        title: j['title'] as String,
        titleMy: j['titleMy'] as String?,
        status: j['status'] as String,
        startsAt: _dt(j['startsAt']),
        endsAt: _dt(j['endsAt']),
        coverImageUrl: j['coverImageUrl'] as String?,
        venue: (j['venue'] as Map<String, dynamic>?)?['name'] as String?,
      );
}

class DashboardTotals {
  DashboardTotals({required this.views, required this.orders, required this.ticketsSold, required this.capacity, required this.revenueMmk, required this.discountMmk, required this.checkedIn, this.conversion});
  final int views, orders, ticketsSold, capacity, revenueMmk, discountMmk, checkedIn;
  final double? conversion;
  factory DashboardTotals.fromJson(Map<String, dynamic> j) => DashboardTotals(
        views: _i(j['views']),
        orders: _i(j['orders']),
        ticketsSold: _i(j['ticketsSold']),
        capacity: _i(j['capacity']),
        revenueMmk: _i(j['revenueMmk']),
        discountMmk: _i(j['discountMmk']),
        checkedIn: _i(j['checkedIn']),
        conversion: (j['conversion'] as num?)?.toDouble(),
      );
}

/// Seat counts for one ticket type of a seated event.
class SeatCounts {
  const SeatCounts({required this.available, required this.held, required this.guest, required this.sold, required this.comp});
  final int available, held, guest, sold, comp;
  factory SeatCounts.fromJson(Map<String, dynamic> j) =>
      SeatCounts(available: _i(j['available']), held: _i(j['held']), guest: _i(j['guest']), sold: _i(j['sold']), comp: _i(j['comp']));
}

class EventDashboard {
  EventDashboard({required this.totals, required this.ticketTypes, required this.byGate, required this.daily});
  final DashboardTotals totals;
  final List<({String name, int sold, int quota, int priceMmk, SeatCounts? seats})> ticketTypes;

  /// Seat totals across ticket types; null for unseated events.
  SeatCounts? get seatTotals {
    final all = [for (final t in ticketTypes) if (t.seats != null) t.seats!];
    if (all.isEmpty) return null;
    int sum(int Function(SeatCounts) f) => all.fold(0, (a, c) => a + f(c));
    return SeatCounts(available: sum((c) => c.available), held: sum((c) => c.held), guest: sum((c) => c.guest), sold: sum((c) => c.sold), comp: sum((c) => c.comp));
  }
  final List<({String gate, int count})> byGate;
  final List<({String day, int orders, int revenueMmk})> daily;
  factory EventDashboard.fromJson(Map<String, dynamic> j) => EventDashboard(
        totals: DashboardTotals.fromJson(j['totals'] as Map<String, dynamic>),
        ticketTypes: [
          for (final t in (j['ticketTypes'] as List).cast<Map<String, dynamic>>()) (name: t['name'] as String, sold: _i(t['sold']), quota: _i(t['quota']), priceMmk: _i(t['priceMmk']), seats: t['seats'] == null ? null : SeatCounts.fromJson(t['seats'] as Map<String, dynamic>)),
        ],
        byGate: [for (final g in (j['checkinsByGate'] as List).cast<Map<String, dynamic>>()) (gate: g['gate'] as String, count: _i(g['count']))],
        daily: [for (final d in (j['daily'] as List).cast<Map<String, dynamic>>()) (day: d['day'] as String, orders: _i(d['orders']), revenueMmk: _i(d['revenueMmk']))],
      );
}

class RecentOrder {
  RecentOrder({required this.id, required this.status, required this.createdAt, required this.totalMmk, required this.quantity, this.buyer});
  final String id, status;
  final DateTime createdAt;
  final int totalMmk, quantity;
  final String? buyer;
  factory RecentOrder.fromJson(Map<String, dynamic> j) => RecentOrder(
        id: j['id'] as String,
        status: j['status'] as String,
        createdAt: _dt(j['createdAt']),
        totalMmk: _i(j['totalMmk']),
        quantity: _i(j['quantity']),
        buyer: j['buyer'] as String?,
      );
}

class CrewCode {
  CrewCode({required this.id, required this.label, this.gate, required this.expiresAt, this.revokedAt, this.devices = 0, this.active = true, this.code, this.redeemUri});
  final String id, label;
  final String? gate;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final int devices;
  final bool active;

  /// Only returned when the code is created (stored hashed).
  final String? code;
  final String? redeemUri;

  factory CrewCode.fromJson(Map<String, dynamic> j) => CrewCode(
        id: j['id'] as String,
        label: j['label'] as String,
        gate: j['gate'] as String?,
        expiresAt: _dt(j['expiresAt']),
        revokedAt: _dtn(j['revokedAt']),
        devices: _i(j['devices']),
        active: j['active'] as bool? ?? true,
        code: j['code'] as String?,
        redeemUri: j['redeemUri'] as String?,
      );
}

class AnnouncementItem {
  AnnouncementItem({required this.id, required this.title, this.titleMy, required this.body, this.bodyMy, required this.recipients, required this.createdAt});
  final String id, title, body;
  final String? titleMy, bodyMy;
  final int recipients;
  final DateTime createdAt;
  factory AnnouncementItem.fromJson(Map<String, dynamic> j) => AnnouncementItem(
        id: j['id'] as String,
        title: j['title'] as String,
        titleMy: j['titleMy'] as String?,
        body: j['body'] as String,
        bodyMy: j['bodyMy'] as String?,
        recipients: _i(j['recipients']),
        createdAt: _dt(j['createdAt']),
      );
}

class Announcements {
  Announcements({required this.items, required this.ticketHolders, required this.remainingToday});
  final List<AnnouncementItem> items;
  final int ticketHolders, remainingToday;
  factory Announcements.fromJson(Map<String, dynamic> j) => Announcements(
        items: (j['items'] as List).map((x) => AnnouncementItem.fromJson(x as Map<String, dynamic>)).toList(),
        ticketHolders: _i(j['ticketHolders']),
        remainingToday: _i(j['remainingToday']),
      );
}

class PromoCodeInfo {
  PromoCodeInfo({required this.id, required this.code, required this.kind, required this.value, this.maxUses, required this.used, this.endsAt, required this.isActive, required this.orders, required this.discountGivenMmk});
  final String id, code, kind; // PERCENT | FIXED
  final int value; // percent (whole) or MMK
  final int? maxUses;
  final int used, orders, discountGivenMmk;
  final DateTime? endsAt;
  final bool isActive;
  factory PromoCodeInfo.fromJson(Map<String, dynamic> j) => PromoCodeInfo(
        id: j['id'] as String,
        code: j['code'] as String,
        kind: j['kind'] as String,
        value: (j['value'] as num).round(),
        maxUses: (j['maxUses'] as num?)?.toInt(),
        used: _i(j['used']),
        endsAt: _dtn(j['endsAt']),
        isActive: j['isActive'] as bool,
        orders: _i(j['orders']),
        discountGivenMmk: _i(j['discountGivenMmk']),
      );
}
