/// Live streams and recordings of an event (what can be watched; watching needs a ticket).
library;

DateTime _dt(Object? v) => DateTime.parse(v as String).toUtc();

class LiveStream {
  LiveStream({required this.channelId, required this.sessionId, required this.title, this.titleMy, required this.startsAt, required this.endsAt, required this.isLive});
  final String channelId;
  final String sessionId;
  final String title;
  final String? titleMy;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isLive;

  factory LiveStream.fromJson(Map<String, dynamic> j) => LiveStream(
        channelId: j['channelId'] as String,
        sessionId: j['sessionId'] as String,
        title: j['title'] as String,
        titleMy: j['titleMy'] as String?,
        startsAt: _dt(j['startsAt']),
        endsAt: _dt(j['endsAt']),
        isLive: j['isLive'] as bool,
      );
}

class Recording {
  Recording({required this.id, this.sessionId, required this.title, this.titleMy, this.durationSec, this.availableUntil});
  final String id;
  final String? sessionId;
  final String title;
  final String? titleMy;
  final int? durationSec;
  final DateTime? availableUntil;

  factory Recording.fromJson(Map<String, dynamic> j) => Recording(
        id: j['id'] as String,
        sessionId: j['sessionId'] as String?,
        title: j['title'] as String,
        titleMy: j['titleMy'] as String?,
        durationSec: (j['durationSec'] as num?)?.toInt(),
        availableUntil: j['availableUntil'] == null ? null : _dt(j['availableUntil']),
      );
}

class EventStreams {
  EventStreams({required this.live, required this.recordings});
  final List<LiveStream> live;
  final List<Recording> recordings;

  bool get isEmpty => live.isEmpty && recordings.isEmpty;
  bool get liveNow => live.any((l) => l.isLive);

  factory EventStreams.fromJson(Map<String, dynamic> j) => EventStreams(
        live: (j['live'] as List).map((x) => LiveStream.fromJson(x as Map<String, dynamic>)).toList(),
        recordings: (j['recordings'] as List).map((x) => Recording.fromJson(x as Map<String, dynamic>)).toList(),
      );
}

/// Playback grant: an HLS URL (token in the path), the playback session to heartbeat, and the watermark text.
class WatchGrant {
  WatchGrant({required this.url, required this.sessionId, required this.watermark, this.heartbeatSeconds = 30});
  final String url;
  final String sessionId;
  final String watermark;
  final int heartbeatSeconds;

  factory WatchGrant.fromJson(Map<String, dynamic> j) => WatchGrant(
        url: j['url'] as String,
        sessionId: j['sessionId'] as String,
        watermark: j['watermark'] as String? ?? '',
        heartbeatSeconds: (j['heartbeatSeconds'] as num?)?.toInt() ?? 30,
      );
}
