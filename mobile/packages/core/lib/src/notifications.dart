/// In-app inbox entries (every push/SMS notification also lands here).
library;

class AppNotification {
  AppNotification({required this.id, required this.kind, required this.title, this.titleMy, required this.body, this.bodyMy, this.link, this.eventId, this.readAt, required this.createdAt});
  final String id;
  final String kind;
  final String title;
  final String? titleMy;
  final String body;
  final String? bodyMy;
  final String? link;
  final String? eventId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get unread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        titleMy: j['titleMy'] as String?,
        body: j['body'] as String,
        bodyMy: j['bodyMy'] as String?,
        link: j['link'] as String?,
        eventId: j['eventId'] as String?,
        readAt: j['readAt'] == null ? null : DateTime.parse(j['readAt'] as String).toUtc(),
        createdAt: DateTime.parse(j['createdAt'] as String).toUtc(),
      );
}

class Inbox {
  Inbox({required this.items, required this.unread});
  final List<AppNotification> items;
  final int unread;
  factory Inbox.fromJson(Map<String, dynamic> j) =>
      Inbox(items: (j['items'] as List).map((x) => AppNotification.fromJson(x as Map<String, dynamic>)).toList(), unread: (j['unread'] as num).toInt());
}
