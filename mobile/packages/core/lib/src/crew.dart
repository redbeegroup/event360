/// Models for the Crew (door check-in) app.
library;

DateTime _dt(Object? v) => DateTime.parse(v as String).toUtc();
DateTime? _dtOrNull(Object? v) => v == null ? null : _dt(v);

/// An event the crew member may check tickets in for.
class CrewEvent {
  CrewEvent({required this.id, required this.title, this.titleMy, required this.startsAt, required this.endsAt, this.coverImageUrl, this.venueName, this.city});

  final String id;
  final String title;
  final String? titleMy;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? coverImageUrl;
  final String? venueName;
  final String? city;

  factory CrewEvent.fromJson(Map<String, dynamic> j) {
    final v = j['venue'] as Map<String, dynamic>?;
    return CrewEvent(
      id: j['id'] as String,
      title: j['title'] as String,
      titleMy: j['titleMy'] as String?,
      startsAt: _dt(j['startsAt']),
      endsAt: _dt(j['endsAt']),
      coverImageUrl: j['coverImageUrl'] as String?,
      venueName: v?['name'] as String?,
      city: v?['city'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'titleMy': titleMy,
        'startsAt': startsAt.toIso8601String(),
        'endsAt': endsAt.toIso8601String(),
        'coverImageUrl': coverImageUrl,
        'venue': venueName == null ? null : {'name': venueName, 'city': city ?? ''},
      };
}

/// Result of redeeming a volunteer event code.
class CrewRedeem {
  CrewRedeem({required this.accessToken, required this.event, this.gate, required this.label});
  final String accessToken;
  final CrewEvent event;
  final String? gate;
  final String label;

  factory CrewRedeem.fromJson(Map<String, dynamic> j) => CrewRedeem(
        accessToken: j['accessToken'] as String,
        event: CrewEvent.fromJson(j['event'] as Map<String, dynamic>),
        gate: j['gate'] as String?,
        label: j['label'] as String,
      );
}

class CheckedInInfo {
  CheckedInInfo({required this.at, this.gate, this.by});
  final DateTime at;
  final String? gate;
  final String? by;
  factory CheckedInInfo.fromJson(Map<String, dynamic> j) => CheckedInInfo(at: _dt(j['at']), gate: j['gate'] as String?, by: j['by'] as String?);
}

/// A ticket as door staff see it.
class CrewTicket {
  CrewTicket({
    required this.id,
    required this.code,
    required this.status,
    required this.holderName,
    this.phoneLast4,
    required this.ticketTypeName,
    this.ticketTypeNameMy,
    this.checkedIn,
  });

  final String id;
  final String code;
  final String status; // VALID | CHECKED_IN | VOID | REFUNDED | TRANSFERRED
  final String holderName;
  final String? phoneLast4;
  final String ticketTypeName;
  final String? ticketTypeNameMy;
  final CheckedInInfo? checkedIn;

  bool get isCheckedIn => status == 'CHECKED_IN';

  factory CrewTicket.fromJson(Map<String, dynamic> j) {
    final tt = j['ticketType'] as Map<String, dynamic>;
    return CrewTicket(
      id: j['id'] as String,
      code: j['code'] as String,
      status: j['status'] as String,
      holderName: j['holderName'] as String,
      phoneLast4: j['phoneLast4'] as String?,
      ticketTypeName: tt['name'] as String,
      ticketTypeNameMy: tt['nameMy'] as String?,
      checkedIn: j['checkedIn'] == null ? null : CheckedInInfo.fromJson(j['checkedIn'] as Map<String, dynamic>),
    );
  }
}

/// Outcome of a scan or manual check-in. [result] is one of ACCEPTED, ALREADY_CHECKED_IN, WRONG_EVENT,
/// INVALID, VOID, REFUNDED, TRANSFERRED.
class ScanOutcome {
  ScanOutcome({required this.result, this.ticket, this.reason, this.otherEventTitle, this.offline = false, this.clientId});

  final String result;
  final CrewTicket? ticket;
  final String? reason;
  final String? otherEventTitle;

  /// Decided on the device without the server (signature + local list).
  final bool offline;
  final String? clientId;

  bool get accepted => result == 'ACCEPTED';

  factory ScanOutcome.fromJson(Map<String, dynamic> j) => ScanOutcome(
        result: j['result'] as String,
        ticket: j['ticket'] == null ? null : CrewTicket.fromJson(j['ticket'] as Map<String, dynamic>),
        reason: j['reason'] as String?,
        otherEventTitle: (j['otherEvent'] as Map<String, dynamic>?)?['title'] as String?,
        clientId: j['clientId'] as String?,
      );
}

class ManifestTicket {
  ManifestTicket({required this.id, required this.code, required this.ticketTypeId, required this.version, required this.status, required this.holderName, this.phoneLast4, this.checkedInAt});

  final String id;
  final String code;
  final String ticketTypeId;
  final int version;
  final String status;
  final String holderName;
  final String? phoneLast4;
  final DateTime? checkedInAt;

  factory ManifestTicket.fromJson(Map<String, dynamic> j) => ManifestTicket(
        id: j['id'] as String,
        code: j['code'] as String,
        ticketTypeId: j['tt'] as String,
        version: (j['v'] as num).toInt(),
        status: j['status'] as String,
        holderName: j['holderName'] as String,
        phoneLast4: j['phoneLast4'] as String?,
        checkedInAt: _dtOrNull(j['checkedInAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'tt': ticketTypeId,
        'v': version,
        'status': status,
        'holderName': holderName,
        'phoneLast4': phoneLast4,
        'checkedInAt': checkedInAt?.toIso8601String(),
      };
}

/// Offline copy of an event's tickets plus the QR public key.
class CrewManifest {
  CrewManifest({required this.eventId, required this.generatedAt, required this.publicKey, required this.ticketTypes, required this.tickets});

  final String eventId;
  final DateTime generatedAt;
  final String publicKey; // base64 raw Ed25519
  final Map<String, ({String name, String? nameMy})> ticketTypes;
  final List<ManifestTicket> tickets;

  factory CrewManifest.fromJson(Map<String, dynamic> j) => CrewManifest(
        eventId: j['eventId'] as String,
        generatedAt: _dt(j['generatedAt']),
        publicKey: j['publicKey'] as String,
        ticketTypes: {
          for (final t in (j['ticketTypes'] as List).cast<Map<String, dynamic>>()) t['id'] as String: (name: t['name'] as String, nameMy: t['nameMy'] as String?),
        },
        tickets: (j['tickets'] as List).map((t) => ManifestTicket.fromJson(t as Map<String, dynamic>)).toList(),
      );

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'generatedAt': generatedAt.toIso8601String(),
        'publicKey': publicKey,
        'ticketTypes': [
          for (final e in ticketTypes.entries) {'id': e.key, 'name': e.value.name, 'nameMy': e.value.nameMy},
        ],
        'tickets': tickets.map((t) => t.toJson()).toList(),
      };
}

class CrewRecentScan {
  CrewRecentScan({required this.id, required this.at, this.gate, required this.method, required this.offline, required this.duplicate, required this.undone, this.by, required this.ticketId, required this.ticketCode, required this.holderName, required this.ticketTypeName, this.ticketTypeNameMy, required this.ticketStatus});

  final String id;
  final DateTime at;
  final String? gate;
  final String method;
  final bool offline;
  final bool duplicate;
  final bool undone;
  final String? by;
  final String ticketId;
  final String ticketCode;
  final String holderName;
  final String ticketTypeName;
  final String? ticketTypeNameMy;
  final String ticketStatus;

  factory CrewRecentScan.fromJson(Map<String, dynamic> j) {
    final t = j['ticket'] as Map<String, dynamic>;
    final tt = t['ticketType'] as Map<String, dynamic>;
    return CrewRecentScan(
      id: j['id'] as String,
      at: _dt(j['at']),
      gate: j['gate'] as String?,
      method: j['method'] as String,
      offline: j['offline'] as bool,
      duplicate: j['duplicate'] as bool,
      undone: j['undone'] as bool,
      by: j['by'] as String?,
      ticketId: t['id'] as String,
      ticketCode: t['code'] as String,
      holderName: t['holderName'] as String,
      ticketTypeName: tt['name'] as String,
      ticketTypeNameMy: tt['nameMy'] as String?,
      ticketStatus: t['status'] as String,
    );
  }
}

class CrewStats {
  CrewStats({required this.registered, required this.checkedIn, required this.byTicketType, required this.byGate, required this.recent});

  final int registered;
  final int checkedIn;
  final List<({String name, String? nameMy, int registered, int checkedIn})> byTicketType;
  final List<({String? gate, int checkedIn})> byGate;
  final List<CrewRecentScan> recent;

  factory CrewStats.fromJson(Map<String, dynamic> j) => CrewStats(
        registered: (j['registered'] as num).toInt(),
        checkedIn: (j['checkedIn'] as num).toInt(),
        byTicketType: [
          for (final t in (j['byTicketType'] as List).cast<Map<String, dynamic>>())
            (name: t['name'] as String, nameMy: t['nameMy'] as String?, registered: (t['registered'] as num).toInt(), checkedIn: (t['checkedIn'] as num).toInt()),
        ],
        byGate: [
          for (final g in (j['byGate'] as List).cast<Map<String, dynamic>>()) (gate: g['gate'] as String?, checkedIn: (g['checkedIn'] as num).toInt()),
        ],
        recent: (j['recent'] as List).map((r) => CrewRecentScan.fromJson(r as Map<String, dynamic>)).toList(),
      );
}
