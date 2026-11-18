import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:event360_ticketing/event360_ticketing.dart';
import 'package:test/test.dart';

void main() {
  test('accepts a validly signed ticket and rejects a tampered one', () async {
    final algo = Ed25519();
    final kp = await algo.newKeyPair();
    final pub = await kp.extractPublicKey();
    final payload = utf8.encode(jsonEncode({'tid': 't1', 'eid': 'e1', 'tt': 'tt1', 'v': 1}));
    final sig = await algo.sign(payload, keyPair: kp);
    final qr = '${base64Url.encode(payload)}.${base64Url.encode(sig.bytes)}';

    final verifier = OfflineTicketVerifier(pub.bytes);
    expect((await verifier.verify(qr))?.ticketId, 't1');

    final tampered = '${base64Url.encode(utf8.encode(jsonEncode({'tid': 't2', 'eid': 'e1', 'tt': 'tt1', 'v': 1})))}.${base64Url.encode(sig.bytes)}';
    expect(await verifier.verify(tampered), isNull);
  });
}
