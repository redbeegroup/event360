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
      holdExpiresAt: _dtn(j['holdExpiresAt']),
      paymentProvider: pay?['provider'] as String?,
      paymentAction: pay?['action'] == null ? null : PaymentAction.fromJson(pay!['action'] as Map<String, dynamic>),
      ticketIds: ((j['ticketIds'] as List?) ?? const []).cast<String>(),
    );
  }
}

/// Result of checking a promo code against the chosen tickets (nothing reserved).
class PromoCheck {
  PromoCheck({required this.valid, this.reason, required this.discountMmk, required this.totalMmk});
  final bool valid;
  final String? reason;
  final int discountMmk;
  final int totalMmk;
  factory PromoCheck.fromJson(Map<String, dynamic> j) => PromoCheck(
        valid: j['valid'] as bool,
        reason: j['reason'] as String?,
        discountMmk: (j['discountMmk'] as num).toInt(),
        totalMmk: (j['totalMmk'] as num).toInt(),
      );
}
