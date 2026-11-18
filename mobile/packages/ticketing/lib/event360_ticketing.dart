library event360_ticketing;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Claims carried in a ticket QR (ADR-0001 §6): ticket id, event id, ticket type, QR version.
class TicketClaims {
  const TicketClaims({required this.ticketId, required this.eventId, required this.ticketTypeId, required this.version});

  final String ticketId;
  final String eventId;
  final String ticketTypeId;
  final int version;

  factory TicketClaims.fromJson(Map<String, dynamic> j) => TicketClaims(
        ticketId: j['tid'] as String,
        eventId: j['eid'] as String,
        ticketTypeId: j['tt'] as String,
        version: j['v'] as int,
      );
}

/// Verifies `base64url(payloadJson).base64url(ed25519Signature)` offline with the event public key.
class OfflineTicketVerifier {
  OfflineTicketVerifier(List<int> publicKeyBytes)
      : _publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);

  final SimplePublicKey _publicKey;
  final _algo = Ed25519();

  /// Returns the claims when the signature is valid, otherwise null.
  Future<TicketClaims?> verify(String qr) async {
    final parts = qr.split('.');
    if (parts.length != 2) return null;
    try {
      final payload = base64Url.decode(base64Url.normalize(parts[0]));
      final sig = base64Url.decode(base64Url.normalize(parts[1]));
      final ok = await _algo.verify(payload, signature: Signature(sig, publicKey: _publicKey));
      if (!ok) return null;
      return TicketClaims.fromJson(jsonDecode(utf8.decode(payload)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
