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

  /// Payouts are money owed to the organization: owners and finance only.
  bool get canSeePayouts => role == 'ORG_OWNER' || role == 'ORG_FINANCE';

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
  const SeatCounts({required this.available, required this.held, required this.guest, required this.sold, required this.comp, this.offered = 0});
  final int available, held, guest, sold, comp;

  /// Seats held for a live waitlist offer.
  final int offered;
  factory SeatCounts.fromJson(Map<String, dynamic> j) => SeatCounts(
      available: _i(j['available']), held: _i(j['held']), guest: _i(j['guest']), sold: _i(j['sold']), comp: _i(j['comp']), offered: _i(j['offered']));
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
    return SeatCounts(available: sum((c) => c.available), held: sum((c) => c.held), guest: sum((c) => c.guest), sold: sum((c) => c.sold), comp: sum((c) => c.comp), offered: sum((c) => c.offered));
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

/// One ticket on an event's attendee list.
class Attendee {
  Attendee({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.isComplimentary,
    required this.ticketTypeName,
    this.seatLabel,
    this.seatLabelMy,
    this.guestName,
    this.holderName,
    this.phone,
  });
  final String id, status;
  final DateTime createdAt;
  final String? seatLabel, seatLabelMy, guestName, holderName, phone;
  final bool isComplimentary;
  final String ticketTypeName;

  /// The holder's name, else the guest's, else the phone number, else ''.
  String get displayName {
    for (final v in [holderName, guestName, phone]) {
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  bool get isIn => status == 'CHECKED_IN';
  bool get isValid => status == 'VALID';
  bool get isDead => !isIn && !isValid;

  factory Attendee.fromJson(Map<String, dynamic> j) {
    final holder = j['holder'] as Map<String, dynamic>?;
    return Attendee(
      id: j['id'] as String,
      status: j['status'] as String,
      createdAt: _dt(j['createdAt']),
      seatLabel: j['seatLabel'] as String?,
      seatLabelMy: j['seatLabelMy'] as String?,
      isComplimentary: j['isComplimentary'] == true,
      guestName: j['guestName'] as String?,
      holderName: holder?['displayName'] as String?,
      phone: holder?['phone'] as String?,
      ticketTypeName: (j['ticketType'] as Map<String, dynamic>?)?['name'] as String? ?? '',
    );
  }
}

/// One seat of an event's seat map, organizer view.
class OrgSeat {
  const OrgSeat({required this.seatKey, required this.status, this.ticketTypeId, this.holdLabel});

  /// AVAILABLE | CHECKOUT_HOLD | WAITLIST_HOLD | GUEST_HOLD | SOLD | UNSOLD
  final String seatKey, status;
  final String? ticketTypeId, holdLabel;
  factory OrgSeat.fromJson(Map<String, dynamic> j) => OrgSeat(
        seatKey: j['seatKey'] as String,
        status: j['status'] as String,
        ticketTypeId: j['ticketTypeId'] as String?,
        holdLabel: j['holdLabel'] as String?,
      );
}

/// Seat map, seat states and per-type counts of an event (organizer view).
class OrgSeating {
  const OrgSeating({required this.layout, required this.seats, required this.colors, required this.counts});
  final Map<String, dynamic>? layout;
  final List<OrgSeat> seats;

  /// Ticket type id -> '#rrggbb'.
  final Map<String, String> colors;
  final Map<String, SeatCounts> counts;
  bool get hasMap => layout != null;

  factory OrgSeating.fromJson(Map<String, dynamic> j) => OrgSeating(
        layout: j['layout'] as Map<String, dynamic>?,
        seats: [for (final s in (j['seats'] as List? ?? const []).cast<Map<String, dynamic>>()) OrgSeat.fromJson(s)],
        colors: {for (final e in ((j['colors'] as Map?) ?? const {}).entries) e.key as String: e.value as String},
        counts: {for (final e in ((j['counts'] as Map?) ?? const {}).entries) e.key as String: SeatCounts.fromJson(e.value as Map<String, dynamic>)},
      );
}

/// A complimentary guest ticket (phone is masked by the server).
class GuestTicket {
  const GuestTicket({
    required this.id,
    required this.guestName,
    required this.phone,
    required this.seatKey,
    required this.status,
    required this.checkedIn,
    this.seatLabel,
    this.seatLabelMy,
    this.label,
  });
  final String id, guestName, phone, seatKey, status;
  final String? seatLabel, seatLabelMy, label;
  final bool checkedIn;
  bool get canRevoke => status == 'VALID' && !checkedIn;

  factory GuestTicket.fromJson(Map<String, dynamic> j) => GuestTicket(
        id: j['id'] as String,
        guestName: j['guestName'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        seatKey: j['seatKey'] as String? ?? '',
        status: j['status'] as String,
        checkedIn: j['checkedIn'] == true,
        seatLabel: j['seatLabel'] as String?,
        seatLabelMy: j['seatLabelMy'] as String?,
        label: j['label'] as String?,
      );
}

class WaitlistTypeCount {
  const WaitlistTypeCount({required this.id, required this.name, required this.waiting, required this.offered, this.nameMy});
  final String id, name;
  final String? nameMy;
  final int waiting, offered;
  factory WaitlistTypeCount.fromJson(Map<String, dynamic> j) => WaitlistTypeCount(
        id: j['id'] as String,
        name: j['name'] as String,
        nameMy: j['nameMy'] as String?,
        waiting: _i(j['waiting']),
        offered: _i(j['offered']),
      );
}

/// Waitlist size per ticket type of an event.
class WaitlistCounts {
  const WaitlistCounts({required this.types, required this.total});
  final List<WaitlistTypeCount> types;
  final int total;
  factory WaitlistCounts.fromJson(Map<String, dynamic> j) => WaitlistCounts(
        types: [for (final t in (j['ticketTypes'] as List? ?? const []).cast<Map<String, dynamic>>()) WaitlistTypeCount.fromJson(t)],
        total: _i(j['total']),
      );
}

/// Thrown by hold/release/comps on HTTP 409 carrying `takenSeats`: those seats changed under the organizer.
class SeatsChanged implements Exception {
  const SeatsChanged(this.message, this.takenSeats, {this.reasonCode});
  final String message;
  final List<String> takenSeats;

  /// The machine-readable reason from the error body (e.g. `SEATS_NOT_AVAILABLE`), when the server sent one.
  final String? reasonCode;

  @override
  String toString() => message;
}

class SalesTicketType {
  SalesTicketType({required this.id, required this.name, this.nameMy, required this.priceMmk, required this.basePriceMmk, this.nextPriceMmk, this.nextPriceAt, required this.quota, required this.sold, required this.revenueMmk});
  final String id, name;

  /// Myanmar name; null when the organizer did not set one.
  final String? nameMy;
  final int priceMmk, basePriceMmk, quota, sold, revenueMmk;
  final int? nextPriceMmk;
  final DateTime? nextPriceAt;
  factory SalesTicketType.fromJson(Map<String, dynamic> j) {
    final next = j['nextPrice'] as Map<String, dynamic>?;
    return SalesTicketType(
      id: j['id'] as String,
      name: j['name'] as String,
      nameMy: j['nameMy'] as String?,
      priceMmk: _i(j['priceMmk']),
      basePriceMmk: _i(j['basePriceMmk']),
      nextPriceMmk: next == null ? null : _i(next['priceMmk']),
      nextPriceAt: next == null ? null : _dtn(next['startsAt']),
      quota: _i(j['quota']),
      sold: _i(j['sold']),
      revenueMmk: _i(j['revenueMmk']),
    );
  }
}

class EventSales {
  EventSales({required this.types, required this.paidOrders, required this.grossMmk, required this.commissionMmk, required this.netMmk, required this.refundedOrders, required this.refundedMmk});
  final List<SalesTicketType> types;
  final int paidOrders, grossMmk, commissionMmk, netMmk, refundedOrders, refundedMmk;

  /// False for a free event, where money figures are not worth showing.
  bool get hasPaidTypes => types.any((t) => t.priceMmk > 0 || t.basePriceMmk > 0);

  factory EventSales.fromJson(Map<String, dynamic> j) => EventSales(
        types: [for (final t in (j['ticketTypes'] as List? ?? const []).cast<Map<String, dynamic>>()) SalesTicketType.fromJson(t)],
        paidOrders: _i(j['paidOrders']),
        grossMmk: _i(j['grossMmk']),
        commissionMmk: _i(j['commissionMmk']),
        netMmk: _i(j['netMmk']),
        refundedOrders: _i(j['refundedOrders']),
        refundedMmk: _i(j['refundedMmk']),
      );
}

class OrgOrderRow {
  OrgOrderRow({required this.id, required this.number, required this.status, required this.needsReview, required this.createdAt, this.paidAt, this.holdExpiresAt, required this.totalMmk, required this.discountMmk, required this.quantity, this.buyerName, this.buyerPhone});
  final String id, number, status;
  final bool needsReview;
  final DateTime createdAt;
  final DateTime? paidAt, holdExpiresAt;
  final int totalMmk, discountMmk, quantity;
  final String? buyerName, buyerPhone;
  factory OrgOrderRow.fromJson(Map<String, dynamic> j) {
    final b = j['buyer'] as Map<String, dynamic>? ?? const {};
    return OrgOrderRow(
      id: j['id'] as String,
      number: j['number'] as String? ?? '',
      status: j['status'] as String,
      needsReview: j['needsReview'] as bool? ?? false,
      createdAt: _dt(j['createdAt']),
      paidAt: _dtn(j['paidAt']),
      holdExpiresAt: _dtn(j['holdExpiresAt']),
      totalMmk: _i(j['totalMmk']),
      discountMmk: _i(j['discountMmk']),
      quantity: _i(j['quantity']),
      buyerName: b['name'] as String?,
      buyerPhone: b['phone'] as String?,
    );
  }
}

class OrgOrderPage {
  OrgOrderPage({required this.orders, this.nextCursor});
  final List<OrgOrderRow> orders;
  final String? nextCursor;
  factory OrgOrderPage.fromJson(Map<String, dynamic> j) => OrgOrderPage(
        orders: [for (final o in (j['orders'] as List? ?? const []).cast<Map<String, dynamic>>()) OrgOrderRow.fromJson(o)],
        nextCursor: j['nextCursor'] as String?,
      );
}

class OrgOrderItem {
  OrgOrderItem({required this.name, this.nameMy, required this.quantity, required this.unitPriceMmk, this.seats = const []});
  final String name;
  final String? nameMy;
  final int quantity, unitPriceMmk;
  final List<({String label, String? labelMy})> seats;
  factory OrgOrderItem.fromJson(Map<String, dynamic> j) => OrgOrderItem(
        name: j['name'] as String,
        nameMy: j['nameMy'] as String?,
        quantity: _i(j['quantity']),
        unitPriceMmk: _i(j['unitPriceMmk']),
        seats: [for (final s in (j['seats'] as List? ?? const []).cast<Map<String, dynamic>>()) (label: s['label'] as String, labelMy: s['labelMy'] as String?)],
      );
}

class OrgOrderDetail {
  OrgOrderDetail({required this.row, required this.subtotalMmk, required this.commissionMmk, this.promoCode, this.groupDiscountBp, required this.items, required this.payments, required this.refunds, required this.ticketsTotal, required this.ticketsValid, required this.ticketsCheckedIn, required this.ticketsVoid});
  final OrgOrderRow row;
  final int subtotalMmk, commissionMmk;
  final String? promoCode;
  final int? groupDiscountBp;
  final List<OrgOrderItem> items;
  final List<({String provider, String status, DateTime createdAt})> payments;
  final List<({String status, int amountMmk, DateTime createdAt, DateTime? completedAt})> refunds;
  final int ticketsTotal, ticketsValid, ticketsCheckedIn, ticketsVoid;
  factory OrgOrderDetail.fromJson(Map<String, dynamic> j) {
    final t = j['tickets'] as Map<String, dynamic>? ?? const {};
    return OrgOrderDetail(
      row: OrgOrderRow.fromJson(j),
      subtotalMmk: _i(j['subtotalMmk']),
      commissionMmk: _i(j['commissionMmk']),
      promoCode: j['promoCode'] as String?,
      groupDiscountBp: (j['groupDiscountBp'] as num?)?.toInt(),
      items: [for (final i in (j['items'] as List? ?? const []).cast<Map<String, dynamic>>()) OrgOrderItem.fromJson(i)],
      payments: [for (final p in (j['payments'] as List? ?? const []).cast<Map<String, dynamic>>()) (provider: p['provider'] as String, status: p['status'] as String, createdAt: _dt(p['createdAt']))],
      refunds: [for (final r in (j['refunds'] as List? ?? const []).cast<Map<String, dynamic>>()) (status: r['status'] as String, amountMmk: _i(r['amountMmk']), createdAt: _dt(r['createdAt']), completedAt: _dtn(r['completedAt']))],
      ticketsTotal: _i(t['total']),
      ticketsValid: _i(t['valid']),
      ticketsCheckedIn: _i(t['checkedIn']),
      ticketsVoid: _i(t['void']),
    );
  }
}

class PayoutEventRow {
  PayoutEventRow({required this.eventId, required this.title, this.titleMy, required this.grossMmk, required this.discountMmk, required this.commissionMmk, required this.refundsMmk, required this.netMmk});
  final String eventId, title;

  /// Myanmar title; null when the event has none.
  final String? titleMy;
  final int grossMmk, discountMmk, commissionMmk, refundsMmk, netMmk;
  factory PayoutEventRow.fromJson(Map<String, dynamic> j) => PayoutEventRow(
        eventId: j['eventId'] as String,
        title: j['title'] as String,
        titleMy: j['titleMy'] as String?,
        grossMmk: _i(j['grossMmk']),
        discountMmk: _i(j['discountMmk']),
        commissionMmk: _i(j['commissionMmk']),
        refundsMmk: _i(j['refundsMmk']),
        netMmk: _i(j['netMmk']),
      );
}

class PayoutRow {
  PayoutRow({required this.id, required this.method, required this.amountMmk, required this.paidAt, this.reference, this.note, this.voidReason, this.voidedAt});
  final String id, method;
  final int amountMmk;
  final DateTime paidAt;
  final String? reference, note, voidReason;
  final DateTime? voidedAt;
  bool get isVoided => voidedAt != null;
  factory PayoutRow.fromJson(Map<String, dynamic> j) => PayoutRow(
        id: j['id'] as String,
        method: j['method'] as String,
        amountMmk: _i(j['amountMmk']),
        paidAt: _dt(j['paidAt']),
        reference: j['reference'] as String?,
        note: j['note'] as String?,
        voidReason: j['voidReason'] as String?,
        voidedAt: _dtn(j['voidedAt']),
      );
}

class PayoutSummary {
  PayoutSummary({required this.earnedMmk, required this.paidOutMmk, required this.owedMmk, required this.reconciled, required this.events, required this.payouts});
  final int earnedMmk, paidOutMmk, owedMmk;
  final bool reconciled;
  final List<PayoutEventRow> events;
  final List<PayoutRow> payouts;
  factory PayoutSummary.fromJson(Map<String, dynamic> j) => PayoutSummary(
        earnedMmk: _i(j['earnedMmk']),
        paidOutMmk: _i(j['paidOutMmk']),
        owedMmk: _i(j['owedMmk']),
        reconciled: j['reconciled'] as bool? ?? true,
        events: [for (final e in (j['events'] as List? ?? const []).cast<Map<String, dynamic>>()) PayoutEventRow.fromJson(e)],
        payouts: [for (final p in (j['payouts'] as List? ?? const []).cast<Map<String, dynamic>>()) PayoutRow.fromJson(p)],
      );
}
