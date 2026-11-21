/// Paid checkout: orders hold seats for 10 minutes while the buyer pays with a wallet.
library;

DateTime? _dtn(Object? v) => v == null ? null : DateTime.parse(v as String).toUtc();

class PaymentMethod {
  PaymentMethod({required this.code, required this.label});
  final String code; // KBZPAY | WAVEPAY | MOCK
  final String label;
  factory PaymentMethod.fromJson(Map<String, dynamic> j) => PaymentMethod(code: j['code'] as String, label: j['label'] as String);
}

/// What the buyer does to pay: open [url] (wallet checkout / KBZPay PWA) or scan [qr] with the wallet app.
class PaymentAction {
  PaymentAction({required this.type, this.url, this.deeplink, this.qr});
  final String type; // REDIRECT | DEEPLINK | QR
  final String? url;
  final String? deeplink;
  final String? qr;
  String? get openUrl => deeplink ?? url;
  factory PaymentAction.fromJson(Map<String, dynamic> j) =>
      PaymentAction(type: j['type'] as String, url: j['url'] as String?, deeplink: j['deeplink'] as String?, qr: j['qr'] as String?);
}

class OrderLine {
  OrderLine({required this.ticketTypeId, required this.name, this.nameMy, required this.quantity, required this.unitPriceMmk});
  final String ticketTypeId;
  final String name;
  final String? nameMy;
  final int quantity;
  final int unitPriceMmk;
  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        ticketTypeId: j['ticketTypeId'] as String,
        name: j['name'] as String,
        nameMy: j['nameMy'] as String?,
        quantity: (j['quantity'] as num).toInt(),
        unitPriceMmk: (j['unitPriceMmk'] as num).toInt(),
      );
}

class Order {
  Order({
    required this.id,
    required this.status,
    required this.eventId,
    required this.eventTitle,
    this.eventTitleMy,
    required this.items,
    required this.totalMmk,
    this.discountMmk = 0,
    this.discountSource,
    this.holdExpiresAt,
    this.paymentProvider,
    this.paymentAction,
    required this.ticketIds,
  });
  final String id;
  final String status; // PENDING_PAYMENT | PAID | CONFIRMED | EXPIRED | CANCELLED | REFUNDED | FAILED
  final String eventId;
  final String eventTitle;
  final String? eventTitleMy;
  final List<OrderLine> items;
  final int totalMmk;
  final int discountMmk;

  /// What the discount came from: GROUP (group discount), PROMO (a code) or null.
  final String? discountSource;
  final DateTime? holdExpiresAt;
  final String? paymentProvider;
  final PaymentAction? paymentAction;
  final List<String> ticketIds;

  bool get isPaid => status == 'PAID' || status == 'CONFIRMED';
  bool get isOpen => status == 'PENDING_PAYMENT' && (holdExpiresAt == null || holdExpiresAt!.isAfter(DateTime.now().toUtc()));
  int get quantity => items.fold(0, (s, i) => s + i.quantity);

  factory Order.fromJson(Map<String, dynamic> j) {
    final ev = j['event'] as Map<String, dynamic>;
    final pay = j['payment'] as Map<String, dynamic>?;
    return Order(
      id: j['id'] as String,
      status: j['status'] as String,
      eventId: ev['id'] as String,
      eventTitle: ev['title'] as String,
      eventTitleMy: ev['titleMy'] as String?,
      items: (j['items'] as List).map((x) => OrderLine.fromJson(x as Map<String, dynamic>)).toList(),
      totalMmk: (j['totalMmk'] as num).toInt(),
      discountMmk: (j['discountMmk'] as num?)?.toInt() ?? 0,
      discountSource: j['discountSource'] as String?,
      holdExpiresAt: _dtn(j['holdExpiresAt']),
      paymentProvider: pay?['provider'] as String?,
      paymentAction: pay?['action'] == null ? null : PaymentAction.fromJson(pay!['action'] as Map<String, dynamic>),
      ticketIds: ((j['ticketIds'] as List?) ?? const []).cast<String>(),
    );
  }
}

/// Result of checking a promo code against the chosen tickets (nothing reserved).
class PromoCheck {
  PromoCheck({required this.valid, this.reason, this.reasonCode, required this.discountMmk, required this.totalMmk, this.discountSource, bool? promoApplied}) : promoApplied = promoApplied ?? valid && discountSource != 'GROUP';
  final bool valid;
  final String? reason; // English, for old clients
  final String? reasonCode; // USED_UP | EXPIRED | NOT_STARTED | NOT_APPLICABLE | INVALID
  final int discountMmk;
  final int totalMmk;

  /// GROUP, PROMO or null: which discount the amounts above come from. A valid code that loses to a bigger group
  /// discount is still [valid], but [promoApplied] is false and the source is GROUP.
  final String? discountSource;
  final bool promoApplied;
  factory PromoCheck.fromJson(Map<String, dynamic> j) => PromoCheck(
        valid: j['valid'] as bool,
        reason: j['reason'] as String?,
        reasonCode: j['reasonCode'] as String?,
        discountMmk: (j['discountMmk'] as num).toInt(),
        totalMmk: (j['totalMmk'] as num).toInt(),
        discountSource: j['discountSource'] as String?,
        promoApplied: j['promoApplied'] as bool?,
      );
}

/// One of the signed-in buyer's waitlist entries (`GET /me/waitlist`).
class WaitlistEntry {
  WaitlistEntry({
    required this.id,
    required this.ticketTypeId,
    required this.eventId,
    required this.status,
    required this.quantity,
    this.position,
    this.offeredQty = 0,
    this.offerExpiresAt,
    this.seatKeys = const [],
    this.orderId,
    this.eventSlug,
    this.eventTitle = '',
    this.eventTitleMy,
    this.ticketTypeName = '',
    this.ticketTypeNameMy,
    this.clockSkew = Duration.zero,
  });
  final String id;
  final String ticketTypeId;
  final String eventId;

  /// WAITING | OFFERED | PURCHASED | EXPIRED | LEFT
  final String status;

  /// How many tickets the buyer asked for.
  final int quantity;

  /// Place in line (1 = next); only while WAITING.
  final int? position;

  /// How many tickets the live offer covers.
  final int offeredQty;
  final DateTime? offerExpiresAt;

  /// Seats reserved for the buyer by a live offer on a seated type (they look taken to everyone else).
  final List<String> seatKeys;

  /// An OFFERED entry that carries an order id is a reopened offer (its checkout was released); it is still "buy now".
  final String? orderId;
  final String? eventSlug;
  final String eventTitle;
  final String? eventTitleMy;
  final String ticketTypeName;
  final String? ticketTypeNameMy;

  /// Server clock minus this phone's clock when the entry was fetched; offers expire on the server's clock.
  final Duration clockSkew;

  /// "Now" on the server's clock.
  DateTime get serverNow => DateTime.now().toUtc().add(clockSkew);

  bool get isWaiting => status == 'WAITING';

  /// A live offer: OFFERED and not past its expiry, whatever [orderId] says.
  bool get isOffered => status == 'OFFERED' && offerExpiresAt != null && offerExpiresAt!.isAfter(serverNow);
  bool get isActive => isWaiting || status == 'OFFERED';
  bool get isSeated => seatKeys.isNotEmpty;

  factory WaitlistEntry.fromJson(Map<String, dynamic> j) {
    final ev = (j['event'] as Map<String, dynamic>?) ?? const {};
    final tt = (j['ticketType'] as Map<String, dynamic>?) ?? const {};
    return WaitlistEntry(
      id: j['id'] as String,
      ticketTypeId: j['ticketTypeId'] as String,
      eventId: j['eventId'] as String? ?? ev['id'] as String? ?? '',
      status: j['status'] as String,
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      position: (j['position'] as num?)?.toInt(),
      offeredQty: (j['offeredQty'] as num?)?.toInt() ?? 0,
      offerExpiresAt: _dtn(j['offerExpiresAt']),
      seatKeys: ((j['seatKeys'] as List?) ?? const []).whereType<String>().toList(),
      orderId: j['orderId'] as String?,
      eventSlug: ev['slug'] as String?,
      eventTitle: ev['title'] as String? ?? '',
      eventTitleMy: ev['titleMy'] as String?,
      ticketTypeName: tt['name'] as String? ?? '',
      ticketTypeNameMy: tt['nameMy'] as String?,
      clockSkew: _dtn(j['serverNow'])?.difference(DateTime.now().toUtc()) ?? Duration.zero,
    );
  }
}

/// The answer to joining a waitlist.
class WaitlistJoin {
  WaitlistJoin({required this.entryId, required this.position});
  final String entryId;
  final int position;
  factory WaitlistJoin.fromJson(Map<String, dynamic> j) => WaitlistJoin(entryId: j['entryId'] as String, position: (j['position'] as num?)?.toInt() ?? 0);
}
